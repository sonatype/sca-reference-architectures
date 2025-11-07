# Service Account for GCE Nexus IQ Service (equivalent to AWS EC2 instance role)
resource "google_service_account" "iq_service" {
  account_id   = "nexus-iq-service"
  display_name = "Nexus IQ Server Service Account"
  description  = "Service account for Nexus IQ Server GCE instances"
  project      = var.gcp_project_id
}

# Service Account for Database Operations (equivalent to AWS RDS enhanced monitoring role)
resource "google_service_account" "iq_database" {
  account_id   = "nexus-iq-database"
  display_name = "Nexus IQ Database Service Account"
  description  = "Service account for database operations and monitoring"
  project      = var.gcp_project_id
}

# IAM Policy Bindings for IQ Service Account

# Allow GCE instances to access Cloud SQL
resource "google_project_iam_member" "iq_service_sql_client" {
  project = var.gcp_project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.iq_service.email}"
}

# Allow GCE instances to access Secret Manager
resource "google_project_iam_member" "iq_service_secret_accessor" {
  project = var.gcp_project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.iq_service.email}"
}

# Allow GCE instances to write logs
resource "google_project_iam_member" "iq_service_log_writer" {
  project = var.gcp_project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.iq_service.email}"
}

# Allow GCE instances to access Filestore
resource "google_project_iam_member" "iq_service_filestore_editor" {
  project = var.gcp_project_id
  role    = "roles/file.editor"
  member  = "serviceAccount:${google_service_account.iq_service.email}"
}

# Allow GCE instances to write metrics
resource "google_project_iam_member" "iq_service_metric_writer" {
  project = var.gcp_project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.iq_service.email}"
}

# IAM Policy Bindings for Database Service Account

# Allow database service account to write logs  
resource "google_project_iam_member" "db_log_writer" {
  project = var.gcp_project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.iq_database.email}"
}

# Allow database service account monitoring access
resource "google_project_iam_member" "db_monitoring_writer" {
  project = var.gcp_project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.iq_database.email}"
}
