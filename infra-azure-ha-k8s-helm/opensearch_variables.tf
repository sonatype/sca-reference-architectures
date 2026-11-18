# OpenSearch cluster built by this configuration (opensearch_cluster.tf), run by the OpenSearch
# Kubernetes Operator on two dedicated AKS node pools.
#
# With search_engine = "opensearch", Terraform builds the cluster unless opensearch_create is
# false, in which case opensearch_endpoint names a cluster you run yourself. The defaults are the
# Size M values; README.md, "Search Backend", gives every size.

variable "opensearch_create" {
  description = "Build the OpenSearch cluster with this configuration. Null, the default, means true whenever search_engine is \"opensearch\" and opensearch_endpoint is empty, so a deployment that sets opensearch_endpoint keeps the cluster it names. Set false to bring your own cluster through opensearch_endpoint, opensearch_username and opensearch_password."
  type        = bool
  default     = null
}

variable "opensearch_version" {
  description = "OpenSearch version the operator runs, the tag of the opensearchproject/opensearch image."
  type        = string
  default     = "3.7.0"

  validation {
    condition     = can(regex("^3\\.[0-9]+\\.[0-9]+$", var.opensearch_version))
    error_message = "opensearch_version must be a 3.x release such as \"3.7.0\"."
  }
}

variable "opensearch_operator_chart_version" {
  description = "Version of the opensearch-operator Helm chart from the OpenSearch project's chart repository."
  type        = string
  default     = "3.0.14"
}

variable "opensearch_data_node_count" {
  description = "Number of OpenSearch data nodes, one pod per AKS node, spread across the three zones. Three dedicated cluster manager nodes run beside them. With opensearch_create = false, set it to your own cluster's data node count, which the deploy uses for the shard counts."
  type        = number
  default     = 3

  validation {
    condition     = var.opensearch_data_node_count >= 1
    error_message = "opensearch_data_node_count must be at least 1."
  }
}

variable "opensearch_data_instance_type" {
  description = "VM size of the AKS nodes the data pods run on. Standard_D2ps_v6 at M, Standard_D4ps_v6 at L, Standard_E8ps_v6 at XL. When Azure has no capacity for it in a zone (ZonalAllocationFailed), use the same size from another series with as many vCPUs and as much memory, such as Standard_D2as_v6."
  type        = string
  default     = "Standard_D2ps_v6"
}

variable "opensearch_manager_instance_type" {
  description = "VM size of the AKS nodes the cluster manager pods run on. Standard_D2pls_v6 at M and L, Standard_D2ps_v6 at XL."
  type        = string
  default     = "Standard_D2pls_v6"
}

variable "opensearch_data_disk_gb" {
  description = "Size in GB of the Premium SSD volume each data pod gets. The size sets the disk's performance tier: 128 (P10) at M, 256 (P15) at L and XL."
  type        = number
  default     = 128
}

variable "opensearch_manager_disk_gb" {
  description = "Size in GB of the Premium SSD volume each cluster manager pod keeps its cluster state on."
  type        = number
  default     = 32
}

variable "opensearch_node_disk_gb" {
  description = "Operating system disk size in GB of each AKS node in the two OpenSearch node pools."
  type        = number
  default     = 50
}

variable "opensearch_data_heap_gb" {
  description = "Java heap of each data pod in GB. Null, the default, takes half of the VM size's memory, at most 31, and never more than three quarters of what the pod can be given on that node."
  type        = number
  default     = null
}

variable "opensearch_manager_heap_gb" {
  description = "Java heap of each cluster manager pod in GB. Null derives it the same way as opensearch_data_heap_gb."
  type        = number
  default     = null
}

variable "opensearch_admin_password" {
  description = "Password of the OpenSearch admin user. Empty, the default, generates one."
  type        = string
  default     = ""
  sensitive   = true

  validation {
    condition     = !can(regex("CHANGE_ME", var.opensearch_admin_password))
    error_message = "opensearch_admin_password still holds a CHANGE_ME placeholder. Set a real value or leave it empty."
  }
}
