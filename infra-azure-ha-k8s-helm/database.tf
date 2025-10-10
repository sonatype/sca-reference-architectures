# Private DNS Zone for PostgreSQL
resource "azurerm_private_dns_zone" "postgres" {
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.iq_rg.name

  tags = merge(local.common_tags, {
    Name = "pdns-postgres-${var.cluster_name}"
  })
}

# Link the private DNS zone to the virtual network
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

# PostgreSQL Flexible Server with Zone Redundancy for HA
resource "azurerm_postgresql_flexible_server" "iq_db" {
  name                   = "psql-${var.cluster_name}"
  resource_group_name    = azurerm_resource_group.iq_rg.name
  location               = azurerm_resource_group.iq_rg.location
  version                = var.postgres_version
  delegated_subnet_id    = azurerm_subnet.db_subnet.id
  private_dns_zone_id    = azurerm_private_dns_zone.postgres.id
  administrator_login    = var.database_username
  administrator_password = var.database_password

  # Disable public network access for security
  public_network_access_enabled = false

  # Zone redundancy for high availability (equivalent to Aurora Multi-AZ)
  zone = "1"
  high_availability {
    mode                      = var.db_high_availability_mode # ZoneRedundant
    standby_availability_zone = "2"
  }

  # Storage configuration (64GB minimum for zone-redundant)
  storage_mb   = var.db_storage_mb
  storage_tier = var.db_storage_tier

  # SKU configuration (equivalent to Aurora db.r6g.large)
  sku_name = var.db_sku_name # GP_Standard_D4s_v3 = 4 vCores, 16GB RAM

  # Backup configuration
  backup_retention_days        = var.backup_retention_period
  geo_redundant_backup_enabled = var.db_geo_redundant_backup_enabled

  # Maintenance window
  maintenance_window {
    day_of_week  = 0 # Sunday
    start_hour   = 4
    start_minute = 0
  }

  # Create mode
  create_mode = "Default"

  tags = merge(local.common_tags, {
    Name = "psql-${var.cluster_name}"
  })

  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgres]
}

# PostgreSQL Database for Nexus IQ Server
resource "azurerm_postgresql_flexible_server_database" "iq_database" {
  name      = var.database_name
  server_id = azurerm_postgresql_flexible_server.iq_db.id
  collation = "en_US.utf8"
  charset   = "UTF8"
}

# PostgreSQL Configuration - Enable required extensions
resource "azurerm_postgresql_flexible_server_configuration" "extensions" {
  name      = "azure.extensions"
  server_id = azurerm_postgresql_flexible_server.iq_db.id
  value     = "uuid-ossp"
}

# PostgreSQL Configuration - Max connections
resource "azurerm_postgresql_flexible_server_configuration" "max_connections" {
  name      = "max_connections"
  server_id = azurerm_postgresql_flexible_server.iq_db.id
  value     = "200"
}

# PostgreSQL Configuration - Shared buffers
resource "azurerm_postgresql_flexible_server_configuration" "shared_buffers" {
  name      = "shared_buffers"
  server_id = azurerm_postgresql_flexible_server.iq_db.id
  value     = "2097152" # 2GB in 8KB pages
}

# PostgreSQL Configuration - Work mem
resource "azurerm_postgresql_flexible_server_configuration" "work_mem" {
  name      = "work_mem"
  server_id = azurerm_postgresql_flexible_server.iq_db.id
  value     = "16384" # 16MB in KB
}

# PostgreSQL Configuration - Maintenance work mem
resource "azurerm_postgresql_flexible_server_configuration" "maintenance_work_mem" {
  name      = "maintenance_work_mem"
  server_id = azurerm_postgresql_flexible_server.iq_db.id
  value     = "524288" # 512MB in KB
}

# PostgreSQL Configuration - Effective cache size
resource "azurerm_postgresql_flexible_server_configuration" "effective_cache_size" {
  name      = "effective_cache_size"
  server_id = azurerm_postgresql_flexible_server.iq_db.id
  value     = "8388608" # 8GB in 8KB pages
}

# PostgreSQL Firewall Rule - Allow access from AKS subnet
resource "azurerm_postgresql_flexible_server_firewall_rule" "aks_access" {
  name             = "allow-aks-subnet"
  server_id        = azurerm_postgresql_flexible_server.iq_db.id
  start_ip_address = cidrhost(var.aks_subnet_cidr, 0)
  end_ip_address   = cidrhost(var.aks_subnet_cidr, -1)
}
