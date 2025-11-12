# Cloud Filestore provides shared NFS storage for multi-instance HA clustering
# No disk attachment needed - NFS is mounted via startup script

# Instance template for Nexus IQ Server with native installation
resource "google_compute_instance_template" "iq_template" {
  name_prefix  = "ref-arch-iq-ha-template-"
  machine_type = var.instance_machine_type
  region       = var.gcp_region

  tags = ["nexus-iq-ha", "allow-health-check"]

  disk {
    source_image = "debian-cloud/debian-12"
    auto_delete  = true
    boot         = true
    disk_type    = "pd-ssd"
    disk_size_gb = 100
  }

  # No additional disk attachment needed - using NFS via Cloud Filestore

  network_interface {
    subnetwork = google_compute_subnetwork.private_subnets[0].id
    # No external IP - instances access internet via NAT
  }

  service_account {
    email  = google_service_account.iq_compute_service.email
    scopes = ["cloud-platform"]
  }

  # Startup script for Docker-based IQ Server installation with HA clustering
  metadata_startup_script = templatefile("${path.module}/scripts/startup.sh", {
    iq_docker_image    = var.iq_docker_image
    db_host            = google_sql_database_instance.iq_ha_db.private_ip_address
    db_port            = "5432"
    db_name            = var.db_name
    db_user            = var.db_username
    db_password_secret = google_secret_manager_secret.db_password.secret_id
    java_opts          = var.java_opts
    gcp_project_id     = var.gcp_project_id
    filestore_ip       = google_filestore_instance.iq_ha_filestore.networks[0].ip_addresses[0]
  })

  labels = merge(var.common_tags, {
    component = "nexus-iq-instance-template"
  })

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    google_project_service.required_apis,
    google_sql_database_instance.iq_ha_db,
    google_filestore_instance.iq_ha_filestore
  ]
}

# Regional Managed Instance Group for HA deployment
resource "google_compute_region_instance_group_manager" "iq_mig" {
  name   = "ref-arch-iq-ha-mig"
  region = var.gcp_region

  base_instance_name = "nexus-iq-ha"
  target_size        = var.iq_target_instances

  version {
    instance_template = google_compute_instance_template.iq_template.id
  }

  # Distribution policy to spread instances across zones (limited to zones with disk replicas)
  distribution_policy_zones = [var.availability_zones[0], var.availability_zones[1]]

  # Named ports for load balancer
  named_port {
    name = "http"
    port = 8070
  }

  named_port {
    name = "admin"
    port = 8071
  }

  # Auto healing policy
  auto_healing_policies {
    health_check      = google_compute_health_check.iq_health_check.id
    initial_delay_sec = 900 # 15 minutes for native installation, NFS mount, database init
  }

  # Update policy for rolling deployments
  update_policy {
    type                         = "PROACTIVE"
    instance_redistribution_type = "PROACTIVE"
    minimal_action               = "REPLACE"
    max_surge_fixed              = 3
    max_unavailable_fixed        = 0
  }

  depends_on = [
    google_compute_instance_template.iq_template,
    google_compute_health_check.iq_health_check
  ]
}

# Health check for auto healing
resource "google_compute_health_check" "iq_health_check" {
  name                = "ref-arch-iq-ha-health-check"
  check_interval_sec  = 30
  timeout_sec         = 10
  healthy_threshold   = 2
  unhealthy_threshold = 3

  http_health_check {
    request_path = "/ping"
    port         = 8070
  }

  log_config {
    enable = true
  }
}

# Regional autoscaler for the MIG
resource "google_compute_region_autoscaler" "iq_autoscaler" {
  name   = "ref-arch-iq-ha-autoscaler"
  region = var.gcp_region
  target = google_compute_region_instance_group_manager.iq_mig.id

  autoscaling_policy {
    max_replicas    = var.iq_max_instances
    min_replicas    = var.iq_min_instances
    cooldown_period = var.scale_out_cooldown_seconds

    cpu_utilization {
      target = var.cpu_target_utilization
    }

    # Scale based on load balancer utilization
    load_balancing_utilization {
      target = 0.8
    }

    # Scaling policies
    scale_in_control {
      max_scaled_in_replicas {
        fixed = 1
      }
      time_window_sec = var.scale_in_cooldown_seconds
    }
  }
}