variable "gcp_project_id" {
  description = "GCP Project ID"
  type        = string

  validation {
    condition     = !can(regex("CHANGE_ME", var.gcp_project_id))
    error_message = "gcp_project_id still holds a CHANGE_ME placeholder. Set a real value in terraform.tfvars."
  }
}

variable "gcp_region" {
  description = "GCP region for resources"
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "Environment name (e.g., prod, staging, dev)"
  type        = string
  default     = "prod"
}

variable "cluster_name" {
  description = "Name of the GKE cluster, and the prefix for every resource name that has to be unique inside a Google Cloud project. Set it to a distinct value per deployment when several sizes share one project."
  type        = string
  default     = "nexus-iq-ha"

  validation {
    # Google Cloud name rules. At most 19 characters, because a service account id is capped
    # at 30 and the longest suffix added is 11.
    condition     = can(regex("^[a-z]([a-z0-9-]{0,17}[a-z0-9])?$", var.cluster_name))
    error_message = "cluster_name must be 1 to 19 characters of lowercase letters, numbers and hyphens, starting with a letter and ending with a letter or number."
  }
}

variable "public_subnet_cidr" {
  description = "CIDR block for public subnet"
  type        = string
  default     = "10.100.1.0/24"
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.100.10.0/24", "10.100.11.0/24", "10.100.12.0/24"]
}

variable "gke_pods_cidr" {
  description = "CIDR block for GKE pods"
  type        = string
  default     = "10.101.0.0/16"
}

variable "gke_services_cidr" {
  description = "CIDR block for GKE services"
  type        = string
  default     = "10.102.0.0/16"
}

variable "gke_master_cidr" {
  description = "CIDR block for GKE master"
  type        = string
  default     = "172.16.0.0/28"
}

variable "node_instance_type" {
  description = "Instance type for GKE nodes"
  type        = string
  default     = "n4a-highmem-8"
}

variable "node_group_min_size" {
  description = "Minimum number of nodes in the node pool"
  type        = number
  default     = 2
}

variable "node_group_max_size" {
  description = "Maximum number of nodes in the node pool"
  type        = number
  default     = 5
}

variable "node_group_desired_size" {
  description = "Desired number of nodes in the node pool"
  type        = number
  default     = 3
}

variable "node_disk_size" {
  description = "Disk size in GB for GKE nodes"
  type        = number
  default     = 100
}

variable "gke_maintenance_window_start" {
  description = "Start time for GKE maintenance window (HH:MM format)"
  type        = string
  default     = "03:00"
}

variable "postgres_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "POSTGRES_18"
}

variable "db_instance_tier" {
  description = "Cloud SQL instance tier. The default is the Size L value, 8 vCPU and 64 GB on the N4 series, which takes only HYPERDISK_BALANCED storage. Size XL is db-custom-N4-16-131072."
  type        = string
  default     = "db-custom-N4-8-65536"
}

variable "db_edition" {
  description = "Cloud SQL edition. ENTERPRISE takes the N4 and db-custom-* tiers; ENTERPRISE_PLUS is required by the newer machine series such as db-perf-optimized-N-* and db-c4a-highmem-*."
  type        = string
  default     = "ENTERPRISE"

  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.db_edition)
    error_message = "db_edition must be ENTERPRISE or ENTERPRISE_PLUS."
  }
}

variable "db_disk_type" {
  description = "Cloud SQL storage type. The N4 tiers (db-custom-N4-*) take only HYPERDISK_BALANCED; the db-custom-* tiers take PD_SSD or PD_HDD. On google provider 8.x a change is an in-place update, and Cloud SQL migrates the storage."
  type        = string
  default     = "HYPERDISK_BALANCED"

  validation {
    condition     = contains(["PD_SSD", "PD_HDD", "HYPERDISK_BALANCED"], var.db_disk_type)
    error_message = "db_disk_type must be PD_SSD, PD_HDD or HYPERDISK_BALANCED."
  }
}

