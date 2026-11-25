variable "azure_region" {
  description = "Azure region for infrastructure deployment"
  type        = string
  default     = "eastus"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "cluster_name" {
  description = "Name of the AKS cluster and the prefix for every resource this deployment creates, so several deployments can share one Azure subscription without colliding. Lowercase letters, digits and hyphens only, starting with a letter, and at most 18 characters once the hyphens are removed: the storage account name is built as st<cluster_name without hyphens>iqha, which Azure caps at 24. That name carries no random suffix, and a storage account name is globally unique across Azure, so a value nobody else has used is needed rather than merely one this subscription has not."
  type        = string
  default     = "nexus-iq-ha"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.cluster_name))
    error_message = "cluster_name must be lowercase letters, digits and hyphens, starting with a letter and ending with a letter or digit. The storage account name strips the hyphens and Azure allows only lowercase alphanumerics there."
  }

  validation {
    condition     = length(replace(var.cluster_name, "-", "")) >= 3 && length(replace(var.cluster_name, "-", "")) <= 18
    error_message = "cluster_name must be 3 to 18 characters once its hyphens are removed. The storage account name is built as st<cluster_name without hyphens>iqha, which Azure caps at 24."
  }
}


variable "vnet_cidr" {
  description = "CIDR block for Virtual Network"
  type        = string
  default     = "10.1.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for public subnet (Application Gateway)"
  type        = string
  default     = "10.1.1.0/24"
}

variable "aks_subnet_cidr" {
  description = "CIDR block for AKS subnet"
  type        = string
  default     = "10.1.10.0/23"
}

variable "db_subnet_cidr" {
  description = "CIDR block for database subnet"
  type        = string
  default     = "10.1.20.0/24"
}


variable "kubernetes_version" {
  description = "Kubernetes version for AKS cluster"
  type        = string
  default     = "1.36"
}

variable "node_instance_type" {
  description = "VM size of the AKS user node pool, where the IQ pods run. The default is the Size M value, 8 vCPU and 32 GB. Size L uses Standard_D16ps_v6 and Size XL Standard_E16ps_v6. When Azure has no capacity for it (ZonalAllocationFailed), set node_pool_zones to the zones that have it, or use the same size from another series with as many vCPUs and as much memory, such as Standard_D8as_v6."
  type        = string
  default     = "Standard_D8ps_v6"
}

variable "node_pool_zones" {
  description = "Availability zones of the IQ Server node pool. Empty, the default, uses zones 1, 2 and 3. When one zone has no capacity for node_instance_type (ZonalAllocationFailed), list the zones that do, for example [\"2\", \"3\"]."
  type        = list(string)
  default     = []
}

variable "system_node_instance_type" {
  description = "VM size of the AKS system node pool, which runs the AKS system pods only and does not change with size. Standard_D2pls_v6 is 2 vCPU and 4 GB (Arm), the AKS minimum for a system pool."
  type        = string
  default     = "Standard_D2pls_v6"
}

variable "system_node_count" {
  description = "Number of nodes in the AKS system node pool, a fixed count with no autoscaling. At least 2, so the system pods survive the loss of one node."
  type        = number
  default     = 2

  validation {
    condition     = var.system_node_count >= 2
    error_message = "system_node_count must be at least 2."
  }
}

variable "node_group_min_size" {
  description = "Minimum number of nodes in the AKS user node pool, one per IQ pod: 2 at Size M and L, 3 at Size XL."
  type        = number
  default     = 2
}

variable "node_group_max_size" {
  description = "Maximum number of nodes in the AKS user node pool: 3 at Size M, 4 at Size L, 5 at Size XL. Must be at least node_group_min_size."
  type        = number
  default     = 2
}

variable "node_group_desired_size" {
  description = "Nodes the AKS user node pool starts with: 2 at Size M and L, 3 at Size XL. Must be from node_group_min_size to node_group_max_size. After the pool exists the cluster autoscaler sets the count, so a later change here has no effect."
  type        = number
  default     = 2
}

variable "node_disk_size" {
  description = "Disk size in GB for AKS worker nodes"
  type        = number
  default     = 50
}


variable "postgres_version" {
  description = "PostgreSQL major version."
  type        = string
  default     = "18"
}

variable "db_sku_name" {
  description = "PostgreSQL Flexible Server SKU. The default, 4 vCPU and 32 GB, is the Size M value; L uses MO_Standard_E8ds_v6 and XL MO_Standard_E16ds_v6, as the Sizing Guide in README.md gives."
  type        = string
  default     = "MO_Standard_E4ds_v6"
}

variable "db_high_availability_mode" {
  description = "High availability mode for PostgreSQL (ZoneRedundant or SameZone)"
  type        = string
  default     = "ZoneRedundant"
}

