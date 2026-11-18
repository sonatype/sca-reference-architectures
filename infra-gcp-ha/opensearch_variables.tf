# OpenSearch cluster built by this configuration (opensearch_cluster.tf).
#
# With search_engine = "opensearch", Terraform builds the cluster unless opensearch_create
# is false, in which case opensearch_endpoint names a cluster you run yourself. The defaults
# are the Size M values; README.md, "Search Backend", gives every size.

variable "opensearch_create" {
  description = "Build the OpenSearch cluster with this configuration. Null, the default, means true whenever search_engine is \"opensearch\" and opensearch_endpoint is empty, so a deployment that sets opensearch_endpoint keeps the cluster it names. Set false to bring your own cluster through opensearch_endpoint, opensearch_username, opensearch_password and opensearch_ca_certificate."
  type        = bool
  default     = null
}

variable "opensearch_version" {
  description = "OpenSearch version installed on every node, from the 3.x package repository."
  type        = string
  default     = "3.7.0"

  validation {
    condition     = can(regex("^3\\.[0-9]+\\.[0-9]+$", var.opensearch_version))
    error_message = "opensearch_version must be a 3.x release such as \"3.7.0\"."
  }
}

variable "opensearch_data_node_count" {
  description = "Number of OpenSearch data nodes. 1 at XS and S, where the one node also manages the cluster. 3 at M and above, which adds three dedicated cluster manager nodes and an internal load balancer in front of the data nodes. With opensearch_create = false, set it to your own cluster's data node count, which the deploy uses for the shard counts."
  type        = number
  default     = 3

  validation {
    condition     = var.opensearch_data_node_count == 1 || var.opensearch_data_node_count >= 3
    error_message = "opensearch_data_node_count must be 1, or 3 or more. Two data nodes cannot keep a quorum of cluster managers."
  }
}

variable "opensearch_data_instance_type" {
  description = "Machine type of each OpenSearch data node. The default is the Size M value. XS uses c4a-standard-1, S and M c4a-standard-2, L c4a-standard-4, XL c4a-highmem-8. When a C4A type is out of stock in every zone of the region (ZONE_RESOURCE_POOL_EXHAUSTED), an x86 C4 type with at least as many vCPUs, such as c4-standard-2, works too: the nodes then boot the x86 Ubuntu image. The heap default assumes the C4A memory of 4 GB per vCPU, and C4 has less (c4-standard-2 has 7 GB, c4-standard-4 15 GB), so set opensearch_data_heap_gb to half of it, 3 for c4-standard-2."
  type        = string
  default     = "c4a-standard-2"
}

variable "opensearch_manager_instance_type" {
  description = "Machine type of each dedicated cluster manager node, used only when opensearch_data_node_count is above 1. c4a-standard-1 at M and L, c4a-standard-2 at XL. When a C4A type is out of stock, an x86 C4 type such as c4-standard-2 works too; it has 7 GB, so set opensearch_manager_heap_gb to 3 with it."
  type        = string
  default     = "c4a-standard-1"
}

variable "opensearch_data_disk_gb" {
  description = "Size in GB of the Hyperdisk Balanced data disk on each data node. 25 at XS, 50 at S, 100 at M, 150 at L, 250 at XL."
  type        = number
  default     = 100

  validation {
    condition     = var.opensearch_data_disk_gb >= 10
    error_message = "opensearch_data_disk_gb must be at least 10."
  }
}

variable "opensearch_boot_disk_gb" {
  description = "Size in GB of the boot disk on every OpenSearch node. A cluster manager keeps its cluster state on this disk."
  type        = number
  default     = 20
}

variable "opensearch_boot_image" {
  description = "Boot image for the OpenSearch nodes. Empty, the default, picks Ubuntu 24.04 LTS for the machine type's architecture."
  type        = string
  default     = ""
}

variable "opensearch_data_heap_gb" {
  description = "Java heap of each data node in GB. Null, the default, takes half of the machine type's memory, at most 31."
  type        = number
  default     = null
}

variable "opensearch_manager_heap_gb" {
  description = "Java heap of each cluster manager node in GB. Null, the default, takes half of the machine type's memory, at most 31."
  type        = number
  default     = null
}

variable "opensearch_zones" {
  description = "Zones the OpenSearch nodes are spread across, node n of each role going to zone n. Empty, the default, uses this configuration's own zones. Change it and apply again when a zone has no capacity for the machine type (ZONE_RESOURCE_POOL_EXHAUSTED). If no zone has capacity, change opensearch_data_instance_type or opensearch_manager_instance_type instead."
  type        = list(string)
  default     = []
}

variable "opensearch_admin_password" {
  description = "Password of the OpenSearch admin user. Empty, the default, generates one. Stored in Secret Manager and read by the nodes at boot."
  type        = string
  default     = ""
  sensitive   = true

  validation {
    condition     = !can(regex("CHANGE_ME", var.opensearch_admin_password))
    error_message = "opensearch_admin_password still holds a CHANGE_ME placeholder. Set a real value or leave it empty."
  }
}
