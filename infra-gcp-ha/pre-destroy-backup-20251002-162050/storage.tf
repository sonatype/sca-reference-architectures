# Cloud Filestore for persistent shared storage (equivalent to AWS EFS)
# Enables true multi-instance HA clustering with concurrent NFS access
resource "google_filestore_instance" "iq_ha_filestore" {
  name     = "nexus-iq-ha-filestore-${random_string.suffix.result}"
  location = var.filestore_zone
  tier     = var.filestore_tier
  project  = var.gcp_project_id

  file_shares {
    capacity_gb = var.filestore_capacity_gb
    name        = "nexus_iq_ha_data"

    nfs_export_options {
      ip_ranges   = [var.private_subnet_cidrs[0], var.private_subnet_cidrs[1], var.private_subnet_cidrs[2]]
      access_mode = "READ_WRITE"
      squash_mode = "NO_ROOT_SQUASH"
    }
  }

  networks {
    network = google_compute_network.iq_ha_vpc.name
    modes   = ["MODE_IPV4"]
  }

  labels = merge(var.common_tags, {
    component = "nexus-iq-ha-storage"
  })

  depends_on = [google_project_service.required_apis]
}