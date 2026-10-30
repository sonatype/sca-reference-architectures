# =============================================================================
# SEARCH BACKEND
# =============================================================================
# IAM for IQ Server pods when the Nexus One index lives in an AWS-managed
# OpenSearch domain.
#
# The domain itself is not created here. See the OpenSearch section of this
# directory's README.md for why, and for the shape each size needs.
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
          "arn:aws:es:${var.aws_region}:${data.aws_caller_identity.current.account_id}:domain/${var.opensearch_domain_name}",
          "arn:aws:es:${var.aws_region}:${data.aws_caller_identity.current.account_id}:domain/${var.opensearch_domain_name}/*"
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
