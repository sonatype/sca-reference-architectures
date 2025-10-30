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

variable "gcp_zone" {
  description = "GCP zone for GCE instances"
  type        = string
  default     = "us-central1-a"
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

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# GCE Variables
variable "gce_machine_type" {
  description = "GCE machine type for Nexus IQ Server"
  type        = string
  default     = "e2-standard-8"
}

variable "gce_boot_image" {
  description = "Boot image for GCE instances"
  type        = string
  default     = "debian-cloud/debian-12"
}

variable "gce_boot_disk_size" {
  description = "Boot disk size in GB"
  type        = number
  default     = 100
}

variable "iq_desired_count" {
  description = "Desired number of IQ Server instances"
  type        = number
  default     = 1
}

variable "iq_version" {
  description = "Nexus IQ Server version to install"
  type        = string
  default     = "1.196.0-01"
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

variable "postgres_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "POSTGRES_17"
}

variable "db_instance_tier" {
  description = "Database instance tier (use db-perf-optimized-N-8 for ENTERPRISE_PLUS or db-custom-16-65536 for ENTERPRISE)"
  type        = string
  default     = "db-perf-optimized-N-8"
}

variable "db_edition" {
  description = "Database edition (ENTERPRISE or ENTERPRISE_PLUS)"
  type        = string
  default     = "ENTERPRISE_PLUS"

  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.db_edition)
    error_message = "Database edition must be ENTERPRISE or ENTERPRISE_PLUS."
  }
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
  description = "Number of automated backups to retain"
  type        = number
  default     = 7
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

# Logging Variables
variable "log_retention_days" {
  description = "Log retention in days"
  type        = number
  default     = 30
}

variable "java_opts" {
  description = "Java options for Nexus IQ Server"
  type        = string
  default     = "-Xmx48g -Xms48g -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
}