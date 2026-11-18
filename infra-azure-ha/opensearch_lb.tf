# The internal load balancer in front of the data nodes, built when there are three or more.
# Standard SKU, so it spans the zones; TCP on 9200 passes TLS through to the nodes, whose
# certificates carry the frontend address. The probe is TCP because an HTTPS probe would not
# trust the private authority.

resource "azurerm_lb" "opensearch" {
  count               = local.os_create && local.os_cluster ? 1 : 0
  name                = "lbi-opensearch-${var.cluster_name}"
  location            = azurerm_resource_group.iq_rg.location
  resource_group_name = azurerm_resource_group.iq_rg.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                          = "opensearch"
    subnet_id                     = azurerm_subnet.opensearch[0].id
    private_ip_address_allocation = "Static"
    private_ip_address            = local.os_lb_ip
    zones                         = ["1", "2", "3"]
  }

  tags = merge(local.os_tags, {
    Name = "lbi-opensearch-${var.cluster_name}"
  })
}

resource "azurerm_lb_backend_address_pool" "opensearch" {
  count           = local.os_create && local.os_cluster ? 1 : 0
  name            = "opensearch-data-nodes"
  loadbalancer_id = azurerm_lb.opensearch[0].id
}

resource "azurerm_lb_probe" "opensearch" {
  count               = local.os_create && local.os_cluster ? 1 : 0
  name                = "opensearch-9200"
  loadbalancer_id     = azurerm_lb.opensearch[0].id
  protocol            = "Tcp"
  port                = 9200
  interval_in_seconds = 5
  probe_threshold     = 2
}

resource "azurerm_lb_rule" "opensearch" {
  count                          = local.os_create && local.os_cluster ? 1 : 0
  name                           = "opensearch-9200"
  loadbalancer_id                = azurerm_lb.opensearch[0].id
  protocol                       = "Tcp"
  frontend_port                  = 9200
  backend_port                   = 9200
  frontend_ip_configuration_name = "opensearch"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.opensearch[0].id]
  probe_id                       = azurerm_lb_probe.opensearch[0].id
  idle_timeout_in_minutes        = 30
}

resource "azurerm_network_interface_backend_address_pool_association" "opensearch" {
  for_each                = local.os_cluster ? { for k, n in local.os_nodes : k => n if n.has_data } : {}
  network_interface_id    = azurerm_network_interface.opensearch[each.key].id
  ip_configuration_name   = "primary"
  backend_address_pool_id = azurerm_lb_backend_address_pool.opensearch[0].id
}
