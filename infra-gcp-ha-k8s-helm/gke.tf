resource "google_container_cluster" "iq_gke" {
  name     = local.cluster_name
  location = var.gcp_region
  project  = var.gcp_project_id

  remove_default_node_pool = true
  initial_node_count       = 1

  network    = google_compute_network.iq_vpc.name
  subnetwork = google_compute_subnetwork.public_subnet.name

  ip_allocation_policy {
    cluster_secondary_range_name  = "gke-pods"
    services_secondary_range_name = "gke-services"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.gke_master_cidr
  }

  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"
      display_name = "All networks"
    }
  }

  workload_identity_config {
    workload_pool = "${var.gcp_project_id}.svc.id.goog"
  }

  addons_config {
    http_load_balancing {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
    network_policy_config {
      disabled = false
    }
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
  }

  network_policy {
    enabled  = true
    provider = "PROVIDER_UNSPECIFIED"
  }

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus {
      enabled = true
    }
  }

  release_channel {
    channel = "REGULAR"
  }

  maintenance_policy {
    daily_maintenance_window {
      start_time = var.gke_maintenance_window_start
    }
  }

  resource_labels = local.common_tags

  deletion_protection = false

  depends_on = [
    google_project_service.required_apis,
    google_compute_subnetwork.public_subnet,
    google_service_networking_connection.private_vpc_connection
  ]
}

resource "google_container_node_pool" "iq_node_pool" {
  name       = "${local.cluster_name}-node-pool"
  location   = var.gcp_region
  cluster    = google_container_cluster.iq_gke.name
  project    = var.gcp_project_id
  node_count = var.node_group_desired_size

  autoscaling {
    min_node_count = var.node_group_min_size
    max_node_count = var.node_group_max_size
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = var.node_instance_type
    disk_size_gb = var.node_disk_size
    disk_type    = "pd-standard"

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    labels = merge(local.common_tags, {
      workload = "nexus-iq-ha"
    })

    tags = ["nexus-iq-ha", "gke-node"]

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
}

resource "google_service_account" "gke_workload_identity" {
  account_id   = "${local.cluster_name}-wi-sa"
  display_name = "GKE Workload Identity for Nexus IQ HA"
  project      = var.gcp_project_id

  depends_on = [google_project_service.required_apis]
}

resource "google_service_account_iam_member" "gke_workload_identity_binding" {
  service_account_id = google_service_account.gke_workload_identity.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.gcp_project_id}.svc.id.goog[nexus-iq/nexus-iq-sa]"
}

resource "google_project_iam_member" "gke_logging_writer" {
  project = var.gcp_project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.gke_workload_identity.email}"
}

resource "google_project_iam_member" "gke_monitoring_writer" {
  project = var.gcp_project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.gke_workload_identity.email}"
}

resource "google_project_iam_member" "gke_secret_accessor" {
  project = var.gcp_project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.gke_workload_identity.email}"
}

resource "google_service_account" "fluentd_workload_identity" {
  account_id   = "${local.cluster_name}-fluentd-sa"
  display_name = "Fluentd Workload Identity for Cloud Logging"
  project      = var.gcp_project_id

  depends_on = [google_project_service.required_apis]
}

resource "google_service_account_iam_member" "fluentd_workload_identity_binding" {
  service_account_id = google_service_account.fluentd_workload_identity.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.gcp_project_id}.svc.id.goog[nexus-iq/fluentd-aggregator-sa]"
}

resource "google_project_iam_member" "fluentd_logging_writer" {
  project = var.gcp_project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.fluentd_workload_identity.email}"
}

data "google_container_cluster" "iq_gke" {
  name       = google_container_cluster.iq_gke.name
  location   = google_container_cluster.iq_gke.location
  project    = var.gcp_project_id
  depends_on = [google_container_node_pool.iq_node_pool]
}
