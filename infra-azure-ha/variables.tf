
variable "azure_region" {
  description = "Azure region for resources"
  type        = string
  default     = "East US 2"
}

variable "cluster_name" {
  description = "Name prefix for every resource this deployment creates, so several deployments can share one Azure subscription without colliding. Change it and the resource group, virtual network, container app and its environment, Log Analytics workspace, Application Insights, public IP and its DNS label, Application Gateway and its diagnostics, Key Vault, storage account, backup vault and policy, and PostgreSQL Flexible Server all move with it. Lowercase letters, digits and hyphens only, starting with a letter, 3 to 14 characters: the longest names built from it are the storage account and the Key Vault, both of which strip the hyphens and add 8 random characters, and Azure caps each at 24."
  type        = string
  default     = "ref-arch-iq-ha"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.cluster_name))
    error_message = "cluster_name must be lowercase letters, digits and hyphens, starting with a letter and ending with a letter or digit. The storage account and Key Vault names strip the hyphens and Azure allows only lowercase alphanumerics there."
  }

  validation {
    condition     = length(var.cluster_name) >= 3 && length(var.cluster_name) <= 14
    error_message = "cluster_name must be 3 to 14 characters. The storage account and Key Vault names are built as st<cluster_name without hyphens><8 random characters> and kv<cluster_name without hyphens><8 random characters>, which Azure caps at 24."
  }
}


variable "vnet_cidr" {
  description = "CIDR block for VNet"
  type        = string
  default     = "10.1.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (Application Gateway) - Multiple for HA"
  type        = list(string)
  default     = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (Container Apps) - Multiple for HA"
  type        = list(string)
  default     = ["10.1.8.0/23", "10.1.16.0/23", "10.1.24.0/23"]
}

variable "db_subnet_cidr" {
  description = "CIDR block for database subnet"
  type        = string
  default     = "10.1.40.0/24"
}


variable "container_cpu" {
  description = "vCPU per IQ Server replica. The default is the Size M and L value. It must fit on one node of workload_profile_type."
  type        = number
  default     = 8.0
}

variable "container_memory" {
  description = "Memory per IQ Server replica. The default is the Size M and L value. It must fit on one node of workload_profile_type."
  type        = string
  default     = "64Gi"
}

variable "workload_profile_type" {
  description = "Azure Container Apps workload profile type, which sets the cores and memory of each node the replicas run on. E8 is 8 cores and 64 GB, which is what the published Size M and L rows of README.md ask for per node; E16 is 16 cores and 128 GB for Size XL. A profile smaller than container_cpu and container_memory cannot host a replica, and the app then reports insufficient capacity rather than naming the profile. Run `az rest --method get --url \"https://management.azure.com/subscriptions/<id>/providers/Microsoft.App/locations/<region>/availableManagedEnvironmentsWorkloadProfileTypes?api-version=2024-03-01\"` for the types a region offers."
  type        = string
  default     = "E8"
}

variable "iq_min_replicas" {
  description = "Minimum number of IQ Server replicas (HA requires minimum 2)"
  type        = number
  default     = 2

  validation {
    condition     = var.iq_min_replicas >= 2
    error_message = "HA deployment requires minimum 2 IQ Server replicas."
  }
}

