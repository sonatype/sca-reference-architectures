
resource "azurerm_storage_account" "iq_storage" {
  name                     = "st${replace(var.cluster_name, "-", "")}iqha"
  resource_group_name      = azurerm_resource_group.iq_rg.name
  location                 = azurerm_resource_group.iq_rg.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "FileStorage"


  https_traffic_only_enabled = false


  min_tls_version = "TLS1_2"



  network_rules {
    default_action             = "Allow"
    bypass                     = ["AzureServices"]
    virtual_network_subnet_ids = [azurerm_subnet.aks_subnet.id]
    ip_rules                   = []
  }

  tags = merge(local.common_tags, {
    Name = "st-${var.cluster_name}-iq-ha"
  })
}


resource "azurerm_storage_share" "iq_data" {
  name                 = "iq-data-ha"
  storage_account_name = azurerm_storage_account.iq_storage.name
  quota                = var.storage_share_quota_gb
  enabled_protocol     = "NFS"

  metadata = {
    environment = var.environment
    purpose     = "nexus-iq-ha-shared-storage"
  }
}


resource "azurerm_storage_share" "iq_cluster" {
  name                 = "iq-cluster-ha"
  storage_account_name = azurerm_storage_account.iq_storage.name
  quota                = 100
  enabled_protocol     = "NFS"

  metadata = {
    environment = var.environment
    purpose     = "nexus-iq-ha-cluster-coordination"
  }
}

