# The IOPS Filestore Regional accepts for a capacity: 4,000 to 17,000 per TB, and never under 2,000.
locals {
  filestore_min_iops = max(2000, ceil(var.filestore_capacity_gb * 4000 / 1024 / 100) * 100)
  filestore_max_iops = floor(var.filestore_capacity_gb * 17000 / 1024 / 100) * 100
}

# Cloud Filestore for persistent shared storage (equivalent to AWS EFS)
# Enables true multi-instance HA clustering with concurrent NFS access.
# A Regional instance takes a region as its location and keeps its data in every zone of it.
resource "google_filestore_instance" "iq_ha_filestore" {
  name     = "${local.app_name}-filestore-${random_string.suffix.result}"
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