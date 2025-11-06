
resource "aws_cloudwatch_log_group" "iq_logs" {
  name              = "/eks/${var.cluster_name}/nexus-iq-server"
  retention_in_days = var.log_retention_days

  tags = {
    Name        = "${var.cluster_name}-iq-logs"
    Description = "Unified log group for all Nexus IQ Server logs"
    Environment = var.environment
    Project     = "nexus-iq-server-ha"
  }
}

resource "aws_iam_policy" "fluentd_cloudwatch" {
  name        = "${var.cluster_name}-fluentd-cloudwatch-policy"
  description = "IAM policy for Fluentd to write logs to CloudWatch"

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
        Resource = [
          "${aws_cloudwatch_log_group.iq_logs.arn}:*",
          "arn:aws:logs:*:*:log-group:/eks/${var.cluster_name}/*:*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "logs:CreateLogGroup"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "${var.cluster_name}-fluentd-cloudwatch-policy"
    Environment = var.environment
    Project     = "nexus-iq-server-ha"
  }
}

resource "aws_iam_role" "fluentd_irsa" {
  name = "${var.cluster_name}-fluentd-irsa-role"

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
          StringLike = {
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:nexus-iq:*"
          }
          StringEquals = {
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "${var.cluster_name}-fluentd-irsa-role"
    Environment = var.environment
    Project     = "nexus-iq-server-ha"
  }
}

resource "aws_iam_role_policy_attachment" "fluentd_cloudwatch" {
  role       = aws_iam_role.fluentd_irsa.name
  policy_arn = aws_iam_policy.fluentd_cloudwatch.arn
}
