# Cloud Filestore for persistent shared storage (Single-instance)
resource "google_filestore_instance" "iq_filestore" {
  name     = "nexus-iq-filestore"
  location = var.filestore_zone
  tier     = var.filestore_tier
  project  = var.gcp_project_id

  file_shares {
    capacity_gb = var.filestore_capacity_gb
    name        = "nexus_iq_data"

    nfs_export_options {
      ip_ranges   = [var.private_subnet_cidr]
      access_mode = "READ_WRITE"
      squash_mode = "NO_ROOT_SQUASH"
    }
  }

  networks {
    network = google_compute_network.iq_vpc.name
    modes   = ["MODE_IPV4"]
  }

  labels = {
    environment = var.environment
    component   = "nexus-iq-storage"
  }

  depends_on = [google_project_service.required_apis]
}

# Cloud Filestore for HA persistent shared storage (Optional)
resource "google_filestore_instance" "iq_ha_filestore" {
  count    = var.enable_ha ? 1 : 0
  name     = "nexus-iq-ha-filestore"
  location = var.filestore_zone
  tier     = var.filestore_ha_tier
  project  = var.gcp_project_id

  file_shares {
    capacity_gb = var.filestore_ha_capacity_gb
    name        = "nexus_iq_ha_data"

    nfs_export_options {
      ip_ranges   = [var.private_subnet_cidr]
      access_mode = "READ_WRITE"
      squash_mode = "NO_ROOT_SQUASH"
    }
  }

  networks {
    network = google_compute_network.iq_vpc.name
    modes   = ["MODE_IPV4"]
  }

  labels = {
    environment = var.environment
    component   = "nexus-iq-ha-storage"
  }

  depends_on = [google_project_service.required_apis]
}

# Cloud Storage bucket for backups and logs
resource "google_storage_bucket" "iq_backups" {
  name          = "nexus-iq-backups-${random_string.suffix.result}"
  location      = var.gcp_region
  project       = var.gcp_project_id
  force_destroy = var.storage_force_destroy

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = var.backup_retention_days
    }
    action {
      type = "Delete"
    }
  }

  lifecycle_rule {
    condition {
      num_newer_versions = var.backup_max_versions
    }
    action {
      type = "Delete"
    }
  }

  encryption {
    default_kms_key_name = google_kms_crypto_key.iq_storage_key.id
  }

  labels = {
    environment = var.environment
    component   = "nexus-iq-backups"
  }

  depends_on = [google_project_service.required_apis]
}

# Cloud Storage bucket for application logs
resource "google_storage_bucket" "iq_logs" {
  name          = "nexus-iq-logs-${random_string.suffix.result}"
  location      = var.gcp_region
  project       = var.gcp_project_id
  force_destroy = var.storage_force_destroy

  uniform_bucket_level_access = true

  lifecycle_rule {
    condition {
      age = var.log_retention_days
    }
    action {
      type = "Delete"
    }
  }

  encryption {
    default_kms_key_name = google_kms_crypto_key.iq_storage_key.id
  }

  labels = {
    environment = var.environment
    component   = "nexus-iq-logs"
  }

  depends_on = [google_project_service.required_apis]
}

# Cloud Storage bucket for load balancer logs
resource "google_storage_bucket" "lb_logs" {
  name          = "nexus-iq-lb-logs-${random_string.suffix.result}"
  location      = var.gcp_region
  project       = var.gcp_project_id
  force_destroy = var.storage_force_destroy

  uniform_bucket_level_access = true

  lifecycle_rule {
    condition {
      age = var.lb_log_retention_days
    }
    action {
      type = "Delete"
    }
  }

  encryption {
    default_kms_key_name = google_kms_crypto_key.iq_storage_key.id
  }

  labels = {
    environment = var.environment
    component   = "nexus-iq-lb-logs"
  }

  depends_on = [google_project_service.required_apis]
}

# KMS Key Ring for encryption
resource "google_kms_key_ring" "iq_keyring" {
  name     = "nexus-iq-keyring"
  location = var.gcp_region
  project  = var.gcp_project_id

  depends_on = [google_project_service.required_apis]
}

# KMS Crypto Key for storage encryption
resource "google_kms_crypto_key" "iq_storage_key" {
  name     = "nexus-iq-storage-key"
  key_ring = google_kms_key_ring.iq_keyring.id
  purpose  = "ENCRYPT_DECRYPT"

  rotation_period = var.kms_key_rotation_period

  lifecycle {
    prevent_destroy = true
  }

  labels = {
    environment = var.environment
    component   = "nexus-iq-encryption"
  }
}

# KMS Crypto Key for database encryption
resource "google_kms_crypto_key" "iq_database_key" {
  name     = "nexus-iq-database-key"
  key_ring = google_kms_key_ring.iq_keyring.id
  purpose  = "ENCRYPT_DECRYPT"

  rotation_period = var.kms_key_rotation_period

  lifecycle {
    prevent_destroy = true
  }

  labels = {
    environment = var.environment
    component   = "nexus-iq-database-encryption"
  }
}

# IAM binding for Cloud SQL to use KMS key
resource "google_kms_crypto_key_iam_binding" "database_key_binding" {
  crypto_key_id = google_kms_crypto_key.iq_database_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"

  members = [
    "serviceAccount:service-${data.google_project.current.number}@gcp-sa-cloud-sql.iam.gserviceaccount.com",
  ]
}

# IAM binding for Cloud Storage to use KMS key
resource "google_kms_crypto_key_iam_binding" "storage_key_binding" {
  crypto_key_id = google_kms_crypto_key.iq_storage_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"

  members = [
    "serviceAccount:service-${data.google_project.current.number}@gs-project-accounts.iam.gserviceaccount.com",
    "serviceAccount:${google_service_account.iq_service.email}",
  ]
}

# Cloud Storage bucket for Terraform state (optional)
resource "google_storage_bucket" "terraform_state" {
  count         = var.create_terraform_state_bucket ? 1 : 0
  name          = "nexus-iq-terraform-state-${random_string.suffix.result}"
  location      = var.gcp_region
  project       = var.gcp_project_id
  force_destroy = false

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 5
    }
    action {
      type = "Delete"
    }
  }

  encryption {
    default_kms_key_name = google_kms_crypto_key.iq_storage_key.id
  }

  labels = {
    environment = var.environment
    component   = "terraform-state"
  }

  depends_on = [google_project_service.required_apis]
}

# Cloud Storage bucket for config and secrets backup
resource "google_storage_bucket" "iq_config_backup" {
  name          = "nexus-iq-config-backup-${random_string.suffix.result}"
  location      = var.gcp_region
  project       = var.gcp_project_id
  force_destroy = var.storage_force_destroy

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = var.config_backup_retention_days
    }
    action {
      type = "Delete"
    }
  }

  lifecycle_rule {
    condition {
      num_newer_versions = var.config_backup_max_versions
    }
    action {
      type = "Delete"
    }
  }

  encryption {
    default_kms_key_name = google_kms_crypto_key.iq_storage_key.id
  }

  labels = {
    environment = var.environment
    component   = "nexus-iq-config-backup"
  }

  depends_on = [google_project_service.required_apis]
}

# Data source for current project information
data "google_project" "current" {
  project_id = var.gcp_project_id
}