variable "iq_max_replicas" {
  description = "Maximum number of IQ Server replicas for auto scaling"
  type        = number
  default     = 4
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


variable "cpu_utilization_threshold" {
  description = "CPU utilization percentage threshold for auto scaling"
  type        = number
  default     = 70
}

variable "memory_utilization_threshold" {
  description = "Memory utilization percentage threshold for auto scaling"
  type        = number
  default     = 80
}

variable "scale_rule_concurrent_requests" {
  description = "Concurrent requests threshold for auto scaling"
  type        = number
  default     = 100
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
  description = "PostgreSQL Flexible Server SKU. The default, 8 vCores and 64 GB, is the Size M and L value; XL uses MO_Standard_E16ds_v6, as the Sizing Guide in README.md gives."
  type        = string
  default     = "MO_Standard_E8ds_v6"
}

variable "db_storage_mb" {
  description = "PostgreSQL storage in MB. Azure accepts 32768, 65536, 131072, 262144, 524288, 1048576 and larger powers of two. It sets the size when the server is created, and storage grows automatically past it. Terraform ignores later changes, so raise a live server's storage with the Azure CLI or portal."
  type        = number
  default     = 131072
}

variable "db_storage_tier" {
  description = "Performance tier of the PostgreSQL storage. P10 is the default for 128 GB."
  type        = string
  default     = "P10"
}

variable "db_backup_retention_days" {
  description = "Database backup retention period in days"
  type        = number
  default     = 7
}

variable "db_geo_redundant_backup_enabled" {
  description = "Enable geo-redundant backup for additional HA (not supported in all regions)"
  type        = bool
  default     = false
}

variable "db_high_availability_mode" {
  description = "High availability mode for PostgreSQL (ZoneRedundant for HA)"
  type        = string
  default     = "ZoneRedundant"

  validation {
    condition     = contains(["ZoneRedundant", "SameZone"], var.db_high_availability_mode)
    error_message = "HA mode must be either 'ZoneRedundant' or 'SameZone'."
  }
}


variable "app_gateway_sku_name" {
  description = "Application Gateway SKU name (v2 required for zone redundancy)"
  type        = string
  default     = "Standard_v2"
}

variable "app_gateway_sku_tier" {
  description = "Application Gateway SKU tier (v2 required for zone redundancy)"
  type        = string
  default     = "Standard_v2"
}

variable "app_gateway_capacity" {
  description = "Application Gateway capacity (instances)"
  type        = number
  default     = 2
}

variable "app_gateway_zones" {
  description = "Availability zones for Application Gateway (for zone redundancy)"
  type        = list(string)
  default     = ["1", "2", "3"]
}


variable "log_share_quota_gb" {
  description = "Quota in GB of the Azure Files share mounted at /var/log/nexus-iq-server, which holds IQ Server's application, request and audit logs off the container's ephemeral storage. A full share stops IQ Server writing those files but leaves the container running. With storage_account_tier = \"Premium\" the share is billed on this full size and cannot be below 100."
  type        = number
  default     = 128
}

variable "storage_account_tier" {
  description = "Storage account performance tier. Standard (HDD) is recommended for cost efficiency. Use Premium if NFS protocol is required."
  type        = string
  default     = "Standard"
}

variable "storage_account_replication_type" {
  description = "Storage account replication type (ZRS for zone redundancy)"
  type        = string
  default     = "ZRS"
}

variable "file_share_quota_gb" {
  description = "File share quota in GB for IQ Server data. The default is the Size M value; L uses 1536 and XL 4096, as README.md gives. On Premium the quota is the provisioned and billed size."
  type        = number
  default     = 500
}


variable "enable_monitoring" {
  description = "Enable Application Insights monitoring"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Log retention in days"
  type        = number
  default     = 30
}

variable "enable_container_insights" {
  description = "Enable Container Apps monitoring and insights"
  type        = bool
  default     = true
}


variable "enable_backup" {
  description = "Enable backup for storage and database"
  type        = bool
  default     = true
}


variable "key_vault_sku_name" {
  description = "Key Vault SKU name"
  type        = string
  default     = "standard"
}

variable "key_vault_soft_delete_retention_days" {
  description = "Key Vault soft delete retention in days"
  type        = number
  default     = 7
}


variable "common_tags" {
  description = "Common tags to apply to all resources. Azure treats tag names as case-insensitive, so do not supply two keys differing only in capitalization. Put per-deployment values in terraform.tfvars, which is gitignored, rather than in terraform.tfvars.example."
  type        = map(string)
  default = {
    Project        = "nexus-iq-server-ha"
    Environment    = "production"
    Terraform      = "true"
    DeploymentType = "high-availability"
  }
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
  description = "Password for opensearch_username. Delivered to the container app as a secret rather than a plain environment variable, and also written to Key Vault alongside the four database secrets, so the vault is the record of every credential this deployment holds. Nothing reads it back out of the vault. sensitive = true only keeps it out of CLI output: Terraform holds every variable in the state file as plain text, so treat terraform.tfstate as a secret, keep it in a backend that encrypts at rest and restrict who can read it. Keep the value in terraform.tfvars, which is gitignored, and never in terraform.tfvars.example."
  type        = string
  default     = ""
  sensitive   = true
}

variable "container_registry_server" {
  description = "Login server of a private container registry holding iq_docker_image, for example myregistry.azurecr.io. Leave empty for an image on a public registry, which writes no registry block and no credential."
  type        = string
  default     = ""
}

variable "container_registry_username" {
  description = "User name the container app authenticates to the private registry with. Required when container_registry_server is set."
  type        = string
  default     = ""
}

variable "container_registry_password" {
  description = "Password for container_registry_username, delivered to the container app as a secret rather than a plain value. sensitive = true keeps it out of CLI output only: Terraform holds every variable in the state file as plain text, so treat terraform.tfstate as a secret. Keep the value in terraform.tfvars, which is gitignored, and never in terraform.tfvars.example."
  type        = string
  default     = ""
  sensitive   = true
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

variable "opensearch_index_replicas" {
  description = "Replicas per Nexus One index shard, written as nexusOne.connection.nexusOneIndexReplicas. A single-data-node cluster cannot place a replica, so 0 is the only workable value there. Bounds-checked 0 to 10 by IQ Server itself."
  type        = number
  default     = 1

  validation {
    condition     = var.opensearch_index_replicas >= 0 && var.opensearch_index_replicas <= 10
    error_message = "opensearch_index_replicas must be between 0 and 10."
  }
}

