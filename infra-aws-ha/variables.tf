
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
    one deployment per size, for example "ref-arch-m-cluster" through
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
  description = "Memory for ECS task in MiB. The default is the Size M value, the most Fargate allows at 8192 CPU."
  type        = number
  default     = 61440
}

variable "ecs_memory_reservation" {
  description = "Soft memory limit for the IQ Server container in MiB. The default is the Size M and L heap plus direct memory, 44 GB and 8 GB."
  type        = number
  default     = 53248
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
  default     = "-Xms44g -Xmx44g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/Java_Heap_logs -XX:+CrashOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
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
  description = "Aurora PostgreSQL engine version. The parameter group family follows its major version. An existing deployment sets the version it runs; upgrading is the deployer's decision."
  type        = string
  default     = "18.6"
}

variable "aurora_instance_class" {
  description = "Aurora instance class. Scale with number of IQ nodes: db.r8g.2xlarge for 1-3 nodes, db.r8g.4xlarge for 3-4 nodes."
  type        = string
  default     = "db.r8g.2xlarge"
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
# "opensearch" uses an AWS-managed OpenSearch domain. By default this
# configuration creates that domain, in opensearch.tf, sized by the
# opensearch_* variables below. A customer who already runs a domain names it
# in opensearch_domain_endpoint and opensearch_domain_name instead, and nothing
# is created.
#
# The created domain carries prevent_destroy, because it holds the index and
# rebuilding that index on a large estate is measured in hours. Removing it is
# therefore deliberate: see the note at the top of opensearch.tf.
#
# Sizing the domain: the shape each size needs is in the OpenSearch section of
# this directory's README.md. The defaults below are the Size M shape, so an L
# or XL deployment that leaves them unset gets an M domain.

variable "search_engine" {
  description = "Search backend for IQ Server: \"lucene\" (default) uses the index built into IQ Server and needs nothing else, \"opensearch\" uses an AWS-managed OpenSearch domain, created here unless opensearch_domain_endpoint names an existing one."
  type        = string
  default     = "lucene"

  validation {
    condition     = contains(["lucene", "opensearch"], var.search_engine)
    error_message = "search_engine must be one of: 'lucene', 'opensearch'."
  }
}

variable "opensearch_engine_version" {
  description = "OpenSearch engine version for the created domain, as AWS names it. Pinned rather than tracking the newest, so two bring-ups run the same engine and a measurement describes a known version."
  type        = string
  default     = "OpenSearch_3.7"

  validation {
    condition     = can(regex("^OpenSearch_[0-9]+\\.[0-9]+$", var.opensearch_engine_version))
    error_message = "opensearch_engine_version must look like \"OpenSearch_3.7\"."
  }
}

variable "opensearch_instance_type" {
  description = <<-EOT
    Data node instance type for the created domain.

    The default is the published type for Size M.
    Smaller types have been measured failing in ways that read as something
    else: a 1 vCPU node decayed 36 times over on the write path, from 223k to
    6.2k documents a second, and a 2 GiB node gives about 1.5 GiB to the JVM and
    swaps.

    See the OpenSearch section of this directory's README.md for the type each
    size needs.
  EOT
  type        = string
  default     = "m8g.large.search"

  validation {
    condition     = can(regex("\\.search$", var.opensearch_instance_type))
    error_message = "opensearch_instance_type must be an OpenSearch instance type, ending in \".search\", for example \"m8g.large.search\"."
  }
}

variable "opensearch_instance_count" {
  description = "Data nodes in the created domain. Three is the smallest count that can place a replica and spread across three availability zones, so a single-node domain is for a deployment that does neither."
  type        = number
  default     = 3

  validation {
    condition     = var.opensearch_instance_count >= 1 && var.opensearch_instance_count <= 20
    error_message = "opensearch_instance_count must be between 1 and 20."
  }
}

variable "opensearch_dedicated_master_type" {
  description = "Instance type for the three dedicated master nodes, which are created whenever the domain has more than one data node. Masters hold cluster state and run no indexing or search, so they are smaller than the data nodes."
  type        = string
  default     = "m8g.medium.search"

  validation {
    condition     = can(regex("\\.search$", var.opensearch_dedicated_master_type))
    error_message = "opensearch_dedicated_master_type must be an OpenSearch instance type, ending in \".search\"."
  }
}

variable "opensearch_volume_size_gb" {
  description = <<-EOT
    gp3 storage per data node, in GB.

    The index needs room for more than one copy of itself: a replica doubles it,
    and a re-index holds a second generation while it runs and for a short while
    after it cuts over. AWS also reserves 20% of each volume, capped at 20 GiB.

    See the OpenSearch section of this directory's README.md for the size each
    tier needs.
  EOT
  type        = number
  default     = 100

  validation {
    condition     = var.opensearch_volume_size_gb >= 10 && var.opensearch_volume_size_gb <= 3000
    error_message = "opensearch_volume_size_gb must be between 10 and 3000."
  }
}

variable "opensearch_availability_zone_count" {
  description = "Availability zones the created domain's data nodes spread across. 1 disables zone awareness. Above 1, opensearch_instance_count has to be a multiple of this, because AWS spreads data nodes evenly and refuses a domain where it cannot."
  type        = number
  default     = 3

  validation {
    condition     = contains([1, 2, 3], var.opensearch_availability_zone_count)
    error_message = "opensearch_availability_zone_count must be 1, 2 or 3."
  }
}

variable "opensearch_domain_endpoint" {
  description = "Host name of an OpenSearch domain that already exists, with no scheme and no trailing slash, for example \"search-my-domain-abc123.us-east-1.es.amazonaws.com\". Setting this means the domain is NOT created here and this one is used instead. Leave empty to have this configuration create the domain."
  type        = string
  default     = ""
}

variable "opensearch_domain_name" {
  description = <<-EOT
    Name of that same existing domain, for example "my-domain". Required when
    opensearch_domain_endpoint is set, and ignored when the domain is created
    here. Used to build the ARN the ECS task role is granted data-plane access
    on, so the grant names one domain rather than every domain in the account.

    An existing domain has to be in this same AWS account and in aws_region,
    because the ARN is built from aws_region and the calling account. A domain in
    another account or another region cannot be named this way, and the symptom
    is a 403 from the domain at runtime rather than an error at plan time.
    Reaching one would need the full ARN supplied instead, plus a matching
    principal in the domain's own access policy.
  EOT
  type        = string
  default     = ""
}

variable "opensearch_log_retention_days" {
  description = "Retention for the created domain's three CloudWatch log groups: the two slow logs and the application log. 30 days covers a rebuild and the weeks after it, which is when a slow query is worth attributing."
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.opensearch_log_retention_days)
    error_message = "opensearch_log_retention_days must be a retention period CloudWatch Logs accepts."
  }
}

