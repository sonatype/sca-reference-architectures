# Cloud Filestore provides shared NFS storage for multi-instance HA clustering
# No disk attachment needed - NFS is mounted via startup script

# Arm machine series boot an arm64 image, and the N4, N4A, C4 and C4A series
# accept only Hyperdisk.
locals {
  machine_is_arm      = can(regex("^(n4a|c4a|t2a)-", var.instance_machine_type))
  machine_needs_hyper = can(regex("^(n4|n4a|n4d|c4|c4a|c4d)-", var.instance_machine_type))
}

# Instance template for Nexus IQ Server with native installation
resource "google_compute_instance_template" "iq_template" {
  name_prefix  = "${local.infra_name}-template-"
  machine_type = var.instance_machine_type
  region       = var.gcp_region

  tags = ["nexus-iq-ha", "allow-health-check"]

  disk {
    source_image = local.machine_is_arm ? "debian-cloud/debian-12-arm64" : "debian-cloud/debian-12"
    auto_delete  = true
    boot         = true
    disk_type    = local.machine_needs_hyper ? "hyperdisk-balanced" : "pd-ssd"
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
    iq_log_levels      = var.iq_log_levels
    gcp_project_id     = var.gcp_project_id
    filestore_ip       = google_filestore_instance.iq_ha_filestore.networks[0].ip_addresses[0]

    search_engine              = var.search_engine
    opensearch_uri             = local.opensearch_enabled ? local.opensearch_uri : ""
    opensearch_username        = var.opensearch_username
    opensearch_password_secret = local.opensearch_enabled ? google_secret_manager_secret.opensearch_password[0].secret_id : ""
    opensearch_index_replicas  = var.opensearch_index_replicas
    opensearch_ca_secret       = local.opensearch_private_ca ? google_secret_manager_secret.opensearch_ca[0].secret_id : ""
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
    google_filestore_instance.iq_ha_filestore,
    google_secret_manager_secret_version.db_credentials,
    google_secret_manager_secret_version.db_password,
    google_secret_manager_secret_iam_member.iq_compute_db_credentials,
    google_secret_manager_secret_iam_member.iq_compute_db_password,
    google_secret_manager_secret_version.opensearch_password,
    google_secret_manager_secret_iam_member.iq_compute_opensearch_password,
    google_secret_manager_secret_version.opensearch_ca,
    google_secret_manager_secret_iam_member.iq_compute_opensearch_ca
  ]
}

# Regional Managed Instance Group for HA deployment
resource "google_compute_region_instance_group_manager" "iq_mig" {
  name   = "${local.infra_name}-mig"
  region = var.gcp_region

  base_instance_name = local.app_name
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

  # The autoscaler owns the live size, so target_size is ignored after create.
  # Otherwise every apply would reset the group to iq_target_instances.
  lifecycle {
    ignore_changes = [target_size]
  }

  depends_on = [
    google_compute_instance_template.iq_template,
    google_compute_health_check.iq_health_check
  ]
}

# Health check for auto healing
resource "google_compute_health_check" "iq_health_check" {
  name                = "${local.infra_name}-health-check"
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
  name   = "${local.infra_name}-autoscaler"
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