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
  default     = 6

  validation {
    condition     = var.iq_max_instances >= 2
    error_message = "Maximum instances must be at least 2."
  }
}

variable "iq_target_instances" {
  description = "Target number of instances in MIG"
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
}

variable "postgres_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "POSTGRES_15"
}

variable "db_instance_tier" {
  description = "Database instance tier (Sonatype HA benchmark: 8 vCPU, 30GB RAM)"
  type        = string
  default     = "db-custom-8-30720"
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

variable "enable_read_replica" {
  description = "Enable read replica for database"
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
  default     = "-Xms48g -Xmx48g -XX:+AlwaysPreTouch -XX:+CrashOnOutOfMemoryError -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
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
  description = "Filestore capacity in GB. Minimum 1024 for BASIC_HDD, 2560 for BASIC_SSD. Provisioning 10240+ (10 TiB) unlocks BASIC_HDD's higher performance tier."
  type        = number
  default     = 1024

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
}