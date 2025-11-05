variable "azure_region" {
  description = "Azure region for infrastructure deployment"
  type        = string
  default     = "eastus2"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "cluster_name" {
  description = "Name of the AKS cluster and resource prefix"
  type        = string
  default     = "nexus-iq-ha"
}

# Network Configuration
variable "vnet_cidr" {
  description = "CIDR block for Virtual Network"
  type        = string
  default     = "10.1.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for public subnet (Application Gateway)"
  type        = string
  default     = "10.1.1.0/24"
}

variable "aks_subnet_cidr" {
  description = "CIDR block for AKS subnet"
  type        = string
  default     = "10.1.10.0/23"
}

variable "db_subnet_cidr" {
  description = "CIDR block for database subnet"
  type        = string
  default     = "10.1.20.0/24"
}

# AKS Configuration
variable "kubernetes_version" {
  description = "Kubernetes version for AKS cluster"
  type        = string
  default     = "1.27"
}

variable "node_instance_type" {
  description = "VM size for AKS worker nodes"
  type        = string
  default     = "Standard_D8s_v3" # 8 vCPU, 32GB RAM
}

variable "node_group_min_size" {
  description = "Minimum number of nodes in AKS node pool"
  type        = number
  default     = 2
}

variable "node_group_max_size" {
  description = "Maximum number of nodes in AKS node pool"
  type        = number
  default     = 6
}

variable "node_group_desired_size" {
  description = "Desired number of nodes in AKS node pool"
  type        = number
  default     = 3
}

variable "node_disk_size" {
  description = "Disk size in GB for AKS worker nodes"
  type        = number
  default     = 50
}

# PostgreSQL Configuration
variable "postgres_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "15"
}

variable "db_sku_name" {
  description = "SKU name for PostgreSQL Flexible Server"
  type        = string
  default     = "MO_Standard_E16s_v3" # Memory Optimized: 16 vCores, 128GB RAM (matches AWS r6g.4xlarge)
}

variable "db_high_availability_mode" {
  description = "High availability mode for PostgreSQL (ZoneRedundant or SameZone)"
  type        = string
  default     = "ZoneRedundant"
}

variable "db_storage_mb" {
  description = "Storage size in MB for PostgreSQL"
  type        = number
  default     = 65536 # 64GB
}

variable "db_storage_tier" {
  description = "Storage tier for PostgreSQL (P6, P10, P15, P20, etc.)"
  type        = string
  default     = "P6" # Minimum for 64GB
}

variable "database_name" {
  description = "Name of the PostgreSQL database"
  type        = string
  default     = "nexusiq"
}

variable "database_username" {
  description = "Username for PostgreSQL database"
  type        = string
  default     = "nexusiq"
}

variable "database_password" {
  description = "Password for PostgreSQL database"
  type        = string
  sensitive   = true
}

variable "backup_retention_period" {
  description = "Number of days to retain automated backups"
  type        = number
  default     = 7
}

variable "db_geo_redundant_backup_enabled" {
  description = "Enable geo-redundant backups for PostgreSQL (not supported in all regions)"
  type        = bool
  default     = false
}

# Storage Configuration
variable "storage_account_tier" {
  description = "Storage account tier (Premium for Azure Files Premium)"
  type        = string
  default     = "Premium"
}

variable "storage_account_replication_type" {
  description = "Storage account replication type (ZRS for zone-redundant)"
  type        = string
  default     = "ZRS"
}

variable "storage_share_quota_gb" {
  description = "Quota in GB for Azure Files share"
  type        = number
  default     = 512
}

# Application Gateway Configuration
variable "app_gateway_sku_name" {
  description = "SKU name for Application Gateway"
  type        = string
  default     = "Standard_v2"
}

variable "app_gateway_sku_tier" {
  description = "SKU tier for Application Gateway"
  type        = string
  default     = "Standard_v2"
}

variable "app_gateway_capacity" {
  description = "Capacity for Application Gateway (only used if autoscale is disabled)"
  type        = number
  default     = 2
}

variable "app_gateway_min_capacity" {
  description = "Minimum capacity for Application Gateway autoscale"
  type        = number
  default     = 2
}

variable "app_gateway_max_capacity" {
  description = "Maximum capacity for Application Gateway autoscale"
  type        = number
  default     = 10
}

# Nexus IQ Server Configuration
variable "nexus_iq_version" {
  description = "Version of Nexus IQ Server to deploy"
  type        = string
  default     = "1.195.0"
}

variable "nexus_iq_license" {
  description = "Base64 encoded Nexus IQ Server license"
  type        = string
  sensitive   = true
}

variable "nexus_iq_admin_password" {
  description = "Initial admin password for Nexus IQ Server"
  type        = string
  sensitive   = true
  default     = "admin123"
}

variable "nexus_iq_replica_count" {
  description = "Number of Nexus IQ Server replicas for high availability"
  type        = number
  default     = 3
}

variable "nexus_iq_memory_request" {
  description = "Memory request for Nexus IQ Server pods"
  type        = string
  default     = "16Gi"
}

variable "nexus_iq_memory_limit" {
  description = "Memory limit for Nexus IQ Server pods"
  type        = string
  default     = "24Gi"
}

variable "nexus_iq_cpu_request" {
  description = "CPU request for Nexus IQ Server pods"
  type        = string
  default     = "4"
}

variable "nexus_iq_cpu_limit" {
  description = "CPU limit for Nexus IQ Server pods"
  type        = string
  default     = "6"
}

# Helm Configuration
variable "helm_chart_version" {
  description = "Version of the Nexus IQ Server HA Helm chart"
  type        = string
  default     = "195.0.0"
}

variable "helm_namespace" {
  description = "Kubernetes namespace for Nexus IQ Server deployment"
  type        = string
  default     = "nexus-iq"
}

variable "agic_helm_version" {
  description = "Version of Application Gateway Ingress Controller Helm chart"
  type        = string
  default     = "1.7.2"
}

variable "aad_pod_identity_version" {
  description = "Version of AAD Pod Identity Helm chart"
  type        = string
  default     = "4.1.18"
}

# Monitoring Configuration
variable "log_retention_days" {
  description = "Number of days to retain logs in Log Analytics"
  type        = number
  default     = 30
}

variable "enable_fluentd" {
  description = "Enable Fluentd for log aggregation"
  type        = bool
  default     = true
}

variable "enable_monitoring" {
  description = "Enable Application Insights monitoring"
  type        = bool
  default     = true
}

# HPA Configuration
variable "enable_hpa" {
  description = "Enable Horizontal Pod Autoscaler"
  type        = bool
  default     = true
}

variable "hpa_min_replicas" {
  description = "Minimum replicas for HPA"
  type        = number
  default     = 2
}

variable "hpa_max_replicas" {
  description = "Maximum replicas for HPA"
  type        = number
  default     = 10
}

variable "hpa_target_cpu_utilization" {
  description = "Target CPU utilization percentage for HPA"
  type        = number
  default     = 70
}

variable "hpa_target_memory_utilization" {
  description = "Target memory utilization percentage for HPA"
  type        = number
  default     = 80
}

# Ingress Configuration
variable "ingress_hostname" {
  description = "Hostname for Nexus IQ Server ingress"
  type        = string
  default     = ""
}

variable "ingress_tls_enabled" {
  description = "Enable TLS for ingress"
  type        = bool
  default     = false
}
