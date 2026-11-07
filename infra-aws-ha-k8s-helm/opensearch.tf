# =============================================================================
# SEARCH BACKEND
# =============================================================================
# IAM for IQ Server pods when the Nexus One index lives in an AWS-managed
# OpenSearch domain.
#
# The domain is created here too, at the bottom of this file, unless
# opensearch_domain_endpoint names one that already exists. It carries
# prevent_destroy because it holds the index, and its network interfaces sit in
# this VPC's subnets, so a teardown deletes the domain before the VPC. See the
# "terraform destroy will not delete the domain" section of this directory's
# README.md for the sequence, and its OpenSearch section for the shape each size
# needs.
#
# IQ Server reaches the domain by signing its requests with SigV4, so the pods
# need an IAM role. On EKS that is IAM Roles for Service Accounts: the role
# trusts the cluster's OIDC provider for one service account, and the chart
# annotates that service account with the role ARN. helm-install.sh reads the
# iq_server_irsa_role_arn output and writes it into the annotation.

resource "aws_iam_role" "iq_server_irsa" {
  count = var.search_engine == "opensearch" ? 1 : 0

  name = "${var.cluster_name}-iq-server-irsa-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          # Named down to the one service account the chart runs IQ Server under,
          # rather than every service account in the namespace.
          StringEquals = {
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:${var.helm_namespace}:nexus-iq-sa"
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge({
    Name        = "${var.cluster_name}-iq-server-irsa-role"
    Environment = var.environment
    Project     = "nexus-iq-server-ha"
  }, var.common_tags)
}

resource "aws_iam_policy" "iq_server_opensearch" {
  count = var.search_engine == "opensearch" ? 1 : 0

  name        = "${var.cluster_name}-iq-server-opensearch-policy"
  description = "Data-plane access to the OpenSearch domain holding the Nexus One index"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # One action per HTTP verb, because that is how AWS checks a signed
        # OpenSearch request. The domain's access_policies below says why a signed
        # request is the only kind it accepts.
        Effect = "Allow"
        Action = [
          "es:ESHttpGet",
          "es:ESHttpPost",
          "es:ESHttpPut",
          "es:ESHttpHead",
          "es:ESHttpDelete"
        ]
        Resource = [
          "arn:aws:es:${var.aws_region}:${data.aws_caller_identity.current.account_id}:domain/${local.opensearch_name}",
          "arn:aws:es:${var.aws_region}:${data.aws_caller_identity.current.account_id}:domain/${local.opensearch_name}/*"
        ]
      }
    ]
  })

  tags = merge({
    Name        = "${var.cluster_name}-iq-server-opensearch-policy"
    Environment = var.environment
    Project     = "nexus-iq-server-ha"
  }, var.common_tags)
}

resource "aws_iam_role_policy_attachment" "iq_server_opensearch" {
  count = var.search_engine == "opensearch" ? 1 : 0

  role       = aws_iam_role.iq_server_irsa[0].name
  policy_arn = aws_iam_policy.iq_server_opensearch[0].arn
}

# The nexus-iq-sa service account currently receives the Fluentd role, because
# helm-install.sh substitutes every empty role-arn annotation with the same
# value. Attaching the same CloudWatch policy here keeps what the pods can do
# today, so turning OpenSearch on only ever adds permissions.
resource "aws_iam_role_policy_attachment" "iq_server_cloudwatch" {
  count = var.search_engine == "opensearch" ? 1 : 0

  role       = aws_iam_role.iq_server_irsa[0].name
  policy_arn = aws_iam_policy.fluentd_cloudwatch.arn
}

# =============================================================================
# THE DOMAIN
# =============================================================================
# Created when search_engine is "opensearch" and opensearch_domain_endpoint is
# left empty. A customer who already runs a domain names it in that endpoint and
# opensearch_domain_name instead, and nothing below is created.
#
# Defaults are the smallest supported shape rather than any published size, so a
# value left unset is obviously too small rather than quietly wrong for the
# estate it holds.

