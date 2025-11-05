# Storage Account for Azure Files Premium (Zone-Redundant)
resource "azurerm_storage_account" "iq_storage" {
  name                     = "st${replace(var.cluster_name, "-", "")}iqha" # Storage account names must be lowercase and alphanumeric
  resource_group_name      = azurerm_resource_group.iq_rg.name
  location                 = azurerm_resource_group.iq_rg.location
  account_tier             = var.storage_account_tier             # Premium
  account_replication_type = var.storage_account_replication_type # ZRS (Zone-Redundant Storage)
  account_kind             = "FileStorage"                        # Required for Premium Files

  # Disable secure transfer for NFS (NFS doesn't use HTTPS)
  https_traffic_only_enabled = false

  # Minimum TLS version (not applicable for NFS)
  min_tls_version = "TLS1_2"

  # Network rules - allow access from AKS subnet
  # Note: Initially set to "Allow" to enable share creation, then can be restricted
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

# Azure Files Premium Share for Nexus IQ HA shared storage
resource "azurerm_storage_share" "iq_data" {
  name                 = "iq-data-ha"
  storage_account_name = azurerm_storage_account.iq_storage.name
  quota                = var.storage_share_quota_gb
  enabled_protocol     = "NFS"  # NFSv4.1 for better Linux compatibility and performance

  metadata = {
    environment = var.environment
    purpose     = "nexus-iq-ha-shared-storage"
  }
}

# Azure Files Premium Share for Nexus IQ cluster coordination
resource "azurerm_storage_share" "iq_cluster" {
  name                 = "iq-cluster-ha"
  storage_account_name = azurerm_storage_account.iq_storage.name
  quota                = 100 # 100GB for cluster coordination
  enabled_protocol     = "NFS"  # NFSv4.1 for better Linux compatibility and performance

  metadata = {
    environment = var.environment
    purpose     = "nexus-iq-ha-cluster-coordination"
  }
}

