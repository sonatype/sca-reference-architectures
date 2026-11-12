# General Variables
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

variable "availability_zones" {
  description = "List of availability zones for multi-zone deployment"
  type        = list(string)
  default     = ["us-central1-a", "us-central1-b", "us-central1-c"]
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# Docker Configuration
variable "iq_docker_image" {
  description = "Docker image for Nexus IQ Server"
  type        = string
  default     = "sonatype/nexus-iq-server:latest"
}

# Network Variables
variable "public_subnet_cidr" {
  description = "CIDR block for public subnet"
  type        = string
  default     = "10.200.1.0/24"
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ)"
  type        = list(string)
  default     = ["10.200.10.0/24", "10.200.11.0/24", "10.200.12.0/24"]
}

variable "db_subnet_cidr" {
  description = "CIDR block for database subnet"
  type        = string
  default     = "10.200.20.0/24"
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = alltrue([for v in var.allowed_ssh_cidrs : !can(regex("CHANGE_ME", v))])
    error_message = "allowed_ssh_cidrs still holds a CHANGE_ME placeholder. Set a real value in terraform.tfvars."
  }
}

# Compute Engine Variables
variable "instance_machine_type" {
  description = "Machine type for Compute Engine instances (n4a-highmem-8 = 8 vCPU, 64GB RAM)"
  type        = string
  default     = "n4a-highmem-8"
}

variable "iq_min_instances" {
  description = "Minimum number of instances in MIG"
  type        = number
  default     = 2

  validation {
    condition     = var.iq_min_instances >= 2
    error_message = "Minimum instances must be at least 2 for HA."
  }
}

variable "iq_max_instances" {
  description = "Maximum number of instances in MIG"
  type        = number
  default     = 4

  validation {
    condition     = var.iq_max_instances >= 2
    error_message = "Maximum instances must be at least 2."
  }
}

variable "iq_target_instances" {
  description = "Target number of instances in MIG"
  type        = number
  default     = 3
}

# Database Variables
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

variable "postgres_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "POSTGRES_18"
}

variable "db_instance_tier" {
  description = "Database instance tier (Sonatype HA benchmark: 8 vCPU, 30GB RAM)"
  type        = string
  default     = "db-custom-8-30720"
}

variable "db_edition" {
  description = "Cloud SQL edition. ENTERPRISE takes the db-custom-* tiers; ENTERPRISE_PLUS is required by the newer machine series such as db-perf-optimized-N-* and db-c4a-highmem-*."
  type        = string
  default     = "ENTERPRISE"

  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.db_edition)
    error_message = "db_edition must be ENTERPRISE or ENTERPRISE_PLUS."
  }
}

variable "db_disk_type" {
  description = "Cloud SQL storage type. PD_SSD suits the db-custom-* tiers; the C4A machine series takes HYPERDISK_BALANCED. Set it at create: changing it replaces the instance."
  type        = string
  default     = "PD_SSD"

  validation {
    condition     = contains(["PD_SSD", "PD_HDD", "HYPERDISK_BALANCED"], var.db_disk_type)
    error_message = "db_disk_type must be PD_SSD, PD_HDD or HYPERDISK_BALANCED."
  }
}

variable "db_availability_type" {
  description = "Database availability type (REGIONAL for HA)"
  type        = string
  default     = "REGIONAL"

  validation {
    condition     = contains(["ZONAL", "REGIONAL"], var.db_availability_type)
    error_message = "Database availability type must be ZONAL or REGIONAL."
  }
}

variable "db_disk_size" {
  description = "Database disk size in GB. The default is the Size L value."
  type        = number
  default     = 256
}

variable "db_backup_start_time" {
  description = "Database backup start time (HH:MM format)"
  type        = string
  default     = "03:00"
}

variable "db_max_disk_size" {
  description = "Maximum database disk size in GB"
  type        = number
  default     = 1000
}

