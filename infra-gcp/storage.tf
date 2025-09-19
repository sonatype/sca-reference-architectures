# Cloud Filestore instance for shared filesystem
resource "google_filestore_instance" "iq_filestore" {
  name     = "ref-arch-iq-filestore"
  location = var.gcp_zone
  tier     = var.filestore_tier

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
    network      = google_compute_network.iq_vpc.name
    modes        = ["MODE_IPV4"]
    connect_mode = "DIRECT_PEERING"
  }

  depends_on = [google_project_service.required_apis]
}

# Storage bucket for backups and logs (optional)
resource "google_storage_bucket" "iq_backups" {
  name          = "ref-arch-iq-backups-${random_string.suffix.result}"
  location      = var.gcp_region
  force_destroy = var.storage_force_destroy

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  encryption {
    default_kms_key_name = var.kms_key_name != "" ? var.kms_key_name : null
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
      age                   = var.backup_transition_days
      matches_storage_class = ["STANDARD"]
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  lifecycle_rule {
    condition {
      age                   = var.backup_archive_days
      matches_storage_class = ["NEARLINE"]
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }
}

# Storage bucket for load balancer access logs
resource "google_storage_bucket" "lb_logs" {
  name          = "ref-arch-iq-lb-logs-${random_string.suffix.result}"
  location      = var.gcp_region
  force_destroy = var.storage_force_destroy

  uniform_bucket_level_access = true

  versioning {
    enabled = false
  }

  lifecycle_rule {
    condition {
      age = var.log_retention_days
    }
    action {
      type = "Delete"
    }
  }

  lifecycle_rule {
    condition {
      age                   = 30
      matches_storage_class = ["STANDARD"]
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
}

# IAM binding for service account access to storage buckets
resource "google_storage_bucket_iam_member" "iq_backups_access" {
  bucket = google_storage_bucket.iq_backups.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.iq_service_account.email}"
}

resource "google_storage_bucket_iam_member" "lb_logs_access" {
  bucket = google_storage_bucket.lb_logs.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.lb_service_account.email}"
}