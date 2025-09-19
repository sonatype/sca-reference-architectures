# General Variables
variable "gcp_project_id" {
  description = "GCP project ID"
  type        = string
}

variable "gcp_region" {
  description = "GCP region for resources"
  type        = string
  default     = "us-central1"
}

variable "gcp_zone" {
  description = "GCP zone for zonal resources"
  type        = string
  default     = "us-central1-a"
}

variable "gcp_region_secondary" {
  description = "Secondary GCP region for read replicas and DR"
  type        = string
  default     = "us-east1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

# Network Variables
variable "public_subnet_cidr" {
  description = "CIDR block for public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for private subnet"
  type        = string
  default     = "10.0.2.0/24"
}

variable "db_subnet_cidr" {
  description = "CIDR block for database subnet"
  type        = string
  default     = "10.0.3.0/24"
}

variable "services_subnet_cidr" {
  description = "CIDR block for services secondary range"
  type        = string
  default     = "10.1.0.0/16"
}

variable "pods_subnet_cidr" {
  description = "CIDR block for pods secondary range"
  type        = string
  default     = "10.2.0.0/16"
}

variable "vpc_connector_cidr" {
  description = "CIDR block for VPC connector"
  type        = string
  default     = "10.0.4.0/28"
}

# Deployment Configuration
variable "iq_deployment_mode" {
  description = "Deployment mode: single for single-instance, ha for high-availability"
  type        = string
  default     = "single"
  validation {
    condition     = contains(["single", "ha"], var.iq_deployment_mode)
    error_message = "Deployment mode must be either 'single' or 'ha'."
  }
}

# Cloud Run Variables
variable "iq_docker_image" {
  description = "Docker image for Nexus IQ Server"
  type        = string
  default     = "sonatypecommunity/nexus-iq-server:latest"
}

variable "iq_cpu" {
  description = "CPU allocation for Cloud Run service"
  type        = string
  default     = "2"
}

variable "iq_memory" {
  description = "Memory allocation for Cloud Run service"
  type        = string
  default     = "4Gi"
}

variable "iq_max_concurrency" {
  description = "Maximum concurrent requests per instance"
  type        = number
  default     = 1000
}

variable "iq_min_instances_single" {
  description = "Minimum instances for single deployment mode"
  type        = number
  default     = 1
}

variable "iq_max_instances_single" {
  description = "Maximum instances for single deployment mode"
  type        = number
  default     = 1
}

variable "iq_min_instances_ha" {
  description = "Minimum instances for HA deployment mode"
  type        = number
  default     = 2
}

variable "iq_max_instances_ha" {
  description = "Maximum instances for HA deployment mode"
  type        = number
  default     = 10
}

variable "java_opts" {
  description = "Java options for IQ Server"
  type        = string
  default     = "-Xmx3g -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
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
}

variable "db_instance_tier" {
  description = "Cloud SQL instance tier"
  type        = string
  default     = "db-custom-2-4096"
}

variable "db_allocated_storage" {
  description = "Initial allocated storage for Cloud SQL in GB"
  type        = number
  default     = 100
}

variable "db_max_allocated_storage" {
  description = "Maximum allocated storage for Cloud SQL in GB"
  type        = number
  default     = 1000
}

variable "postgres_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "15"
}

variable "db_backup_retention_days" {
  description = "Database backup retention period in days"
  type        = number
  default     = 7
}

variable "db_backup_start_time" {
  description = "Database backup start time (HH:MM format)"
  type        = string
  default     = "03:00"
}

variable "db_deletion_protection" {
  description = "Enable deletion protection for database"
  type        = bool
  default     = true
}

variable "enable_read_replica" {
  description = "Enable read replica for HA deployment"
  type        = bool
  default     = false
}

# Storage Variables
variable "filestore_tier" {
  description = "Cloud Filestore tier (BASIC_HDD, BASIC_SSD, HIGH_SCALE_SSD)"
  type        = string
  default     = "BASIC_SSD"
}

