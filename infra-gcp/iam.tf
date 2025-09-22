# Service Account for Cloud Run Nexus IQ Service
resource "google_service_account" "iq_service" {
  account_id   = "nexus-iq-service"
  display_name = "Nexus IQ Server Service Account"
  description  = "Service account for Nexus IQ Server Cloud Run service"
  project      = var.gcp_project_id
}

# Service Account for Load Balancer
resource "google_service_account" "iq_load_balancer" {
  account_id   = "nexus-iq-lb"
  display_name = "Nexus IQ Load Balancer Service Account"
  description  = "Service account for Nexus IQ Load Balancer"
  project      = var.gcp_project_id
}

# Service Account for Cloud SQL Proxy (if needed)
resource "google_service_account" "iq_sql_proxy" {
  account_id   = "nexus-iq-sql-proxy"
  display_name = "Nexus IQ SQL Proxy Service Account"
  description  = "Service account for Cloud SQL Proxy connections"
  project      = var.gcp_project_id
}

# Service Account for Monitoring and Logging
resource "google_service_account" "iq_monitoring" {
  account_id   = "nexus-iq-monitoring"
  display_name = "Nexus IQ Monitoring Service Account"
  description  = "Service account for monitoring and logging operations"
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

# Allow Cloud Run service to write metrics
resource "google_project_iam_member" "iq_service_metric_writer" {
  project = var.gcp_project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.iq_service.email}"
}

# Allow Cloud Run service to access Cloud Storage for backups
resource "google_project_iam_member" "iq_service_storage_admin" {
  project = var.gcp_project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.iq_service.email}"
}

# Allow Cloud Run service to access Filestore
resource "google_project_iam_member" "iq_service_filestore_editor" {
  project = var.gcp_project_id
  role    = "roles/file.editor"
  member  = "serviceAccount:${google_service_account.iq_service.email}"
}

# Allow Cloud Run service to access KMS for encryption/decryption
resource "google_project_iam_member" "iq_service_kms_user" {
  project = var.gcp_project_id
  role    = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member  = "serviceAccount:${google_service_account.iq_service.email}"
}

# IAM Policy Bindings for Load Balancer Service Account

# Allow Load Balancer to invoke Cloud Run services
resource "google_project_iam_member" "lb_service_run_invoker" {
  project = var.gcp_project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.iq_load_balancer.email}"
}

# Allow Load Balancer to write logs
resource "google_project_iam_member" "lb_service_log_writer" {
  project = var.gcp_project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.iq_load_balancer.email}"
}

# IAM Policy Bindings for SQL Proxy Service Account

# Allow SQL Proxy to connect to Cloud SQL instances
resource "google_project_iam_member" "sql_proxy_sql_client" {
  project = var.gcp_project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.iq_sql_proxy.email}"
}

# IAM Policy Bindings for Monitoring Service Account

# Allow monitoring service to read/write logs
resource "google_project_iam_member" "monitoring_log_writer" {
  project = var.gcp_project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.iq_monitoring.email}"
}

resource "google_project_iam_member" "monitoring_log_viewer" {
  project = var.gcp_project_id
  role    = "roles/logging.viewer"
  member  = "serviceAccount:${google_service_account.iq_monitoring.email}"
}

# Allow monitoring service to write metrics
resource "google_project_iam_member" "monitoring_metric_writer" {
  project = var.gcp_project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.iq_monitoring.email}"
}

resource "google_project_iam_member" "monitoring_metric_descriptor_writer" {
  project = var.gcp_project_id
  role    = "roles/monitoring.metricDescriptorWriter"
  member  = "serviceAccount:${google_service_account.iq_monitoring.email}"
}

# Allow monitoring service to read compute resources for dashboards
resource "google_project_iam_member" "monitoring_compute_viewer" {
  project = var.gcp_project_id
  role    = "roles/compute.viewer"
  member  = "serviceAccount:${google_service_account.iq_monitoring.email}"
}

# Custom IAM Role for Nexus IQ Operations
resource "google_project_iam_custom_role" "nexus_iq_operator" {
  role_id     = "nexusIqOperator"
  title       = "Nexus IQ Operator"
  description = "Custom role for Nexus IQ Server operations"
  permissions = [
    "cloudsql.instances.get",
    "cloudsql.instances.list",
    "cloudsql.databases.get",
    "cloudsql.databases.list",
    "run.services.get",
    "run.services.list",
    "run.revisions.get",
    "run.revisions.list",
    "storage.buckets.get",
    "storage.objects.create",
    "storage.objects.delete",
    "storage.objects.get",
    "storage.objects.list",
    "secretmanager.versions.access",
    "file.instances.get",
    "file.snapshots.create",
    "file.snapshots.get",
    "file.snapshots.list",
    "monitoring.timeSeries.create",
    "logging.logEntries.create"
  ]
}

