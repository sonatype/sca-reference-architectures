# Service Account for Cloud Run Nexus IQ Service (equivalent to AWS ECS task role)
resource "google_service_account" "iq_service" {
  account_id   = "nexus-iq-service"
  display_name = "Nexus IQ Server Service Account"
  description  = "Service account for Nexus IQ Server Cloud Run service"
  project      = var.gcp_project_id
}

# Service Account for Load Balancer (equivalent to AWS ALB service role)
resource "google_service_account" "iq_load_balancer" {
  account_id   = "nexus-iq-lb"
  display_name = "Nexus IQ Load Balancer Service Account"
  description  = "Service account for Nexus IQ Load Balancer"
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

# Allow Cloud Run service to access Cloud SQL
resource "google_project_iam_member" "iq_service_sql_client" {
  project = var.gcp_project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.iq_service.email}"
}

# Allow Cloud Run service to access Secret Manager
resource "google_project_iam_member" "iq_service_secret_accessor" {
  project = var.gcp_project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.iq_service.email}"
}

# Allow Cloud Run service to write logs
resource "google_project_iam_member" "iq_service_log_writer" {
  project = var.gcp_project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.iq_service.email}"
}

# Allow Cloud Run service to access Filestore
resource "google_project_iam_member" "iq_service_filestore_editor" {
  project = var.gcp_project_id
  role    = "roles/file.editor"
  member  = "serviceAccount:${google_service_account.iq_service.email}"
}

# IAM Policy Bindings for Load Balancer Service Account

# Allow Load Balancer to access Cloud Run services  
resource "google_project_iam_member" "lb_service_invoker" {
  project = var.gcp_project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.iq_load_balancer.email}"
}

# Allow Load Balancer to write logs
resource "google_project_iam_member" "lb_log_writer" {
  project = var.gcp_project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.iq_load_balancer.email}"
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

