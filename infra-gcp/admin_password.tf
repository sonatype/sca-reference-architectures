# IQ Server's initial admin password, read from Secret Manager by the instance
# startup script and handed to the container as NXIQ_INITIAL_ADMIN_PASSWORD,
# which IQ Server reads on its first start only. The service account's
# project-wide secretAccessor grant covers it.
resource "google_secret_manager_secret" "iq_admin_password" {
  secret_id = "${local.app_name}-iq-admin-password"
  project   = var.gcp_project_id

  replication {
    auto {}
  }

  depends_on = [google_project_service.required_apis]
}

resource "google_secret_manager_secret_version" "iq_admin_password" {
  secret      = google_secret_manager_secret.iq_admin_password.id
  secret_data = var.iq_admin_initial_password
}

output "iq_admin_initial_password" {
  description = "The initial admin password IQ Server was given, read by iq-post-deploy.sh"
  value       = var.iq_admin_initial_password
  sensitive   = true
}
