
resource "azurerm_private_dns_zone" "postgres" {
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.iq_rg.name

  tags = merge(local.common_tags, {
    Name = "pdns-postgres-${var.cluster_name}"
  })
}


resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = "pdns-link-postgres-${var.cluster_name}"
  resource_group_name   = azurerm_resource_group.iq_rg.name
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  virtual_network_id    = azurerm_virtual_network.iq_vnet.id
  registration_enabled  = false

  tags = merge(local.common_tags, {
    Name = "pdns-link-postgres-${var.cluster_name}"
  })
}


resource "azurerm_postgresql_flexible_server" "iq_db" {
  name                   = "psql-${var.cluster_name}"
  resource_group_name    = azurerm_resource_group.iq_rg.name
  location               = azurerm_resource_group.iq_rg.location
  version                = var.postgres_version
  delegated_subnet_id    = azurerm_subnet.db_subnet.id
  private_dns_zone_id    = azurerm_private_dns_zone.postgres.id
  administrator_login    = var.database_username
  administrator_password = var.database_password


  public_network_access_enabled = false


  zone = "1"
  high_availability {
    mode                      = var.db_high_availability_mode
    standby_availability_zone = "2"
  }


  storage_mb   = var.db_storage_mb
  storage_tier = var.db_storage_tier


  sku_name = var.db_sku_name


  backup_retention_days        = var.backup_retention_period
  geo_redundant_backup_enabled = var.db_geo_redundant_backup_enabled


  maintenance_window {
    day_of_week  = 0
    start_hour   = 4
    start_minute = 0
  }


  create_mode = "Default"

  tags = merge(local.common_tags, {
    Name = "psql-${var.cluster_name}"
  })

  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgres]
}


resource "azurerm_postgresql_flexible_server_database" "iq_database" {
  name      = var.database_name
  server_id = azurerm_postgresql_flexible_server.iq_db.id
  collation = "en_US.utf8"
  charset   = "UTF8"
}


resource "azurerm_postgresql_flexible_server_configuration" "extensions" {
  name      = "azure.extensions"
  server_id = azurerm_postgresql_flexible_server.iq_db.id
  value     = "uuid-ossp"
}


resource "azurerm_postgresql_flexible_server_configuration" "max_connections" {
  name      = "max_connections"
  server_id = azurerm_postgresql_flexible_server.iq_db.id
  value     = "200"
}


resource "azurerm_postgresql_flexible_server_configuration" "shared_buffers" {
  name      = "shared_buffers"
  server_id = azurerm_postgresql_flexible_server.iq_db.id
  value     = "2097152"
}


resource "azurerm_postgresql_flexible_server_configuration" "work_mem" {
  name      = "work_mem"
  server_id = azurerm_postgresql_flexible_server.iq_db.id
  value     = "16384"
}


resource "azurerm_postgresql_flexible_server_configuration" "maintenance_work_mem" {
  name      = "maintenance_work_mem"
  server_id = azurerm_postgresql_flexible_server.iq_db.id
  value     = "524288"
}


resource "azurerm_postgresql_flexible_server_configuration" "effective_cache_size" {
  name      = "effective_cache_size"
  server_id = azurerm_postgresql_flexible_server.iq_db.id
  value     = "8388608"
}


resource "azurerm_postgresql_flexible_server_firewall_rule" "aks_access" {
  name             = "allow-aks-subnet"
  server_id        = azurerm_postgresql_flexible_server.iq_db.id
  start_ip_address = cidrhost(var.aks_subnet_cidr, 0)
  end_ip_address   = cidrhost(var.aks_subnet_cidr, -1)
}