variable "opensearch_create_log_resource_policy" {
  description = <<-EOT
    Whether to create the CloudWatch Logs resource policy that lets OpenSearch
    write the created domain's slow and application logs.

    A resource policy is account-wide and AWS allows 10 per region, so an account
    already at that quota cannot take another one and the apply fails with
    LimitExceededException. The answer at the quota is one policy covering every
    domain's log groups, written once by hand outside this configuration, and
    this set to false in each deployment.

    False affects the policy and nothing else. The domain's three log groups and
    its log_publishing_options are still created, so the shared policy has groups
    to name and the domain keeps its logs. That also means false without such a
    policy in the account is not a working configuration: the domain create fails
    on the log_publishing_options, rather than coming up with no logs.
  EOT
  type        = bool
  default     = true
}

variable "opensearch_index_replicas" {
  description = "Replicas per shard for the Nexus One index, written to config.yml as search.nexusOneIndexReplicas. This architecture always writes it; when IQ Server is not given a count, it uses 1. One is the default here, matching the default domain's three data nodes: at 0 replicas losing a node means rebuilding the index rather than recovering it."
  type        = number
  default     = 1

  validation {
    condition     = var.opensearch_index_replicas >= 0 && var.opensearch_index_replicas <= 10
    error_message = "opensearch_index_replicas must be between 0 and 10, the range IQ Server accepts."
  }
}