variable "db_storage_mb" {
  description = "PostgreSQL storage in MB. Azure accepts 32768, 65536, 131072, 262144, 524288, 1048576 and larger powers of two. It sets the size when the server is created, and storage grows automatically past it. Terraform ignores later changes, so raise a live server's storage with the Azure CLI or portal."
  type        = number
  default     = 131072
}

variable "db_storage_tier" {
  description = "Storage tier for PostgreSQL (P10, P15, P20, etc.). P10 is the default for 128 GB."
  type        = string
  default     = "P10"
}

variable "database_name" {
  description = "Name of the PostgreSQL database"
  type        = string
  default     = "nexusiq"
}

variable "database_username" {
  description = "Username for PostgreSQL database"
  type        = string
  default     = "nexusiq"
}

variable "database_password" {
  description = "Password for PostgreSQL database"
  type        = string
  sensitive   = true

  validation {
    condition     = !can(regex("CHANGE_ME", var.database_password))
    error_message = "database_password still holds a CHANGE_ME placeholder. Set a real value in terraform.tfvars."
  }
}

variable "iq_admin_initial_password" {
  description = "Password for IQ Server's admin user, at least 12 characters. It is kept in a Kubernetes secret that helm-install.sh creates and the chart reads through iq_server.initialAdminPasswordSecret, and given to IQ Server as NXIQ_INITIAL_ADMIN_PASSWORD, which IQ Server reads only on its very first start, against an empty database. Changing it afterwards changes nothing: change the password in IQ Server instead."
  type        = string
  sensitive   = true

  validation {
    condition     = !can(regex("CHANGE_ME", var.iq_admin_initial_password)) && length(var.iq_admin_initial_password) >= 12
    error_message = "iq_admin_initial_password must be a real password of at least 12 characters, not a CHANGE_ME placeholder. Set it in terraform.tfvars."
  }
}

variable "backup_retention_period" {
  description = "Number of days to retain automated backups"
  type        = number
  default     = 7
}

variable "db_geo_redundant_backup_enabled" {
  description = "Enable geo-redundant backups for PostgreSQL (not supported in all regions)"
  type        = bool
  default     = false
}


variable "storage_account_tier" {
  description = "Storage account tier. Premium is required for NFS protocol (used in this Kubernetes deployment)."
  type        = string
  default     = "Premium"
}

variable "storage_account_replication_type" {
  description = "Storage account replication type (ZRS for zone-redundant)"
  type        = string
  default     = "ZRS"
}

variable "storage_share_quota_gb" {
  description = "Quota in GB for the Azure Files share. The default is the Size M value; L uses 1,536 and XL 4,096, as README.md gives. The share is Premium, so the quota is the provisioned size."
  type        = number
  default     = 500
}


variable "app_gateway_sku_name" {
  description = "SKU name for Application Gateway"
  type        = string
  default     = "Standard_v2"
}

variable "app_gateway_sku_tier" {
  description = "SKU tier for Application Gateway"
  type        = string
  default     = "Standard_v2"
}

variable "app_gateway_capacity" {
  description = "Capacity for Application Gateway (only used if autoscale is disabled)"
  type        = number
  default     = 2
}

variable "app_gateway_min_capacity" {
  description = "Minimum capacity for Application Gateway autoscale"
  type        = number
  default     = 2
}

variable "app_gateway_max_capacity" {
  description = "Maximum capacity for Application Gateway autoscale"
  type        = number
  default     = 10
}


variable "nexus_iq_replica_count" {
  description = "Number of Nexus IQ Server pods at start, the HPA minimum: 2 at Size M and L, 3 at Size XL."
  type        = number
  default     = 2
}


variable "helm_chart_version" {
  description = "Version of the Nexus IQ Server HA Helm chart. The chart sets the IQ Server image, so this also sets the IQ Server version."
  type        = string
  default     = "209.4.0"
}

variable "helm_namespace" {
  description = "Kubernetes namespace for Nexus IQ Server deployment"
  type        = string
  default     = "nexus-iq"
}

variable "agic_helm_version" {
  description = "Version of Application Gateway Ingress Controller Helm chart"
  type        = string
  default     = "1.7.2"
}

variable "aad_pod_identity_version" {
  description = "Version of AAD Pod Identity Helm chart"
  type        = string
  default     = "4.1.18"
}


variable "log_retention_days" {
  description = "Number of days to retain logs in Log Analytics"
  type        = number
  default     = 30
}


variable "ingress_hostname" {
  description = "Hostname for Nexus IQ Server ingress"
  type        = string
  default     = ""
}

variable "ingress_tls_enabled" {
  description = "Enable TLS for ingress"
  type        = bool
  default     = false
}


