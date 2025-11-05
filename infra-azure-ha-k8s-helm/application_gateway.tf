# Application Gateway for Kubernetes Ingress (Zone-Redundant)
resource "azurerm_application_gateway" "appgw" {
  name                = "agw-${var.cluster_name}"
  resource_group_name = azurerm_resource_group.iq_rg.name
  location            = azurerm_resource_group.iq_rg.location
  zones               = local.availability_zones

  sku {
    name = var.app_gateway_sku_name # Standard_v2 or WAF_v2
    tier = var.app_gateway_sku_tier
    # Note: capacity is not specified when using autoscale_configuration
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
    port                                = 8070  # Nexus IQ Server port
    protocol                            = "Http"
    request_timeout                     = 60
    probe_name                          = "health-probe"
    pick_host_name_from_backend_address = false  # Use Application Gateway FQDN, not backend IP
    host_name                           = azurerm_public_ip.appgw_pip.fqdn  # Send App Gateway FQDN to backend
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
    path                                      = "/ping"  # Nexus IQ health check endpoint
    port                                      = 8070     # Nexus IQ Server port
    interval                                  = 30
    timeout                                   = 30
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = false  # Don't use backend IP
    host                                      = azurerm_public_ip.appgw_pip.fqdn  # Use App Gateway FQDN
    match {
      status_code = ["200-399"]
    }
  }

  # SSL Policy
  ssl_policy {
    policy_type = "Predefined"
    policy_name = "AppGwSslPolicy20220101"
  }

  # Enable HTTP/2
  enable_http2 = true

  # Autoscale configuration
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

# User Assigned Identity for Application Gateway Ingress Controller
resource "azurerm_user_assigned_identity" "agic_identity" {
  name                = "agic-identity-${var.cluster_name}"
  resource_group_name = azurerm_resource_group.iq_rg.name
  location            = azurerm_resource_group.iq_rg.location

  tags = local.common_tags
}

# Role assignment for AGIC identity to manage Application Gateway
resource "azurerm_role_assignment" "agic_appgw_contributor" {
  principal_id         = azurerm_user_assigned_identity.agic_identity.principal_id
  role_definition_name = "Contributor"
  scope                = azurerm_application_gateway.appgw.id
}

# Role assignment for AGIC identity to read resource group
resource "azurerm_role_assignment" "agic_rg_reader" {
  principal_id         = azurerm_user_assigned_identity.agic_identity.principal_id
  role_definition_name = "Reader"
  scope                = azurerm_resource_group.iq_rg.id
}

# Role assignment for AGIC identity to manage Public IP
resource "azurerm_role_assignment" "agic_pip_contributor" {
  principal_id         = azurerm_user_assigned_identity.agic_identity.principal_id
  role_definition_name = "Contributor"
  scope                = azurerm_public_ip.appgw_pip.id
}

# Role assignment for AGIC identity to manage Virtual Network
resource "azurerm_role_assignment" "agic_vnet_contributor" {
  principal_id         = azurerm_user_assigned_identity.agic_identity.principal_id
  role_definition_name = "Contributor"
  scope                = azurerm_virtual_network.iq_vnet.id
}
