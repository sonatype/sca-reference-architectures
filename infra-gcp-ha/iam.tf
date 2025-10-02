# Service account for Compute Engine instances
resource "google_service_account" "iq_compute_service" {
  account_id   = "nexus-iq-ha-compute-sa"
  display_name = "Nexus IQ HA Compute Service Account"
  description  = "Service account for Nexus IQ HA Compute Engine instances"
  project      = var.gcp_project_id
}

# IAM roles for the compute service account
resource "google_project_iam_member" "iq_compute_logging" {
  project = var.gcp_project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.iq_compute_service.email}"
}

resource "google_project_iam_member" "iq_compute_monitoring" {
  project = var.gcp_project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.iq_compute_service.email}"
}

resource "google_project_iam_member" "iq_compute_monitoring_reader" {
  project = var.gcp_project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.iq_compute_service.email}"
}

# Secret Manager access for database credentials
resource "google_secret_manager_secret_iam_member" "iq_compute_db_credentials" {
  secret_id = google_secret_manager_secret.db_credentials.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.iq_compute_service.email}"
  project   = var.gcp_project_id
}

resource "google_secret_manager_secret_iam_member" "iq_compute_db_password" {
  secret_id = google_secret_manager_secret.db_password.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.iq_compute_service.email}"
  project   = var.gcp_project_id
}

# Cloud SQL Client role for database access
resource "google_project_iam_member" "iq_compute_sql_client" {
  project = var.gcp_project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.iq_compute_service.email}"
}

# Compute Engine instance admin (for metadata and disk operations)
resource "google_project_iam_member" "iq_compute_instance_admin" {
  project = var.gcp_project_id
  role    = "roles/compute.instanceAdmin.v1"
  member  = "serviceAccount:${google_service_account.iq_compute_service.email}"
}

# Storage admin for persistent disk access
resource "google_project_iam_member" "iq_compute_storage_admin" {
  project = var.gcp_project_id
  role    = "roles/compute.storageAdmin"
  member  = "serviceAccount:${google_service_account.iq_compute_service.email}"
}

# Service account for load balancer health checks
resource "google_service_account" "iq_load_balancer" {
  account_id   = "nexus-iq-ha-lb-sa"
  display_name = "Nexus IQ HA Load Balancer Service Account"
  description  = "Service account for Nexus IQ HA Load Balancer health checks"
  project      = var.gcp_project_id
}

# Load balancer service account permissions
resource "google_project_iam_member" "iq_lb_health_check" {
  project = var.gcp_project_id
  role    = "roles/compute.loadBalancerServiceUser"
  member  = "serviceAccount:${google_service_account.iq_load_balancer.email}"
}

# Monitoring roles for load balancer
resource "google_project_iam_member" "iq_lb_monitoring" {
  project = var.gcp_project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.iq_load_balancer.email}"
}