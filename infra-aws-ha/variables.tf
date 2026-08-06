
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
  description = "Enable NAT Gateway for private subnets. When vpn_only = true, this must stay true — the ALB and ECS tasks move into private subnets and need outbound egress (ECR pulls, etc). Enforced via a lifecycle precondition on aws_lb.iq_alb in load_balancer.tf rather than a variable validation block, to avoid raising this module's required_version floor (variable-level cross-variable validation needs Terraform >= 1.9; lifecycle preconditions have worked since 1.2)."
  type        = bool
  default     = true
}


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
  default     = "-Xms24g -Xmx24g -XX:+UseG1GC -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
}


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
  default     = "15.10"
}

variable "aurora_instance_class" {
  description = "Aurora instance class. Scale with number of IQ nodes: db.r6g.2xlarge for 1-3 nodes, db.r6g.4xlarge for 3-4 nodes."
  type        = string
  default     = "db.r6g.2xlarge"
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
  default     = false
}


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


variable "efs_throughput_mode" {
  description = "EFS throughput mode. Elastic is recommended for pay-per-use pricing with automatic scaling."
  type        = string
  default     = "elastic"

  validation {
    condition     = contains(["bursting", "provisioned", "elastic"], var.efs_throughput_mode)
    error_message = "EFS throughput mode must be one of: 'bursting', 'provisioned', or 'elastic'."
  }
}

variable "efs_provisioned_throughput_in_mibps" {
  description = "EFS provisioned throughput in MiB/s"
  type        = number
  default     = 100
}


variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

variable "fluent_bit_image" {
  description = "Fluent Bit Docker image (use custom image with IQ Server parsers)"
  type        = string
  default     = "public.ecr.aws/aws-observability/aws-for-fluent-bit:stable"
}

variable "enable_log_archive" {
  description = "Enable S3 archival of logs for compliance"
  type        = bool
  default     = false
}

variable "log_archive_retention_days" {
  description = "Days to retain archived logs in S3 before deletion"
  type        = number
  default     = 2555
}


variable "enable_prometheus" {
  description = "Enable Prometheus monitoring"
  type        = bool
  default     = true
}


variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "nexus-iq-server-ha"
    Environment = "production"
    Terraform   = "true"
  }
}


# =============================================================================
# VPN-ONLY ACCESS
# =============================================================================
# By default this reference architecture is reachable from the public
# internet (ALB in the public subnets, security group open to 0.0.0.0/0).
# Set vpn_only = true to lock down the pure-AWS side of that instead: the ALB
# moves into the private subnets and its security group only accepts traffic
# from cloudconnexa_client_cidr_blocks.
#
# vpn_only alone does not stand up any VPN. Actually wiring a VPN path (e.g.
# Sonatype's CloudConnexa) is a separate, optional second step handled by the
# vpn-overlay/ directory alongside this one — see its README and the "VPN-Only
# Access" section of this folder's README for the two-step flow. Keeping that
# wiring out of this folder's own .tf files means it never adds a provider
# dependency (and therefore never affects plan/apply) for the default,
# non-VPN case.

variable "vpn_only" {
  description = "Lock this environment's ALB down to cloudconnexa_client_cidr_blocks instead of the public internet: the ALB becomes internal (private subnets, no public IP path) and its security group only accepts cloudconnexa_client_cidr_blocks. This variable only controls plain AWS resources in this folder — it does not create any VPN itself. See ../vpn-overlay/ (and this README's 'VPN-Only Access' section) for the optional second step that actually wires up Sonatype CloudConnexa VPN access. Defaults to false, preserving this reference architecture's existing public-internet behavior."
  type        = bool
  default     = false
}

variable "cloudconnexa_client_cidr_blocks" {
  description = "CIDR block(s) permitted to reach the ALB security group on 80/443 when vpn_only = true. Should cover only the VPC CIDR and/or the CloudConnexa VPN client IP pool CIDR, so that only traffic arriving via the CloudConnexa VPN connector (or from other resources already inside the VPC) can reach the application. Leave as the default empty list to fall back to this VPC's actual CIDR (aws_vpc.iq_vpc.cidr_block, via a local — see locals.tf), which stays correct even if var.vpc_cidr is overridden. Verify against your CloudConnexa network's actual configured client/route CIDR before applying, since this depends on details of the cloudconnexa-network module (see ../vpn-overlay/) that are not visible from this reference architecture alone. Only used when vpn_only = true."
  type        = list(string)
  default     = []
}

variable "enable_vpc_flow_logs" {
  description = "Enable VPC Flow Logs to CloudWatch Logs for all traffic in this VPC. Defaults to null, which tracks vpn_only (flow logs auto-enable once this environment is VPN-only, since they become the primary way to reconstruct which VPN client reached which backend during a security incident) — set explicitly to true or false to override that default independently of vpn_only."
  type        = bool
  default     = null
}