variable "filestore_capacity_gb" {
  description = "Cloud Filestore capacity in GB"
  type        = number
  default     = 1024
}

variable "storage_force_destroy" {
  description = "Force destroy storage buckets (for testing only)"
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Backup retention in days"
  type        = number
  default     = 30
}

variable "backup_transition_days" {
  description = "Days before transitioning to NEARLINE storage"
  type        = number
  default     = 7
}

variable "backup_archive_days" {
  description = "Days before transitioning to COLDLINE storage"
  type        = number
  default     = 30
}

variable "log_retention_days" {
  description = "Log retention in days"
  type        = number
  default     = 90
}

# Load Balancer Variables
variable "ssl_certificate_name" {
  description = "Name of the SSL certificate for HTTPS"
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "Domain name for the application"
  type        = string
  default     = ""
}

variable "enable_cdn" {
  description = "Enable Cloud CDN"
  type        = bool
  default     = false
}

variable "lb_log_sample_rate" {
  description = "Load balancer log sampling rate"
  type        = number
  default     = 1.0
}

# Security Variables
variable "enable_cloud_armor" {
  description = "Enable Cloud Armor security policies"
  type        = bool
  default     = true
}

variable "rate_limit_threshold" {
  description = "Rate limit threshold for Cloud Armor"
  type        = number
  default     = 100
}

variable "enable_ssh_access" {
  description = "Enable SSH access for debugging"
  type        = bool
  default     = false
}

variable "ssh_source_ranges" {
  description = "Source IP ranges for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_web_security_scanner" {
  description = "Enable Web Security Scanner"
  type        = bool
  default     = false
}

# IAM Variables
variable "enable_workload_identity" {
  description = "Enable Workload Identity for Kubernetes integration"
  type        = bool
  default     = false
}

variable "kubernetes_namespace" {
  description = "Kubernetes namespace for Workload Identity"
  type        = string
  default     = "nexus-iq"
}

variable "kubernetes_service_account" {
  description = "Kubernetes service account for Workload Identity"
  type        = string
  default     = "nexus-iq"
}

variable "private_registry" {
  description = "Use private Artifact Registry"
  type        = bool
  default     = false
}

# Encryption Variables
variable "kms_key_name" {
  description = "KMS key name for encryption (optional)"
  type        = string
  default     = ""
}

# IAP Variables (Identity-Aware Proxy)
variable "iap_oauth2_client_id" {
  description = "OAuth2 client ID for IAP"
  type        = string
  default     = ""
}

variable "iap_oauth2_client_secret" {
  description = "OAuth2 client secret for IAP"
  type        = string
  default     = ""
  sensitive   = true
}

# Monitoring and Alerting Variables
variable "alert_email_addresses" {
  description = "Email addresses for monitoring alerts"
  type        = list(string)
  default     = []
}

variable "notification_channels" {
  description = "Notification channel IDs for alerts"
  type        = list(string)
  default     = []
}

variable "alert_error_rate_threshold" {
  description = "Threshold for error rate alerts"
  type        = number
  default     = 0.05
}

variable "alert_cpu_threshold" {
  description = "Threshold for CPU utilization alerts (0-1)"
  type        = number
  default     = 0.8
}

variable "alert_memory_threshold" {
  description = "Threshold for memory utilization alerts (0-1)"
  type        = number
  default     = 0.8
}

variable "alert_db_connections_threshold" {
  description = "Threshold for database connections alert"
  type        = number
  default     = 80
}

variable "availability_slo_target" {
  description = "SLO target for service availability (0-1)"
  type        = number
  default     = 0.999
}

# Feature Flags
variable "enable_monitoring_dashboard" {
  description = "Enable monitoring dashboard creation"
  type        = bool
  default     = true
}

variable "enable_uptime_checks" {
  description = "Enable uptime monitoring checks"
  type        = bool
  default     = true
}

variable "enable_slo_monitoring" {
  description = "Enable SLO monitoring"
  type        = bool
  default     = true
}