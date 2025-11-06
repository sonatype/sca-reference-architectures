
resource "azurerm_storage_account" "iq_storage" {
  name                     = "st${replace(lower("refarchiq"), "-", "")}${random_string.storage_suffix.result}"
  resource_group_name      = azurerm_resource_group.iq_rg.name
  location                 = azurerm_resource_group.iq_rg.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  min_tls_version          = "TLS1_2"


  https_traffic_only_enabled = true


  network_rules {
    default_action = "Allow"
    bypass         = ["AzureServices", "Logging", "Metrics"]
  }

  tags = {
    Name = "st-ref-arch-iq"
  }
}


resource "random_string" "storage_suffix" {
  length  = 6
  special = false
  upper   = false
}


resource "azurerm_storage_share" "iq_file_share" {
  name                 = "nexus-iq-data"
  storage_account_name = azurerm_storage_account.iq_storage.name
  quota                = var.file_share_quota
  enabled_protocol     = "SMB"

  depends_on = [azurerm_storage_account.iq_storage]
}


resource "azurerm_container_app_environment_storage" "iq_storage" {
  name                         = "nexus-iq-storage"
  container_app_environment_id = azurerm_container_app_environment.iq_env.id
  account_name                 = azurerm_storage_account.iq_storage.name
  share_name                   = azurerm_storage_share.iq_file_share.name
  access_key                   = azurerm_storage_account.iq_storage.primary_access_key
  access_mode                  = "ReadWrite"

  depends_on = [
    azurerm_storage_share.iq_file_share,
    azurerm_container_app_environment.iq_env
  ]
}