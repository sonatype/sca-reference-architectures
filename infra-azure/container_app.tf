# Log Analytics Workspace for Container App Environment
resource "azurerm_log_analytics_workspace" "iq_logs" {
  name                = "log-ref-arch-iq"
  location            = azurerm_resource_group.iq_rg.location
  resource_group_name = azurerm_resource_group.iq_rg.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days

  tags = {
    Name = "log-ref-arch-iq"
  }
}

# Application Insights (optional monitoring)
resource "azurerm_application_insights" "iq_insights" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "appi-ref-arch-iq"
  location            = azurerm_resource_group.iq_rg.location
  resource_group_name = azurerm_resource_group.iq_rg.name
  workspace_id        = azurerm_log_analytics_workspace.iq_logs.id
  application_type    = "web"

  tags = {
    Name = "appi-ref-arch-iq"
  }
}

# Container App Environment
resource "azurerm_container_app_environment" "iq_env" {
  name                       = "cae-ref-arch-iq"
  location                   = azurerm_resource_group.iq_rg.location
  resource_group_name        = azurerm_resource_group.iq_rg.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.iq_logs.id
  infrastructure_subnet_id   = azurerm_subnet.private_subnet.id

  tags = {
    Name = "cae-ref-arch-iq"
  }
}

# Container App
resource "azurerm_container_app" "iq_app" {
  name                         = "ca-ref-arch-iq"
  container_app_environment_id = azurerm_container_app_environment.iq_env.id
  resource_group_name          = azurerm_resource_group.iq_rg.name
  revision_mode                = "Single"

  identity {
    type = "SystemAssigned"
  }

  template {
    min_replicas = 1
    max_replicas = 1

    volume {
      name         = "iq-data"
      storage_type = "AzureFile"
      storage_name = azurerm_container_app_environment_storage.iq_storage.name
    }

    container {
      name   = "nexus-iq-server"
      image  = var.iq_docker_image
      cpu    = var.container_cpu
      memory = var.container_memory

      # Override entrypoint to create custom config.yml with database configuration
      command = ["/bin/sh"]
      args = [
        "-c",
        <<-EOF
          set -e
          echo "Generating custom config.yml with PostgreSQL database configuration"

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
      archivedFileCount: 50

logging:
  level: INFO
  loggers:
    com.sonatype.insight.scan: INFO
    eu.medsea.mimeutil.MimeUtil2: INFO
    org.apache.http: INFO
    org.apache.http.wire: INFO
    org.eclipse.birt.report.engine.layout.pdf.font.FontConfigReader: WARN
    org.eclipse.jetty: INFO
    org.apache.shiro.web.filter.authc.BasicHttpAuthenticationFilter: INFO
  appenders:
  - type: file
    threshold: ALL
    logFormat: "%d{'yyyy-MM-dd HH:mm:ss,SSSZ'} %level [%thread] %X{username} %logger - %msg%n"
    currentLogFilename: "/var/log/nexus-iq-server/nexus-iq-server.log"
    archivedLogFilenamePattern: "/var/log/nexus-iq-server/nexus-iq-server-%d.log.gz"
    archivedFileCount: 50
  - type: console
    threshold: INFO
    logFormat: "%d{'yyyy-MM-dd HH:mm:ss,SSSZ'} %level [%thread] %X{username} %logger - %msg%n"

# Create base directory structure
createSampleData: true
CONFIGEOF

          # Replace placeholders with actual values (same approach as AWS)
          sed -i "s|\$DB_HOST|$DB_HOST|g" /etc/nexus-iq-server/config.yml
          sed -i "s|\$DB_PORT|$DB_PORT|g" /etc/nexus-iq-server/config.yml
          sed -i "s|\$DB_NAME|$DB_NAME|g" /etc/nexus-iq-server/config.yml
          sed -i "s|\$DB_USER|$DB_USER|g" /etc/nexus-iq-server/config.yml
          sed -i "s|\$DB_PASSWORD|$DB_PASSWORD|g" /etc/nexus-iq-server/config.yml

          echo "Generated config.yml with PostgreSQL database configuration"

          # Start the application using Java with wildcard JAR path (same approach as AWS)
          exec java $JAVA_OPTS -jar /opt/sonatype/nexus-iq-server/nexus-iq-server-*.jar server /etc/nexus-iq-server/config.yml
        EOF
      ]

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
        value = azurerm_postgresql_flexible_server.iq_db.fqdn
      }

      env {
        name  = "DB_PORT"
        value = "5432"
      }

      env {
        name  = "DB_NAME"
        value = azurerm_postgresql_flexible_server_database.iq_database.name
      }

      env {
        name        = "DB_USER"
        secret_name = "db-username"
      }

      env {
        name        = "DB_PASSWORD"
        secret_name = "db-password"
      }

      env {
        name  = "NEXUS_SECURITY_RANDOMPASSWORD"
        value = "false"
      }

      volume_mounts {
        name = "iq-data"
        path = "/sonatype-work"
      }

      startup_probe {
        transport               = "HTTP"
        port                    = 8070
        path                    = "/"
        interval_seconds        = 30
        failure_count_threshold = 10
      }

      liveness_probe {
        transport               = "HTTP"
        port                    = 8070
        path                    = "/"
        interval_seconds        = 30
        failure_count_threshold = 3
      }

      readiness_probe {
        transport               = "HTTP"
        port                    = 8070
        path                    = "/"
        interval_seconds        = 15
        failure_count_threshold = 3
      }
    }
  }

  secret {
    name  = "db-username"
    value = var.db_username
  }

  secret {
    name  = "db-password"
    value = var.db_password
  }

  ingress {
    external_enabled           = true
    allow_insecure_connections = true
    target_port                = 8070
    transport                  = "http"

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  # Force immediate revision replacement instead of gradual rollout
  lifecycle {
    replace_triggered_by = [
      azurerm_container_app_environment_storage.iq_storage
    ]
  }

  tags = {
    Name = "ca-ref-arch-iq"
  }

  depends_on = [
    azurerm_postgresql_flexible_server.iq_db,
    azurerm_postgresql_flexible_server_database.iq_database,
    azurerm_container_app_environment_storage.iq_storage
  ]
}