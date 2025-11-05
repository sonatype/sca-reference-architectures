
resource "azurerm_kubernetes_cluster" "iq_aks" {
  name                = "aks-${var.cluster_name}"
  location            = azurerm_resource_group.iq_rg.location
  resource_group_name = azurerm_resource_group.iq_rg.name
  dns_prefix          = var.cluster_name
  kubernetes_version  = var.kubernetes_version


  automatic_channel_upgrade = "stable"


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


    enable_node_public_ip = false


    node_labels = {
      "nodepool-type" = "system"
      "environment"   = var.environment
      "workload"      = "system"
    }

    tags = merge(local.common_tags, {
      Name = "aks-${var.cluster_name}-system-nodepool"
    })
  }


  identity {
    type = "SystemAssigned"
  }


  network_profile {
    network_plugin     = "azure"
    network_policy     = "azure"
    dns_service_ip     = "10.2.0.10"
    service_cidr       = "10.2.0.0/16"
    load_balancer_sku  = "standard"
    outbound_type      = "loadBalancer"
  }


  role_based_access_control_enabled = true


  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.iq_logs.id
  }


  azure_policy_enabled = true


  http_application_routing_enabled = false


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


  node_labels = {
    "nodepool-type" = "user"
    "environment"   = var.environment
    "workload"      = "application"
  }


  node_taints = []

  tags = merge(local.common_tags, {
    Name = "aks-${var.cluster_name}-user-nodepool"
  })
}


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











resource "azurerm_role_assignment" "aks_storage_contributor" {
  principal_id         = azurerm_kubernetes_cluster.iq_aks.identity[0].principal_id
  role_definition_name = "Storage Account Contributor"
  scope                = azurerm_storage_account.iq_storage.id

  depends_on = [
    azurerm_kubernetes_cluster.iq_aks,
    azurerm_storage_account.iq_storage
  ]
}


resource "azurerm_role_assignment" "aks_network_contributor" {
  principal_id         = azurerm_kubernetes_cluster.iq_aks.identity[0].principal_id
  role_definition_name = "Network Contributor"
  scope                = azurerm_virtual_network.iq_vnet.id

  depends_on = [
    azurerm_kubernetes_cluster.iq_aks,
    azurerm_virtual_network.iq_vnet
  ]
}


resource "azurerm_role_assignment" "aks_nsg_contributor_public" {
  principal_id         = azurerm_kubernetes_cluster.iq_aks.identity[0].principal_id
  role_definition_name = "Network Contributor"
  scope                = azurerm_network_security_group.public_nsg.id

  depends_on = [
    azurerm_kubernetes_cluster.iq_aks,
    azurerm_network_security_group.public_nsg
  ]
}

resource "azurerm_role_assignment" "aks_nsg_contributor_aks" {
  principal_id         = azurerm_kubernetes_cluster.iq_aks.identity[0].principal_id
  role_definition_name = "Network Contributor"
  scope                = azurerm_network_security_group.aks_nsg.id

  depends_on = [
    azurerm_kubernetes_cluster.iq_aks,
    azurerm_network_security_group.aks_nsg
  ]
}

resource "azurerm_role_assignment" "aks_nsg_contributor_db" {
  principal_id         = azurerm_kubernetes_cluster.iq_aks.identity[0].principal_id
  role_definition_name = "Network Contributor"
  scope                = azurerm_network_security_group.db_nsg.id

  depends_on = [
    azurerm_kubernetes_cluster.iq_aks,
    azurerm_network_security_group.db_nsg
  ]
}


resource "null_resource" "wait_for_cluster" {
  provisioner "local-exec" {
    command = "sleep 60"
  }

  depends_on = [
    azurerm_kubernetes_cluster.iq_aks

  ]
}
