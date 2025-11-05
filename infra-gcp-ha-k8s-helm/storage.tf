resource "google_filestore_instance" "iq_ha_filestore" {
  name     = "${local.cluster_name}-filestore-${random_string.suffix.result}"
  location = var.filestore_zone
  tier     = var.filestore_tier
  project  = var.gcp_project_id

  file_shares {
    capacity_gb = var.filestore_capacity_gb
    name        = "nexus_iq_ha_data"

    nfs_export_options {
      ip_ranges   = [var.gke_pods_cidr, google_compute_subnetwork.public_subnet.ip_cidr_range]
      access_mode = "READ_WRITE"
      squash_mode = "NO_ROOT_SQUASH"
    }
  }

  networks {
    network = google_compute_network.iq_vpc.name
    modes   = ["MODE_IPV4"]
  }

  labels = merge(local.common_tags, {
    component = "nexus-iq-ha-storage"
  })

  depends_on = [google_project_service.required_apis]
}
