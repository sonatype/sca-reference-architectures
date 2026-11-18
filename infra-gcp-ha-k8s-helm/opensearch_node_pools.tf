# Two dedicated node pools for OpenSearch, one node per zone each, labeled by role and tainted so
# only OpenSearch pods run there. vm.max_map_count is set on the nodes, so the operator needs no
# privileged init container.

resource "google_container_node_pool" "os" {
  for_each = local.opensearch_create ? {
    data    = { type = var.opensearch_data_instance_type, nodes = var.opensearch_data_node_count }
    manager = { type = var.opensearch_manager_instance_type, nodes = 3 }
  } : {}

  name           = "${local.cluster_name}-os-${each.key}"
  location       = var.gcp_region
  cluster        = google_container_cluster.iq_gke.name
  project        = var.gcp_project_id
  node_locations = local.os_zones
  # node_count is per zone in a regional cluster.
  node_count = ceil(each.value.nodes / length(local.os_zones))

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = each.value.type
    disk_size_gb = var.opensearch_node_disk_gb
    disk_type    = local.os_hyperdisk[each.key] ? "hyperdisk-balanced" : "pd-balanced"

    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]

    labels = merge(local.common_tags, {
      workload        = "opensearch"
      opensearch-role = each.key
    })

    taint {
      key    = "dedicated"
      value  = "opensearch"
      effect = "NO_SCHEDULE"
    }

    tags = ["gke-node", "nexus-iq-opensearch"]

    linux_node_config {
      sysctls = {
        "vm.max_map_count" = "262144"
      }
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }

  lifecycle {
    precondition {
      condition     = length(local.os_zones) > 0
      error_message = "opensearch_zones is empty and the region's zones could not be read."
    }
    precondition {
      condition     = var.opensearch_data_node_count >= 3
      error_message = "opensearch_data_node_count must be 3 or more when this configuration builds the OpenSearch cluster."
    }
  }
}
