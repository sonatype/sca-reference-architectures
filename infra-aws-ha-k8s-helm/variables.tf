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

variable "kubernetes_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.36"
}

variable "node_instance_type" {
  description = "EC2 instance type for EKS worker nodes. Graviton (arm64) and x86_64 types both work, the node AMI follows the instance architecture. Graviton5 types such as m9gd and r9g are not offered in every region, and the plan fails reading the type where it is missing: pick an x86 or an earlier Graviton type there."
  type        = string
  default     = "m9gd.2xlarge"
}

variable "node_group_min_size" {
  description = "Minimum number of nodes in EKS node group"
  type        = number
  default     = 2
}

variable "node_group_max_size" {
  description = "Maximum number of nodes in EKS node group"
  type        = number
  default     = 5
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

variable "aurora_engine_version" {
  description = "Aurora PostgreSQL engine version. An existing deployment sets the version it runs; upgrading is the deployer's decision."
  type        = string
  default     = "18.6"
}

variable "aurora_instance_class" {
  description = "Aurora instance class. The default is the Size M and L value; Size XL uses db.r8g.4xlarge."
  type        = string
  default     = "db.r8g.2xlarge"
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

  validation {
    condition     = !can(regex("CHANGE_ME", var.database_password))
    error_message = "database_password still holds a CHANGE_ME placeholder. Set a real value in terraform.tfvars."
  }
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
  default     = false
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

variable "helm_chart_version" {
  description = "Version of the Nexus IQ Server HA Helm chart"
  type        = string
  default     = "201.0.0"
}

variable "helm_namespace" {
  description = "Kubernetes namespace for Nexus IQ Server deployment"
  type        = string
  default     = "nexus-iq"
}

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

  validation {
    condition     = !can(regex("CHANGE_ME", var.acm_certificate_arn))
    error_message = "acm_certificate_arn still holds a CHANGE_ME placeholder. Set a real value in terraform.tfvars."
  }
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 7
}
