# General Variables
variable "azure_region" {
  description = "Azure region for resources"
  type        = string
  default     = "East US"
}

variable "cluster_name" {
  description = "Name prefix for the HA cluster resources"
  type        = string
  default     = "ref-arch-iq-ha"
}

# Network Variables
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

# Container App Variables (HA Configuration)
variable "container_cpu" {
  description = "CPU allocation per container replica"
  type        = number
  default     = 2.0
}

variable "container_memory" {
  description = "Memory allocation per container replica"
  type        = string
  default     = "4Gi"
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
  default     = 10
}

variable "iq_docker_image" {
  description = "Docker image for Nexus IQ Server"
  type        = string
  default     = "sonatype/nexus-iq-server:latest"
}

variable "java_opts" {
  description = "Java options for IQ Server"
  type        = string
  default     = "-Xmx3g -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
}

# Auto Scaling Variables
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

# Database Variables (Zone-Redundant PostgreSQL)
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
  description = "PostgreSQL version"
  type        = string
  default     = "15"
}

variable "db_sku_name" {
  description = "Database SKU name for zone-redundant HA deployment"
  type        = string
  default     = "GP_Standard_D4s_v3" # 4 vCores, 16GB RAM
}

variable "db_backup_retention_days" {
  description = "Database backup retention period in days"
  type        = number
  default     = 7
}

variable "db_geo_redundant_backup_enabled" {
  description = "Enable geo-redundant backup for additional HA"
  type        = bool
  default     = true
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

# Application Gateway Variables (Zone-Redundant)
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

# Storage Variables (Premium for HA)
variable "storage_account_tier" {
  description = "Storage account performance tier (Premium required for zone redundancy)"
  type        = string
  default     = "Premium"
}

variable "storage_account_replication_type" {
  description = "Storage account replication type (ZRS for zone redundancy)"
  type        = string
  default     = "ZRS" # Zone-Redundant Storage
}

variable "file_share_quota_gb" {
  description = "File share quota in GB for IQ Server data"
  type        = number
  default     = 200
}

# Monitoring Variables
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

# Backup Variables
variable "enable_backup" {
  description = "Enable backup for storage and database"
  type        = bool
  default     = true
}

# Key Vault Variables
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

# Tagging Variables
variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Project        = "nexus-iq-server-ha"
    Environment    = "production"
    Terraform      = "true"
    DeploymentType = "high-availability"
  }
}