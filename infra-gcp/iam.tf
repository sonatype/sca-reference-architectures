# Service account for Cloud Run service
resource "google_service_account" "iq_service_account" {
  account_id   = "ref-arch-iq-service"
  display_name = "Nexus IQ Server Service Account"
  description  = "Service account for Nexus IQ Server Cloud Run service"
}

# Service account for load balancer
resource "google_service_account" "lb_service_account" {
  account_id   = "ref-arch-iq-lb"
  display_name = "Nexus IQ Load Balancer Service Account"
  description  = "Service account for load balancer access logs"
}

# Cloud SQL Client role for database access
resource "google_project_iam_member" "iq_cloudsql_client" {
  project = var.gcp_project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.iq_service_account.email}"
}

# Secret Manager access for database credentials
resource "google_secret_manager_secret_iam_member" "db_credentials_access" {
  secret_id = google_secret_manager_secret.db_credentials.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.iq_service_account.email}"
}

resource "google_secret_manager_secret_iam_member" "db_password_access" {
  secret_id = google_secret_manager_secret.db_password.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.iq_service_account.email}"
}

# Cloud Logging Writer role
resource "google_project_iam_member" "iq_logging_writer" {
  project = var.gcp_project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.iq_service_account.email}"
}

# Cloud Monitoring Metric Writer role
resource "google_project_iam_member" "iq_monitoring_writer" {
  project = var.gcp_project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.iq_service_account.email}"
}

# Cloud Trace Agent role
resource "google_project_iam_member" "iq_trace_agent" {
  project = var.gcp_project_id
  role    = "roles/cloudtrace.agent"
  member  = "serviceAccount:${google_service_account.iq_service_account.email}"
}

# Storage bucket access for backups
resource "google_project_iam_member" "iq_storage_admin" {
  project = var.gcp_project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.iq_service_account.email}"
}

# Filestore access for shared storage
resource "google_project_iam_member" "iq_filestore_viewer" {
  project = var.gcp_project_id
  role    = "roles/file.viewer"
  member  = "serviceAccount:${google_service_account.iq_service_account.email}"
}

# Load balancer service account permissions
resource "google_project_iam_member" "lb_logging_writer" {
  project = var.gcp_project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.lb_service_account.email}"
}

# Custom IAM role for IQ service specific permissions
resource "google_project_iam_custom_role" "iq_custom_role" {
  role_id     = "ref_arch_iq_custom_role"
  title       = "Nexus IQ Server Custom Role"
  description = "Custom role with specific permissions for Nexus IQ Server"
  permissions = [
    "cloudsql.instances.connect",
    "secretmanager.versions.access",
    "storage.objects.create",
    "storage.objects.delete",
    "storage.objects.get",
    "storage.objects.list",
    "logging.logEntries.create",
    "monitoring.metricDescriptors.create",
    "monitoring.metricDescriptors.get",
    "monitoring.metricDescriptors.list",
    "monitoring.monitoredResourceDescriptors.get",
    "monitoring.monitoredResourceDescriptors.list",
    "monitoring.timeSeries.create"
  ]
}

# Assign custom role to service account
resource "google_project_iam_member" "iq_custom_role_binding" {
  project = var.gcp_project_id
  role    = google_project_iam_custom_role.iq_custom_role.name
  member  = "serviceAccount:${google_service_account.iq_service_account.email}"
}

# Workload Identity binding (for future Kubernetes integration if needed)
resource "google_service_account_iam_member" "workload_identity_binding" {
  count              = var.enable_workload_identity ? 1 : 0
  service_account_id = google_service_account.iq_service_account.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.gcp_project_id}.svc.id.goog[${var.kubernetes_namespace}/${var.kubernetes_service_account}]"
}

# Cloud KMS access for encryption (if KMS is used)
resource "google_project_iam_member" "iq_kms_decrypt" {
  count   = var.kms_key_name != "" ? 1 : 0
  project = var.gcp_project_id
  role    = "roles/cloudkms.cryptoKeyDecrypter"
  member  = "serviceAccount:${google_service_account.iq_service_account.email}"
}

resource "google_project_iam_member" "iq_kms_encrypt" {
  count   = var.kms_key_name != "" ? 1 : 0
  project = var.gcp_project_id
  role    = "roles/cloudkms.cryptoKeyEncrypter"
  member  = "serviceAccount:${google_service_account.iq_service_account.email}"
}

# Artifact Registry access (if using private container registry)
resource "google_project_iam_member" "iq_artifact_registry_reader" {
  count   = var.private_registry ? 1 : 0
  project = var.gcp_project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.iq_service_account.email}"
}

# Error Reporting Agent role
resource "google_project_iam_member" "iq_error_reporting_writer" {
  project = var.gcp_project_id
  role    = "roles/errorreporting.writer"
  member  = "serviceAccount:${google_service_account.iq_service_account.email}"
}