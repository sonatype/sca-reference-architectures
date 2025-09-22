# Cloud Run Service for Nexus IQ Server
resource "google_cloud_run_service" "iq_service" {
  name     = "nexus-iq-server"
  location = var.gcp_region
  project  = var.gcp_project_id

  template {
    metadata {
      annotations = {
        "autoscaling.knative.dev/minScale"                = var.iq_min_instances
        "autoscaling.knative.dev/maxScale"                = var.iq_max_instances
        "run.googleapis.com/cpu-throttling"               = "false"
        "run.googleapis.com/execution-environment"        = "gen2"
        "run.googleapis.com/vpc-access-connector"         = google_vpc_access_connector.iq_connector.name
        "run.googleapis.com/vpc-access-egress"            = "private-ranges-only"
        "run.googleapis.com/cloudsql-instances"           = google_sql_database_instance.iq_db.connection_name
      }
    }

    spec {
      container_concurrency = var.container_concurrency
      timeout_seconds      = var.container_timeout
      service_account_name = google_service_account.iq_service.email

      containers {
        image = var.iq_docker_image

        ports {
          name           = "http1"
          container_port = 8070
          protocol       = "TCP"
        }

        resources {
          limits = {
            cpu    = var.iq_cpu_limit
            memory = var.iq_memory_limit
          }
          requests = {
            cpu    = var.iq_cpu_request
            memory = var.iq_memory_request
          }
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
          value_from {
            secret_key_ref {
              name = google_secret_manager_secret.db_credentials.secret_id
              key  = "username"
            }
          }
        }

        env {
          name = "DB_PASSWORD"
          value_from {
            secret_key_ref {
              name = google_secret_manager_secret.db_credentials.secret_id
              key  = "password"
            }
          }
        }

        # Health check configuration
        liveness_probe {
          http_get {
            path = "/"
            port = 8070
          }
          initial_delay_seconds = 120
          timeout_seconds      = 10
          period_seconds       = 30
          failure_threshold    = 3
        }

        startup_probe {
          http_get {
            path = "/"
            port = 8070
          }
          initial_delay_seconds = 60
          timeout_seconds      = 10
          period_seconds       = 10
          failure_threshold    = 12
        }

        # Volume mounts for persistent data
        volume_mounts {
          name       = "iq-data"
          mount_path = "/sonatype-work"
        }
      }

      volumes {
        name = "iq-data"
        nfs {
          server    = google_filestore_instance.iq_filestore.networks[0].ip_addresses[0]
          path      = "/nexus_iq_data"
          read_only = false
        }
      }
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  autogenerate_revision_name = true

  depends_on = [
    google_project_service.required_apis,
    google_sql_database_instance.iq_db,
    google_filestore_instance.iq_filestore
  ]
}

# Cloud Run Service for IQ-HA (High Availability) - Optional
resource "google_cloud_run_service" "iq_ha_service" {
  count    = var.enable_ha ? 1 : 0
  name     = "nexus-iq-ha-server"
  location = var.gcp_region
  project  = var.gcp_project_id

  template {
    metadata {
      annotations = {
        "autoscaling.knative.dev/minScale"                = var.iq_ha_min_instances
        "autoscaling.knative.dev/maxScale"                = var.iq_ha_max_instances
        "run.googleapis.com/cpu-throttling"               = "false"
        "run.googleapis.com/execution-environment"        = "gen2"
        "run.googleapis.com/vpc-access-connector"         = google_vpc_access_connector.iq_connector.name
        "run.googleapis.com/vpc-access-egress"            = "private-ranges-only"
        "run.googleapis.com/cloudsql-instances"           = google_sql_database_instance.iq_ha_db[0].connection_name
      }
    }

    spec {
      container_concurrency = var.container_concurrency
      timeout_seconds      = var.container_timeout
      service_account_name = google_service_account.iq_service.email

      containers {
        image = var.iq_docker_image

        ports {
          name           = "http1"
          container_port = 8070
          protocol       = "TCP"
        }

        resources {
          limits = {
            cpu    = var.iq_ha_cpu_limit
            memory = var.iq_ha_memory_limit
          }
          requests = {
            cpu    = var.iq_ha_cpu_request
            memory = var.iq_ha_memory_request
          }
        }

        env {
          name  = "JAVA_OPTS"
          value = var.java_opts_ha
        }

        env {
          name  = "DB_TYPE"
          value = "postgresql"
        }

        env {
          name  = "DB_HOST"
          value = google_sql_database_instance.iq_ha_db[0].private_ip_address
        }

        env {
          name  = "DB_PORT"
          value = "5432"
        }

        env {
          name  = "DB_NAME"
          value = google_sql_database.iq_ha_database[0].name
        }

        env {
          name = "DB_USER"
          value_from {
            secret_key_ref {
              name = google_secret_manager_secret.db_ha_credentials[0].secret_id
              key  = "username"
            }
          }
        }

        env {
          name = "DB_PASSWORD"
          value_from {
            secret_key_ref {
              name = google_secret_manager_secret.db_ha_credentials[0].secret_id
              key  = "password"
            }
          }
        }

        # Health check configuration
        liveness_probe {
          http_get {
            path = "/"
            port = 8070
          }
          initial_delay_seconds = 120
          timeout_seconds      = 10
          period_seconds       = 30
          failure_threshold    = 3
        }

        startup_probe {
          http_get {
            path = "/"
            port = 8070
          }
          initial_delay_seconds = 60
          timeout_seconds      = 10
          period_seconds       = 10
          failure_threshold    = 12
        }

        # Volume mounts for persistent data
        volume_mounts {
          name       = "iq-ha-data"
          mount_path = "/sonatype-work"
        }
      }

      volumes {
        name = "iq-ha-data"
        nfs {
          server    = google_filestore_instance.iq_ha_filestore[0].networks[0].ip_addresses[0]
          path      = "/nexus_iq_ha_data"
          read_only = false
        }
      }
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  autogenerate_revision_name = true

  depends_on = [
    google_project_service.required_apis,
    google_sql_database_instance.iq_ha_db,
    google_filestore_instance.iq_ha_filestore
  ]
}

# IAM policy for Cloud Run to access other services
resource "google_cloud_run_service_iam_binding" "iq_invoker" {
  location = google_cloud_run_service.iq_service.location
  project  = google_cloud_run_service.iq_service.project
  service  = google_cloud_run_service.iq_service.name
  role     = "roles/run.invoker"
  members = [
    "serviceAccount:${google_service_account.iq_load_balancer.email}",
    "allUsers"
  ]
}

resource "google_cloud_run_service_iam_binding" "iq_ha_invoker" {
  count    = var.enable_ha ? 1 : 0
  location = google_cloud_run_service.iq_ha_service[0].location
  project  = google_cloud_run_service.iq_ha_service[0].project
  service  = google_cloud_run_service.iq_ha_service[0].name
  role     = "roles/run.invoker"
  members = [
    "serviceAccount:${google_service_account.iq_load_balancer.email}",
    "allUsers"
  ]
}

# Cloud Run Domain Mapping (optional for custom domains)
resource "google_cloud_run_domain_mapping" "iq_domain" {
  count    = var.custom_domain != "" ? 1 : 0
  location = var.gcp_region
  name     = var.custom_domain

  metadata {
    namespace = var.gcp_project_id
  }

  spec {
    route_name = google_cloud_run_service.iq_service.name
  }
}

resource "google_cloud_run_domain_mapping" "iq_ha_domain" {
  count    = var.enable_ha && var.custom_domain_ha != "" ? 1 : 0
  location = var.gcp_region
  name     = var.custom_domain_ha

  metadata {
    namespace = var.gcp_project_id
  }

  spec {
    route_name = google_cloud_run_service.iq_ha_service[0].name
  }
}