# =============================================================================
# SEARCH BACKEND
# =============================================================================
# IAM for IQ Server pods when the Nexus One index lives in an AWS-managed
# OpenSearch domain.
#
# The domain is created here too, at the bottom of this file, unless
# opensearch_domain_endpoint names one that already exists. It carries
# prevent_destroy because it holds the index, so a deliberate teardown runs
# `terraform state rm aws_opensearch_domain.nexus_one` first.
#
# See the OpenSearch section of this directory's README.md for the shape each
# size needs.
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
        # Lets the pods sign their OpenSearch requests with SigV4, which is what
        # config.yml's "aws" search type does. A domain with fine-grained access
        # control turned off keeps no user database, so it cannot check a user
        # name and password and only accepts signed requests. AWS checks each
        # HTTP verb against its own action, so all five are granted rather than
        # guessing which ones IQ Server uses.
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

# In the private subnets with the node group, so the domain is not reachable
# from the internet and needs no IP allow list. The pods' own traffic leaves
# through the nodes, so the node security group is the source.
resource "aws_security_group" "opensearch" {
  count = local.opensearch_create ? 1 : 0

  name_prefix = "${var.cluster_name}-opensearch-sg"
  description = "HTTPS from the EKS nodes to the OpenSearch domain"
  vpc_id      = aws_vpc.iq_vpc.id

  ingress {
    description = "HTTPS from inside the VPC, which is where the nodes are"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.iq_vpc.cidr_block]
  }

  tags = merge({
    Name        = "${var.cluster_name}-opensearch-sg"
    Environment = var.environment
    Project     = "nexus-iq-server-ha"
  }, var.common_tags)
}

resource "aws_opensearch_domain" "nexus_one" {
  count = local.opensearch_create ? 1 : 0

  domain_name    = "${var.cluster_name}-nexus-one"
  engine_version = var.opensearch_engine_version

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
  # only this deployment's own pods can reach the index.
  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { AWS = aws_iam_role.iq_server_irsa[0].arn }
        Action    = "es:*"
        Resource  = "arn:aws:es:${var.aws_region}:${data.aws_caller_identity.current.account_id}:domain/${var.cluster_name}-nexus-one/*"
      }
    ]
  })

  lifecycle {
    prevent_destroy = true

    precondition {
      condition = !local.opensearch_zone_aware || (
        var.opensearch_instance_count % var.opensearch_availability_zone_count == 0
      )
      error_message = "opensearch_instance_count must be a multiple of opensearch_availability_zone_count, because AWS spreads data nodes evenly across zones and refuses a domain where it cannot."
    }
  }

  tags = merge({
    Name        = "${var.cluster_name}-nexus-one"
    Environment = var.environment
    Project     = "nexus-iq-server-ha"
  }, var.common_tags)
}
