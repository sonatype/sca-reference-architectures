# Private DNS Zone for PostgreSQL
resource "azurerm_private_dns_zone" "iq_db_dns" {
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.iq_rg.name

  tags = {
    Name = "private-dns-zone-postgres"
  }
}

# Private DNS Zone Virtual Network Link
resource "azurerm_private_dns_zone_virtual_network_link" "iq_db_dns_link" {
  name                  = "vnetlink-ref-arch-iq-db"
  resource_group_name   = azurerm_resource_group.iq_rg.name
  private_dns_zone_name = azurerm_private_dns_zone.iq_db_dns.name
  virtual_network_id    = azurerm_virtual_network.iq_vnet.id
  registration_enabled  = false

  tags = {
    Name = "privatelink-postgres-database"
  }
}

# PostgreSQL Flexible Server
resource "azurerm_postgresql_flexible_server" "iq_db" {
  name                          = "psql-ref-arch-iq"
  resource_group_name           = azurerm_resource_group.iq_rg.name
  location                      = azurerm_resource_group.iq_rg.location
  version                       = var.postgres_version
  delegated_subnet_id           = azurerm_subnet.db_subnet.id
  private_dns_zone_id           = azurerm_private_dns_zone.iq_db_dns.id
  administrator_login           = var.db_username
  administrator_password        = var.db_password
  zone                          = "1"
  public_network_access_enabled = false

  storage_mb                   = var.db_storage_mb
  auto_grow_enabled            = var.db_auto_grow_enabled
  backup_retention_days        = var.db_backup_retention_days
  geo_redundant_backup_enabled = var.db_geo_redundant_backup_enabled

  sku_name = var.db_sku_name

  dynamic "high_availability" {
    for_each = var.db_high_availability_enabled ? [1] : []
    content {
      mode                      = "ZoneRedundant"
      standby_availability_zone = "2"
    }
  }

  authentication {
    active_directory_auth_enabled = false
    password_auth_enabled         = true
  }

  tags = {
    Name = "psql-ref-arch-iq"
  }

  depends_on = [azurerm_private_dns_zone_virtual_network_link.iq_db_dns_link]
}

# PostgreSQL Database
resource "azurerm_postgresql_flexible_server_database" "iq_database" {
  name      = var.db_name
  server_id = azurerm_postgresql_flexible_server.iq_db.id
  collation = "en_US.utf8"
  charset   = "utf8"
}

# PostgreSQL Firewall Rule (allow Azure services)
resource "azurerm_postgresql_flexible_server_firewall_rule" "allow_azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_postgresql_flexible_server.iq_db.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

