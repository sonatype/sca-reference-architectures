# General Variables
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
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

# Network Variables
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.100.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for public subnet"
  type        = string
  default     = "10.100.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for private subnet"
  type        = string
  default     = "10.100.10.0/24"
}

variable "db_subnet_cidr" {
  description = "CIDR block for database subnet"
  type        = string
  default     = "10.100.20.0/24"
}

variable "services_subnet_cidr" {
  description = "CIDR block for services secondary range"
  type        = string
  default     = "10.100.30.0/24"
}

variable "pods_subnet_cidr" {
  description = "CIDR block for pods secondary range"
  type        = string
  default     = "10.100.40.0/24"
}

variable "vpc_connector_cidr" {
  description = "CIDR block for VPC connector"
  type        = string
  default     = "10.100.50.0/28"
}

# High Availability Configuration
variable "enable_ha" {
  description = "Enable high availability configuration for IQ-HA"
  type        = bool
  default     = false
}

# Cloud Run Variables
variable "iq_docker_image" {
  description = "Docker image for Nexus IQ Server"
  type        = string
  default     = "sonatypecommunity/nexus-iq-server:latest"
}

variable "iq_min_instances" {
  description = "Minimum number of Cloud Run instances"
  type        = string
  default     = "1"
}

variable "iq_max_instances" {
  description = "Maximum number of Cloud Run instances"
  type        = string
  default     = "10"
}

variable "iq_ha_min_instances" {
  description = "Minimum number of Cloud Run instances for HA"
  type        = string
  default     = "2"
}

variable "iq_ha_max_instances" {
  description = "Maximum number of Cloud Run instances for HA"
  type        = string
  default     = "20"
}

variable "container_concurrency" {
  description = "Maximum number of concurrent requests per container"
  type        = number
  default     = 80
}

variable "container_timeout" {
  description = "Container timeout in seconds"
  type        = number
  default     = 300
}

variable "iq_cpu_limit" {
  description = "CPU limit for IQ service"
  type        = string
  default     = "2000m"
}

variable "iq_memory_limit" {
  description = "Memory limit for IQ service"
  type        = string
  default     = "4Gi"
}

variable "iq_cpu_request" {
  description = "CPU request for IQ service"
  type        = string
  default     = "1000m"
}

variable "iq_memory_request" {
  description = "Memory request for IQ service"
  type        = string
  default     = "2Gi"
}

variable "iq_ha_cpu_limit" {
  description = "CPU limit for IQ HA service"
  type        = string
  default     = "4000m"
}

variable "iq_ha_memory_limit" {
  description = "Memory limit for IQ HA service"
  type        = string
  default     = "8Gi"
}

variable "iq_ha_cpu_request" {
  description = "CPU request for IQ HA service"
  type        = string
  default     = "2000m"
}

variable "iq_ha_memory_request" {
  description = "Memory request for IQ HA service"
  type        = string
  default     = "4Gi"
}

variable "java_opts" {
  description = "Java options for IQ Server"
  type        = string
  default     = "-Xmx2g -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
}

variable "java_opts_ha" {
  description = "Java options for IQ HA Server"
  type        = string
  default     = "-Xmx4g -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
}

# Database Variables
variable "postgres_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "POSTGRES_15"
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

variable "db_instance_tier" {
  description = "Cloud SQL instance tier"
  type        = string
  default     = "db-custom-2-7680"
}

variable "db_ha_instance_tier" {
  description = "Cloud SQL instance tier for HA"
  type        = string
  default     = "db-custom-4-15360"
}

variable "db_availability_type" {
  description = "Database availability type (ZONAL or REGIONAL)"
  type        = string
  default     = "ZONAL"
  
  validation {
    condition     = contains(["ZONAL", "REGIONAL"], var.db_availability_type)
    error_message = "Database availability type must be ZONAL or REGIONAL."
  }
}

variable "db_disk_size" {
  description = "Database disk size in GB"
  type        = number
  default     = 100
}

variable "db_max_disk_size" {
  description = "Maximum database disk size in GB"
  type        = number
  default     = 1000
}

variable "db_ha_disk_size" {
  description = "Database disk size in GB for HA"
  type        = number
  default     = 200
}

variable "db_ha_max_disk_size" {
  description = "Maximum database disk size in GB for HA"
  type        = number
  default     = 2000
}

variable "db_max_connections" {
  description = "Maximum database connections"
  type        = string
  default     = "200"
}

variable "db_ha_max_connections" {
  description = "Maximum database connections for HA"
  type        = string
  default     = "400"
}

variable "db_backup_start_time" {
  description = "Database backup start time (HH:MM format)"
  type        = string
  default     = "03:00"
}

