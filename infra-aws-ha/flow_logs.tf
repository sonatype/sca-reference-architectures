
# =============================================================================
# VPC Flow Logs (optional, see var.enable_vpc_flow_logs)
# =============================================================================
# Records accepted/rejected traffic for every ENI in the VPC to CloudWatch
# Logs. This is the most reliable way to reconstruct which client reached
# which backend during a security incident — particularly important once
# var.vpn_only = true, since at that point the CloudConnexa connector and
# internal ALB are the only path into the environment.
# =============================================================================

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  count             = local.enable_vpc_flow_logs ? 1 : 0
  name              = "/aws/vpc-flow-logs/${var.cluster_name}"
  retention_in_days = var.log_retention_days

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-vpc-flow-logs"
  })
}

resource "aws_iam_role" "vpc_flow_logs" {
  count       = local.enable_vpc_flow_logs ? 1 : 0
  name_prefix = "${var.cluster_name}-flow-logs-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-vpc-flow-logs-role"
  })
}

resource "aws_iam_role_policy" "vpc_flow_logs" {
  count = local.enable_vpc_flow_logs ? 1 : 0
  name  = "${var.cluster_name}-vpc-flow-logs-policy"
  role  = aws_iam_role.vpc_flow_logs[0].id

  # Scoped to the one log group this role delivers to (Terraform creates and
  # manages that group, so the role itself never needs logs:CreateLogGroup or
  # account-wide Describe* — only write access to its own log streams).
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "${aws_cloudwatch_log_group.vpc_flow_logs[0].arn}:*"
      }
    ]
  })
}

resource "aws_flow_log" "vpc" {
  count                = local.enable_vpc_flow_logs ? 1 : 0
  iam_role_arn         = aws_iam_role.vpc_flow_logs[0].arn
  log_destination      = aws_cloudwatch_log_group.vpc_flow_logs[0].arn
  log_destination_type = "cloud-watch-logs"
  traffic_type         = "ALL"
  vpc_id               = aws_vpc.iq_vpc.id

  tags = merge(var.common_tags, {
    Name = "${var.cluster_name}-vpc-flow-log"
  })
}
