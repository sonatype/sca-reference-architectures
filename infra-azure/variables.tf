
variable "azure_region" {
  description = "Azure region for resources"
  type        = string
  default     = "West US 2"
}


variable "cluster_name" {
  description = "Name prefix for every resource this deployment creates, so several deployments can share one Azure subscription without colliding. The default reproduces the names this configuration has always used, so leaving it alone changes nothing. Change it and the resource group, virtual network, container app and its environment, Log Analytics workspace, Application Insights, public IP and its DNS label, Application Gateway, Key Vault, storage account, PostgreSQL Flexible Server and the private DNS zone link all move with it. Lowercase letters, digits and hyphens only, starting with a letter, 3 to 14 characters: the Key Vault name is built as kv-<cluster_name>-<6 random characters> and Azure caps a Key Vault name at 24."
  type        = string
  default     = "ref-arch-iq"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.cluster_name))
    error_message = "cluster_name must be lowercase letters, digits and hyphens, starting with a letter and ending with a letter or digit. The storage account name strips the hyphens and Azure allows only lowercase alphanumerics there."
  }

  validation {
    condition     = length(var.cluster_name) >= 3 && length(var.cluster_name) <= 14
    error_message = "cluster_name must be 3 to 14 characters. The longest name built from it is the Key Vault, kv-<cluster_name>-<6 random characters>, which Azure caps at 24."
  }
}


variable "vnet_cidr" {
  description = "CIDR block for Virtual Network"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for public subnet (Application Gateway)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for private subnet (Container Apps)"
  type        = string
  default     = "10.0.8.0/23"
}

variable "db_subnet_cidr" {
  description = "CIDR block for database subnet"
  type        = string
  default     = "10.0.30.0/24"
}


variable "container_cpu" {
  description = "CPU allocation for container (0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 4.0)"
  type        = number
  default     = 4.0
}

variable "container_memory" {
  description = "Memory allocation for container in Gi (0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 8Gi)"
  type        = string
  default     = "8Gi"
}

variable "iq_docker_image" {
  description = "Docker image for Nexus IQ Server"
  type        = string
  default     = "sonatype/nexus-iq-server:latest"
}

variable "java_opts" {
  description = "Java options for IQ Server"
  type        = string
  default     = "-Xms6g -Xmx6g -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
}


variable "db_name" {
  description = "Database name"
  type        = string
  default     = "nexusiq"
}

variable "db_username" {
  description = "Database administrator username"
  type        = string
  default     = "nexusiq"
}

variable "db_password" {
  description = "Database administrator password"
  type        = string
  sensitive   = true
}

variable "postgres_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "15"
}

variable "db_sku_name" {
  description = "Database SKU name. Scale with number of IQ nodes: 8 vCores for 1-3 nodes, 16 vCores for 3-4 nodes."
  type        = string
  default     = "GP_Standard_D8s_v3"
}

variable "db_storage_mb" {
  description = "Database storage in MB"
  type        = number
  default     = 524288
}

variable "db_auto_grow_enabled" {
  description = "Enable auto grow for database storage"
  type        = bool
  default     = true
}

variable "db_backup_retention_days" {
  description = "Database backup retention period in days"
  type        = number
  default     = 7
}

variable "db_geo_redundant_backup_enabled" {
  description = "Enable geo-redundant backups"
  type        = bool
  default     = false
}

variable "db_high_availability_enabled" {
  description = "Enable high availability for database"
  type        = bool
  default     = false
}


variable "app_gateway_sku_name" {
  description = "Application Gateway SKU name"
  type        = string
  default     = "Standard_v2"
}

variable "app_gateway_sku_tier" {
  description = "Application Gateway SKU tier"
  type        = string
  default     = "Standard_v2"
}

variable "app_gateway_capacity" {
  description = "Application Gateway capacity"
  type        = number
  default     = 2
}

variable "ssl_certificate_path" {
  description = "Path to SSL certificate file (optional)"
  type        = string
  default     = ""
}

variable "ssl_certificate_password" {
  description = "Password for SSL certificate (optional)"
  type        = string
  sensitive   = true
  default     = ""
}


variable "storage_account_tier" {
  description = "Storage account tier (Standard, Premium)"
  type        = string
  default     = "Standard"
}

variable "storage_account_replication_type" {
  description = "Storage account replication type (LRS, ZRS, GRS, RAGRS)"
  type        = string
  default     = "LRS"
}

variable "file_share_quota" {
  description = "File share quota in GB"
  type        = number
  default     = 500
}


variable "log_retention_days" {
  description = "Log Analytics workspace retention in days"
  type        = number
  default     = 30
}


variable "enable_monitoring" {
  description = "Enable Application Insights monitoring"
  type        = bool
  default     = true
}


variable "key_vault_sku_name" {
  description = "Key Vault SKU name"
  type        = string
  default     = "standard"
}


# =============================================================================
# SEARCH BACKEND (Lucene or self-managed OpenSearch)
# =============================================================================
# search_engine selects which engine IQ Server's config.yml points to, through
# the conditional `search:` block in container_app.tf. Azure has no first-party
# managed OpenSearch, so "opensearch" means a cluster you run yourself on Azure
# Virtual Machines and reach over basic auth. This configuration does not
# provision that cluster: you supply its endpoint, so switching engines never
# destroys a cluster or its indexed data. README.md has the cluster
# specification and the build steps.

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

  validation {
    condition     = var.search_engine != "opensearch" || length(var.opensearch_endpoint) > 0
    error_message = "opensearch_endpoint must be set when search_engine is 'opensearch'."
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
  description = "User name IQ Server authenticates to OpenSearch with. Mandatory on this connection type, so it has no usable default."
  type        = string
  default     = ""

  validation {
    condition     = var.search_engine != "opensearch" || length(var.opensearch_username) > 0
    error_message = "opensearch_username must be set when search_engine is 'opensearch'."
  }
}

variable "opensearch_password" {
  description = "Password for opensearch_username. Delivered to the container app as a secret rather than a plain environment variable, which is the route db_password already takes; it is not copied into Key Vault, because nothing would read it back and a second copy is a second thing to rotate. sensitive = true only keeps it out of CLI output: Terraform holds every variable in the state file as plain text, so treat terraform.tfstate as a secret, keep it in a backend that encrypts at rest and restrict who can read it. Keep the value in terraform.tfvars, which is gitignored, and never in terraform.tfvars.example."
  type        = string
  default     = ""
  sensitive   = true

  validation {
    condition     = var.search_engine != "opensearch" || length(var.opensearch_password) > 0
    error_message = "opensearch_password must be set when search_engine is 'opensearch'."
  }
}

variable "opensearch_index_replicas" {
  description = "Replicas per Nexus One index shard, written as nexusOne.connection.nexusOneIndexReplicas. A single-data-node cluster cannot place a replica, so 0 is the only workable value at XS and S. Bounds-checked 0 to 10 by IQ Server itself."
  type        = number
  default     = 0

  validation {
    condition     = var.opensearch_index_replicas >= 0 && var.opensearch_index_replicas <= 10
    error_message = "opensearch_index_replicas must be between 0 and 10."
  }
}


variable "common_tags" {
  description = "Tags merged into every resource this root creates, on top of the Name and project tags it sets itself. A key you supply with one of those names replaces it, which is why project is lowercase: Azure treats tag names as case-insensitive, so a map holding both Project and project would send one name twice. Put the values in terraform.tfvars, which is gitignored, rather than in terraform.tfvars.example."
  type        = map(string)
  default     = {}
}