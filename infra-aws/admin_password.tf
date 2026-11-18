# IQ Server's initial admin password. ecs.tf hands it to the container as
# NXIQ_INITIAL_ADMIN_PASSWORD, which IQ Server reads on its first start only.
resource "aws_secretsmanager_secret" "iq_admin_password" {
  name                    = "${var.cluster_name}-iq-admin-initial-password"
  description             = "Initial admin password for Nexus IQ Server"
  recovery_window_in_days = 0

  tags = {
    Name = "${var.cluster_name}-iq-admin-initial-password"
  }
}

resource "aws_secretsmanager_secret_version" "iq_admin_password" {
  secret_id     = aws_secretsmanager_secret.iq_admin_password.id
  secret_string = var.iq_admin_initial_password
}

output "iq_admin_password_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the initial admin password, force-deleted by tf-destroy.sh"
  value       = aws_secretsmanager_secret.iq_admin_password.arn
}

output "iq_admin_initial_password" {
  description = "The initial admin password IQ Server was given, read by iq-post-deploy.sh"
  value       = var.iq_admin_initial_password
  sensitive   = true
}
