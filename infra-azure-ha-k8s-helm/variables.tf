variable "azure_region" {
  description = "Azure region for infrastructure deployment"
  type        = string
  default     = "eastus2"
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
  description = "VM size for AKS worker nodes. The default is the Size M and L value, 8 vCPU and 64 GB. Size XL uses Standard_E16ps_v6."
  type        = string
  default     = "Standard_E8ps_v6"
}

variable "node_group_min_size" {
  description = "Minimum number of nodes in AKS node pool"
  type        = number
  default     = 2
}

variable "node_group_max_size" {
  description = "Maximum number of nodes in AKS node pool"
  type        = number
  default     = 6
}

variable "node_group_desired_size" {
  description = "Desired number of nodes in AKS node pool"
  type        = number
  default     = 3
}

variable "node_disk_size" {
  description = "Disk size in GB for AKS worker nodes"
  type        = number
  default     = 50
}


variable "postgres_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "15"
}

variable "db_sku_name" {
  description = "PostgreSQL Flexible Server SKU. The default, 16 vCores, is the Size XL value; M and L use GP_Standard_D8ds_v6, as the Sizing Guide in README.md gives."
  type        = string
  default     = "MO_Standard_E16ds_v6"
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
  description = "Quota in GB for Azure Files share"
  type        = number
  default     = 512
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


variable "nexus_iq_version" {
  description = "Version of Nexus IQ Server to deploy"
  type        = string
  default     = "1.195.0"
}

variable "nexus_iq_license" {
  description = "Base64 encoded Nexus IQ Server license"
  type        = string
  sensitive   = true
}

variable "nexus_iq_admin_password" {
  description = "Initial admin password for Nexus IQ Server"
  type        = string
  sensitive   = true
  default     = "admin123"
}

variable "nexus_iq_replica_count" {
  description = "Number of Nexus IQ Server replicas for high availability"
  type        = number
  default     = 3
}


variable "helm_chart_version" {
  description = "Version of the Nexus IQ Server HA Helm chart"
  type        = string
  default     = "195.0.0"
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

variable "enable_fluentd" {
  description = "Enable Fluentd for log aggregation"
  type        = bool
  default     = true
}

variable "enable_monitoring" {
  description = "Enable Application Insights monitoring"
  type        = bool
  default     = true
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
# SEARCH BACKEND (Lucene or self-managed OpenSearch)
# =============================================================================
# search_engine selects which engine IQ Server's config.yml should use. On this
# root IQ Server's configuration comes from helm-values.yaml rather than from
# Terraform, so helm-install.sh and helm-upgrade.sh read these values out of
# terraform.tfvars through search-values.sh and append the search: block to
# helm-values-runtime.yaml. Terraform itself only checks them.
#
# Azure has no first-party managed OpenSearch, so "opensearch" means a cluster
# you run yourself on Azure Virtual Machines and reach over basic auth. This
# configuration does not provision that cluster: you supply its endpoint, so
# switching engines never destroys a cluster or its indexed data. README.md has
# the cluster specification and the build steps.
#
# load_search_vars in search-values.sh reads terraform.tfvars, so it sees only
# what is written there. It applies the same defaults these variables declare
# to the port, TLS and replica settings, and the endpoint, user name and
# password have to be written there when search_engine is "opensearch".

variable "search_engine" {
  description = "Which search backend IQ Server's config.yml should use: \"lucene\" (default, embedded index, no external dependency) or \"opensearch\" (a self-managed OpenSearch cluster whose endpoint must be supplied in opensearch_endpoint)."
  type        = string
  default     = "lucene"

  validation {
    condition     = contains(["lucene", "opensearch"], var.search_engine)
    error_message = "search_engine must be one of: 'lucene', 'opensearch'."
  }
}

variable "opensearch_endpoint" {
  description = "Host name or IP address of the OpenSearch cluster's client endpoint, without a scheme or port (for example \"opensearch.internal.example.com\"). Required when search_engine is \"opensearch\"; ignored otherwise."
  type        = string
  default     = ""
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
  description = "User name IQ Server authenticates to OpenSearch with. Mandatory on this connection type, so it has no usable default."
  type        = string
  default     = ""
}

variable "opensearch_password" {
  description = "Password for opensearch_username. This root has no Key Vault, so helm-install.sh and helm-upgrade.sh read it out of terraform.tfvars and write it into helm-values-runtime.yaml, which that root's .gitignore excludes. That is the same route database_password already takes. sensitive = true only keeps it out of CLI output: Terraform holds every variable in the state file as plain text, so treat terraform.tfstate as a secret, keep it in a backend that encrypts at rest and restrict who can read it. Keep the value in terraform.tfvars, which is gitignored, and never in terraform.tfvars.example."
  type        = string
  default     = ""
  sensitive   = true
}

variable "opensearch_index_replicas" {
  description = "Replicas per Nexus One index shard, written as nexusOne.connection.nexusOneIndexReplicas. A single-data-node cluster cannot place a replica, so 0 is the only workable value there. Bounds-checked 0 to 10 by IQ Server itself."
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
}
