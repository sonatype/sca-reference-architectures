# Log Analytics Workspace for Container App Environment (HA)
resource "azurerm_log_analytics_workspace" "iq_logs_ha" {
  name                = "log-ref-arch-iq-ha"
  location            = azurerm_resource_group.iq_rg.location
  resource_group_name = azurerm_resource_group.iq_rg.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days

  tags = merge(var.common_tags, {
    Name = "log-ref-arch-iq-ha"
  })
}

# Application Insights for monitoring (HA deployment)
resource "azurerm_application_insights" "iq_insights_ha" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "appi-ref-arch-iq-ha"
  location            = azurerm_resource_group.iq_rg.location
  resource_group_name = azurerm_resource_group.iq_rg.name
  workspace_id        = azurerm_log_analytics_workspace.iq_logs_ha.id
  application_type    = "web"

  tags = merge(var.common_tags, {
    Name = "appi-ref-arch-iq-ha"
  })
}

# Container App Environment with multi-subnet support for HA
resource "azurerm_container_app_environment" "iq_env_ha" {
  name                       = "cae-ref-arch-iq-ha"
  location                   = azurerm_resource_group.iq_rg.location
  resource_group_name        = azurerm_resource_group.iq_rg.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.iq_logs_ha.id

  # Use the first private subnet for the environment (Container Apps will be distributed across zones)
  infrastructure_subnet_id = azurerm_subnet.private_subnets[0].id

  # Workload profile to support higher resource limits (4.0 vCPU / 8.0 Gi)
  workload_profile {
    name                  = "D4-Profile-HA"
    workload_profile_type = "D4" # 4 vCPU, 16 GB RAM capacity per node
    minimum_count         = 1
    maximum_count         = 3 # Support multiple replicas across zones
  }

  tags = merge(var.common_tags, {
    Name = "cae-ref-arch-iq-ha"
  })
}

