# =============================================================================
# OPENSEARCH DOMAIN
# =============================================================================
# The domain that holds the Nexus One index. Created when search_engine is
# "opensearch" and opensearch_domain_endpoint is empty; naming an existing domain
# there creates nothing here.
#
# The domain carries prevent_destroy, and its interfaces sit in this VPC, so a
# teardown removes it from state and deletes it first:
#
#     DOMAIN=$(terraform output -raw opensearch_domain_name)
#     terraform state rm aws_opensearch_domain.nexus_one
#     aws opensearch delete-domain --domain-name "$DOMAIN"
#     # wait for the delete to finish
#     ./tf-destroy.sh
#
# Switching search_engine to "lucene", or to another domain, takes the same steps.

locals {
  # Naming an endpoint means use that domain, so creating and naming are exclusive.
  opensearch_create = var.search_engine == "opensearch" && length(var.opensearch_domain_endpoint) == 0

  # AWS caps a domain name at 28 characters, so cluster_name contributes at most 18.
  # Two deployments must differ within those 18.
  opensearch_domain_name = format(
    "%s-nexus-one",
    replace(substr(var.cluster_name, 0, min(18, length(var.cluster_name))), "/-+$/", "")
  )

  # The log groups follow the domain; only the resource policy has its own switch.
  opensearch_logs = local.opensearch_create

  opensearch_dedicated_master = local.opensearch_create && var.opensearch_instance_count > 1

  opensearch_zone_aware = local.opensearch_create && var.opensearch_availability_zone_count > 1

  # The endpoint and name the rest of the configuration reads, created or named.
  opensearch_endpoint = local.opensearch_create ? (
    length(aws_opensearch_domain.nexus_one) > 0 ? aws_opensearch_domain.nexus_one[0].endpoint : ""
  ) : var.opensearch_domain_endpoint

  opensearch_name = local.opensearch_create ? (
    length(aws_opensearch_domain.nexus_one) > 0 ? aws_opensearch_domain.nexus_one[0].domain_name : ""
  ) : var.opensearch_domain_name
}

# The OpenSearch service-linked role must exist in the account before the first
# domain. It is not managed here, because AWS allows one per account and every
# deployment's domain depends on it. Create it once:
#
#     aws iam create-service-linked-role \
#       --aws-service-name opensearchservice.amazonaws.com

# Reachable only from the IQ Server task, inside the private subnets.
resource "aws_security_group" "opensearch" {
  count = local.opensearch_create ? 1 : 0

  name_prefix = "${var.cluster_name}-opensearch-sg"
  description = "HTTPS from the IQ Server task to the OpenSearch domain"
  vpc_id      = aws_vpc.iq_vpc.id

  ingress {
    description     = "HTTPS from the IQ Server ECS task"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  tags = {
    Name = "${var.cluster_name}-opensearch-sg"
  }
}

# Slow logs and the application log. Audit logs need fine-grained access control,
# which stays off so that SigV4 requests work.
resource "aws_cloudwatch_log_group" "opensearch" {
  for_each = local.opensearch_logs ? toset(["INDEX_SLOW_LOGS", "SEARCH_SLOW_LOGS", "ES_APPLICATION_LOGS"]) : toset([])

  name              = "/aws/opensearch/${local.opensearch_domain_name}/${lower(each.key)}"
  retention_in_days = var.opensearch_log_retention_days

  tags = {
    Name = "${local.opensearch_domain_name}-${lower(each.key)}"
  }
}

# Lets OpenSearch write to the log groups. AWS allows 10 log resource policies per
# region; an account at that limit writes one shared policy and sets
# opensearch_create_log_resource_policy = false.
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

  # The grant must exist first, or AWS rejects log_publishing_options.
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

  # One subnet per zone, or exactly one without zone awareness.
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

  # This deployment's task role only. Fine-grained access control is off, so a
  # SigV4-signed request is the only kind the domain accepts.
  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { AWS = aws_iam_role.ecs_task_role.arn }
        Action = [
          "es:ESHttpGet",
          "es:ESHttpPost",
          "es:ESHttpPut",
          "es:ESHttpHead",
          "es:ESHttpDelete"
        ]
        Resource = "arn:aws:es:${var.aws_region}:${data.aws_caller_identity.current.account_id}:domain/${local.opensearch_domain_name}/*"
      }
    ]
  })

  lifecycle {
    prevent_destroy = true

    precondition {
      condition     = length(local.opensearch_domain_name) <= 28
      error_message = "The domain name built from cluster_name is longer than the 28 characters AWS allows. opensearch.tf truncates cluster_name to 18 characters for this, so the name exceeds the limit only if that truncation is removed."
    }

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
    Name = local.opensearch_domain_name
  }
}