locals {
  # Reading the endpoint rather than a separate flag keeps creating a domain and
  # naming one mutually exclusive by construction.
  opensearch_create = var.search_engine == "opensearch" && length(var.opensearch_domain_endpoint) == 0

  # AWS caps a domain name at 28 characters, and "-nexus-one" takes 10 of them,
  # so cluster_name contributes at most 18. cluster_name is allowed to be longer
  # than that because the names it has to fit elsewhere are longer, so the
  # prefix is truncated here rather than the deployment being refused. Two
  # deployments whose cluster_name shares its first 18 characters would ask for
  # the same domain name, so keep that part distinct.
  opensearch_domain_name = format(
    "%s-nexus-one",
    replace(substr(var.cluster_name, 0, min(18, length(var.cluster_name))), "/-+$/", "")
  )

  # The log groups are created whenever the domain is, so a shared hand-written
  # policy has groups to cover. Only the policy itself is behind
  # opensearch_create_log_resource_policy.
  opensearch_logs = local.opensearch_create

  opensearch_dedicated_master = local.opensearch_create && var.opensearch_instance_count > 1

  opensearch_zone_aware = local.opensearch_create && var.opensearch_availability_zone_count > 1

  # What the rest of this configuration reads, whichever way the domain arrived,
  # so a created domain and a named one are indistinguishable downstream.
  opensearch_endpoint = local.opensearch_create ? (
    length(aws_opensearch_domain.nexus_one) > 0 ? aws_opensearch_domain.nexus_one[0].endpoint : ""
  ) : var.opensearch_domain_endpoint

  opensearch_name = local.opensearch_create ? (
    length(aws_opensearch_domain.nexus_one) > 0 ? aws_opensearch_domain.nexus_one[0].domain_name : ""
  ) : var.opensearch_domain_name
}

# THE SERVICE-LINKED ROLE IS AN ACCOUNT-LEVEL PREREQUISITE, NOT A RESOURCE HERE.
# OpenSearch assumes AWSServiceRoleForAmazonOpenSearchService to put a VPC
# domain's network interfaces in these subnets, and the role has to exist in the
# account before the first domain is created. AWS creates it on its own when a
# VPC domain is created through the console, so an account that has ever held one
# already has it.
#
# It is deliberately not a resource in this configuration. AWS allows one per
# account, and this root is per deployment, so whichever deployment created it
# would own an object every other deployment's domain depends on: its teardown
# would try to delete the role out from under them. Create it once per account
# instead, before the first apply:
#
#     aws iam create-service-linked-role \
#       --aws-service-name opensearchservice.amazonaws.com
#
# The command fails when the role is already there, saying the name is taken,
# which is the one failure that means there is nothing to do. To check first:
#
#     aws iam list-roles \
#       --path-prefix /aws-service-role/opensearchservice.amazonaws.com/ \
#       --query 'Roles[].RoleName' --output text
#
# The calling identity needs iam:CreateServiceLinkedRole. An account still
# carrying the legacy AWSServiceRoleForAmazonElasticsearchService role goes on
# using that one and needs nothing.

# In the private subnets with the node group, so the domain is not reachable
# from the internet and needs no IP allow list. A pod's traffic leaves through
# its node, so the node security group is the source and nothing else in the VPC
# reaches the domain.
resource "aws_security_group" "opensearch" {
  count = local.opensearch_create ? 1 : 0

  name_prefix = "${var.cluster_name}-opensearch-sg"
  description = "HTTPS from the EKS nodes to the OpenSearch domain"
  vpc_id      = aws_vpc.iq_vpc.id

  # Both node security groups, because a pod's traffic carries whichever one its
  # node was launched with: the EKS module builds its own for the managed node
  # group, and eks.tf declares a second one.
  ingress {
    description = "HTTPS from the EKS nodes"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    security_groups = [
      aws_security_group.eks_nodes.id,
      module.eks.node_security_group_id,
    ]
  }

  tags = merge({
    Name        = "${var.cluster_name}-opensearch-sg"
    Environment = var.environment
    Project     = "nexus-iq-server-ha"
  }, var.common_tags)
}

# Domain-side logs, which are the only account of a failure the cluster itself saw. Without these a
# 5xx returned to IQ Server leaves nothing on the OpenSearch side to read, and a slow search cannot
# be told apart from a slow query.
#
# Audit logs are not here: they need fine-grained access control, which this architecture cannot turn
# on without breaking SigV4.
resource "aws_cloudwatch_log_group" "opensearch" {
  for_each = local.opensearch_logs ? toset(["INDEX_SLOW_LOGS", "SEARCH_SLOW_LOGS", "ES_APPLICATION_LOGS"]) : toset([])

  name              = "/aws/opensearch/${local.opensearch_domain_name}/${lower(each.key)}"
  retention_in_days = var.opensearch_log_retention_days

  tags = merge(var.common_tags, {
    Name = "${local.opensearch_domain_name}-${lower(each.key)}"
  })
}

