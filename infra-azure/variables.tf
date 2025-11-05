# General Variables
variable "azure_region" {
  description = "Azure region for resources"
  type        = string
  default     = "West US 2"
}

# Network Variables
variable "vnet_cidr" {
  description = "CIDR block for Virtual Network"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for public subnet (Application Gateway)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for private subnet (Container Apps)"
  type        = string
  default     = "10.0.8.0/23"
}

variable "db_subnet_cidr" {
  description = "CIDR block for database subnet"
  type        = string
  default     = "10.0.30.0/24"
}

# Container App Variables
variable "container_cpu" {
  description = "CPU allocation for container (0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 4.0)"
  type        = number
  default     = 4.0
}

variable "container_memory" {
  description = "Memory allocation for container in Gi (0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 8Gi)"
  type        = string
  default     = "8Gi"
}

variable "iq_docker_image" {
  description = "Docker image for Nexus IQ Server"
  type        = string
  default     = "sonatype/nexus-iq-server:latest"
}

variable "java_opts" {
  description = "Java options for IQ Server"
  type        = string
  default     = "-Xms6g -Xmx6g -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
}

# Database Variables
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
  description = "Database SKU name (B_Standard_B1ms, GP_Standard_D4s_v3, MO_Standard_E16s_v3)"
  type        = string
  default     = "MO_Standard_E16s_v3"
}

variable "db_storage_mb" {
  description = "Database storage in MB"
  type        = number
  default     = 524288 # 512 GB
}

variable "db_auto_grow_enabled" {
  description = "Enable auto grow for database storage"
  type        = bool
  default     = true
}

variable "db_backup_retention_days" {
  description = "Database backup retention period in days"
  type        = number
  default     = 7
}

variable "db_geo_redundant_backup_enabled" {
  description = "Enable geo-redundant backups"
  type        = bool
  default     = false
}

variable "db_high_availability_enabled" {
  description = "Enable high availability for database"
  type        = bool
  default     = false
}

# Application Gateway Variables
variable "app_gateway_sku_name" {
  description = "Application Gateway SKU name"
  type        = string
  default     = "Standard_v2"
}

variable "app_gateway_sku_tier" {
  description = "Application Gateway SKU tier"
  type        = string
  default     = "Standard_v2"
}

variable "app_gateway_capacity" {
  description = "Application Gateway capacity"
  type        = number
  default     = 2
}

variable "ssl_certificate_path" {
  description = "Path to SSL certificate file (optional)"
  type        = string
  default     = ""
}

variable "ssl_certificate_password" {
  description = "Password for SSL certificate (optional)"
  type        = string
  sensitive   = true
  default     = ""
}

# Storage Variables
variable "storage_account_tier" {
  description = "Storage account tier (Standard, Premium)"
  type        = string
  default     = "Standard"
}

variable "storage_account_replication_type" {
  description = "Storage account replication type (LRS, ZRS, GRS, RAGRS)"
  type        = string
  default     = "LRS"
}

variable "file_share_quota" {
  description = "File share quota in GB"
  type        = number
  default     = 500
}

# Logging Variables
variable "log_retention_days" {
  description = "Log Analytics workspace retention in days"
  type        = number
  default     = 30
}

# Monitoring Variables
variable "enable_monitoring" {
  description = "Enable Application Insights monitoring"
  type        = bool
  default     = true
}

# Security Variables
variable "key_vault_sku_name" {
  description = "Key Vault SKU name"
  type        = string
  default     = "standard"
}