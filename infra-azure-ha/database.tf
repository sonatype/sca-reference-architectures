# Private DNS Zone for PostgreSQL (required for private endpoints)
resource "azurerm_private_dns_zone" "postgres" {
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.iq_rg.name

  tags = merge(var.common_tags, {
    Name = "pdns-postgres-ha"
  })
}

# Link the private DNS zone to the virtual network
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

# PostgreSQL Flexible Server with Zone Redundancy (HA)
resource "azurerm_postgresql_flexible_server" "iq_db_ha" {
  name                   = "psqlfs-ref-arch-iq-ha"
  resource_group_name    = azurerm_resource_group.iq_rg.name
  location               = azurerm_resource_group.iq_rg.location
  version                = var.postgres_version
  delegated_subnet_id    = azurerm_subnet.db_subnet.id
  private_dns_zone_id    = azurerm_private_dns_zone.postgres.id
  administrator_login    = var.db_username
  administrator_password = var.db_password

  # Disable public network access when using VNet integration
  public_network_access_enabled = false

  # Zone redundancy for HA (equivalent to AWS Aurora Multi-AZ)
  zone = "1"
  high_availability {
    mode                      = var.db_high_availability_mode # ZoneRedundant
    standby_availability_zone = "2"
  }

  # Storage configuration
  storage_mb   = 65536 # 64GB initial
  storage_tier = "P6"  # Premium tier for better performance (P6 is minimum for 64GB)

  # SKU (Memory Optimized - matches AWS db.r6g.4xlarge)
  sku_name = var.db_sku_name # MO_Standard_E16s_v3 = 16 vCores, 128GB RAM

  # Backup configuration
  backup_retention_days        = var.db_backup_retention_days
  geo_redundant_backup_enabled = var.db_geo_redundant_backup_enabled

  # Security
  create_mode = "Default"

  # Maintenance window
  maintenance_window {
    day_of_week  = 0 # Sunday
    start_hour   = 4
    start_minute = 0
  }

  tags = merge(var.common_tags, {
    Name = "psqlfs-ref-arch-iq-ha"
  })

  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgres]
}

# Database for Nexus IQ Server
resource "azurerm_postgresql_flexible_server_database" "iq_database_ha" {
  name      = var.db_name
  server_id = azurerm_postgresql_flexible_server.iq_db_ha.id
  collation = "en_US.utf8"
  charset   = "utf8"
}

# PostgreSQL Configuration for IQ Server optimization (similar to AWS Aurora parameter groups)
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
  value     = "1000" # Log queries taking longer than 1 second
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

# Firewall rule to allow Container Apps private subnets
resource "azurerm_postgresql_flexible_server_firewall_rule" "container_apps" {
  count            = length(var.private_subnet_cidrs)
  name             = "AllowContainerApps-${count.index + 1}"
  server_id        = azurerm_postgresql_flexible_server.iq_db_ha.id
  start_ip_address = cidrhost(var.private_subnet_cidrs[count.index], 1)
  end_ip_address   = cidrhost(var.private_subnet_cidrs[count.index], -2)
}

# Additional firewall rule for Azure services
resource "azurerm_postgresql_flexible_server_firewall_rule" "azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_postgresql_flexible_server.iq_db_ha.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}