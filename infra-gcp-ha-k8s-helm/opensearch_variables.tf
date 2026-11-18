# OpenSearch cluster built by this configuration (opensearch_cluster.tf), run by the OpenSearch
# Kubernetes Operator on two dedicated GKE node pools.
#
# With search_engine = "opensearch", Terraform builds the cluster unless opensearch_create is
# false, in which case opensearch_endpoint names a cluster you run yourself. The defaults are the
# Size M values; README.md, "Search Backend", gives every size.

variable "opensearch_create" {
  description = "Build the OpenSearch cluster with this configuration. Null, the default, means true whenever search_engine is \"opensearch\". Set false to bring your own cluster through opensearch_endpoint, opensearch_username, opensearch_password and opensearch_ca_certificate."
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
  description = "Number of OpenSearch data nodes, one pod per GKE node, spread across opensearch_zones. Three dedicated cluster manager nodes run beside them. With opensearch_create = false, set it to your own cluster's data node count, which the deploy uses for the shard counts."
  type        = number
  default     = 3

  validation {
    condition     = var.opensearch_data_node_count >= 1
    error_message = "opensearch_data_node_count must be at least 1."
  }
}

variable "opensearch_data_instance_type" {
  description = "Machine type of the GKE nodes the data pods run on. c4a-standard-2 at M, c4a-standard-4 at L, c4a-highmem-8 at XL. When a C4A type is out of stock (ZONE_RESOURCE_POOL_EXHAUSTED), set opensearch_zones to a zone that has it first; if none has, an x86 C4 type with as many vCPUs, such as c4-standard-2, works too."
  type        = string
  default     = "c4a-standard-2"
}

variable "opensearch_manager_instance_type" {
  description = "Machine type of the GKE nodes the cluster manager pods run on. c4a-standard-1 at M and L, c4a-standard-2 at XL. The same out-of-stock fallback as opensearch_data_instance_type applies."
  type        = string
  default     = "c4a-standard-1"
}

variable "opensearch_data_disk_gb" {
  description = "Size in GB of the Hyperdisk Balanced volume each data pod gets. 100 at M, 150 at L, 250 at XL."
  type        = number
  default     = 100
}

variable "opensearch_manager_disk_gb" {
  description = "Size in GB of the volume each cluster manager pod keeps its cluster state on."
  type        = number
  default     = 20
}

variable "opensearch_node_disk_gb" {
  description = "Boot disk size in GB of each GKE node in the two OpenSearch node pools."
  type        = number
  default     = 50
}

variable "opensearch_data_heap_gb" {
  description = "Java heap of each data pod in GB. Null, the default, takes half of the machine type's memory, at most 31, and never more than three quarters of what the pod can be given on that node."
  type        = number
  default     = null
}

variable "opensearch_manager_heap_gb" {
  description = "Java heap of each cluster manager pod in GB. Null derives it the same way as opensearch_data_heap_gb."
  type        = number
  default     = null
}

variable "opensearch_zones" {
  description = "Zones the OpenSearch node pools use. Empty, the default, takes the first three zones of gcp_region. Change it and apply again when a zone has no capacity for the machine type (ZONE_RESOURCE_POOL_EXHAUSTED). One zone works too: the pools then place every node in it."
  type        = list(string)
  default     = []
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
