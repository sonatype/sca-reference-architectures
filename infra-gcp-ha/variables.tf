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
  default     = "sonatype/nexus-iq-server:1.209.2"
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
  description = "Machine type for Compute Engine instances. The default is the Size M value, n4a-standard-8 with 8 vCPU and 32 GB; Size L uses n4a-standard-16 and Size XL n4a-highmem-16."
  type        = string
  default     = "n4a-standard-8"
}

variable "iq_min_instances" {
  description = "Minimum number of instances in the MIG: 2 at Size M and L, 3 at Size XL. HA requires at least 2."
  type        = number
  default     = 2

  validation {
    condition     = var.iq_min_instances >= 2
    error_message = "Minimum instances must be at least 2 for HA."
  }
}

variable "iq_max_instances" {
  description = "Maximum number of instances in the MIG: 3 at Size M, 4 at Size L, 5 at Size XL. Must be at least iq_min_instances."
  type        = number
  default     = 2

  validation {
    condition     = var.iq_max_instances >= 2
    error_message = "Maximum instances must be at least 2."
  }
}

variable "iq_target_instances" {
  description = "Number of instances the MIG starts with. Set it to iq_min_instances: 2 at Size M and L, 3 at Size XL."
  type        = number
  default     = 2
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

variable "iq_admin_initial_password" {
  description = "Password for IQ Server's admin user, at least 12 characters. It is kept in Secret Manager, which the instance startup script reads, and given to IQ Server as NXIQ_INITIAL_ADMIN_PASSWORD, which IQ Server reads only on its very first start, against an empty database. Changing it afterwards changes nothing: change the password in IQ Server instead."
  type        = string
  sensitive   = true

  validation {
    condition     = !can(regex("CHANGE_ME", var.iq_admin_initial_password)) && length(var.iq_admin_initial_password) >= 12
    error_message = "iq_admin_initial_password must be a real password of at least 12 characters, not a CHANGE_ME placeholder. Set it in terraform.tfvars."
  }
}

variable "postgres_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "POSTGRES_18"
}

variable "db_instance_tier" {
  description = "Cloud SQL instance tier. The default is the Size M value, 4 vCPU and 32 GB on the N4 series, which takes only HYPERDISK_BALANCED storage. Size L is db-custom-N4-8-65536 and Size XL db-custom-N4-16-131072."
  type        = string
  default     = "db-custom-N4-4-32768"
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
  description = "Cloud SQL storage type. The N4 tiers (db-custom-N4-*) and the C4A series take only HYPERDISK_BALANCED; the db-custom-* tiers take PD_SSD or PD_HDD. On google provider 8.x a change is an in-place update, and Cloud SQL migrates the storage."
  type        = string
  default     = "HYPERDISK_BALANCED"

  validation {
    condition     = contains(["PD_SSD", "PD_HDD", "HYPERDISK_BALANCED"], var.db_disk_type)
    error_message = "db_disk_type must be PD_SSD, PD_HDD or HYPERDISK_BALANCED."
  }
}

variable "db_disk_provisioned_iops" {
  description = "Provisioned IOPS for a HYPERDISK_BALANCED data disk, read and write combined. Ignored on PD_SSD and PD_HDD. The default is the Size M value, also used at Size L. The Hyperdisk default for a disk up to 256 GB is 4,000. Size XL uses 10,000. Set together with db_disk_provisioned_throughput: both null leaves them to Cloud SQL, which is the Hyperdisk default on a new instance and the current values on an existing one."
  type        = number
  default     = 8000
}

variable "db_disk_provisioned_throughput" {
  description = "Provisioned throughput in MiB/s for a HYPERDISK_BALANCED data disk. Ignored on PD_SSD and PD_HDD. The default is the Size M value, 240 (252 MB/s), the most Cloud SQL allows at 4 vCPU. Size L uses 340 (357 MB/s) and Size XL 425 (446 MB/s). These values keep the 170 MiB/s (178 MB/s) per 4,000 IOPS of the Cloud SQL Hyperdisk default. Hyperdisk Balanced takes from the larger of 140 and IOPS / 256 up to the smaller of 2,400 and IOPS / 4. Set together with db_disk_provisioned_iops: both null leaves them to Cloud SQL."
  type        = number
  default     = 240
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
  description = "Database disk size in GB. The default is the Size M value; Size L uses 256 and Size XL 512."
  type        = number
  default     = 128
}