# =============================================================================
# SEARCH BACKEND (built-in index or self-managed OpenSearch)
# =============================================================================
# helm-install.sh and helm-upgrade.sh read the search settings through search-values.sh
# and write the search: block. "opensearch" means an OpenSearch cluster this configuration
# builds on AKS (opensearch_cluster.tf) unless opensearch_create is false, in which case
# opensearch_endpoint names a cluster you run yourself.

variable "search_engine" {
  description = "Search backend for IQ Server, with no default: \"opensearch\" uses an OpenSearch cluster for Advanced Search and the Nexus One index, built here unless opensearch_endpoint names one you run; \"builtin\" builds no OpenSearch, so Advanced Search uses IQ Server's built-in index, and Nexus One (IQ Server 1.210 and later) can keep its index in IQ Server's PostgreSQL database, chosen on the Nexus One setup page."
  type        = string

  validation {
    condition     = contains(["opensearch", "builtin"], var.search_engine)
    error_message = "search_engine must be \"opensearch\", for an OpenSearch cluster, or \"builtin\", for no OpenSearch: Advanced Search then uses IQ Server's built-in index, and Nexus One (IQ Server 1.210 and later) can keep its index in IQ Server's PostgreSQL database. Replace the CHANGE_ME placeholder in terraform.tfvars with one of them."
  }
}

variable "opensearch_endpoint" {
  description = "Host name or IP address of the OpenSearch cluster's client endpoint, without a scheme or port (for example \"opensearch.internal.example.com\"). Required when search_engine is \"opensearch\" and opensearch_create is false; ignored otherwise."
  type        = string
  default     = ""

  validation {
    condition     = !can(regex("CHANGE_ME", var.opensearch_endpoint))
    error_message = "opensearch_endpoint still holds a CHANGE_ME placeholder. Set a real value in terraform.tfvars."
  }
}

variable "opensearch_port" {
  description = "TCP port the OpenSearch cluster listens on. 9200 is the OpenSearch default."
  type        = number
  default     = 9200

  validation {
    condition     = var.opensearch_port > 0 && var.opensearch_port <= 65535
    error_message = "opensearch_port must be between 1 and 65535."
  }
}

variable "opensearch_use_tls" {
  description = "Whether IQ Server reaches OpenSearch over HTTPS. True builds an https:// URI and is the recommendation, because the basic-auth password is sent on every request. False builds http://, which IQ Server accepts and which sends that password in clear text, so use it only inside a private subnet you control. A private certificate authority needs its certificate added to a copy of the JVM trust store: see README.md."
  type        = bool
  default     = true
}

variable "opensearch_username" {
  description = "User name IQ Server authenticates to OpenSearch with. Empty, the default, means iq-server when this configuration builds the cluster; required for a cluster you bring."
  type        = string
  default     = ""
}

variable "opensearch_password" {
  description = "Password for opensearch_username. This root has no Key Vault, so helm-install.sh and helm-upgrade.sh read it out of terraform.tfvars and write it into helm-values-runtime.yaml, which that root's .gitignore excludes. That is the same route database_password already takes. sensitive = true only keeps it out of CLI output: Terraform holds every variable in the state file as plain text, so treat terraform.tfstate as a secret, keep it in a backend that encrypts at rest and restrict who can read it. Keep the value in terraform.tfvars, which is gitignored, and never in terraform.tfvars.example."
  type        = string
  default     = ""
  sensitive   = true

  validation {
    condition     = !can(regex("CHANGE_ME", var.opensearch_password))
    error_message = "opensearch_password still holds a CHANGE_ME placeholder. Set a real value in terraform.tfvars."
  }
}

variable "opensearch_index_replicas" {
  description = "Replicas per Nexus One index shard, written as nexusOne.connection.nexusOneIndexReplicas. Use 0 on one data node: it cannot place a replica, and 1 would leave the index yellow, which still serves reads and writes. Bounds-checked 0 to 10 by IQ Server itself."
  type        = number
  default     = 1

  validation {
    condition     = var.opensearch_index_replicas >= 0 && var.opensearch_index_replicas <= 10
    error_message = "opensearch_index_replicas must be between 0 and 10."
  }
}


variable "common_tags" {
  description = "Extra tags merged into every resource this root creates, on top of the four it sets itself: project, Environment, ManagedBy and Purpose. A key you supply overrides the one of those it matches, which is why project is lowercase here: Azure treats tag names as case-insensitive, so a map holding both Project and project would send one name twice. Put the values in terraform.tfvars, which is gitignored, rather than in terraform.tfvars.example."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for v in values(var.common_tags) : !can(regex("CHANGE_ME", v))])
    error_message = "common_tags still holds a CHANGE_ME placeholder. Set a real value in terraform.tfvars."
  }
}
