# Azure Kubernetes Service (AKS) Cluster
resource "azurerm_kubernetes_cluster" "iq_aks" {
  name                = "aks-${var.cluster_name}"
  location            = azurerm_resource_group.iq_rg.location
  resource_group_name = azurerm_resource_group.iq_rg.name
  dns_prefix          = var.cluster_name
  kubernetes_version  = var.kubernetes_version

  # Enable automatic upgrades
  automatic_channel_upgrade = "stable"

  # Default node pool
  default_node_pool {
    name                = "system"
    vm_size             = var.node_instance_type
    vnet_subnet_id      = azurerm_subnet.aks_subnet.id
    zones               = local.availability_zones
    enable_auto_scaling = true
    min_count           = var.node_group_min_size
    max_count           = var.node_group_max_size
    os_disk_size_gb     = var.node_disk_size
    os_disk_type        = "Managed"
    type                = "VirtualMachineScaleSets"

    # Enable node public IP for outbound connectivity
    enable_node_public_ip = false

    # Node labels for system workloads
    node_labels = {
      "nodepool-type" = "system"
      "environment"   = var.environment
      "workload"      = "system"
    }

    tags = merge(local.common_tags, {
      Name = "aks-${var.cluster_name}-system-nodepool"
    })
  }

  # Identity configuration - use SystemAssigned managed identity
  identity {
    type = "SystemAssigned"
  }

  # Network configuration
  network_profile {
    network_plugin     = "azure"
    network_policy     = "azure"
    dns_service_ip     = "10.2.0.10"
    service_cidr       = "10.2.0.0/16"
    load_balancer_sku  = "standard"
    outbound_type      = "loadBalancer"
  }

  # Enable RBAC (Kubernetes RBAC only, no Azure AD integration)
  role_based_access_control_enabled = true

  # Add-ons
  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.iq_logs.id
  }

  # Enable Azure Policy for Kubernetes
  azure_policy_enabled = true

  # HTTP Application Routing (disabled, we use Application Gateway)
  http_application_routing_enabled = false

  # Key Vault Secrets Provider
  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "2m"
  }

  tags = merge(local.common_tags, {
    Name = "aks-${var.cluster_name}"
  })

  depends_on = [
    azurerm_subnet.aks_subnet
  ]
}

# User node pool for application workloads
resource "azurerm_kubernetes_cluster_node_pool" "user_pool" {
  name                  = "user"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.iq_aks.id
  vm_size               = var.node_instance_type
  vnet_subnet_id        = azurerm_subnet.aks_subnet.id
  zones                 = local.availability_zones
  enable_auto_scaling   = true
  min_count             = var.node_group_min_size
  max_count             = var.node_group_max_size
  os_disk_size_gb       = var.node_disk_size
  os_disk_type          = "Managed"
  mode                  = "User"

  # Node labels for application workloads
  node_labels = {
    "nodepool-type" = "user"
    "environment"   = var.environment
    "workload"      = "application"
  }

  # Node taints to ensure only application workloads run here
  node_taints = []

  tags = merge(local.common_tags, {
    Name = "aks-${var.cluster_name}-user-nodepool"
  })
}

# Log Analytics Workspace for AKS monitoring
resource "azurerm_log_analytics_workspace" "iq_logs" {
  name                = "log-${var.cluster_name}"
  location            = azurerm_resource_group.iq_rg.location
  resource_group_name = azurerm_resource_group.iq_rg.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days

  tags = merge(local.common_tags, {
    Name = "log-${var.cluster_name}"
  })
}

# Application Insights for application monitoring
resource "azurerm_application_insights" "iq_insights" {
  name                = "appi-${var.cluster_name}"
  location            = azurerm_resource_group.iq_rg.location
  resource_group_name = azurerm_resource_group.iq_rg.name
  workspace_id        = azurerm_log_analytics_workspace.iq_logs.id
  application_type    = "web"

  tags = merge(local.common_tags, {
    Name = "appi-${var.cluster_name}"
  })
}

# Role assignment for AKS to pull images from ACR (if needed)
# Uncomment if using Azure Container Registry
# resource "azurerm_role_assignment" "aks_acr" {
#   principal_id                     = azurerm_kubernetes_cluster.iq_aks.kubelet_identity[0].object_id
#   role_definition_name             = "AcrPull"
#   scope                            = azurerm_container_registry.acr.id
#   skip_service_principal_aad_check = true
# }

# Role assignment for AKS to access storage account
resource "azurerm_role_assignment" "aks_storage_contributor" {
  principal_id         = azurerm_kubernetes_cluster.iq_aks.kubelet_identity[0].object_id
  role_definition_name = "Storage Account Contributor"
  scope                = azurerm_storage_account.iq_storage.id

  depends_on = [
    azurerm_kubernetes_cluster.iq_aks,
    azurerm_storage_account.iq_storage
  ]
}

# Wait for cluster to be ready before creating Kubernetes resources
resource "null_resource" "wait_for_cluster" {
  provisioner "local-exec" {
    command = "sleep 60"
  }

  depends_on = [
    azurerm_kubernetes_cluster.iq_aks,
    azurerm_kubernetes_cluster_node_pool.user_pool
  ]
}
