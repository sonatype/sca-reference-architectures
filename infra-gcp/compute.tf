# GCE Instance for Nexus IQ Server (Single Instance)
resource "google_compute_instance" "iq_server" {
  name         = "nexus-iq-server"
  machine_type = var.gce_machine_type
  zone         = var.gcp_zone
  project      = var.gcp_project_id

  tags = ["nexus-iq-server", "allow-health-check"]

  boot_disk {
    initialize_params {
      image = var.gce_boot_image
      size  = var.gce_boot_disk_size
      type  = "pd-ssd"
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
    db_host     = google_sql_database_instance.iq_db.private_ip_address
    db_port     = "5432"
    db_name     = google_sql_database.iq_database.name
    db_username = var.db_username
    db_password = var.db_password
    iq_version  = var.iq_version
    java_opts   = var.java_opts
  })

  service_account {
    email  = google_service_account.iq_service.email
    scopes = ["cloud-platform"]
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    google_project_service.required_apis,
    google_sql_database_instance.iq_db
  ]
}

# Unmanaged Instance Group for Load Balancer
resource "google_compute_instance_group" "iq_group" {
  name        = "nexus-iq-instance-group"
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
  name    = "nexus-iq-allow-health-check"
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
  name    = "nexus-iq-allow-lb"
  network = google_compute_network.iq_vpc.name
  project = var.gcp_project_id

  allow {
    protocol = "tcp"
    ports    = ["8070"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["nexus-iq-server"]
}
