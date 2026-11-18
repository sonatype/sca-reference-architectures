# OpenSearch cluster built by this configuration (opensearch_cluster.tf).
#
# With search_engine = "opensearch", Terraform builds the cluster unless opensearch_create
# is false, in which case opensearch_endpoint names a cluster you run yourself. The defaults
# are the Size M values; README.md, "Search Backend", gives every size.

variable "opensearch_create" {
  description = "Build the OpenSearch cluster with this configuration. Null, the default, means true whenever search_engine is \"opensearch\". Set false to bring your own cluster through opensearch_endpoint, opensearch_username, opensearch_password and opensearch_ca_pem."
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
  description = "Number of OpenSearch data nodes. 1 at XS and S, where the one node also manages the cluster. 3 at M and above, which adds three dedicated cluster manager nodes and an internal load balancer in front of the data nodes. With opensearch_create = false, set it to your own cluster's data node count, because the deploy sets the Nexus One shard counts from it."
  type        = number
  default     = 3

  validation {
    condition     = var.opensearch_data_node_count == 1 || (var.opensearch_data_node_count >= 3 && var.opensearch_data_node_count <= 9)
    error_message = "opensearch_data_node_count must be 1, or 3 to 9. Two data nodes cannot keep a quorum of cluster managers, and the subnet layout has room for nine."
  }
}

variable "opensearch_data_instance_type" {
  description = "VM size of each OpenSearch data node. The default is the Size M value. XS uses Standard_D2pls_v6, S and M Standard_D2ps_v6, L Standard_D4ps_v6, XL Standard_E8ps_v6."
  type        = string
  default     = "Standard_D2ps_v6"
}

variable "opensearch_manager_instance_type" {
  description = "VM size of each dedicated cluster manager node, used only when opensearch_data_node_count is above 1. Standard_D2pls_v6 at M and L, Standard_D2ps_v6 at XL."
  type        = string
  default     = "Standard_D2pls_v6"
}

variable "opensearch_data_disk_gb" {
  description = "Size in GB of the Premium SSD data disk on each data node. The size sets the disk's performance tier: 32 (P4) at XS, 64 (P6) at S, 128 (P10) at M, 256 (P15) at L and XL."
  type        = number
  default     = 128

  validation {
    condition     = var.opensearch_data_disk_gb >= 32
    error_message = "opensearch_data_disk_gb must be at least 32."
  }
}

variable "opensearch_os_disk_gb" {
  description = "Size in GB of the Premium SSD operating system disk on every OpenSearch node. A cluster manager keeps its cluster state on this disk."
  type        = number
  default     = 30
}

variable "opensearch_data_heap_gb" {
  description = "Java heap of each data node in GB. Null, the default, takes half of the VM size's memory, at most 31."
  type        = number
  default     = null
}

variable "opensearch_manager_heap_gb" {
  description = "Java heap of each cluster manager node in GB. Null, the default, takes half of the VM size's memory, at most 31."
  type        = number
  default     = null
}

variable "opensearch_zones" {
  description = "Availability zones the OpenSearch nodes are spread across, node n of each role going to zone n. Empty, the default, uses zones 1, 2 and 3. Change it and apply again when a zone has no capacity for the VM size."
  type        = list(string)
  default     = []
}

variable "opensearch_subnet_cidr" {
  description = "CIDR block of the subnet the OpenSearch nodes and their load balancer use. Must sit inside vnet_cidr and overlap no other subnet. Node addresses are fixed inside it: data nodes from .11, cluster managers from .21, the load balancer at .100."
  type        = string
  default     = "10.0.50.0/24"
}

variable "opensearch_admin_password" {
  description = "Password of the OpenSearch admin user. Empty, the default, generates one. Stored in Key Vault and read by the nodes at boot. OpenSearch refuses a weak admin password, so a value you set needs upper and lower case letters, digits and a symbol."
  type        = string
  default     = ""
  sensitive   = true

  validation {
    condition     = !can(regex("CHANGE_ME", var.opensearch_admin_password))
    error_message = "opensearch_admin_password still holds a CHANGE_ME placeholder. Set a real value or leave it empty."
  }
}

variable "opensearch_ca_pem" {
  description = "The certificate authority that signed the OpenSearch cluster's certificate, base64 encoded, for a cluster using a private authority. IQ Server has no per-connection trust setting, so the entrypoint copies the JVM's own trust store, adds this authority to the copy, and names the copy with javax.net.ssl.trustStore. The JVM store is never replaced, because it also serves IQ Server's calls to the Sonatype data service. Leave empty for a certificate signed by a public authority. This is a public certificate and not a credential."
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^[A-Za-z0-9+/=\\s]*$", var.opensearch_ca_pem))
    error_message = "opensearch_ca_pem must be the certificate base64 encoded, for example base64 < ca.pem, not the PEM text itself. The entrypoint decodes it with base64 -d, which fails on a raw PEM and stops every replica from starting."
  }
}
