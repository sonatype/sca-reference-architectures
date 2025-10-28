# General Variables
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the ECS cluster"
  type        = string
  default     = "ref-arch-iq-ha-cluster"
}

# Network Variables
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (EKS nodes)"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.20.0/24", "10.0.30.0/24"]
}

variable "db_subnet_cidrs" {
  description = "CIDR blocks for database subnets"
  type        = list(string)
  default     = ["10.0.40.0/24", "10.0.50.0/24", "10.0.60.0/24"]
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnets"
  type        = bool
  default     = true
}

# ECS Variables
variable "ecs_cpu" {
  description = "CPU units for ECS task (1024 = 1 vCPU)"
  type        = number
  default     = 8192
}

variable "ecs_memory" {
  description = "Memory for ECS task in MiB"
  type        = number
  default     = 32768
}

variable "ecs_memory_reservation" {
  description = "Soft memory limit for ECS task in MiB"
  type        = number
  default     = 24576
}

variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights for ECS"
  type        = bool
  default     = true
}

# IQ Server Variables
variable "iq_desired_count" {
  description = "Desired number of IQ Server tasks (HA requires minimum 2)"
  type        = number
  default     = 3

  validation {
    condition     = var.iq_desired_count >= 2
    error_message = "HA deployment requires minimum 2 IQ Server instances."
  }
}

variable "iq_min_count" {
  description = "Minimum number of IQ Server tasks for auto scaling"
  type        = number
  default     = 2

  validation {
    condition     = var.iq_min_count >= 2
    error_message = "HA deployment requires minimum 2 IQ Server instances."
  }
}

variable "iq_max_count" {
  description = "Maximum number of IQ Server tasks for auto scaling"
  type        = number
  default     = 5
}

variable "iq_cpu_target_value" {
  description = "Target CPU utilization percentage for auto scaling"
  type        = number
  default     = 70
}

variable "iq_memory_target_value" {
  description = "Target memory utilization percentage for auto scaling"
  type        = number
  default     = 80
}

variable "iq_docker_image" {
  description = "Docker image for Nexus IQ Server"
  type        = string
  default     = "sonatype/nexus-iq-server:latest"
}

variable "java_opts" {
  description = "Java options for IQ Server"
  type        = string
  default     = "-Xmx8g -Xms8g -XX:+UseG1GC -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
}

# Database Variables (Aurora PostgreSQL for HA)
variable "db_name" {
  description = "Database name"
  type        = string
  default     = "nexusiq"
}

variable "db_username" {
  description = "Database master username"
  type        = string
  default     = "nexusiq"
}

variable "db_password" {
  description = "Database master password"
  type        = string
  sensitive   = true
}

variable "aurora_engine_version" {
  description = "Aurora PostgreSQL engine version"
  type        = string
  default     = "15.4"
}

variable "aurora_instance_class" {
  description = "Aurora instance class"
  type        = string
  default     = "db.m5.4xlarge"
}

variable "aurora_instances" {
  description = "Number of Aurora instances (minimum 2 for Multi-AZ)"
  type        = number
  default     = 2

  validation {
    condition     = var.aurora_instances >= 2
    error_message = "Aurora cluster requires minimum 2 instances for HA."
  }
}

variable "db_backup_retention_period" {
  description = "Database backup retention period in days"
  type        = number
  default     = 7
}

variable "db_backup_window" {
  description = "Database backup window"
  type        = string
  default     = "03:00-04:00"
}

variable "db_maintenance_window" {
  description = "Database maintenance window"
  type        = string
  default     = "sun:04:00-sun:05:00"
}

variable "db_skip_final_snapshot" {
  description = "Skip final snapshot when deleting database"
  type        = bool
  default     = false
}

variable "db_deletion_protection" {
  description = "Enable deletion protection for database"
  type        = bool
  default     = true
}

# Load Balancer Variables
variable "ssl_certificate_arn" {
  description = "ARN of SSL certificate for ALB HTTPS listener"
  type        = string
  default     = ""
}

variable "alb_deletion_protection" {
  description = "Enable deletion protection for ALB"
  type        = bool
  default     = false
}

# EFS Variables
variable "efs_throughput_mode" {
  description = "EFS throughput mode"
  type        = string
  default     = "provisioned"

  validation {
    condition     = contains(["bursting", "provisioned"], var.efs_throughput_mode)
    error_message = "EFS throughput mode must be either 'bursting' or 'provisioned'."
  }
}

variable "efs_provisioned_throughput_in_mibps" {
  description = "EFS provisioned throughput in MiB/s"
  type        = number
  default     = 100
}

# Logging Variables
variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

# Monitoring Variables
variable "enable_prometheus" {
  description = "Enable Prometheus monitoring"
  type        = bool
  default     = false
}

# Tagging Variables
variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "nexus-iq-server-ha"
    Environment = "production"
    Terraform   = "true"
  }
}