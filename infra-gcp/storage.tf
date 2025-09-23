# Cloud Filestore for persistent shared storage (equivalent to AWS EFS)
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

# Data source for current project information
data "google_project" "current" {
  project_id = var.gcp_project_id
}