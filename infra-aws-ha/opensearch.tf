# =============================================================================
# OPENSEARCH DOMAIN
# =============================================================================
# The AWS-managed OpenSearch domain that holds the Nexus One index.
#
# Created here when search_engine is "opensearch" and opensearch_domain_endpoint
# is left empty, which is the usual case. A customer who already runs a domain
# sets opensearch_domain_endpoint and opensearch_domain_name instead, and nothing
# in this file is created.
#
# WHY THE DOMAIN IS PROTECTED RATHER THAN LEFT OUT OF TERRAFORM.
#
# The domain holds the index, and rebuilding that index on a large estate is
# measured in hours, so a `terraform destroy` that takes the domain with it is a
# real loss. The earlier answer was to leave the domain out of this
# configuration entirely, which protected the data and left a customer who
# builds exactly what we publish with no way to turn Nexus One on.
#
# So the domain is created here and carries `prevent_destroy`. A deliberate
# teardown removes it from state first:
#
#     terraform state rm aws_opensearch_domain.nexus_one
#     terraform destroy
#
# and then the domain is deleted by hand, or kept and named through
# opensearch_domain_endpoint on the next apply. That makes losing the index a
# decision rather than a side effect.
#
# SIZING. The shape each size needs is in the OpenSearch section of this
# directory's README.md. The variables below default to the smallest supported
# shape rather than to any published size, so a value left unset is obviously
# too small rather than quietly wrong for the estate it is holding.

locals {
  # Whether to create the domain, as opposed to naming one the customer already
  # runs. Reading the endpoint rather than a separate flag keeps the two
  # mutually exclusive by construction: a customer cannot ask for both and get
  # an apply that silently prefers one.
  opensearch_create = var.search_engine == "opensearch" && length(var.opensearch_domain_endpoint) == 0

  # Dedicated master nodes are what keep a multi-node domain's cluster state off
  # the data nodes. AWS requires three for a quorum, so this is on or off rather
  # than a count, and it is off for a single data node where there is no quorum
  # to form and nothing to protect.
  opensearch_dedicated_master = local.opensearch_create && var.opensearch_instance_count > 1

  # Zone awareness spreads shards across availability zones, and needs the data
  # node count to be a multiple of the zone count or AWS refuses the domain.
  opensearch_zone_aware = local.opensearch_create && var.opensearch_availability_zone_count > 1

  # The endpoint and name the rest of this configuration uses, whichever way the
  # domain arrived. Every consumer reads these rather than the variables, so a
  # created domain and a named one are indistinguishable downstream.
  opensearch_endpoint = local.opensearch_create ? (
    length(aws_opensearch_domain.nexus_one) > 0 ? aws_opensearch_domain.nexus_one[0].endpoint : ""
  ) : var.opensearch_domain_endpoint

  opensearch_name = local.opensearch_create ? (
    length(aws_opensearch_domain.nexus_one) > 0 ? aws_opensearch_domain.nexus_one[0].domain_name : ""
  ) : var.opensearch_domain_name
}

# The domain sits in the private subnets with the ECS tasks, so it is not
# reachable from the internet at all and needs no IP allow list.
resource "aws_security_group" "opensearch" {
  count = local.opensearch_create ? 1 : 0

  name_prefix = "${var.cluster_name}-opensearch-sg"
  description = "HTTPS from the IQ Server tasks to the OpenSearch domain"
  vpc_id      = aws_vpc.iq_vpc.id

  # 443 only, and only from the tasks. The domain speaks HTTPS and nothing else,
  # and enforce_https below refuses a plaintext request even on this port.
  ingress {
    description     = "HTTPS from the IQ Server ECS tasks"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  tags = {
    Name = "${var.cluster_name}-opensearch-sg"
  }
}

# Domain-side logs, which are the only account of a failure the cluster itself saw. Without these a
# 5xx returned to IQ Server leaves nothing on the OpenSearch side to read, and a slow search cannot
# be told apart from a slow query.
#
# Audit logs are not here: they need fine-grained access control, which this architecture cannot turn
# on without breaking SigV4.
resource "aws_cloudwatch_log_group" "opensearch" {
  for_each = local.opensearch_create ? toset(["INDEX_SLOW_LOGS", "SEARCH_SLOW_LOGS", "ES_APPLICATION_LOGS"]) : toset([])

  name              = "/aws/opensearch/${var.cluster_name}-nexus-one/${lower(each.key)}"
  retention_in_days = var.opensearch_log_retention_days

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-nexus-one-${lower(each.key)}"
  })
}

# OpenSearch writes these streams itself, so the service principal needs its own grant on the log
# groups. The domain's access policy governs requests to the domain and does not cover this.
resource "aws_cloudwatch_log_resource_policy" "opensearch" {
  count = local.opensearch_create ? 1 : 0

  policy_name = "${var.cluster_name}-nexus-one-logs"

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
            "aws:SourceArn" = "arn:aws:es:${var.aws_region}:${data.aws_caller_identity.current.account_id}:domain/${var.cluster_name}-nexus-one"
          }
        }
      }
    ]
  })
}

resource "aws_opensearch_domain" "nexus_one" {
  count = local.opensearch_create ? 1 : 0

  domain_name    = "${var.cluster_name}-nexus-one"
  engine_version = var.opensearch_engine_version

  dynamic "log_publishing_options" {
    for_each = toset(["INDEX_SLOW_LOGS", "SEARCH_SLOW_LOGS", "ES_APPLICATION_LOGS"])

    content {
      log_type                 = log_publishing_options.key
      cloudwatch_log_group_arn = aws_cloudwatch_log_group.opensearch[log_publishing_options.key].arn
      enabled                  = true
    }
  }

  # The service-side grant has to exist before the domain tries to publish, or AWS rejects the
  # log_publishing_options with a validation error rather than creating the domain without logs.
  depends_on = [aws_cloudwatch_log_resource_policy.opensearch]

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

  # One subnet per availability zone the domain spreads across, and exactly one
  # when it does not. Passing more subnets than zones is refused by AWS.
  vpc_options {
    subnet_ids = local.opensearch_zone_aware ? slice(
      aws_subnet.private_subnets[*].id, 0, var.opensearch_availability_zone_count
    ) : [aws_subnet.private_subnets[0].id]
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

  # The IQ Server task role alone, named rather than wildcarded, so only this
  # deployment's own tasks can reach the index. IQ signs its requests with
  # SigV4, which is why an IAM principal rather than a user and password.
  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { AWS = aws_iam_role.ecs_task_role.arn }
        Action    = "es:*"
        Resource  = "arn:aws:es:${var.aws_region}:${data.aws_caller_identity.current.account_id}:domain/${var.cluster_name}-nexus-one/*"
      }
    ]
  })

  lifecycle {
    # See the note at the top of this file. The domain holds the index, and
    # rebuilding it is measured in hours, so removing it has to be deliberate.
    prevent_destroy = true

    precondition {
      condition = !local.opensearch_zone_aware || (
        var.opensearch_instance_count % var.opensearch_availability_zone_count == 0
      )
      error_message = "opensearch_instance_count must be a multiple of opensearch_availability_zone_count, because AWS spreads data nodes evenly across zones and refuses a domain where it cannot."
    }

    precondition {
      condition     = var.opensearch_availability_zone_count <= length(var.private_subnet_cidrs)
      error_message = "opensearch_availability_zone_count cannot exceed the number of private subnets, since the domain needs one subnet per zone."
    }
  }

  tags = {
    Name = "${var.cluster_name}-nexus-one"
  }
}