# Bind custom role to IQ service account 
resource "google_project_iam_member" "iq_service_custom_role" {
  project = var.gcp_project_id
  role    = google_project_iam_custom_role.nexus_iq_operator.name
  member  = "serviceAccount:${google_service_account.iq_service.email}"
}

# IAM Bindings for Admin Users (optional)
resource "google_project_iam_member" "admin_users_compute_admin" {
  for_each = var.admin_users
  project  = var.gcp_project_id
  role     = "roles/compute.admin"
  member   = each.value
}

resource "google_project_iam_member" "admin_users_sql_admin" {
  for_each = var.admin_users
  project  = var.gcp_project_id
  role     = "roles/cloudsql.admin"
  member   = each.value
}

resource "google_project_iam_member" "admin_users_run_admin" {
  for_each = var.admin_users
  project  = var.gcp_project_id
  role     = "roles/run.admin"
  member   = each.value
}

resource "google_project_iam_member" "admin_users_storage_admin" {
  for_each = var.admin_users
  project  = var.gcp_project_id
  role     = "roles/storage.admin"
  member   = each.value
}

# IAM Bindings for Developer Users (optional)
resource "google_project_iam_member" "developer_users_compute_viewer" {
  for_each = var.developer_users
  project  = var.gcp_project_id
  role     = "roles/compute.viewer"
  member   = each.value
}

resource "google_project_iam_member" "developer_users_sql_viewer" {
  for_each = var.developer_users
  project  = var.gcp_project_id
  role     = "roles/cloudsql.viewer"
  member   = each.value
}

resource "google_project_iam_member" "developer_users_run_viewer" {
  for_each = var.developer_users
  project  = var.gcp_project_id
  role     = "roles/run.viewer"
  member   = each.value
}

resource "google_project_iam_member" "developer_users_logging_viewer" {
  for_each = var.developer_users
  project  = var.gcp_project_id
  role     = "roles/logging.viewer"
  member   = each.value
}

resource "google_project_iam_member" "developer_users_monitoring_viewer" {
  for_each = var.developer_users
  project  = var.gcp_project_id
  role     = "roles/monitoring.viewer"
  member   = each.value
}

# Workload Identity binding for Kubernetes (if needed for future expansion)
resource "google_service_account_iam_binding" "workload_identity_binding" {
  count              = var.enable_workload_identity ? 1 : 0
  service_account_id = google_service_account.iq_service.name
  role               = "roles/iam.workloadIdentityUser"

  members = [
    "serviceAccount:${var.gcp_project_id}.svc.id.goog[${var.k8s_namespace}/${var.k8s_service_account}]"
  ]
}

# Service Account Keys (for external applications if needed)
resource "google_service_account_key" "iq_service_key" {
  count              = var.create_service_account_keys ? 1 : 0
  service_account_id = google_service_account.iq_service.name
  public_key_type    = "TYPE_X509_PEM_FILE"
}

resource "google_service_account_key" "monitoring_service_key" {
  count              = var.create_service_account_keys ? 1 : 0
  service_account_id = google_service_account.iq_monitoring.name
  public_key_type    = "TYPE_X509_PEM_FILE"
}

# Store service account keys in Secret Manager (if created)
resource "google_secret_manager_secret" "iq_service_key" {
  count     = var.create_service_account_keys ? 1 : 0
  secret_id = "nexus-iq-service-account-key"
  project   = var.gcp_project_id

  replication {
    automatic = true
  }
}

resource "google_secret_manager_secret_version" "iq_service_key" {
  count       = var.create_service_account_keys ? 1 : 0
  secret      = google_secret_manager_secret.iq_service_key[0].id
  secret_data = base64decode(google_service_account_key.iq_service_key[0].private_key)
}

# IAM Audit Configuration
resource "google_project_iam_audit_config" "audit_config" {
  project = var.gcp_project_id
  service = "allServices"

  audit_log_config {
    log_type = "ADMIN_READ"
  }

  audit_log_config {
    log_type = "DATA_READ"
  }

  audit_log_config {
    log_type = "DATA_WRITE"
  }
}