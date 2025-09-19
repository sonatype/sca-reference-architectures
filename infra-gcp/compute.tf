# Cloud Run Service for Nexus IQ Server
resource "google_cloud_run_v2_service" "iq_service" {
  name     = "ref-arch-iq-service"
  location = var.gcp_region

  template {
    max_instance_request_concurrency = var.iq_max_concurrency
    
    scaling {
      min_instance_count = var.iq_deployment_mode == "ha" ? var.iq_min_instances_ha : var.iq_min_instances_single
      max_instance_count = var.iq_deployment_mode == "ha" ? var.iq_max_instances_ha : var.iq_max_instances_single
    }

    vpc_access {
      connector = google_vpc_access_connector.iq_connector.id
      egress    = "ALL_TRAFFIC"
    }

    containers {
      image = var.iq_docker_image

      resources {
        limits = {
          cpu    = var.iq_cpu
          memory = var.iq_memory
        }
      }

      ports {
        name           = "http1"
        container_port = 8070
      }

      ports {
        name           = "admin"
        container_port = 8071
      }

      env {
        name  = "JAVA_OPTS"
        value = var.java_opts
      }

      env {
        name  = "DB_TYPE"
        value = "postgresql"
      }

      env {
        name  = "DB_HOST"
        value = google_sql_database_instance.iq_db.private_ip_address
      }

      env {
        name  = "DB_PORT"
        value = "5432"
      }

      env {
        name  = "DB_NAME"
        value = google_sql_database.iq_database.name
      }

      env {
        name = "DB_USER"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.db_credentials.secret_id
            version = "latest"
          }
        }
      }

      env {
        name = "DB_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.db_password.secret_id
            version = "latest"
          }
        }
      }

      # Mount Cloud Filestore as volume for persistent data
      volume_mounts {
        name       = "iq-data"
        mount_path = "/sonatype-work"
      }

      startup_probe {
        http_get {
          path = "/"
          port = 8070
        }
        initial_delay_seconds = 120
        timeout_seconds       = 5
        period_seconds        = 10
        failure_threshold     = 10
      }

      liveness_probe {
        http_get {
          path = "/"
          port = 8070
        }
        initial_delay_seconds = 120
        timeout_seconds       = 5
        period_seconds        = 30
        failure_threshold     = 3
      }
    }

    volumes {
      name = "iq-data"
      nfs {
        server = google_filestore_instance.iq_filestore.networks[0].ip_addresses[0]
        path   = "/nexus_iq_data"
      }
    }

    service_account = google_service_account.iq_service_account.email

    annotations = {
      "autoscaling.knative.dev/minScale"                       = var.iq_deployment_mode == "ha" ? var.iq_min_instances_ha : var.iq_min_instances_single
      "autoscaling.knative.dev/maxScale"                       = var.iq_deployment_mode == "ha" ? var.iq_max_instances_ha : var.iq_max_instances_single
      "run.googleapis.com/execution-environment"               = "gen2"
      "run.googleapis.com/vpc-access-connector"                = google_vpc_access_connector.iq_connector.name
      "run.googleapis.com/vpc-access-egress"                   = "all-traffic"
      "run.googleapis.com/cpu-throttling"                      = "false"
    }
  }

  traffic {
    percent = 100
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
  }

  depends_on = [
    google_project_service.required_apis,
    google_vpc_access_connector.iq_connector,
    google_sql_database_instance.iq_db,
    google_filestore_instance.iq_filestore,
    google_secret_manager_secret_version.db_credentials,
    google_secret_manager_secret_version.db_password
  ]
}

# IAM policy for Cloud Run service to be publicly accessible (through load balancer)
resource "google_cloud_run_service_iam_member" "iq_service_invoker" {
  location = google_cloud_run_v2_service.iq_service.location
  service  = google_cloud_run_v2_service.iq_service.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Network Endpoint Group for Cloud Run
resource "google_compute_region_network_endpoint_group" "iq_neg" {
  name                  = "ref-arch-iq-neg"
  network_endpoint_type = "SERVERLESS"
  region                = var.gcp_region

  cloud_run {
    service = google_cloud_run_v2_service.iq_service.name
  }
}