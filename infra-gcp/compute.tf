# Cloud Run Service for Nexus IQ Server
resource "google_cloud_run_service" "iq_service" {
  name     = "nexus-iq-server"
  location = var.gcp_region
  project  = var.gcp_project_id

  template {
    metadata {
      annotations = {
        "autoscaling.knative.dev/minScale"         = var.iq_min_instances
        "autoscaling.knative.dev/maxScale"         = var.iq_max_instances
        "run.googleapis.com/cpu-throttling"        = "false"
        "run.googleapis.com/execution-environment" = "gen2"
        "run.googleapis.com/vpc-access-connector"  = google_vpc_access_connector.iq_connector.name
        "run.googleapis.com/vpc-access-egress"     = "private-ranges-only"
        "run.googleapis.com/cloudsql-instances"    = google_sql_database_instance.iq_db.connection_name
      }
    }

    spec {
      container_concurrency = var.container_concurrency
      timeout_seconds       = var.container_timeout
      service_account_name  = google_service_account.iq_service.email

      containers {
        image = var.iq_docker_image

        # Override entrypoint to create custom config.yml with database configuration
        command = ["/bin/sh"]
        args = [
          "-c",
          <<-EOF
          set -e
          echo "Generating custom config.yml with PostgreSQL database configuration"

          # Create necessary directories
          mkdir -p /etc/nexus-iq-server
          mkdir -p /var/log/nexus-iq-server

          # Generate custom config.yml with PostgreSQL database configuration
          cat > /etc/nexus-iq-server/config.yml << 'CONFIGEOF'
sonatypeWork: /sonatype-work

# Database configuration for PostgreSQL
database:
  type: postgresql
  hostname: $DB_HOST
  port: $DB_PORT
  name: $DB_NAME
  username: $DB_USER
  password: $DB_PASSWORD

server:
  applicationConnectors:
  - type: http
    port: 8070
  adminConnectors:
  - type: http
    port: 8071
  requestLog:
    appenders:
    - type: file
      currentLogFilename: "/var/log/nexus-iq-server/request.log"
      archivedLogFilenamePattern: "/var/log/nexus-iq-server/request-%d.log.gz"
      archivedFileCount: 5
logging:
  level: DEBUG
  loggers:
    com.sonatype.insight.scan: INFO
    eu.medsea.mimeutil.MimeUtil2: INFO
    org.apache.http: INFO
    org.apache.http.wire: ERROR
    org.eclipse.birt.report.engine.layout.pdf.font.FontConfigReader: WARN
    org.eclipse.jetty: INFO
    org.apache.shiro.web.filter.authc.BasicHttpAuthenticationFilter: INFO
    com.networknt.schema: OFF
    com.sonatype.insight.audit:
      appenders:
      - type: file
        currentLogFilename: "/var/log/nexus-iq-server/audit.log"
        archivedLogFilenamePattern: "/var/log/nexus-iq-server/audit-%d.log.gz"
        archivedFileCount: 50
  appenders:
  - type: console
    threshold: INFO
    logFormat: "%d{'yyyy-MM-dd HH:mm:ss,SSSZ'} %level [%thread] %X{username} %logger - %msg%n"
  - type: file
    threshold: ALL
    currentLogFilename: "/var/log/nexus-iq-server/clm-server.log"
    archivedLogFilenamePattern: "/var/log/nexus-iq-server/clm-server-%d.log.gz"
    logFormat: "%d{'yyyy-MM-dd HH:mm:ss,SSSZ'} %level [%thread] %X{username} %logger - %msg%n"
    archivedFileCount: 5
createSampleData: true
CONFIGEOF

          # Replace placeholders with actual values
          sed -i "s|\$DB_HOST|$DB_HOST|g" /etc/nexus-iq-server/config.yml
          sed -i "s|\$DB_PORT|$DB_PORT|g" /etc/nexus-iq-server/config.yml
          sed -i "s|\$DB_NAME|$DB_NAME|g" /etc/nexus-iq-server/config.yml
          sed -i "s|\$DB_USER|$DB_USER|g" /etc/nexus-iq-server/config.yml
          sed -i "s|\$DB_PASSWORD|$DB_PASSWORD|g" /etc/nexus-iq-server/config.yml

          echo "Generated config.yml with PostgreSQL database configuration"

          # Start IQ Server with custom config
          exec java $JAVA_OPTS -jar /opt/sonatype/nexus-iq-server/nexus-iq-server-*.jar server /etc/nexus-iq-server/config.yml
          EOF
        ]

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
          name  = "NEXUS_SECURITY_RANDOMPASSWORD"
          value = "false"
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
          timeout_seconds       = 10
          period_seconds        = 30
          failure_threshold     = 3
        }

        startup_probe {
          http_get {
            path = "/"
            port = 8070
          }
          initial_delay_seconds = 60
          timeout_seconds       = 10
          period_seconds        = 10
          failure_threshold     = 12
        }

        # Volume mounts for persistent data
        # Volume mounts removed - using external storage services
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

