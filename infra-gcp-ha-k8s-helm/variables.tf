variable "gcp_project_id" {
  description = "GCP Project ID"
  type        = string
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
  description = "Name of the GKE cluster"
  type        = string
  default     = "nexus-iq-ha"
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

variable "kubernetes_version" {
  description = "Kubernetes version for GKE cluster"
  type        = string
  default     = "1.27"
}

variable "node_instance_type" {
  description = "Instance type for GKE nodes"
  type        = string
  default     = "n2-standard-8"
}

variable "node_group_min_size" {
  description = "Minimum number of nodes in the node pool"
  type        = number
  default     = 2
}

variable "node_group_max_size" {
  description = "Maximum number of nodes in the node pool"
  type        = number
  default     = 6
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
  default     = "POSTGRES_15"
}

variable "db_instance_tier" {
  description = "Cloud SQL instance tier"
  type        = string
  default     = "db-custom-8-30720"
}

variable "db_availability_type" {
  description = "Database availability type (REGIONAL for HA, ZONAL for single-zone)"
  type        = string
  default     = "REGIONAL"
}

variable "db_disk_size" {
  description = "Database disk size in GB"
  type        = number
  default     = 100
}

variable "db_max_disk_size" {
  description = "Maximum database disk size in GB for autoresize"
  type        = number
  default     = 500
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
  description = "Number of database backups to retain"
  type        = number
  default     = 7
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

variable "enable_read_replica" {
  description = "Enable read replica for database"
  type        = bool
  default     = true
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
}

variable "filestore_zone" {
  description = "Zone for Filestore instance"
  type        = string
  default     = "us-central1-a"
}

variable "filestore_tier" {
  description = "Filestore tier (BASIC_HDD, BASIC_SSD, HIGH_SCALE_SSD, ENTERPRISE)"
  type        = string
  default     = "BASIC_SSD"
}

variable "filestore_capacity_gb" {
  description = "Filestore capacity in GB (minimum 2560 for BASIC_SSD)"
  type        = number
  default     = 2560
}

variable "log_retention_days" {
  description = "Log retention days for Cloud Logging"
  type        = number
  default     = 30
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
  default     = "195.0.0"
}

variable "java_opts" {
  description = "Java options for Nexus IQ Server"
  type        = string
  default     = "-Xms24g -Xmx24g -XX:+UseG1GC -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
}
