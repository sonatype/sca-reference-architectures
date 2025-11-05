resource "google_compute_firewall" "allow_gke_ingress" {
  name    = "${local.cluster_name}-allow-gke-ingress"
  network = google_compute_network.iq_vpc.name
  project = var.gcp_project_id

  allow {
    protocol = "tcp"
    ports    = ["8070", "8071"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["gke-node"]

  description = "Allow ingress traffic to Nexus IQ Server on GKE nodes"
}

resource "google_compute_firewall" "allow_gke_health_checks" {
  name    = "${local.cluster_name}-allow-gke-health-checks"
  network = google_compute_network.iq_vpc.name
  project = var.gcp_project_id

  allow {
    protocol = "tcp"
    ports    = ["8070"]
  }

  source_ranges = [
    "35.191.0.0/16",
    "130.211.0.0/22"
  ]
  target_tags = ["gke-node"]

  description = "Allow GCP health check probes to reach GKE nodes"
}

resource "google_compute_firewall" "allow_filestore_nfs" {
  name    = "${local.cluster_name}-allow-filestore-nfs"
  network = google_compute_network.iq_vpc.name
  project = var.gcp_project_id

  allow {
    protocol = "tcp"
    ports    = ["2049"]
  }

  source_ranges = [
    var.gke_pods_cidr,
    google_compute_subnetwork.public_subnet.ip_cidr_range
  ]

  description = "Allow NFS traffic from GKE pods to Filestore"
}

resource "google_compute_firewall" "allow_internal_gke" {
  name    = "${local.cluster_name}-allow-internal-gke"
  network = google_compute_network.iq_vpc.name
  project = var.gcp_project_id

  allow {
    protocol = "tcp"
  }

  allow {
    protocol = "udp"
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [
    var.gke_pods_cidr,
    var.gke_services_cidr,
    google_compute_subnetwork.public_subnet.ip_cidr_range
  ]

  description = "Allow internal communication within GKE cluster"
}

resource "google_compute_firewall" "allow_master_to_nodes" {
  name    = "${local.cluster_name}-allow-master-to-nodes"
  network = google_compute_network.iq_vpc.name
  project = var.gcp_project_id

  allow {
    protocol = "tcp"
    ports    = ["443", "10250", "8443"]
  }

  source_ranges = [var.gke_master_cidr]
  target_tags   = ["gke-node"]

  description = "Allow GKE master to communicate with nodes"
}

resource "google_compute_firewall" "allow_nodes_to_master" {
  name    = "${local.cluster_name}-allow-nodes-to-master"
  network = google_compute_network.iq_vpc.name
  project = var.gcp_project_id

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }

  source_tags       = ["gke-node"]
  destination_ranges = [var.gke_master_cidr]

  description = "Allow GKE nodes to communicate with master"
}

resource "google_compute_security_policy" "cloud_armor_policy" {
  name    = "${local.cluster_name}-cloud-armor-policy"
  project = var.gcp_project_id

  rule {
    action   = "rate_based_ban"
    priority = "1000"

    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }

    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"

      enforce_on_key = "IP"

      rate_limit_threshold {
        count        = var.cloud_armor_rate_limit_threshold
        interval_sec = 60
      }

      ban_duration_sec = 600
    }

    description = "Rate limiting rule"
  }

  rule {
    action   = "allow"
    priority = "2147483647"

    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }

    description = "Default allow rule"
  }

  adaptive_protection_config {
    layer_7_ddos_defense_config {
      enable = true
    }
  }
}

resource "google_compute_global_address" "ingress_ip" {
  name    = "${local.cluster_name}-ingress-ip"
  project = var.gcp_project_id

  depends_on = [google_project_service.required_apis]
}