variable "db_backup_start_time" {
  description = "Database backup start time (HH:MM format)"
  type        = string
  default     = "03:00"
}

variable "db_max_disk_size" {
  description = "Maximum database disk size in GB. The default is the Size M value; Size L uses 1,000 and Size XL 2,000."
  type        = number
  default     = 500
}

variable "db_max_connections" {
  description = "PostgreSQL max_connections. Each IQ Server node opens up to 90, 45 in its main pool and 45 in its lock pool, so the default, 500, covers the five nodes the XL autoscaling maximum allows plus 50 for Cloud SQL's own and administrative connections."
  type        = string
  default     = "500"
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
  description = "Java options for Nexus IQ Server. The default is the Size M value, a 20 GB heap and 4 GB direct memory on a 32 GB VM."
  type        = string
  default     = "-Xms20g -Xmx20g -XX:MaxDirectMemorySize=4g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/heap-dump.hprof -XX:+ExitOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
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
variable "filestore_tier" {
  description = "Filestore service tier. REGIONAL keeps the share in every zone of gcp_region and takes a fixed IOPS figure from filestore_max_iops."
  type        = string
  default     = "REGIONAL"

  validation {
    condition     = var.filestore_tier == "REGIONAL"
    error_message = "filestore_tier must be REGIONAL, the tier this architecture is built and sized for."
  }
}

variable "filestore_capacity_gb" {
  description = "Filestore capacity in GB. The default is the Size M capacity: 500 at Size M, 1,536 at Size L, 4,096 at Size XL. Regional takes 100 to 10,239 in steps of 1 GB."
  type        = number
  default     = 500

  validation {
    condition     = var.filestore_capacity_gb >= 100 && var.filestore_capacity_gb <= 10239 && floor(var.filestore_capacity_gb) == var.filestore_capacity_gb
    error_message = "filestore_capacity_gb must be a whole number from 100 to 10239 for a Regional instance."
  }
}

variable "filestore_max_iops" {
  description = "Fixed read IOPS bought for the Filestore instance. The default is the Size M figure: 8,000 at Size M, 16,000 at Size L, 24,000 at Size XL. Write IOPS is 30% of this, and throughput follows it. A Regional instance takes 4,000 to 17,000 per TB of capacity and at least 2,000."
  type        = number
  default     = 8000

  validation {
    condition     = var.filestore_max_iops >= 2000 && var.filestore_max_iops % 1000 == 0
    error_message = "filestore_max_iops must be a multiple of 1000 and at least 2000."
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
# means an OpenSearch cluster on Compute Engine VMs, which this configuration builds
# (opensearch_cluster.tf) unless opensearch_create is false, in which case
# opensearch_endpoint names a cluster you run yourself.
# Every instance reads the same endpoint, so they share one index.

variable "search_engine" {
  description = "Search backend for IQ Server, with no default: \"opensearch\" uses an OpenSearch cluster for Advanced Search and the Nexus One index, built here unless opensearch_endpoint names one you run; \"builtin\" builds no OpenSearch, so Advanced Search uses IQ Server's built-in index, and Nexus One can keep its index in IQ Server's PostgreSQL database, chosen on the Nexus One setup page."
  type        = string

  validation {
    condition     = contains(["opensearch", "builtin"], var.search_engine)
    error_message = "search_engine must be \"opensearch\", for an OpenSearch cluster, or \"builtin\", for no OpenSearch: Advanced Search then uses IQ Server's built-in index, and Nexus One can keep its index in IQ Server's PostgreSQL database. Replace the CHANGE_ME placeholder in terraform.tfvars with one of them."
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

  validation {
    condition     = !can(regex("CHANGE_ME", var.opensearch_password))
    error_message = "opensearch_password still holds a CHANGE_ME placeholder. Set a real value in terraform.tfvars."
  }
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
  description = "Prefix for every resource name that has to be unique inside a Google Cloud project. Empty, the default, keeps the default names. Set it to a distinct value per deployment when several sizes share one project."
  type        = string
  default     = ""

  validation {
    # Google Cloud name rules. At most 19 characters, because a service account id is capped
    # at 30 and the longest suffix added is 11.
    condition     = var.cluster_name == "" || can(regex("^[a-z]([a-z0-9-]{0,17}[a-z0-9])?$", var.cluster_name))
    error_message = "cluster_name must be empty, or 1 to 19 characters of lowercase letters, numbers and hyphens, starting with a letter and ending with a letter or number."
  }
}