variable "db_disk_provisioned_iops" {
  description = "Provisioned IOPS for a HYPERDISK_BALANCED data disk, read and write combined. Ignored on PD_SSD and PD_HDD. The default is the Size L value. The Hyperdisk default for a disk up to 256 GB is 4,000. Size XL uses 10000. null leaves it to Cloud SQL: the Hyperdisk default for the disk size on a new instance, and the current value on an existing one."
  type        = number
  default     = 8000
}

variable "db_availability_type" {
  description = "Database availability type (REGIONAL for HA, ZONAL for single-zone)"
  type        = string
  default     = "REGIONAL"
}

variable "db_disk_size" {
  description = "Database disk size in GB. The default is the Size L value."
  type        = number
  default     = 256
}

variable "db_max_disk_size" {
  description = "Maximum database disk size in GB for autoresize"
  type        = number
  default     = 1000
}

variable "db_max_connections" {
  description = "Maximum database connections"
  type        = string
  default     = "400"
}

variable "db_backup_start_time" {
  description = "Database backup start time (HH:MM format)"
  type        = string
  default     = "03:00"
}

variable "db_transaction_log_retention_days" {
  description = "Transaction log retention days for point-in-time recovery"
  type        = number
  default     = 7
}

variable "db_backup_retention_count" {
  description = "Number of automated backups to retain. Cloud SQL refuses a count that is not greater than db_transaction_log_retention_days, with \"backup retention should be > transaction log retention\", so this stays above that variable."
  type        = number
  default     = 8
}

variable "db_maintenance_window_day" {
  description = "Database maintenance window day (1-7, 1=Monday)"
  type        = number
  default     = 7
}

variable "db_maintenance_window_hour" {
  description = "Database maintenance window hour (0-23)"
  type        = number
  default     = 3
}

variable "db_deletion_protection" {
  description = "Enable deletion protection for database"
  type        = bool
  default     = false
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "nexusiq"
}

variable "db_username" {
  description = "Database username"
  type        = string
  default     = "nexusiq"
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true

  validation {
    condition     = !can(regex("CHANGE_ME", var.db_password))
    error_message = "db_password still holds a CHANGE_ME placeholder. Set a real value in terraform.tfvars."
  }
}

variable "filestore_zone" {
  description = "Zone for Filestore instance"
  type        = string
  default     = "us-central1-a"
}

variable "filestore_tier" {
  description = "Filestore tier. BASIC_HDD is recommended for cost efficiency. For higher IOPS, provision 10+ TiB to unlock the higher performance tier, or use BASIC_SSD."
  type        = string
  default     = "BASIC_HDD"
}

variable "filestore_capacity_gb" {
  description = "Filestore capacity in GB. The default is the Size L capacity. Minimum 1024 for BASIC_HDD, 2560 for BASIC_SSD. Provisioning 10240+ (10 TiB) unlocks BASIC_HDD's higher performance tier."
  type        = number
  default     = 2560
}

variable "log_retention_days" {
  description = "Log retention days for Cloud Logging"
  type        = number
  default     = 7
}

variable "enable_monitoring_alerts" {
  description = "Enable monitoring alert policies"
  type        = bool
  default     = true
}

variable "cloud_armor_rate_limit_threshold" {
  description = "Rate limit threshold for Cloud Armor (requests per minute)"
  type        = number
  default     = 1000
}

variable "nexus_iq_replica_count" {
  description = "Number of Nexus IQ Server replicas (minimum 2 for HA)"
  type        = number
  default     = 3
}

variable "nexus_iq_admin_password" {
  description = "Nexus IQ Server admin password"
  type        = string
  sensitive   = true
  default     = "admin123"
}

variable "helm_chart_version" {
  description = "Nexus IQ Server Helm chart version"
  type        = string
  default     = "201.0.0"
}

# Search Backend
#
# search_engine picks the engine the search: block in config.yml names. "opensearch"
# needs a cluster you run yourself, named by opensearch_endpoint.
# Every pod reads the same endpoint, so they share one index.

variable "search_engine" {
  description = "Which search backend Nexus IQ Server uses: \"lucene\" (default, the built-in index, nothing else to run) or \"opensearch\" (a self-managed OpenSearch cluster, whose host must be supplied in opensearch_endpoint)."
  type        = string
  default     = "lucene"

  validation {
    condition     = contains(["lucene", "opensearch"], var.search_engine)
    error_message = "search_engine must be one of: 'lucene', 'opensearch'."
  }
}

