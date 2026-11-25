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
    # The EKS module names the cluster IAM role "<cluster_name>-cluster-", and AWS caps a
    # role name prefix at 38 characters, so cluster_name can be at most 29.
    condition     = length(var.cluster_name) <= 29
    error_message = "cluster_name must be 29 characters or fewer, because the EKS cluster's IAM role is named with the prefix '<cluster_name>-cluster-' and AWS caps an IAM role name prefix at 38 characters."
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
  default     = "1.36"
}

variable "node_instance_type" {
  description = "EC2 instance type for EKS worker nodes. Graviton (arm64) and x86_64 types both work, the node AMI follows the instance architecture. Graviton5 types such as m9gd and r9g are not offered in every region, and the plan fails reading the type where it is missing: pick an x86 or an earlier Graviton type there. The default is the Size M value, m8g.2xlarge with 8 vCPU and 32 GB; Size L uses m8g.4xlarge and Size XL r9g.4xlarge."
  type        = string
  default     = "m8g.2xlarge"
}

variable "node_group_min_size" {
  description = "Minimum number of nodes in the EKS node group, one per IQ pod: 2 at Size M and L, 3 at Size XL."
  type        = number
  default     = 2
}

variable "node_group_max_size" {
  description = "Maximum number of nodes in the EKS node group: 3 at Size M, 4 at Size L, 5 at Size XL. Must be at least node_group_min_size."
  type        = number
  default     = 2
}

variable "node_group_desired_size" {
  description = "Number of nodes the EKS node group runs. Set it to node_group_min_size: 2 at Size M and L, 3 at Size XL."
  type        = number
  default     = 2
}

variable "node_disk_size" {
  description = "Disk size in GB for EKS worker nodes"
  type        = number
  default     = 50
}

variable "aurora_engine_version" {
  description = "Aurora PostgreSQL engine version."
  type        = string
  default     = "18.6"
}

