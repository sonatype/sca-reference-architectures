
variable "azure_region" {
  description = "Azure region for resources"
  type        = string
  default     = "East US"
}


variable "cluster_name" {
  description = "Name prefix for every resource this deployment creates, so several deployments can share one Azure subscription without colliding. Change it and the resource group, virtual network, container app and its environment, Log Analytics workspace, Application Insights, Key Vault, storage account, PostgreSQL Flexible Server and the private DNS zone link all move with it. Lowercase letters, digits and hyphens only, starting with a letter, 3 to 14 characters: the Key Vault name is built as kv-<cluster_name>-<6 random characters> and Azure caps a Key Vault name at 24."
  type        = string
  default     = "ref-arch-iq"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", var.cluster_name))
    error_message = "cluster_name must be lowercase letters, digits and single hyphens, starting with a letter and ending with a letter or digit. The storage account name strips the hyphens and Azure allows only lowercase alphanumerics there, and the Key Vault name kv-<cluster_name>-<suffix> may not hold two hyphens in a row."
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
  description = "CIDR block for the public subnet. It is created with its NSG and holds no resources."
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
  description = "vCPU for the IQ Server container. The default is the Size M value. It must fit on one node of workload_profile_type."
  type        = number
  default     = 8.0
}

variable "container_memory" {
  description = "Memory for the IQ Server container. The default is the Size M value. It must fit on one node of workload_profile_type."
  type        = string
  default     = "64Gi"
}

variable "workload_profile_type" {
  description = "Azure Container Apps dedicated workload profile type, which sets the cores and memory of the node the container runs on. E8 is 8 cores and 64 GB, for Size M. E4 is 4 cores and 32 GB, for Size S. D4 is 4 cores and 16 GB, for Size XS."
  type        = string
  default     = "E8"
}

variable "iq_docker_image" {
  description = "Docker image for Nexus IQ Server"
  type        = string
  default     = "sonatype/nexus-iq-server:latest"
}

variable "java_opts" {
  description = "Java options for IQ Server"
  type        = string
  default     = "-Xms48g -Xmx48g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/Java_Heap_logs -XX:+CrashOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
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
  description = "PostgreSQL major version. An existing deployment sets the version it runs; upgrading is the deployer's decision."
  type        = string
  default     = "18"
}

variable "db_sku_name" {
  description = "PostgreSQL Flexible Server SKU. The default, 8 vCores and 64 GB, is the Size M value; the Sizing Guide in README.md gives XS and S."
  type        = string
  default     = "MO_Standard_E8ds_v6"
}

variable "db_storage_mb" {
  description = "Database storage in MB when the server is created. Flexible Server accepts 32768, 65536, 131072, 262144, 524288 and larger powers of two. The default, 128 GB, is the Size M value. Terraform ignores later changes, so raise a live server's storage with the Azure CLI or portal."
  type        = number
  default     = 131072
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



variable "log_share_quota_gb" {
  description = "Quota in GB of the Azure Files share mounted at /var/log/nexus-iq-server, which holds IQ Server's application, request and audit logs off the container's ephemeral storage. A full share stops IQ Server writing those files but leaves the container running. With storage_account_tier = \"Premium\" the share is billed on this full size and cannot be below 100."
  type        = number
  default     = 128
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
  description = "Password for opensearch_username. Delivered to the container app as a secret rather than a plain environment variable, which is the route db_password already takes; it is not copied into Key Vault, because nothing would read it back and a second copy is a second thing to rotate. sensitive = true only keeps it out of CLI output: Terraform holds every variable in the state file as plain text, so treat terraform.tfstate as a secret, keep it in a backend that encrypts at rest and restrict who can read it. Keep the value in terraform.tfvars, which is gitignored, and never in terraform.tfvars.example."
  type        = string
  default     = ""
  sensitive   = true
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
  description = "Tags merged into every resource this root creates, alongside the Name and project tags it sets itself. A project key you supply replaces this root's, and Name always stays this root's. project is lowercase because Azure treats tag names as case-insensitive, so a map holding both Project and project would send one name twice. Put the values in terraform.tfvars, which is gitignored, rather than in terraform.tfvars.example."
  type        = map(string)
  default     = {}
}