# OpenSearch writes these streams itself, so the service principal needs its own grant on the log
# groups. The domain's access policy governs requests to the domain and does not cover this.
#
# A resource policy is account-wide and AWS allows 10 per region, so an account at that quota takes
# one hand-written policy covering every domain's log groups instead and sets
# opensearch_create_log_resource_policy to false here. That leaves the log groups and the domain's
# log_publishing_options in place, so the shared policy has groups to name and the domain keeps its
# logs. With the toggle false and no such policy in the account, the domain create fails on the
# log_publishing_options rather than coming up without logs.
resource "aws_cloudwatch_log_resource_policy" "opensearch" {
  count = local.opensearch_logs && var.opensearch_create_log_resource_policy ? 1 : 0

  policy_name = "${local.opensearch_domain_name}-logs"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "es.amazonaws.com" }
        Action = [
          "logs:PutLogEvents",
          "logs:CreateLogStream",
        ]
        Resource = [for lg in aws_cloudwatch_log_group.opensearch : "${lg.arn}:*"]
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
          ArnLike = {
            "aws:SourceArn" = "arn:aws:es:${var.aws_region}:${data.aws_caller_identity.current.account_id}:domain/${local.opensearch_domain_name}"
          }
        }
      }
    ]
  })
}

resource "aws_opensearch_domain" "nexus_one" {
  count = local.opensearch_create ? 1 : 0

  domain_name    = local.opensearch_domain_name
  engine_version = var.opensearch_engine_version

  dynamic "log_publishing_options" {
    for_each = local.opensearch_logs ? toset(["INDEX_SLOW_LOGS", "SEARCH_SLOW_LOGS", "ES_APPLICATION_LOGS"]) : toset([])

    content {
      log_type                 = log_publishing_options.key
      cloudwatch_log_group_arn = aws_cloudwatch_log_group.opensearch[log_publishing_options.key].arn
      enabled                  = true
    }
  }

  # The service-side grant has to exist before the domain tries to publish, or AWS rejects the
  # log_publishing_options with a validation error rather than creating the domain without logs.
  depends_on = [
    aws_cloudwatch_log_resource_policy.opensearch,
  ]

  cluster_config {
    instance_type  = var.opensearch_instance_type
    instance_count = var.opensearch_instance_count

    dedicated_master_enabled = local.opensearch_dedicated_master
    dedicated_master_type    = local.opensearch_dedicated_master ? var.opensearch_dedicated_master_type : null
    dedicated_master_count   = local.opensearch_dedicated_master ? 3 : null

    zone_awareness_enabled = local.opensearch_zone_aware

    dynamic "zone_awareness_config" {
      for_each = local.opensearch_zone_aware ? [1] : []
      content {
        availability_zone_count = var.opensearch_availability_zone_count
      }
    }
  }

  # One subnet per zone the domain spreads across, and exactly one when it does
  # not. More subnets than zones is refused by AWS.
  vpc_options {
    subnet_ids = local.opensearch_zone_aware ? slice(
      aws_subnet.private[*].id, 0, var.opensearch_availability_zone_count
    ) : [aws_subnet.private[0].id]
    security_group_ids = [aws_security_group.opensearch[0].id]
  }

  ebs_options {
    ebs_enabled = true
    volume_type = "gp3"
    volume_size = var.opensearch_volume_size_gb
  }

  encrypt_at_rest {
    enabled = true
  }

  node_to_node_encryption {
    enabled = true
  }

  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }

  # The IRSA role the IQ Server pods assume, named rather than wildcarded, so
  # only this deployment's own pods can reach the index. An IAM principal rather
  # than a user and password, because fine-grained access control is off: the
  # domain keeps no user database, so a SigV4-signed request is the only kind it
  # can authenticate.
  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { AWS = aws_iam_role.iq_server_irsa[0].arn }
        Action    = "es:*"
        Resource  = "arn:aws:es:${var.aws_region}:${data.aws_caller_identity.current.account_id}:domain/${local.opensearch_domain_name}/*"
      }
    ]
  })

  lifecycle {
    prevent_destroy = true

    precondition {
      condition     = length(local.opensearch_domain_name) <= 28
      error_message = "The domain name built from cluster_name is longer than the 28 characters AWS allows. opensearch.tf truncates cluster_name to 18 characters for this, so reaching this message means that truncation was changed."
    }

    precondition {
      condition = !local.opensearch_zone_aware || (
        var.opensearch_instance_count % var.opensearch_availability_zone_count == 0
      )
      error_message = "opensearch_instance_count must be a multiple of opensearch_availability_zone_count, because AWS spreads data nodes evenly across zones and refuses a domain where it cannot."
    }

    precondition {
      condition     = var.opensearch_availability_zone_count <= length(aws_subnet.private)
      error_message = "opensearch_availability_zone_count cannot exceed the number of private subnets this root builds, which is two, since the domain needs one subnet per zone. Three zones needs a third private subnet in main.tf."
    }
  }

  tags = merge({
    Name        = local.opensearch_domain_name
    Environment = var.environment
    Project     = "nexus-iq-server-ha"
  }, var.common_tags)
}