variable "db_max_connections" {
  description = "Maximum database connections"
  type        = string
  default     = "200"
}

variable "db_transaction_log_retention_days" {
  description = "Transaction log retention in days"
  type        = number
  default     = 7
}

variable "db_backup_retention_count" {
  description = "Number of automated backups to retain. Cloud SQL refuses a count that is not greater than db_transaction_log_retention_days, with \"backup retention should be > transaction log retention\", so this stays above that variable."
  type        = number
  default     = 8
}

variable "db_maintenance_window_day" {
  description = "Database maintenance window day (1=Monday, 7=Sunday)"
  type        = number
  default     = 7
}

variable "db_maintenance_window_hour" {
  description = "Database maintenance window hour (0-23)"
  type        = number
  default     = 4
}

variable "db_deletion_protection" {
  description = "Enable deletion protection for database"
  type        = bool
  default     = true
}

# Load Balancer Variables
variable "enable_ssl" {
  description = "Enable SSL/HTTPS for load balancer"
  type        = bool
  default     = true
}

variable "domain_name" {
  description = "Domain name for SSL certificate"
  type        = string
  default     = ""

  validation {
    condition     = !can(regex("CHANGE_ME", var.domain_name))
    error_message = "domain_name still holds a CHANGE_ME placeholder. Set a real value in terraform.tfvars."
  }
}

variable "lb_backend_timeout_sec" {
  description = "Seconds the load balancer waits for a response from Nexus IQ Server before answering 502. A large scan upload or report export can run longer than the default."
  type        = number
  default     = 30
}

# Auto Scaling Variables
variable "cpu_target_utilization" {
  description = "Target CPU utilization for auto scaling"
  type        = number
  default     = 0.7

  validation {
    condition     = var.cpu_target_utilization > 0 && var.cpu_target_utilization <= 1
    error_message = "CPU target utilization must be between 0 and 1."
  }
}

variable "scale_in_cooldown_seconds" {
  description = "Cooldown period for scaling in (seconds)"
  type        = number
  default     = 300
}

variable "scale_out_cooldown_seconds" {
  description = "Cooldown period for scaling out (seconds)"
  type        = number
  default     = 60
}

# Logging Variables
variable "log_retention_days" {
  description = "Log retention in days"
  type        = number
  default     = 30
}

# Java Options
variable "java_opts" {
  description = "Java options for Nexus IQ Server"
  type        = string
  default     = "-Xms48g -Xmx48g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/heap-dump.hprof -XX:+ExitOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
}

variable "iq_log_levels" {
  description = "Extra logger levels written under logging.loggers in config.yml, as logger name to level, for example { \"com.sonatype.insight.brain.search\" = \"DEBUG\" } for a support case. Every line lands in clm-server.log on Filestore."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for k, v in var.iq_log_levels : can(regex("^[A-Za-z0-9_.$-]+$", k)) && contains(["ALL", "TRACE", "DEBUG", "INFO", "WARN", "ERROR", "OFF"], upper(v))])
    error_message = "iq_log_levels takes logger names and levels such as DEBUG or WARN."
  }
}

# Storage Variables
variable "filestore_zone" {
  description = "Zone for Filestore instance (should be in the same region)"
  type        = string
  default     = "us-central1-a"
}

variable "filestore_tier" {
  description = "Filestore tier. BASIC_HDD is recommended for cost efficiency. For higher IOPS, provision 10+ TiB to unlock the higher performance tier, or use BASIC_SSD."
  type        = string
  default     = "BASIC_HDD"

  validation {
    condition     = contains(["BASIC_HDD", "BASIC_SSD", "HIGH_SCALE_SSD"], var.filestore_tier)
    error_message = "Filestore tier must be one of: BASIC_HDD, BASIC_SSD, HIGH_SCALE_SSD."
  }
}

