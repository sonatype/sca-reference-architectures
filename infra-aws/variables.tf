
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = <<-EOT
    Base name every resource in this root is named from: the ECS cluster becomes
    "<cluster_name>-iq-cluster", the load balancer "<cluster_name>-iq-alb", the log
    group "/ecs/<cluster_name>-nexus-iq-server", and so on.

    Change it per deployment so several deployments can share one AWS account. Many
    of these names have to be unique across an account or a region, IAM roles, the
    load balancer, the target groups, the log group, the SSM parameters, the
    Secrets Manager secret and the RDS identifier among them, so two deployments
    that leave this at the default collide on the second apply. Running one
    deployment per size, for example "ref-arch-xs" through "ref-arch-xl", is what
    this is for.

    The default reproduces the names this root used before the variable existed, so
    leaving it alone changes nothing.
  EOT
  type        = string
  default     = "ref-arch"

  validation {
    # The longest name built from this is the admin target group,
    # "<cluster_name>-iq-admin-tg", and AWS caps a target group or load balancer
    # name at 32 characters. Checked here so a too-long name fails the plan rather
    # than the apply, after the VPC and the database already exist.
    condition     = length(var.cluster_name) <= 20
    error_message = "cluster_name must be 20 characters or fewer, to leave room for the 12-character '-iq-admin-tg' suffix under AWS's 32-character target group name limit."
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
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.20.0/24"]
}

variable "db_subnet_cidrs" {
  description = "CIDR blocks for database subnets"
  type        = list(string)
  default     = ["10.0.30.0/24", "10.0.40.0/24"]
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

variable "iq_desired_count" {
  description = "Desired number of ECS tasks"
  type        = number
  default     = 1
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
  description = "Database username"
  type        = string
  default     = "nexusiq"
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  description = "RDS instance class. Scale with number of IQ nodes: db.r6g.2xlarge for 1-3 nodes, db.r6g.4xlarge for 3-4 nodes."
  type        = string
  default     = "db.r6g.2xlarge"
}

variable "db_allocated_storage" {
  description = "Initial allocated storage for RDS in GB"
  type        = number
  default     = 500
}

variable "db_max_allocated_storage" {
  description = "Maximum allocated storage for RDS in GB"
  type        = number
  default     = 1000
}

variable "postgres_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "15.19"
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
  default     = true
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
  description = "Replicas per shard for the Nexus One index, written to config.yml as search.nexusOneIndexReplicas. IQ Server's own default is 0, so this configuration always writes the value rather than relying on that default. Leave it at 0 on a domain with one data node, which has nowhere to put a replica."
  type        = number
  default     = 0

  validation {
    condition     = var.opensearch_index_replicas >= 0 && var.opensearch_index_replicas <= 10
    error_message = "opensearch_index_replicas must be between 0 and 10, the range IQ Server accepts."
  }
}