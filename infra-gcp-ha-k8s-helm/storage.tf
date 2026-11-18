# The IOPS Filestore Regional accepts for a capacity: 4,000 to 17,000 per TB, and never under 2,000.
locals {
  filestore_min_iops = max(2000, ceil(var.filestore_capacity_gb * 4000 / 1024 / 100) * 100)
  filestore_max_iops = floor(var.filestore_capacity_gb * 17000 / 1024 / 100) * 100
}

# A Regional instance takes a region as its location and keeps its data in every zone of it.
# The pods mount it through the plain NFS PersistentVolume in filestore-pv.yaml, so the GKE
# Filestore CSI driver is not needed. Its Regional support starts at 1 TB, above the Size M share.
resource "google_filestore_instance" "iq_ha_filestore" {
  name     = "${local.cluster_name}-filestore-${random_string.suffix.result}"
  location = var.gcp_region
  tier     = var.filestore_tier
  project  = var.gcp_project_id

  performance_config {
    fixed_iops {
      max_iops = var.filestore_max_iops
    }
  }

  lifecycle {
    precondition {
      condition     = var.filestore_max_iops >= local.filestore_min_iops && var.filestore_max_iops <= local.filestore_max_iops
      error_message = "filestore_max_iops must be between ${local.filestore_min_iops} and ${local.filestore_max_iops} for a ${var.filestore_capacity_gb} GB Regional instance."
    }
  }

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