variable "filestore_capacity_gb" {
  description = "Filestore capacity in GB. The default is the Size L capacity. Minimum 1024 for BASIC_HDD, 2560 for BASIC_SSD. Provisioning 10240+ (10 TiB) unlocks BASIC_HDD's higher performance tier."
  type        = number
  default     = 2560

  validation {
    condition     = var.filestore_capacity_gb >= 1024
    error_message = "Filestore capacity must be at least 1024 GB (1 TiB) for BASIC_HDD or 2560 GB (2.5 TiB) for BASIC_SSD."
  }
}

# Common Tags
variable "common_tags" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default = {
    "environment" = "prod"
    "component"   = "nexus-iq-ha"
    "managed-by"  = "terraform"
    "team"        = "platform"
    "cost-center" = "engineering"
  }

  validation {
    condition     = alltrue([for v in values(var.common_tags) : !can(regex("CHANGE_ME", v))])
    error_message = "common_tags still holds a CHANGE_ME placeholder. Set a real value in terraform.tfvars."
  }
}

# Search Backend
#
# search_engine picks the engine the search: block in config.yml names. "opensearch"
# needs a cluster you run yourself, named by opensearch_endpoint.
# Every instance reads the same endpoint, so they share one index.

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
}

variable "opensearch_port" {
  description = "Port the OpenSearch cluster listens on. 9200 is the OpenSearch default. This port is also what the firewall rules in search.tf and security.tf open."
  type        = number
  default     = 9200

  validation {
    condition     = var.opensearch_port > 0 && var.opensearch_port < 65536
    error_message = "opensearch_port must be between 1 and 65535."
  }
}

variable "opensearch_use_tls" {
  description = "Connect to OpenSearch over https rather than http. Leave this true unless the cluster has no certificate, because the basic auth password is sent on every request. With TLS, a private certificate authority has to be trusted by the JVM: see README.md, \"Trusting a private certificate authority\"."
  type        = bool
  default     = true
}

variable "opensearch_username" {
  description = "OpenSearch user Nexus IQ Server authenticates as. This user needs to create, read and write the Nexus One indices. Required when search_engine is \"opensearch\"."
  type        = string
  default     = ""

  validation {
    condition     = !can(regex("[\\'\"$`\\\\]", var.opensearch_username))
    error_message = "The OpenSearch user name may not hold a single quote, a double quote, a dollar sign, a backtick or a backslash. The startup script writes it into a single-quoted YAML scalar inside a double-quoted shell string, and those five are the characters that would break one or the other. Everything else, including | & : # and a space, is written through intact."
  }
}

variable "opensearch_password" {
  description = "Password for opensearch_username. Stored in Secret Manager and read by each instance at boot, so it is never written into the instance template's metadata. Required when search_engine is \"opensearch\"."
  type        = string
  default     = ""
  sensitive   = true
}

variable "opensearch_ca_certificate" {
  description = "PEM certificate of a private authority that signed the OpenSearch cluster's certificates. When set with opensearch_use_tls, each instance adds it to a copy of the JVM trust store on Filestore and points the JVM at the copy. Leave empty for a certificate from a public authority."
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

# Resource Naming
#
# cluster_name prefixes every name that must be unique in a project, so deployments with
# different values can share one. Empty keeps the default names.

variable "cluster_name" {
  description = "Prefix for every resource name that has to be unique inside a Google Cloud project. Empty, the default, reproduces the names this architecture has always published, so an existing deployment is not renamed. Set it to a distinct value per deployment when several sizes share one project."
  type        = string
  default     = ""

  validation {
    # Google Cloud name rules. At most 19 characters, because a service account id is capped
    # at 30 and the longest suffix added is 11.
    condition     = var.cluster_name == "" || can(regex("^[a-z]([a-z0-9-]{0,17}[a-z0-9])?$", var.cluster_name))
    error_message = "cluster_name must be empty, or 1 to 19 characters of lowercase letters, numbers and hyphens, starting with a letter and ending with a letter or number."
  }
}
