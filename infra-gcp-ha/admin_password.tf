# IQ Server's initial admin password, read from Secret Manager by the instance
# startup script and handed to the container as NXIQ_INITIAL_ADMIN_PASSWORD,
# which IQ Server reads on its first start only.
resource "google_secret_manager_secret" "iq_admin_password" {
  secret_id = "${local.app_name}-iq-admin-password-${random_string.suffix.result}"
  project   = var.gcp_project_id

  replication {
    auto {}
  }

  labels = merge(var.common_tags, {
    component = "nexus-iq-ha-admin-password"
  })

  depends_on = [google_project_service.required_apis]
}

resource "google_secret_manager_secret_version" "iq_admin_password" {
  secret      = google_secret_manager_secret.iq_admin_password.id
  secret_data = var.iq_admin_initial_password
}

resource "google_secret_manager_secret_iam_member" "iq_compute_admin_password" {
  secret_id = google_secret_manager_secret.iq_admin_password.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.iq_compute_service.email}"
  project   = var.gcp_project_id
}

output "iq_admin_initial_password" {
  description = "The initial admin password IQ Server was given, read by iq-post-deploy.sh"
  value       = var.iq_admin_initial_password
  sensitive   = true
}
