
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = <<-EOT
    Base name every resource in this root is named from: the ECS cluster itself, the
    load balancer, the target groups, the IAM roles and policies, the log group, the
    SSM parameters, the Secrets Manager secret, the Aurora cluster, the KMS aliases,
    the EFS backup vault, and the Name tag on each network resource.

    Change it per deployment so several deployments can share one AWS account. Many
    of those names have to be unique across an account or a region, so two
    deployments that leave this at the default collide on the second apply. Running
    one deployment per size, for example "ref-arch-xs-cluster" through
    "ref-arch-xl-cluster", is what this is for.

    The default reproduces the names this root has always used, so leaving it alone
    changes nothing.
  EOT
  type        = string
  default     = "ref-arch-iq-ha-cluster"

  validation {
    # The longest name built from this that AWS length-limits is the target group,
    # "<cluster_name>-iq-tg", and AWS caps a target group or load balancer name at
    # 32 characters. Checked here so a too-long name fails the plan rather than the
    # apply, after the VPC and Aurora already exist.
    condition     = length(var.cluster_name) <= 26
    error_message = "cluster_name must be 26 characters or fewer, to leave room for the 6-character '-iq-tg' suffix under AWS's 32-character target group name limit."
  }

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.cluster_name))
    error_message = "cluster_name must be lowercase letters, numbers and hyphens, and must not start or end with a hyphen, because it is used in load balancer and target group names."
  }
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
  default     = 4
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
  default     = "15.19"
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
# SEARCH BACKEND
# =============================================================================
# search_engine picks which search backend IQ Server's config.yml points at. It
# switches the `search:` block in the config.yml heredoc in ecs.tf on and off.
#
# "opensearch" needs an OpenSearch domain that already exists, named in
# opensearch_domain_name and reached at opensearch_domain_endpoint. This
# configuration deliberately does not create the domain. The domain holds the
# index, so keeping it outside Terraform means switching engines, replacing the
# ECS service or destroying this stack never deletes the indexed data, and the
# domain can be resized, upgraded and backed up on its own schedule.
#
# Sizing the domain is a separate exercise. See the OpenSearch section of this
# directory's README.md for the shape each size needs.

variable "search_engine" {
  description = "Search backend for IQ Server: \"lucene\" (default) uses the index built into IQ Server and needs nothing else, \"opensearch\" points IQ Server at an existing AWS-managed OpenSearch domain."
  type        = string
  default     = "lucene"

  validation {
    condition     = contains(["lucene", "opensearch"], var.search_engine)
    error_message = "search_engine must be one of: 'lucene', 'opensearch'."
  }
}

variable "opensearch_domain_endpoint" {
  description = "Host name of an existing OpenSearch domain, with no scheme and no trailing slash, for example \"search-my-domain-abc123.us-east-1.es.amazonaws.com\". Required when search_engine is \"opensearch\", ignored otherwise."
  type        = string
  default     = ""

  validation {
    condition     = var.search_engine != "opensearch" || length(var.opensearch_domain_endpoint) > 0
    error_message = "opensearch_domain_endpoint must be set when search_engine is 'opensearch'."
  }
}

variable "opensearch_domain_name" {
  description = <<-EOT
    Name of that same OpenSearch domain, for example "my-domain". Used only to
    build the ARN the ECS task role is granted data-plane access on, so the grant
    names one domain rather than every domain in the account. Required when
    search_engine is "opensearch".

    The domain has to be in this same AWS account and in aws_region, because the
    ARN is built from aws_region and the calling account. A domain in another
    account or another region cannot be named this way, and the symptom is a 403
    from the domain at runtime rather than an error at plan time. Reaching one
    would need the full ARN supplied instead, plus a matching principal in the
    domain's own access policy.
  EOT
  type        = string
  default     = ""

  validation {
    condition     = var.search_engine != "opensearch" || length(var.opensearch_domain_name) > 0
    error_message = "opensearch_domain_name must be set when search_engine is 'opensearch'."
  }
}

variable "opensearch_index_replicas" {
  description = "Replicas per shard for the Nexus One index, written to config.yml as search.nexusOneIndexReplicas. IQ Server's own default is 0, so this configuration always writes the value rather than relying on that default. A domain with more than one data node should carry at least 1 so losing a node does not mean rebuilding the index."
  type        = number
  default     = 0

  validation {
    condition     = var.opensearch_index_replicas >= 0 && var.opensearch_index_replicas <= 10
    error_message = "opensearch_index_replicas must be between 0 and 10, the range IQ Server accepts."
  }
}