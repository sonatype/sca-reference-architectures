
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the ECS cluster"
  type        = string
  default     = "ref-arch-iq-ha-vpn-cluster"
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
  description = "Enable NAT Gateway for private subnets"
  type        = bool
  default     = true
}


variable "ecs_cpu" {
  description = "CPU units for ECS task (1024 = 1 vCPU). Defaults to 16384 (16 vCPU) for Size XL."
  type        = number
  default     = 16384
}

variable "ecs_memory" {
  description = "Memory for ECS task in MiB. Defaults to 131072 (128 GB) for Size XL."
  type        = number
  default     = 131072
}

variable "ecs_memory_reservation" {
  description = "Soft memory limit for ECS task in MiB. Defaults to 98304 (96 GB) for Size XL."
  type        = number
  default     = 98304
}

variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights for ECS"
  type        = bool
  default     = true
}


variable "iq_desired_count" {
  description = "Desired number of IQ Server tasks (HA requires minimum 2). Defaults to 4 nodes for Size XL."
  type        = number
  default     = 4

  validation {
    condition     = var.iq_desired_count >= 2
    error_message = "HA deployment requires minimum 2 IQ Server instances."
  }
}

variable "iq_min_count" {
  description = "Minimum number of IQ Server tasks for auto scaling. Defaults to 3 for Size XL."
  type        = number
  default     = 3

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
  description = "Java options for IQ Server. Defaults to the Size XL heap settings."
  type        = string
  default     = "-Xms96g -Xmx96g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/Java_Heap_logs -XX:+CrashOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
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
  description = "Aurora instance class. Scale with number of IQ nodes: db.r6g.2xlarge for 1-3 nodes, db.r6g.4xlarge for 3-4 nodes. Defaults to db.r6g.4xlarge for Size XL."
  type        = string
  default     = "db.r6g.4xlarge"
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
    Project     = "nexus-iq-server-ha-vpn"
    Environment = "production"
    Terraform   = "true"
  }
}


# =============================================================================
# CLOUDCONNEXA VPN CONFIGURATION
# =============================================================================
# These variables configure the two CloudConnexa module invocations in
# cloudconnexa.tf, which are what make this environment VPN-only. They mirror
# the equivalent variables in sonatype/terraform-sca-cloud
# (src/infrastructure/aws/global/variables.tf).

variable "environment" {
  description = "The deployment environment (e.g., 'dev', 'staging', 'prod'). Used for CloudConnexa network tagging."
  type        = string
  default     = "dev"
}

variable "create_cloudconnexa" {
  description = "Create the CloudConnexa VPN network and application routing that this VPN-only variant depends on. Requires CLOUDCONNEXA_CLIENT_ID and CLOUDCONNEXA_CLIENT_SECRET environment variables. Leave this true unless you are substituting a different VPN mechanism — with it false and the ALB already internal/private, the environment would be unreachable."
  type        = bool
  default     = true
}

variable "cloudconnexa_base_url" {
  description = "CloudConnexa API base URL"
  type        = string
  default     = "https://sonatype.api.openvpn.com"
}

variable "cloudconnexa_connector_count" {
  description = "Number of CloudConnexa VPN connector instances. 2+ recommended for connector redundancy, consistent with this architecture's HA design."
  type        = number
  default     = 2
}

variable "cloudconnexa_connector_version" {
  description = "Change this value to trigger recreation of CloudConnexa connector instances (e.g., to apply user_data changes)"
  type        = string
  default     = "1"
}

variable "cloudconnexa_segment" {
  description = "CloudConnexa network segment tag (mirrors the 'segment' input on terraform-sca-cloud's cloudconnexa-network module invocation)."
  type        = string
  default     = "iq-server"
}

variable "cloudconnexa_product" {
  description = "CloudConnexa network product tag (mirrors the 'product' input on terraform-sca-cloud's cloudconnexa-network module invocation)."
  type        = string
  default     = "iq-server-perf-test"
}

variable "cloudconnexa_owner" {
  description = "Owner (team or email) for CloudConnexa network ownership tagging. Set this to your team's identifier before applying."
  type        = string
  default     = ""
}

variable "cloudconnexa_application_domain" {
  description = "Domain name CloudConnexa VPN clients use to reach the IQ Server ALB, via CloudConnexa's domain-based routing. Defaults to null, which falls back to the ALB's own AWS-generated DNS name (aws_lb.iq_alb.dns_name). Override with a custom Route53 record aliased to the internal ALB for a friendlier URL, matching the pattern used in terraform-sca-cloud (which routes to a custom control-plane domain rather than a raw ALB DNS name)."
  type        = string
  default     = null
}

variable "cloudconnexa_client_cidr_blocks" {
  description = "CIDR block(s) permitted to reach the ALB security group on 80/443. Should cover only the VPC CIDR and/or the CloudConnexa VPN client IP pool CIDR, so that only traffic arriving via the CloudConnexa VPN connector (or from other resources already inside the VPC) can reach the application. Defaults to the VPC CIDR (covers the common case where the CloudConnexa connector NATs client traffic to a VPC-internal address) — verify against your CloudConnexa network's actual configured client/route CIDR before applying, since this depends on details of the cloudconnexa-network module that are not visible from this reference architecture alone."
  type        = list(string)
  default     = ["10.0.0.0/16"]
}