variable "opensearch_endpoint" {
  description = "Host name or IP address of an OpenSearch cluster you already run, with no scheme and no port (for example \"opensearch.internal.example.com\"). Required when search_engine is \"opensearch\", ignored otherwise."
  type        = string
  default     = ""

  validation {
    # search.tf builds "<scheme>://<endpoint>:<port>", so a scheme or port here produces
    # a URI that only fails when IQ Server connects. Empty is allowed; the precondition
    # requires a value when search_engine is "opensearch".
    condition     = var.opensearch_endpoint == "" || can(regex("^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$", var.opensearch_endpoint))
    error_message = "opensearch_endpoint must be a host name or IP address only, with no scheme, no port, no path and no trailing dot, for example \"opensearch.internal.example.com\"."
  }

  validation {
    condition     = !can(regex("CHANGE_ME", var.opensearch_endpoint))
    error_message = "opensearch_endpoint still holds a CHANGE_ME placeholder. Set a real value in terraform.tfvars."
  }
}

variable "opensearch_port" {
  description = "Port the OpenSearch cluster listens on. 9200 is the OpenSearch default. This port is also what the firewall rule in search.tf opens."
  type        = number
  default     = 9200

  validation {
    condition     = var.opensearch_port > 0 && var.opensearch_port < 65536
    error_message = "opensearch_port must be between 1 and 65535."
  }
}

variable "opensearch_use_tls" {
  description = "Connect to OpenSearch over https rather than http. Leave this true unless the cluster has no certificate, because the basic auth password is sent on every request. With TLS, a private certificate authority has to be trusted by the JVM in every pod: see README.md, \"Trusting a private certificate authority\"."
  type        = bool
  default     = true
}

variable "opensearch_username" {
  description = "OpenSearch user Nexus IQ Server authenticates as. This user needs to create, read and write the Nexus One indices. Required when search_engine is \"opensearch\"."
  type        = string
  default     = ""

  validation {
    condition     = !can(regex("\\{\\{", var.opensearch_username))
    error_message = "The OpenSearch user name may not contain {{. The chart runs iq_server.config through its template engine, so {{ would be read as the start of a template action, even inside a quoted value."
  }
}

variable "opensearch_password" {
  description = "Password for opensearch_username. render-values.sh reads this from a Terraform output and writes it into the generated values file, the same route the database password takes on this architecture. Required when search_engine is \"opensearch\"."
  type        = string
  default     = ""
  sensitive   = true

  validation {
    condition     = !can(regex("\\{\\{", var.opensearch_password))
    error_message = "The OpenSearch password may not contain {{. The chart runs iq_server.config through its template engine, so {{ would be read as the start of a template action, even inside a quoted value."
  }

  validation {
    condition     = !can(regex("CHANGE_ME", var.opensearch_password))
    error_message = "opensearch_password still holds a CHANGE_ME placeholder. Set a real value in terraform.tfvars."
  }
}

variable "opensearch_ca_certificate" {
  description = "PEM certificate of a private authority that signed the OpenSearch cluster's certificates. When set with opensearch_use_tls, render-values.sh stores it in the Kubernetes Secret nexus-iq-opensearch-ca, and each IQ Server pod adds it to a copy of the JVM trust store at start. Leave empty for a certificate from a public authority."
  type        = string
  default     = ""
}

variable "opensearch_index_replicas" {
  description = "Replicas every Nexus One index is created with, written to config.yml as nexusOne.connection.nexusOneIndexReplicas, which is where the Nexus One index reads it. Use 0 on one data node: it cannot place a replica, and 1 would leave the index yellow, which still serves reads and writes. Applied only when an index is created: an existing index keeps its count until it is rebuilt."
  type        = number
  default     = 1

  validation {
    condition     = var.opensearch_index_replicas >= 0 && var.opensearch_index_replicas <= 10
    error_message = "opensearch_index_replicas must be between 0 and 10, the range Nexus IQ Server accepts."
  }
}
