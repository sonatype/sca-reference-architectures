# CloudWatch Logging Infrastructure for Nexus IQ Server on EKS
# Implements structured logging with Fluentd sidecar (similar to infra-aws-ha Fluent Bit setup)

# CloudWatch Log Groups for structured logging
resource "aws_cloudwatch_log_group" "iq_logs_application" {
  name              = "/eks/${var.cluster_name}/nexus-iq-server/application"
  retention_in_days = var.log_retention_days

  tags = {
    Name        = "${var.cluster_name}-iq-logs-application"
    Description = "Main application logs from Nexus IQ Server"
    Environment = var.environment
    Project     = "nexus-iq-server-ha"
  }
}

resource "aws_cloudwatch_log_group" "iq_logs_request" {
  name              = "/eks/${var.cluster_name}/nexus-iq-server/request"
  retention_in_days = var.log_retention_days

  tags = {
    Name        = "${var.cluster_name}-iq-logs-request"
    Description = "HTTP request logs with parsed fields"
    Environment = var.environment
    Project     = "nexus-iq-server-ha"
  }
}

resource "aws_cloudwatch_log_group" "iq_logs_audit" {
  name              = "/eks/${var.cluster_name}/nexus-iq-server/audit"
  retention_in_days = var.log_retention_days

  tags = {
    Name        = "${var.cluster_name}-iq-logs-audit"
    Description = "Audit logs in JSON format"
    Environment = var.environment
    Project     = "nexus-iq-server-ha"
  }
}

resource "aws_cloudwatch_log_group" "iq_logs_policy_violation" {
  name              = "/eks/${var.cluster_name}/nexus-iq-server/policy-violation"
  retention_in_days = var.log_retention_days

  tags = {
    Name        = "${var.cluster_name}-iq-logs-policy-violation"
    Description = "Policy violation logs in JSON format"
    Environment = var.environment
    Project     = "nexus-iq-server-ha"
  }
}

resource "aws_cloudwatch_log_group" "iq_logs_stderr" {
  name              = "/eks/${var.cluster_name}/nexus-iq-server/stderr"
  retention_in_days = var.log_retention_days

  tags = {
    Name        = "${var.cluster_name}-iq-logs-stderr"
    Description = "Standard error output from Nexus IQ Server System.err"
    Environment = var.environment
    Project     = "nexus-iq-server-ha"
  }
}

resource "aws_cloudwatch_log_group" "iq_logs_fluentd" {
  name              = "/eks/${var.cluster_name}/nexus-iq-server/fluentd"
  retention_in_days = 7 # Shorter retention for Fluentd internal logs

  tags = {
    Name        = "${var.cluster_name}-iq-logs-fluentd"
    Description = "Fluentd sidecar container logs"
    Environment = var.environment
    Project     = "nexus-iq-server-ha"
  }
}

# IAM Policy for Fluentd to write to CloudWatch Logs
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
          "${aws_cloudwatch_log_group.iq_logs_application.arn}:*",
          "${aws_cloudwatch_log_group.iq_logs_request.arn}:*",
          "${aws_cloudwatch_log_group.iq_logs_audit.arn}:*",
          "${aws_cloudwatch_log_group.iq_logs_policy_violation.arn}:*",
          "${aws_cloudwatch_log_group.iq_logs_stderr.arn}:*",
          "${aws_cloudwatch_log_group.iq_logs_fluentd.arn}:*",
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

# IAM Role for Service Account (IRSA) - Fluentd
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

# Attach CloudWatch policy to IRSA role
resource "aws_iam_role_policy_attachment" "fluentd_cloudwatch" {
  role       = aws_iam_role.fluentd_irsa.name
  policy_arn = aws_iam_policy.fluentd_cloudwatch.arn
}
