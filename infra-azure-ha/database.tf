
resource "azurerm_private_dns_zone" "postgres" {
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.iq_rg.name

  tags = merge(var.common_tags, {
    Name = "pdns-postgres-ha"
  })
}


resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = "pdns-link-postgres-ha"
  resource_group_name   = azurerm_resource_group.iq_rg.name
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  virtual_network_id    = azurerm_virtual_network.iq_vnet.id
  registration_enabled  = false

  tags = merge(var.common_tags, {
    Name = "pdns-link-postgres-ha"
  })
}


resource "azurerm_postgresql_flexible_server" "iq_db_ha" {
  name                   = "psqlfs-ref-arch-iq-ha"
  resource_group_name    = azurerm_resource_group.iq_rg.name
  location               = azurerm_resource_group.iq_rg.location
  version                = var.postgres_version
  delegated_subnet_id    = azurerm_subnet.db_subnet.id
  private_dns_zone_id    = azurerm_private_dns_zone.postgres.id
  administrator_login    = var.db_username
  administrator_password = var.db_password


  public_network_access_enabled = false


  zone = "1"
  high_availability {
    mode                      = var.db_high_availability_mode
    standby_availability_zone = "2"
  }


  storage_mb   = 65536
  storage_tier = "P6"


  sku_name = var.db_sku_name


  backup_retention_days        = var.db_backup_retention_days
  geo_redundant_backup_enabled = var.db_geo_redundant_backup_enabled


  create_mode = "Default"


  maintenance_window {
    day_of_week  = 0
    start_hour   = 4
    start_minute = 0
  }

  tags = merge(var.common_tags, {
    Name = "psqlfs-ref-arch-iq-ha"
  })

  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgres]
}


resource "azurerm_postgresql_flexible_server_database" "iq_database_ha" {
  name      = var.db_name
  server_id = azurerm_postgresql_flexible_server.iq_db_ha.id
  collation = "en_US.utf8"
  charset   = "utf8"
}


resource "azurerm_postgresql_flexible_server_configuration" "shared_preload_libraries" {
  name      = "shared_preload_libraries"
  server_id = azurerm_postgresql_flexible_server.iq_db_ha.id
  value     = "pg_stat_statements"
}

resource "azurerm_postgresql_flexible_server_configuration" "log_statement" {
  name      = "log_statement"
  server_id = azurerm_postgresql_flexible_server.iq_db_ha.id
  value     = "all"
}

resource "azurerm_postgresql_flexible_server_configuration" "log_min_duration_statement" {
  name      = "log_min_duration_statement"
  server_id = azurerm_postgresql_flexible_server.iq_db_ha.id
  value     = "1000"
}

resource "azurerm_postgresql_flexible_server_configuration" "log_checkpoints" {
  name      = "log_checkpoints"
  server_id = azurerm_postgresql_flexible_server.iq_db_ha.id
  value     = "on"
}

resource "azurerm_postgresql_flexible_server_configuration" "log_connections" {
  name      = "log_connections"
  server_id = azurerm_postgresql_flexible_server.iq_db_ha.id
  value     = "on"
}

resource "azurerm_postgresql_flexible_server_configuration" "log_disconnections" {
  name      = "log_disconnections"
  server_id = azurerm_postgresql_flexible_server.iq_db_ha.id
  value     = "on"
}


resource "azurerm_postgresql_flexible_server_firewall_rule" "container_apps" {
  count            = length(var.private_subnet_cidrs)
  name             = "AllowContainerApps-${count.index + 1}"
  server_id        = azurerm_postgresql_flexible_server.iq_db_ha.id
  start_ip_address = cidrhost(var.private_subnet_cidrs[count.index], 1)
  end_ip_address   = cidrhost(var.private_subnet_cidrs[count.index], -2)
}


resource "azurerm_postgresql_flexible_server_firewall_rule" "azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_postgresql_flexible_server.iq_db_ha.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}