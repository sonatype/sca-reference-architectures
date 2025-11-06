
resource "azurerm_application_gateway" "appgw" {
  name                = "agw-${var.cluster_name}"
  resource_group_name = azurerm_resource_group.iq_rg.name
  location            = azurerm_resource_group.iq_rg.location
  zones               = local.availability_zones

  sku {
    name = var.app_gateway_sku_name
    tier = var.app_gateway_sku_tier

  }

  gateway_ip_configuration {
    name      = "gateway-ip-config"
    subnet_id = azurerm_subnet.public_subnet.id
  }

  frontend_port {
    name = "http-port"
    port = 80
  }

  frontend_port {
    name = "https-port"
    port = 443
  }

  frontend_ip_configuration {
    name                 = "frontend-ip-config"
    public_ip_address_id = azurerm_public_ip.appgw_pip.id
  }

  backend_address_pool {
    name = "aks-backend-pool"
  }

  backend_http_settings {
    name                                = "backend-http-settings"
    cookie_based_affinity               = "Disabled"
    port                                = 8070
    protocol                            = "Http"
    request_timeout                     = 60
    probe_name                          = "health-probe"
    pick_host_name_from_backend_address = false
    host_name                           = azurerm_public_ip.appgw_pip.fqdn
  }

  http_listener {
    name                           = "http-listener"
    frontend_ip_configuration_name = "frontend-ip-config"
    frontend_port_name             = "http-port"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "routing-rule"
    rule_type                  = "Basic"
    http_listener_name         = "http-listener"
    backend_address_pool_name  = "aks-backend-pool"
    backend_http_settings_name = "backend-http-settings"
    priority                   = 100
  }

  probe {
    name                                      = "health-probe"
    protocol                                  = "Http"
    path                                      = "/ping"
    port                                      = 8070
    interval                                  = 30
    timeout                                   = 30
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = false
    host                                      = azurerm_public_ip.appgw_pip.fqdn
    match {
      status_code = ["200-399"]
    }
  }


  ssl_policy {
    policy_type = "Predefined"
    policy_name = "AppGwSslPolicy20220101"
  }


  enable_http2 = true


  autoscale_configuration {
    min_capacity = var.app_gateway_min_capacity
    max_capacity = var.app_gateway_max_capacity
  }

  tags = merge(local.common_tags, {
    Name = "agw-${var.cluster_name}"
  })

  depends_on = [
    azurerm_subnet.public_subnet,
    azurerm_public_ip.appgw_pip
  ]
}


resource "azurerm_user_assigned_identity" "agic_identity" {
  name                = "agic-identity-${var.cluster_name}"
  resource_group_name = azurerm_resource_group.iq_rg.name
  location            = azurerm_resource_group.iq_rg.location

  tags = local.common_tags
}


resource "azurerm_role_assignment" "agic_appgw_contributor" {
  principal_id         = azurerm_user_assigned_identity.agic_identity.principal_id
  role_definition_name = "Contributor"
  scope                = azurerm_application_gateway.appgw.id
}


resource "azurerm_role_assignment" "agic_rg_reader" {
  principal_id         = azurerm_user_assigned_identity.agic_identity.principal_id
  role_definition_name = "Reader"
  scope                = azurerm_resource_group.iq_rg.id
}


resource "azurerm_role_assignment" "agic_pip_contributor" {
  principal_id         = azurerm_user_assigned_identity.agic_identity.principal_id
  role_definition_name = "Contributor"
  scope                = azurerm_public_ip.appgw_pip.id
}


resource "azurerm_role_assignment" "agic_vnet_contributor" {
  principal_id         = azurerm_user_assigned_identity.agic_identity.principal_id
  role_definition_name = "Contributor"
  scope                = azurerm_virtual_network.iq_vnet.id
}
