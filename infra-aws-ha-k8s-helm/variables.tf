variable "aws_region" {
  description = "AWS region for infrastructure deployment"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "cluster_name" {
  description = "Name of the EKS cluster and resource prefix"
  type        = string
  default     = "nexus-iq-ha"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

# EKS Configuration
variable "kubernetes_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.27"
}

variable "node_instance_type" {
  description = "EC2 instance type for EKS worker nodes"
  type        = string
  default     = "m5d.2xlarge"
}

variable "node_group_min_size" {
  description = "Minimum number of nodes in EKS node group"
  type        = number
  default     = 2
}

variable "node_group_max_size" {
  description = "Maximum number of nodes in EKS node group"
  type        = number
  default     = 6
}

variable "node_group_desired_size" {
  description = "Desired number of nodes in EKS node group"
  type        = number
  default     = 3
}

variable "node_disk_size" {
  description = "Disk size in GB for EKS worker nodes"
  type        = number
  default     = 50
}

# RDS Configuration
variable "aurora_engine_version" {
  description = "Aurora PostgreSQL engine version"
  type        = string
  default     = "15.4"
}

variable "aurora_instance_class" {
  description = "Instance class for Aurora PostgreSQL"
  type        = string
  default     = "db.m5.4xlarge"
}

variable "aurora_instance_count" {
  description = "Number of Aurora instances (writer + readers)"
  type        = number
  default     = 2
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

variable "skip_final_snapshot" {
  description = "Skip final snapshot when destroying the cluster"
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "Enable deletion protection for RDS cluster"
  type        = bool
  default     = true
}

# EFS Configuration
variable "efs_provisioned_throughput" {
  description = "Provisioned throughput for EFS in MiB/s"
  type        = number
  default     = 100
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
  default     = "8"
}

variable "nexus_iq_cpu_limit" {
  description = "CPU limit for Nexus IQ Server pods"
  type        = string
  default     = "12"
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

# Logging Configuration
variable "enable_fluentd" {
  description = "Enable Fluentd for log aggregation"
  type        = bool
  default     = true
}

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch logs integration"
  type        = bool
  default     = true
}

# Ingress Configuration
variable "enable_ingress_nginx" {
  description = "Enable nginx ingress controller"
  type        = bool
  default     = true
}

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

variable "acm_certificate_arn" {
  description = "ARN of ACM certificate for TLS"
  type        = string
  default     = ""
}

# Monitoring Configuration
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
  default     = 5
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
# Logging Configuration
variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 7
}
