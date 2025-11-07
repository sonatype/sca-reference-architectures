
resource "random_string" "dns_suffix" {
  length  = 6
  special = false
  upper   = false
}


resource "azurerm_public_ip" "app_gw_pip_ha" {
  name                = "pip-ref-arch-iq-ha"
  resource_group_name = azurerm_resource_group.iq_rg.name
  location            = azurerm_resource_group.iq_rg.location
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = "ref-arch-iq-ha-${random_string.dns_suffix.result}"


  zones = var.app_gateway_zones

  tags = merge(var.common_tags, {
    Name = "pip-ref-arch-iq-ha"
  })
}


resource "azurerm_application_gateway" "iq_app_gw_ha" {
  name                = "agw-ref-arch-iq-ha"
  resource_group_name = azurerm_resource_group.iq_rg.name
  location            = azurerm_resource_group.iq_rg.location


  zones = var.app_gateway_zones

  sku {
    name = var.app_gateway_sku_name
    tier = var.app_gateway_sku_tier

  }


  ssl_policy {
    policy_type = "Predefined"
    policy_name = "AppGwSslPolicy20220101"
  }

  gateway_ip_configuration {
    name      = "gateway-ip-config"
    subnet_id = azurerm_subnet.public_subnets[0].id
  }

  frontend_port {
    name = "frontend-port-80"
    port = 80
  }

  frontend_port {
    name = "frontend-port-443"
    port = 443
  }

  frontend_ip_configuration {
    name                 = "frontend-ip-config"
    public_ip_address_id = azurerm_public_ip.app_gw_pip_ha.id
  }


  backend_address_pool {
    name  = "iq-backend-pool-ha"
    fqdns = [azurerm_container_app.iq_app_ha.ingress[0].fqdn]
  }


  backend_http_settings {
    name                                = "iq-http-settings-ha"
    cookie_based_affinity               = "Disabled"
    path                                = "/"
    port                                = 80
    protocol                            = "Http"
    pick_host_name_from_backend_address = true
    request_timeout                     = 60
    connection_draining {
      enabled           = true
      drain_timeout_sec = 60
    }


    probe_name = "iq-health-probe-ha"
  }


  http_listener {
    name                           = "iq-http-listener-ha"
    frontend_ip_configuration_name = "frontend-ip-config"
    frontend_port_name             = "frontend-port-80"
    protocol                       = "Http"
  }


  request_routing_rule {
    name                       = "iq-routing-rule-ha"
    rule_type                  = "Basic"
    http_listener_name         = "iq-http-listener-ha"
    backend_address_pool_name  = "iq-backend-pool-ha"
    backend_http_settings_name = "iq-http-settings-ha"
    rewrite_rule_set_name      = "LocationHeaderRewrite"
    priority                   = 1
  }


  probe {
    name                                      = "iq-health-probe-ha"
    protocol                                  = "Http"
    path                                      = "/"
    interval                                  = 30
    timeout                                   = 30
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = true

    match {
      status_code = ["200", "302", "303", "404"]
    }
  }










  rewrite_rule_set {
    name = "LocationHeaderRewrite"

    rewrite_rule {
      name          = "FixContainerAppHostname"
      rule_sequence = 100

      condition {
        variable    = "http_resp_Location"
        pattern     = "^http://${replace(azurerm_container_app.iq_app_ha.ingress[0].fqdn, ".", "\\.")}(.*)$"
        ignore_case = true
        negate      = false
      }

      response_header_configuration {
        header_name  = "location"
        header_value = "http://${azurerm_public_ip.app_gw_pip_ha.fqdn}{http_resp_Location_1}"
      }
    }
  }


  autoscale_configuration {
    min_capacity = 2
    max_capacity = 10
  }

  tags = merge(var.common_tags, {
    Name = "agw-ref-arch-iq-ha"
  })
}












resource "azurerm_monitor_diagnostic_setting" "app_gw_diagnostics" {
  count                      = var.enable_monitoring ? 1 : 0
  name                       = "agw-ref-arch-iq-ha-diagnostics"
  target_resource_id         = azurerm_application_gateway.iq_app_gw_ha.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.iq_logs_ha.id

  enabled_log {
    category = "ApplicationGatewayAccessLog"
  }

  enabled_log {
    category = "ApplicationGatewayPerformanceLog"
  }

  enabled_log {
    category = "ApplicationGatewayFirewallLog"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}