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
  description = <<-EOT
    Base name every resource in this root is named from: the EKS cluster itself, the
    load balancer, the IAM roles and policies, the log group, the SSM parameters,
    the Secrets Manager secret, the Aurora cluster, the KMS aliases, and the Name
    tag on each network resource.

    Change it per deployment so several deployments can share one AWS account. Many
    of those names have to be unique across an account or a region, so two
    deployments that leave this at the default collide on the second apply. Running
    one deployment per size, for example "nexus-iq-m" through "nexus-iq-xl", is what
    this is for.

    The default reproduces the names this root has always used, so leaving it alone
    changes nothing.
  EOT
  type        = string
  default     = "nexus-iq-ha"

  validation {
    # The longest name built from this that AWS length-limits is the load balancer,
    # "<cluster_name>-alb", capped at 32 characters. The EKS cluster name itself is
    # capped at 100, so the load balancer is the binding one. Checked here so a
    # too-long name fails the plan rather than the apply, after the VPC and Aurora
    # already exist.
    condition     = length(var.cluster_name) <= 28
    error_message = "cluster_name must be 28 characters or fewer, to leave room for the 4-character '-alb' suffix under AWS's 32-character load balancer name limit."
  }

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.cluster_name))
    error_message = "cluster_name must be lowercase letters, numbers and hyphens, and must not start or end with a hyphen, because it is used in load balancer and EKS cluster names."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "kubernetes_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.30"
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
  description = "Aurora PostgreSQL engine version"
  type        = string
  default     = "15.19"
}

variable "aurora_instance_class" {
  description = "Aurora instance class. Scale with number of IQ nodes: db.r6g.2xlarge for 1-3 nodes, db.r6g.4xlarge for 3-4 nodes."
  type        = string
  default     = "db.r6g.2xlarge"
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
  default     = false
}

variable "efs_provisioned_throughput" {
  description = "Provisioned throughput for EFS in MiB/s"
  type        = number
  default     = 100
}

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
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 7
}

# =============================================================================
# SEARCH BACKEND
# =============================================================================
# search_engine picks which search backend IQ Server's config.yml points at. On
# this architecture config.yml is written by the Helm chart from the
# iq_server.config block in helm-values.yaml, and helm-install.sh fills in or
# removes the `search:` block there according to this variable.
#
# "opensearch" needs an OpenSearch domain that already exists, named in
# opensearch_domain_name and reached at opensearch_domain_endpoint. This
# configuration creates the domain unless you name one. The domain holds the
# index, so keeping it outside Terraform means switching engines, replacing the
# node group or destroying this stack never deletes the indexed data, and the
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
  description = "Host name of an OpenSearch domain that already exists, with no scheme and no trailing slash, for example \"search-my-domain-abc123.us-east-1.es.amazonaws.com\". Setting this means the domain is NOT created here and this one is used instead. Leave empty to have this configuration create the domain."
  type        = string
  default     = ""
}

variable "opensearch_domain_name" {
  description = <<-EOT
    Name of that same existing domain, for example "my-domain". Required when
    opensearch_domain_endpoint is set, and ignored when the domain is created
    here. Used to build the ARN the IQ Server pods' IAM role is granted
    data-plane access on, so the grant names one domain rather than every domain
    in the account.

    An existing domain has to be in this same AWS account and in aws_region,
    because the ARN is built from aws_region and the calling account. A domain in
    another account or another region cannot be named this way, and the symptom
    is a 403 from the domain at runtime rather than an error at plan time.
    Reaching one would need the full ARN supplied instead, plus a matching
    principal in the domain's own access policy.
  EOT
  type        = string
  default     = ""

  validation {
    condition     = length(var.opensearch_domain_endpoint) == 0 || length(var.opensearch_domain_name) > 0
    error_message = "opensearch_domain_name must be set when opensearch_domain_endpoint names an existing domain."
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

    The default is the smallest type worth running rather than a published size.
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
  description = "Data nodes in the created domain. Two is the default, because this root builds two private subnets and AWS spreads data nodes evenly across the zones it is given. Two nodes in two zones with one replica keeps a complete copy of the index in each zone."
  type        = number
  default     = 2

  validation {
    condition     = var.opensearch_instance_count >= 1 && var.opensearch_instance_count <= 20
    error_message = "opensearch_instance_count must be between 1 and 20."
  }
}

variable "opensearch_dedicated_master_type" {
  description = "Instance type for the three dedicated master nodes, created whenever the domain has more than one data node. Masters hold cluster state and run no indexing or search, so they are smaller than the data nodes."
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
  default     = 50

  validation {
    condition     = var.opensearch_volume_size_gb >= 10 && var.opensearch_volume_size_gb <= 3000
    error_message = "opensearch_volume_size_gb must be between 10 and 3000."
  }
}

variable "opensearch_availability_zone_count" {
  description = "Availability zones the created domain's data nodes spread across. 1 disables zone awareness. Above 1, opensearch_instance_count has to be a multiple of this, because AWS spreads data nodes evenly and refuses a domain where it cannot. Two is the default and the most this root supports, because it builds two private subnets and the domain needs one subnet per zone. Three needs a third private subnet in main.tf."
  type        = number
  default     = 2

  validation {
    condition     = contains([1, 2, 3], var.opensearch_availability_zone_count)
    error_message = "opensearch_availability_zone_count must be 1, 2 or 3."
  }
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
  description = "Replicas per shard for the Nexus One index, written to config.yml as search.nexusOneIndexReplicas. IQ Server's own default is 0, so this configuration always writes the value rather than relying on that default. One is the default here, matching the default domain's two data nodes: at 0 replicas losing a node means rebuilding the index rather than recovering it."
  type        = number
  default     = 1

  validation {
    condition     = var.opensearch_index_replicas >= 0 && var.opensearch_index_replicas <= 10
    error_message = "opensearch_index_replicas must be between 0 and 10, the range IQ Server accepts."
  }
}

variable "common_tags" {
  description = "Extra tags merged onto the resources this configuration creates for the search backend. Keep the keys lowercase: AWS treats tag keys as case-insensitive when it checks for duplicates, so a key differing only in case from one already set fails the apply. Values name a deployment or a person, so set them in terraform.tfvars, which is gitignored, and never in terraform.tfvars.example."
  type        = map(string)
  default     = {}
}