variable "aurora_instance_class" {
  description = "Aurora instance class. The default is the Size M value; Size L uses db.r8g.2xlarge and Size XL db.r8g.4xlarge."
  type        = string
  default     = "db.r8g.xlarge"
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

variable "iq_admin_initial_password" {
  description = "Password for IQ Server's admin user, at least 12 characters. It is kept in a Kubernetes secret that helm-install.sh creates and the chart reads through iq_server.initialAdminPasswordSecret, and given to IQ Server as NXIQ_INITIAL_ADMIN_PASSWORD, which IQ Server reads only on its very first start, against an empty database. Changing it afterwards changes nothing: change the password in IQ Server instead."
  type        = string
  sensitive   = true

  validation {
    condition     = !can(regex("CHANGE_ME", var.iq_admin_initial_password)) && length(var.iq_admin_initial_password) >= 12
    error_message = "iq_admin_initial_password must be a real password of at least 12 characters, not a CHANGE_ME placeholder. Set it in terraform.tfvars."
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

variable "nexus_iq_replica_count" {
  description = "Number of Nexus IQ Server pods at start, the HPA minimum: 2 at Size M and L, 3 at Size XL."
  type        = number
  default     = 2
}

variable "helm_chart_version" {
  description = "Version of the Nexus IQ Server HA Helm chart. The chart sets the IQ Server image, so this also sets the IQ Server version."
  type        = string
  default     = "209.4.0"
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

# =============================================================================
# SEARCH BACKEND
# =============================================================================
# search_engine decides whether helm-install.sh fills in or removes the search:
# block in helm-values.yaml. "opensearch" creates a domain in opensearch.tf unless
# opensearch_domain_endpoint names one. README.md gives the shape per size.

variable "search_engine" {
  description = "Search backend for IQ Server, with no default: \"opensearch\" uses an AWS-managed OpenSearch domain for Advanced Search and the Nexus One index, created here unless opensearch_domain_endpoint names an existing one; \"builtin\" creates no OpenSearch, so Advanced Search uses IQ Server's built-in index, and Nexus One (IQ Server 1.210 and later) can keep its index in IQ Server's PostgreSQL database, chosen on the Nexus One setup page."
  type        = string

  validation {
    condition     = contains(["opensearch", "builtin"], var.search_engine)
    error_message = "search_engine must be \"opensearch\", for an OpenSearch domain, or \"builtin\", for no OpenSearch: Advanced Search then uses IQ Server's built-in index, and Nexus One (IQ Server 1.210 and later) can keep its index in IQ Server's PostgreSQL database. Replace the CHANGE_ME placeholder in terraform.tfvars with one of them."
  }
}

variable "opensearch_domain_endpoint" {
  description = "Host name of an OpenSearch domain that already exists, with no scheme and no trailing slash, for example \"search-my-domain-abc123.us-east-1.es.amazonaws.com\". Setting this means the domain is NOT created here and this one is used instead. Leave empty to have this configuration create the domain."
  type        = string
  default     = ""

  validation {
    condition     = !can(regex("CHANGE_ME", var.opensearch_domain_endpoint))
    error_message = "opensearch_domain_endpoint still holds a CHANGE_ME placeholder. Set a real value in terraform.tfvars."
  }
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
    condition     = !can(regex("CHANGE_ME", var.opensearch_domain_name))
    error_message = "opensearch_domain_name still holds a CHANGE_ME placeholder. Set a real value in terraform.tfvars."
  }
}

variable "opensearch_engine_version" {
  description = "OpenSearch engine version for the created domain, as AWS names it. The default is OpenSearch_3.7. Any OpenSearch 3.x version is supported."
  type        = string
  default     = "OpenSearch_3.7"

  validation {
    condition     = can(regex("^OpenSearch_3\\.[0-9]+$", var.opensearch_engine_version))
    error_message = "opensearch_engine_version must be an OpenSearch 3.x version, such as \"OpenSearch_3.7\"."
  }
}

variable "opensearch_instance_type" {
  description = <<-EOT
    Data node instance type for the created domain.

    The default is the published type for Size M.
    Use at least the published type for your size.

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
  description = "Data nodes in the created domain. The default, 3, is the Size M, L and XL value: one data node in each of three zones, with one replica, so losing a zone loses no data. iq-post-deploy.sh sets each Nexus One index's shard count to this number, so with opensearch_domain_endpoint set, give it the existing domain's data node count."
  type        = number
  default     = 3

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
    and a rebuild needs free disk for a second copy of the index. AWS also
    reserves 20% of each volume, capped at 20 GB.

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
  description = "Availability zones the created domain's data nodes spread across. 1 disables zone awareness. Above 1, opensearch_instance_count has to be a multiple of this, because AWS spreads data nodes evenly and refuses a domain where it cannot. The default, 3, uses the node group's two private subnets and a third subnet opensearch.tf builds for the domain alone, so the region needs three availability zones."
  type        = number
  default     = 3

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
  description = "Replicas per shard for the Nexus One index, written to config.yml as search.nexusOneIndexReplicas. This architecture always writes it; when IQ Server is not given a count, it uses 1. One is the default here, matching the default domain's three data nodes: at 0 replicas losing a node means rebuilding the index rather than recovering it."
  type        = number
  default     = 1

  validation {
    condition     = var.opensearch_index_replicas >= 0 && var.opensearch_index_replicas <= 10
    error_message = "opensearch_index_replicas must be between 0 and 10, the range IQ Server accepts."
  }
}

variable "common_tags" {
  description = "Extra tags merged onto the resources this configuration creates for the search backend. Keep the keys lowercase, and use none of name, environment or project: AWS treats tag keys as case-insensitive when it checks for duplicates, and this configuration already sets Name, Environment and Project, so a matching key fails the apply. Values name a deployment or a person, so set them in terraform.tfvars, which is gitignored, and never in terraform.tfvars.example."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for v in values(var.common_tags) : !can(regex("CHANGE_ME", v))])
    error_message = "common_tags still holds a CHANGE_ME placeholder. Set a real value in terraform.tfvars."
  }

  validation {
    condition     = alltrue([for k in keys(var.common_tags) : !contains(["name", "environment", "project"], lower(k))])
    error_message = "common_tags must not use the keys name, environment or project in any case. This configuration already sets Name, Environment and Project, and AWS refuses two tag keys that differ only in case."
  }
}
