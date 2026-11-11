# Arm machine series boot an arm64 image, and the N4, N4A, C4 and C4A series
# accept only Hyperdisk.
locals {
  machine_is_arm      = can(regex("^(n4a|c4a|t2a)-", var.gce_machine_type))
  machine_needs_hyper = can(regex("^(n4|n4a|n4d|c4|c4a|c4d)-", var.gce_machine_type))
}

# GCE Instance for Nexus IQ Server (Single Instance)
resource "google_compute_instance" "iq_server" {
  name         = "${local.app_name}-server"
  machine_type = var.gce_machine_type
  zone         = var.gcp_zone
  project      = var.gcp_project_id

  tags = ["nexus-iq-server", "allow-health-check"]

  boot_disk {
    initialize_params {
      image = var.gce_boot_image != "" ? var.gce_boot_image : (local.machine_is_arm ? "debian-cloud/debian-12-arm64" : "debian-cloud/debian-12")
      size  = var.gce_boot_disk_size
      type  = local.machine_needs_hyper ? "hyperdisk-balanced" : "pd-ssd"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.iq_private_subnet.self_link
    # No access_config = no external IP (traffic goes through load balancer)
  }

  metadata = {
    enable-oslogin = "TRUE"
  }

  metadata_startup_script = templatefile("${path.module}/scripts/startup.sh", {
    db_host      = google_sql_database_instance.iq_db.private_ip_address
    db_port      = "5432"
    db_name      = google_sql_database.iq_database.name
    db_username  = var.db_username
    db_password  = var.db_password
    docker_image = var.iq_docker_image
    java_opts    = var.java_opts
    filestore_ip = google_filestore_instance.iq_filestore.networks[0].ip_addresses[0]

    gcp_project_id             = var.gcp_project_id
    search_engine              = var.search_engine
    opensearch_uri             = local.opensearch_enabled ? local.opensearch_uri : ""
    opensearch_username        = var.opensearch_username
    opensearch_password_secret = local.opensearch_enabled ? google_secret_manager_secret.opensearch_password[0].secret_id : ""
    opensearch_index_replicas  = var.opensearch_index_replicas
    opensearch_ca_secret       = local.opensearch_private_ca ? google_secret_manager_secret.opensearch_ca[0].secret_id : ""
  })

  service_account {
    email  = google_service_account.iq_service.email
    scopes = ["cloud-platform"]
  }

  depends_on = [
    google_project_service.required_apis,
    google_sql_database_instance.iq_db,
    google_filestore_instance.iq_filestore,
    google_secret_manager_secret_version.db_credentials,
    google_secret_manager_secret_version.opensearch_password,
    google_secret_manager_secret_version.opensearch_ca,
    google_project_iam_member.iq_service_secret_accessor
  ]
}

# Unmanaged Instance Group for Load Balancer
resource "google_compute_instance_group" "iq_group" {
  name        = "${local.app_name}-instance-group"
  description = "Instance group for Nexus IQ Server"
  zone        = var.gcp_zone
  project     = var.gcp_project_id

  instances = [
    google_compute_instance.iq_server.self_link
  ]

  named_port {
    name = "http"
    port = 8070
  }
}

# Firewall rule to allow health checks
resource "google_compute_firewall" "allow_health_check" {
  name    = "${local.app_name}-allow-health-check"
  network = google_compute_network.iq_vpc.name
  project = var.gcp_project_id

  allow {
    protocol = "tcp"
    ports    = ["8070", "8071"]
  }

  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["nexus-iq-server", "allow-health-check"]
}

# Firewall rule to allow load balancer traffic
resource "google_compute_firewall" "allow_lb_to_instances" {
  name    = "${local.app_name}-allow-lb"
  network = google_compute_network.iq_vpc.name
  project = var.gcp_project_id

  allow {
    protocol = "tcp"
    ports    = ["8070"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["nexus-iq-server"]
}
