# =============================================================================
# OPENSEARCH DOMAIN
# =============================================================================
# The AWS-managed OpenSearch domain that holds the Nexus One index.
#
# Created here when search_engine is "opensearch" and opensearch_domain_endpoint
# is left empty. A customer who already runs a domain sets that endpoint and
# opensearch_domain_name instead, and nothing in this file is created.
#
# This is the single-instance architecture, so the defaults are one data node
# with no replica and no dedicated masters. Three masters exist to hold cluster
# state off the data nodes and need a quorum, which one node cannot form, and a
# single-node domain has nowhere to place a replica. A domain sized for more
# than one node gets both, by raising opensearch_instance_count.
#
# THE DOMAIN IS PROTECTED RATHER THAN LEFT OUT OF TERRAFORM. It holds the index,
# and rebuilding that index on a large estate is measured in hours, so it
# carries prevent_destroy. A deliberate teardown removes it from state first:
#
#     terraform state rm aws_opensearch_domain.nexus_one
#     terraform destroy
#
# which makes losing the index a decision rather than a side effect.
#
# SIZING. The shape each size needs is in the OpenSearch section of this
# directory's README.md. The defaults are the smallest supported shape rather
# than any published size, so a value left unset is obviously too small rather
# than quietly wrong for the estate it holds.

locals {
  # Reading the endpoint rather than a separate flag keeps creating a domain and
  # naming one mutually exclusive by construction, so a customer cannot ask for
  # both and get an apply that silently prefers one.
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

# In the private subnets with the ECS task, so the domain is not reachable from
# the internet and needs no IP allow list.
resource "aws_security_group" "opensearch" {
  count = local.opensearch_create ? 1 : 0

  name_prefix = "${var.cluster_name}-opensearch-sg"
  description = "HTTPS from the IQ Server task to the OpenSearch domain"
  vpc_id      = aws_vpc.iq_vpc.id

  # 443 only, and only from the task. enforce_https below refuses a plaintext
  # request even on this port.
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
  # deployment's own task can reach the index. IQ Server signs its requests with
  # SigV4, which is why this is an IAM principal rather than a password.
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