variable "db_backup_retention_count" {
  description = "Number of automated backups to retain"
  type        = number
  default     = 7
}

variable "db_transaction_log_retention_days" {
  description = "Transaction log retention in days"
  type        = number
  default     = 7
}

variable "db_maintenance_window_day" {
  description = "Database maintenance window day (1=Monday, 7=Sunday)"
  type        = number
  default     = 7
  
  validation {
    condition     = var.db_maintenance_window_day >= 1 && var.db_maintenance_window_day <= 7
    error_message = "Maintenance window day must be between 1 and 7."
  }
}

variable "db_maintenance_window_hour" {
  description = "Database maintenance window hour (0-23)"
  type        = number
  default     = 4
  
  validation {
    condition     = var.db_maintenance_window_hour >= 0 && var.db_maintenance_window_hour <= 23
    error_message = "Maintenance window hour must be between 0 and 23."
  }
}

variable "db_deletion_protection" {
  description = "Enable deletion protection for database"
  type        = bool
  default     = true
}

variable "enable_read_replica" {
  description = "Enable read replica for database"
  type        = bool
  default     = false
}

variable "db_read_replica_tier" {
  description = "Cloud SQL read replica instance tier"
  type        = string
  default     = "db-custom-1-3840"
}

# Storage Variables
variable "filestore_zone" {
  description = "Zone for Filestore instance"
  type        = string
  default     = "us-central1-a"
}

variable "filestore_tier" {
  description = "Filestore tier (BASIC_HDD, BASIC_SSD, HIGH_SCALE_SSD)"
  type        = string
  default     = "BASIC_SSD"
  
  validation {
    condition     = contains(["BASIC_HDD", "BASIC_SSD", "HIGH_SCALE_SSD"], var.filestore_tier)
    error_message = "Filestore tier must be one of: BASIC_HDD, BASIC_SSD, HIGH_SCALE_SSD."
  }
}

variable "filestore_capacity_gb" {
  description = "Filestore capacity in GB"
  type        = number
  default     = 1024
}

variable "filestore_ha_tier" {
  description = "Filestore tier for HA (BASIC_HDD, BASIC_SSD, HIGH_SCALE_SSD)"
  type        = string
  default     = "HIGH_SCALE_SSD"
}

variable "filestore_ha_capacity_gb" {
  description = "Filestore capacity in GB for HA"
  type        = number
  default     = 2048
}

variable "backup_retention_days" {
  description = "Backup retention in days"
  type        = number
  default     = 30
}

variable "backup_max_versions" {
  description = "Maximum backup versions to keep"
  type        = number
  default     = 10
}

variable "log_retention_days" {
  description = "Log retention in days"
  type        = number
  default     = 30
}

variable "lb_log_retention_days" {
  description = "Load balancer log retention in days"
  type        = number
  default     = 30
}

variable "config_backup_retention_days" {
  description = "Configuration backup retention in days"
  type        = number
  default     = 90
}

variable "config_backup_max_versions" {
  description = "Maximum configuration backup versions to keep"
  type        = number
  default     = 5
}

variable "storage_force_destroy" {
  description = "Force destroy storage buckets on terraform destroy"
  type        = bool
  default     = false
}

variable "create_terraform_state_bucket" {
  description = "Create a bucket for Terraform state storage"
  type        = bool
  default     = false
}

# KMS Variables
variable "kms_key_rotation_period" {
  description = "KMS key rotation period in seconds"
  type        = string
  default     = "7776000s"  # 90 days
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
}

variable "domain_name_ha" {
  description = "Domain name for HA SSL certificate"
  type        = string
  default     = ""
}

variable "custom_domain" {
  description = "Custom domain for Cloud Run service"
  type        = string
  default     = ""
}

variable "custom_domain_ha" {
  description = "Custom domain for HA Cloud Run service"
  type        = string
  default     = ""
}

variable "backend_timeout_sec" {
  description = "Backend service timeout in seconds"
  type        = number
  default     = 30
}

variable "backend_log_sample_rate" {
  description = "Backend service log sample rate"
  type        = number
  default     = 1.0
}

variable "health_check_interval" {
  description = "Health check interval in seconds"
  type        = number
  default     = 30
}

variable "health_check_timeout" {
  description = "Health check timeout in seconds"
  type        = number
  default     = 10
}

variable "enable_cdn" {
  description = "Enable Cloud CDN"
  type        = bool
  default     = false
}

# Cloud Armor Variables
variable "enable_cloud_armor" {
  description = "Enable Cloud Armor security policy"
  type        = bool
  default     = true
}

variable "rate_limit_threshold_count" {
  description = "Rate limit threshold count"
  type        = number
  default     = 100
}

