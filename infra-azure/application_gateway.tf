
resource "azurerm_public_ip" "app_gateway_pip" {
  name                = "pip-ref-arch-iq-appgw"
  resource_group_name = azurerm_resource_group.iq_rg.name
  location            = azurerm_resource_group.iq_rg.location
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = "ref-arch-iq-${random_string.dns_suffix.result}"

  tags = {
    Name = "pip-ref-arch-iq-appgw"
  }
}


resource "random_string" "dns_suffix" {
  length  = 6
  special = false
  upper   = false
}


resource "azurerm_application_gateway" "iq_app_gateway" {
  name                = "appgw-ref-arch-iq"
  resource_group_name = azurerm_resource_group.iq_rg.name
  location            = azurerm_resource_group.iq_rg.location

  sku {
    name     = var.app_gateway_sku_name
    tier     = var.app_gateway_sku_tier
    capacity = var.app_gateway_capacity
  }


  ssl_policy {
    policy_type = "Predefined"
    policy_name = "AppGwSslPolicy20220101"
  }

  gateway_ip_configuration {
    name      = "gateway-ip-configuration"
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
    name                 = "frontend-ip-configuration"
    public_ip_address_id = azurerm_public_ip.app_gateway_pip.id
  }

  backend_address_pool {
    name  = "iq-backend-pool"
    fqdns = [azurerm_container_app.iq_app.ingress[0].fqdn]
  }




  backend_http_settings {
    name                                = "iq-http-settings-new"
    cookie_based_affinity               = "Disabled"
    path                                = "/"
    port                                = 80
    protocol                            = "Http"
    request_timeout                     = 60
    pick_host_name_from_backend_address = true

    probe_name = "iq-http-probe-new"
  }

  http_listener {
    name                           = "http-listener"
    frontend_ip_configuration_name = "frontend-ip-configuration"
    frontend_port_name             = "http-port"
    protocol                       = "Http"
  }


  request_routing_rule {
    name                       = "iq-routing-rule"
    rule_type                  = "Basic"
    http_listener_name         = "http-listener"
    backend_address_pool_name  = "iq-backend-pool"
    backend_http_settings_name = "iq-http-settings-new"
    rewrite_rule_set_name      = "LocationHeaderRewrite"
    priority                   = 100
  }



  probe {
    name                                      = "iq-http-probe-new"
    protocol                                  = "Http"
    path                                      = "/"
    port                                      = 80
    interval                                  = 30
    timeout                                   = 30
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = true

    match {
      status_code = ["200", "301", "302", "303"]
    }
  }


  rewrite_rule_set {
    name = "LocationHeaderRewrite"

    rewrite_rule {
      name          = "FixContainerAppHostname"
      rule_sequence = 100

      condition {
        variable    = "http_resp_Location"
        pattern     = "^http://${replace(azurerm_container_app.iq_app.ingress[0].fqdn, ".", "\\.")}(.*)$"
        ignore_case = true
        negate      = false
      }

      response_header_configuration {
        header_name  = "location"
        header_value = "http://${azurerm_public_ip.app_gateway_pip.fqdn}{http_resp_Location_1}"
      }
    }
  }


  dynamic "ssl_certificate" {
    for_each = var.ssl_certificate_path != "" ? [1] : []
    content {
      name     = "iq-ssl-cert"
      data     = filebase64(var.ssl_certificate_path)
      password = var.ssl_certificate_password
    }
  }


  dynamic "http_listener" {
    for_each = var.ssl_certificate_path != "" ? [1] : []
    content {
      name                           = "https-listener"
      frontend_ip_configuration_name = "frontend-ip-configuration"
      frontend_port_name             = "https-port"
      protocol                       = "Https"
      ssl_certificate_name           = "iq-ssl-cert"
    }
  }


  dynamic "request_routing_rule" {
    for_each = var.ssl_certificate_path != "" ? [1] : []
    content {
      name                       = "iq-https-routing-rule"
      rule_type                  = "Basic"
      http_listener_name         = "https-listener"
      backend_address_pool_name  = "iq-backend-pool"
      backend_http_settings_name = "iq-http-settings"
      priority                   = 300
    }
  }

  tags = {
    Name = "appgw-ref-arch-iq"
  }

  depends_on = [
    azurerm_container_app.iq_app,
    azurerm_public_ip.app_gateway_pip
  ]
}