# Container App with High Availability configuration
resource "azurerm_container_app" "iq_app_ha" {
  name                         = "ca-ref-arch-iq-ha"
  container_app_environment_id = azurerm_container_app_environment.iq_env_ha.id
  resource_group_name          = azurerm_resource_group.iq_rg.name
  revision_mode                = "Single"
  workload_profile_name        = "D4-Profile-HA" # Use workload profile to access 4.0 vCPU / 8.0 Gi limits

  identity {
    type = "SystemAssigned"
  }

  template {
    # HA configuration: minimum 2 replicas, up to 10 for scaling (equivalent to AWS ECS 2-6 tasks)
    min_replicas = var.iq_min_replicas
    max_replicas = var.iq_max_replicas

    # Auto-scaling rules (equivalent to AWS ECS Auto Scaling policies)
    # HTTP request-based scaling rule (Container Apps native scaling)
    http_scale_rule {
      name                = "http-requests"
      concurrent_requests = var.scale_rule_concurrent_requests
    }

    # Alternative approach - create config in main container using shared volume

    # Volume for shared storage (equivalent to AWS EFS)
    volume {
      name         = "iq-data-ha"
      storage_type = "AzureFile"
      storage_name = azurerm_container_app_environment_storage.iq_storage_ha.name
    }

    volume {
      name         = "config-volume-ha"
      storage_type = "EmptyDir"
    }

    container {
      name   = "nexus-iq-server"
      image  = var.iq_docker_image
      cpu    = var.container_cpu
      memory = var.container_memory

      # HA deployment: Create complete config.yml with database and clustering in shared volume
      command = ["/bin/sh"]
      args = [
        "-c",
        <<-EOF
          set -e
          echo "Starting Nexus IQ Server HA instance - Replica: $HOSTNAME"

          # Create unique work directory per replica (like AWS ECS tasks)
          UNIQUE_WORK="/sonatype-work/clm-server-$HOSTNAME"
          CLUSTER_DIR="/sonatype-work/clm-cluster"

          echo "Creating unique work directory: $UNIQUE_WORK"
          mkdir -p "$UNIQUE_WORK"

          echo "Creating shared cluster directory: $CLUSTER_DIR"
          mkdir -p "$CLUSTER_DIR"

          # Create HA config.yml in proper documented location (writable via EmptyDir mount)
          # Create HA config.yml with complete database and clustering configuration
          cat > /etc/nexus-iq-server/config.yml << 'CONFIGEOF'
sonatypeWork: $UNIQUE_WORK
clusterDirectory: $CLUSTER_DIR

# Database configuration for PostgreSQL (HA cluster)
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
    bindHost: 0.0.0.0
  adminConnectors:
  - type: http
    port: 8071
    bindHost: 0.0.0.0
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
    logFormat: "%d{'yyyy-MM-dd HH:mm:ss,SSSZ'} %level [%thread] %X{username} %logger - REPLICA:$HOSTNAME %msg%n"
  - type: file
    threshold: ALL
    currentLogFilename: "/var/log/nexus-iq-server/clm-server.log"
    archivedLogFilenamePattern: "/var/log/nexus-iq-server/clm-server-%d.log.gz"
    logFormat: "%d{'yyyy-MM-dd HH:mm:ss,SSSZ'} %level [%thread] %X{username} %logger - REPLICA:$HOSTNAME %msg%n"
    archivedFileCount: 50

createSampleData: true
CONFIGEOF

          # Replace placeholders with actual environment values
          sed -i "s|\$UNIQUE_WORK|$UNIQUE_WORK|g" /etc/nexus-iq-server/config.yml
          sed -i "s|\$CLUSTER_DIR|$CLUSTER_DIR|g" /etc/nexus-iq-server/config.yml
          sed -i "s|\$DB_HOST|$DB_HOST|g" /etc/nexus-iq-server/config.yml
          sed -i "s|\$DB_PORT|$DB_PORT|g" /etc/nexus-iq-server/config.yml
          sed -i "s|\$DB_NAME|$DB_NAME|g" /etc/nexus-iq-server/config.yml
          sed -i "s|\$DB_USER|$DB_USER|g" /etc/nexus-iq-server/config.yml
          sed -i "s|\$DB_PASSWORD|$DB_PASSWORD|g" /etc/nexus-iq-server/config.yml
          sed -i "s|\$HOSTNAME|$HOSTNAME|g" /etc/nexus-iq-server/config.yml

          echo "Successfully created HA config.yml for replica: $HOSTNAME at /etc/nexus-iq-server/config.yml"
          echo "Generated config file contents:"
          cat /etc/nexus-iq-server/config.yml

          # Verify directories exist and are writable
          ls -la /sonatype-work/

          # Start IQ Server with HA configuration using proper documented path
          echo "Starting Nexus IQ Server HA replica: $HOSTNAME"
          exec /opt/sonatype/nexus-iq-server/bin/nexus-iq-server server /etc/nexus-iq-server/config.yml
        EOF
      ]

      # Environment variables for HA deployment
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
        value = azurerm_postgresql_flexible_server.iq_db_ha.fqdn
      }

      env {
        name  = "DB_PORT"
        value = "5432"
      }

      env {
        name  = "DB_NAME"
        value = azurerm_postgresql_flexible_server_database.iq_database_ha.name
      }

      # Use Container App secrets for database credentials
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

      # HA-specific environment variables
      env {
        name  = "CLUSTER_ENABLED"
        value = "true"
      }

      env {
        name  = "CLUSTER_DIRECTORY"
        value = "/sonatype-work/clm-cluster"
      }

      # Mount the shared storage for clustering
      volume_mounts {
        name = "iq-data-ha"
        path = "/sonatype-work"
      }

      volume_mounts {
        name = "config-volume-ha"
        path = "/etc/nexus-iq-server"
      }

    }
  }

  # Database credentials as Container App secrets
  secret {
    name  = "db-username"
    value = var.db_username
  }

  secret {
    name  = "db-password"
    value = var.db_password
  }

  # Ingress configuration for HA
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

  # Auto-scaling configuration (equivalent to AWS ECS Auto Scaling)
  dapr {
    app_id       = "nexus-iq-ha"
    app_port     = 8070
    app_protocol = "http"
  }

  tags = merge(var.common_tags, {
    Name = "ca-ref-arch-iq-ha"
  })

  depends_on = [
    azurerm_postgresql_flexible_server.iq_db_ha,
    azurerm_postgresql_flexible_server_database.iq_database_ha,
    azurerm_container_app_environment_storage.iq_storage_ha
  ]
}