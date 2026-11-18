# The two dedicated node pools the OpenSearch pods run on, one node per pod. Both are tainted so
# nothing else lands there, and set vm.max_map_count on the host so the operator runs no
# privileged init container. AKS spreads each pool across the three zones; the pods' zone spread
# and anti-affinity make it one pod per node and zone.

resource "azurerm_kubernetes_cluster_node_pool" "os_data" {
  count                       = local.opensearch_create ? 1 : 0
  name                        = "osdata"
  temporary_name_for_rotation = "osdatatmp"
  kubernetes_cluster_id       = azurerm_kubernetes_cluster.iq_aks.id
  vm_size                     = var.opensearch_data_instance_type
  vnet_subnet_id              = azurerm_subnet.aks_subnet.id
  zones                       = local.availability_zones
  auto_scaling_enabled        = false
  node_count                  = var.opensearch_data_node_count
  os_disk_size_gb             = var.opensearch_node_disk_gb
  os_disk_type                = "Managed"
  mode                        = "User"

  node_labels = {
    "workload"        = "opensearch"
    "opensearch-role" = "data"
  }

  node_taints = ["dedicated=opensearch:NoSchedule"]

  linux_os_config {
    sysctl_config {
      vm_max_map_count = 262144
    }
  }

  tags = merge(local.common_tags, {
    Name = "aks-${var.cluster_name}-osdata-nodepool"
  })
}

resource "azurerm_kubernetes_cluster_node_pool" "os_manager" {
  count                       = local.opensearch_create ? 1 : 0
  name                        = "osmgr"
  temporary_name_for_rotation = "osmgrtmp"
  kubernetes_cluster_id       = azurerm_kubernetes_cluster.iq_aks.id
  vm_size                     = var.opensearch_manager_instance_type
  vnet_subnet_id              = azurerm_subnet.aks_subnet.id
  zones                       = local.availability_zones
  auto_scaling_enabled        = false
  node_count                  = 3
  os_disk_size_gb             = var.opensearch_node_disk_gb
  os_disk_type                = "Managed"
  mode                        = "User"

  node_labels = {
    "workload"        = "opensearch"
    "opensearch-role" = "manager"
  }

  node_taints = ["dedicated=opensearch:NoSchedule"]

  linux_os_config {
    sysctl_config {
      vm_max_map_count = 262144
    }
  }

  tags = merge(local.common_tags, {
    Name = "aks-${var.cluster_name}-osmgr-nodepool"
  })
}