variable "rate_limit_threshold_interval" {
  description = "Rate limit threshold interval in seconds"
  type        = number
  default     = 60
}

variable "rate_limit_ban_duration" {
  description = "Rate limit ban duration in seconds"
  type        = number
  default     = 600
}

variable "blocked_ip_ranges" {
  description = "List of IP ranges to block"
  type        = list(string)
  default     = []
}

variable "blocked_countries" {
  description = "List of country codes to block"
  type        = list(string)
  default     = []
}

variable "ddos_rate_limit_count" {
  description = "DDoS protection rate limit count"
  type        = number
  default     = 50
}

variable "ddos_rate_limit_interval" {
  description = "DDoS protection rate limit interval in seconds"
  type        = number
  default     = 60
}

variable "ddos_ban_duration" {
  description = "DDoS protection ban duration in seconds"
  type        = number
  default     = 300
}

variable "enable_owasp_rules" {
  description = "Enable OWASP Top 10 protection rules"
  type        = bool
  default     = true
}

variable "enable_header_validation" {
  description = "Enable header validation rules"
  type        = bool
  default     = true
}

# Security Variables
variable "enable_ssh_access" {
  description = "Enable SSH access to instances"
  type        = bool
  default     = false
}

variable "ssh_source_ranges" {
  description = "Source IP ranges allowed for SSH access"
  type        = list(string)
  default     = []
}

variable "enable_iap" {
  description = "Enable Identity-Aware Proxy"
  type        = bool
  default     = false
}

variable "iap_allowed_users" {
  description = "List of users allowed through IAP"
  type        = list(string)
  default     = []
}

variable "enable_binary_authorization" {
  description = "Enable Binary Authorization for container security"
  type        = bool
  default     = false
}

variable "pgp_public_key" {
  description = "PGP public key for Binary Authorization attestor"
  type        = string
  default     = ""
}

variable "enable_scc_notifications" {
  description = "Enable Security Command Center notifications"
  type        = bool
  default     = false
}

variable "organization_id" {
  description = "GCP Organization ID for Security Command Center"
  type        = string
  default     = ""
}

# IAM Variables
variable "admin_users" {
  description = "Set of admin users with full access"
  type        = set(string)
  default     = []
}

variable "developer_users" {
  description = "Set of developer users with read-only access"
  type        = set(string)
  default     = []
}

variable "enable_workload_identity" {
  description = "Enable Workload Identity for Kubernetes integration"
  type        = bool
  default     = false
}

variable "k8s_namespace" {
  description = "Kubernetes namespace for Workload Identity"
  type        = string
  default     = "default"
}

variable "k8s_service_account" {
  description = "Kubernetes service account for Workload Identity"
  type        = string
  default     = "nexus-iq"
}

variable "create_service_account_keys" {
  description = "Create service account keys for external applications"
  type        = bool
  default     = false
}

# Monitoring Variables
variable "enable_monitoring_alerts" {
  description = "Enable monitoring alerts"
  type        = bool
  default     = true
}

variable "alert_email_addresses" {
  description = "List of email addresses for monitoring alerts"
  type        = list(string)
  default     = []
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for notifications"
  type        = string
  default     = ""
  sensitive   = true
}

variable "pagerduty_service_key" {
  description = "PagerDuty service key for notifications"
  type        = string
  default     = ""
  sensitive   = true
}

variable "cpu_alert_threshold" {
  description = "CPU utilization alert threshold (0.0-1.0)"
  type        = number
  default     = 0.8
}

variable "memory_alert_threshold" {
  description = "Memory utilization alert threshold (0.0-1.0)"
  type        = number
  default     = 0.8
}

variable "db_cpu_alert_threshold" {
  description = "Database CPU utilization alert threshold (0.0-1.0)"
  type        = number
  default     = 0.8
}

variable "db_memory_alert_threshold" {
  description = "Database memory utilization alert threshold (0.0-1.0)"
  type        = number
  default     = 0.8
}

variable "error_rate_alert_threshold" {
  description = "Error rate alert threshold (requests per second)"
  type        = number
  default     = 10
}

variable "db_connection_alert_threshold" {
  description = "Database connection count alert threshold"
  type        = number
  default     = 150
}

variable "uptime_check_regions" {
  description = "Regions for uptime checks"
  type        = list(string)
  default     = ["USA", "EUROPE", "ASIA_PACIFIC"]
}

# SLO Variables
variable "slo_target" {
  description = "SLO target (0.0-1.0)"
  type        = number
  default     = 0.995
}

variable "slo_latency_threshold_ms" {
  description = "SLO latency threshold in milliseconds"
  type        = number
  default     = 1000
}