# Storage Account with Zone-Redundant Storage for HA
resource "azurerm_storage_account" "iq_storage_ha" {
  name                     = "strefarchiqha${random_string.storage_suffix.result}"
  resource_group_name      = azurerm_resource_group.iq_rg.name
  location                 = azurerm_resource_group.iq_rg.location
  account_tier             = var.storage_account_tier             # Premium for better performance
  account_replication_type = var.storage_account_replication_type # ZRS for zone redundancy
  account_kind             = "FileStorage"                        # Required for Premium file shares

  # Network security for HA
  network_rules {
    default_action = "Allow" # Allow access from Container Apps subnets
    bypass         = ["AzureServices", "Logging", "Metrics"]

    # Allow access from all private subnets for HA
    virtual_network_subnet_ids = azurerm_subnet.private_subnets[*].id
  }

  tags = merge(var.common_tags, {
    Name = "strefarchiqha"
  })
}

# Random string for storage account uniqueness
resource "random_string" "storage_suffix" {
  length  = 8
  special = false
  upper   = false
}

# Premium File Share for clustering (equivalent to AWS EFS)
resource "azurerm_storage_share" "iq_data_ha" {
  name                 = "iq-data-ha"
  storage_account_name = azurerm_storage_account.iq_storage_ha.name
  quota                = var.file_share_quota_gb
  enabled_protocol     = "SMB"

  metadata = {
    purpose = "nexus-iq-ha-clustering"
  }
}

# Container App Environment Storage for the HA file share
resource "azurerm_container_app_environment_storage" "iq_storage_ha" {
  name                         = "iq-storage-ha"
  container_app_environment_id = azurerm_container_app_environment.iq_env_ha.id
  account_name                 = azurerm_storage_account.iq_storage_ha.name
  share_name                   = azurerm_storage_share.iq_data_ha.name
  access_key                   = azurerm_storage_account.iq_storage_ha.primary_access_key
  access_mode                  = "ReadWrite"
}

# Backup vault for storage (if backup is enabled)
resource "azurerm_data_protection_backup_vault" "iq_backup_vault" {
  count               = var.enable_backup ? 1 : 0
  name                = "bv-ref-arch-iq-ha"
  resource_group_name = azurerm_resource_group.iq_rg.name
  location            = azurerm_resource_group.iq_rg.location
  datastore_type      = "VaultStore"
  redundancy          = "ZoneRedundant" # Zone redundant for HA

  tags = merge(var.common_tags, {
    Name = "bv-ref-arch-iq-ha"
  })
}

# Backup policy for file share
resource "azurerm_data_protection_backup_policy_blob_storage" "iq_backup_policy" {
  count                                  = var.enable_backup ? 1 : 0
  name                                   = "bp-ref-arch-iq-ha"
  vault_id                               = azurerm_data_protection_backup_vault.iq_backup_vault[0].id
  operational_default_retention_duration = "P30D" # 30 days retention

  backup_repeating_time_intervals = ["R/2023-05-15T02:30:00+00:00/P1D"] # Daily backups at 2:30 AM
}