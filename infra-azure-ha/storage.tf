
resource "azurerm_storage_account" "iq_storage_ha" {
  name                     = "strefarchiqha${random_string.storage_suffix.result}"
  resource_group_name      = azurerm_resource_group.iq_rg.name
  location                 = azurerm_resource_group.iq_rg.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "FileStorage"


  network_rules {
    default_action = "Allow"
    bypass         = ["AzureServices", "Logging", "Metrics"]


    virtual_network_subnet_ids = azurerm_subnet.private_subnets[*].id
  }

  tags = merge(var.common_tags, {
    Name = "strefarchiqha"
  })
}


resource "random_string" "storage_suffix" {
  length  = 8
  special = false
  upper   = false
}


resource "azurerm_storage_share" "iq_data_ha" {
  name                 = "iq-data-ha"
  storage_account_name = azurerm_storage_account.iq_storage_ha.name
  quota                = var.file_share_quota_gb
  enabled_protocol     = "SMB"

  metadata = {
    purpose = "nexus-iq-ha-clustering"
  }
}


resource "azurerm_container_app_environment_storage" "iq_storage_ha" {
  name                         = "iq-storage-ha"
  container_app_environment_id = azurerm_container_app_environment.iq_env_ha.id
  account_name                 = azurerm_storage_account.iq_storage_ha.name
  share_name                   = azurerm_storage_share.iq_data_ha.name
  access_key                   = azurerm_storage_account.iq_storage_ha.primary_access_key
  access_mode                  = "ReadWrite"
}


resource "azurerm_data_protection_backup_vault" "iq_backup_vault" {
  count               = var.enable_backup ? 1 : 0
  name                = "bv-ref-arch-iq-ha"
  resource_group_name = azurerm_resource_group.iq_rg.name
  location            = azurerm_resource_group.iq_rg.location
  datastore_type      = "VaultStore"
  redundancy          = "ZoneRedundant"

  tags = merge(var.common_tags, {
    Name = "bv-ref-arch-iq-ha"
  })
}


resource "azurerm_data_protection_backup_policy_blob_storage" "iq_backup_policy" {
  count                                  = var.enable_backup ? 1 : 0
  name                                   = "bp-ref-arch-iq-ha"
  vault_id                               = azurerm_data_protection_backup_vault.iq_backup_vault[0].id
  operational_default_retention_duration = "P30D"

  backup_repeating_time_intervals = ["R/2023-05-15T02:30:00+00:00/P1D"]
}