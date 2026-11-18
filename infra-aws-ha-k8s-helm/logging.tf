
# Container logs reach CloudWatch through the Amazon CloudWatch Observability add-on in
# eks.tf. Its Fluent Bit DaemonSet reads every container's stdout and writes it to the
# groups below. IQ Server's request, audit and policy-violation logs reach stdout through
# the console appenders in helm-values.yaml. The per-pod log files stay on EFS under
# /sonatype-work/clm-cluster/log.
#
# The add-on creates any of these groups that does not exist, with no expiry, so they are
# created here first to keep their retention managed.
resource "aws_cloudwatch_log_group" "container_insights" {
  for_each = toset(["application", "dataplane", "host", "performance"])

  name              = "/aws/containerinsights/${var.cluster_name}/${each.key}"
  retention_in_days = var.log_retention_days

  tags = {
    Name        = "${var.cluster_name}-containerinsights-${each.key}"
    Environment = var.environment
    Project     = "nexus-iq-server-ha"
  }
}

# The add-on's agents run as the cloudwatch-agent service account in the
# amazon-cloudwatch namespace, and assume this role through IRSA.
resource "aws_iam_role" "cloudwatch_agent" {
  name = "${var.cluster_name}-cloudwatch-agent"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = module.eks.oidc_provider_arn
        }
        Condition = {
          StringEquals = {
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:amazon-cloudwatch:cloudwatch-agent"
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "${var.cluster_name}-cloudwatch-agent"
    Environment = var.environment
    Project     = "nexus-iq-server-ha"
  }

  # The add-on takes this role's ARN, so the groups exist before it starts writing.
  depends_on = [aws_cloudwatch_log_group.container_insights]
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.cloudwatch_agent.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}
