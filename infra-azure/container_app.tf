
resource "azurerm_log_analytics_workspace" "iq_logs" {
  name                = "log-${var.cluster_name}"
  location            = azurerm_resource_group.iq_rg.location
  resource_group_name = azurerm_resource_group.iq_rg.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days

  tags = merge(var.common_tags, {
    Name = "log-${var.cluster_name}"
  })
}


resource "azurerm_application_insights" "iq_insights" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "appi-${var.cluster_name}"
  location            = azurerm_resource_group.iq_rg.location
  resource_group_name = azurerm_resource_group.iq_rg.name
  workspace_id        = azurerm_log_analytics_workspace.iq_logs.id
  application_type    = "web"

  tags = merge(var.common_tags, {
    Name = "appi-${var.cluster_name}"
  })
}


resource "azurerm_container_app_environment" "iq_env" {
  name                       = "cae-${var.cluster_name}"
  location                   = azurerm_resource_group.iq_rg.location
  resource_group_name        = azurerm_resource_group.iq_rg.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.iq_logs.id
  infrastructure_subnet_id   = azurerm_subnet.private_subnet.id


  workload_profile {
    name                  = "${var.workload_profile_type}-Profile"
    workload_profile_type = var.workload_profile_type
    minimum_count         = 1
    maximum_count         = 1
  }

  tags = merge(var.common_tags, {
    Name = "cae-${var.cluster_name}"
  })
}


resource "azurerm_container_app" "iq_app" {
  name                         = "ca-${var.cluster_name}"
  container_app_environment_id = azurerm_container_app_environment.iq_env.id
  resource_group_name          = azurerm_resource_group.iq_rg.name
  revision_mode                = "Single"
  workload_profile_name        = "${var.workload_profile_type}-Profile"

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

    volume {
      name         = "config-volume"
      storage_type = "EmptyDir"
    }

    container {
      name   = "nexus-iq-server"
      image  = var.iq_docker_image
      cpu    = var.container_cpu
      memory = var.container_memory


      command = ["/bin/sh"]
      args = [
        "-c",
        <<-EOF
          set -e
          echo "Creating config.yml in proper /etc/nexus-iq-server location"


          cat > /etc/nexus-iq-server/config.yml << 'CONFIGEOF'
sonatypeWork: /sonatype-work


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
    org.apache.hc.client5.http: INFO
    org.apache.hc.client5.http.wire: ERROR
    org.apache.hc.core5.reactor: INFO
    org.apache.http.client.protocol.ResponseProcessCookies: ERROR
    org.postgresql.jdbc.PgConnection: INFO
    org.quartz: INFO
    org.zeroturnaround.exec: INFO
    org.eclipse.jgit: INFO
    software.amazon.awssdk: WARN
    org.jooq.tools: WARN
    org.jooq.Constants: OFF
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
    archivedLogFilenamePattern: "/var/log/nexus-iq-server/clm-server-%d{yyyy-MM-dd-HH}.log.gz"
    logFormat: "%d{'yyyy-MM-dd HH:mm:ss,SSSZ'} %level [%thread] %X{username} %logger - %msg%n"
    archivedFileCount: 24

createSampleData: true
CONFIGEOF


          sed -i "s|\$DB_HOST|$DB_HOST|g" /etc/nexus-iq-server/config.yml
          sed -i "s|\$DB_PORT|$DB_PORT|g" /etc/nexus-iq-server/config.yml
          sed -i "s|\$DB_NAME|$DB_NAME|g" /etc/nexus-iq-server/config.yml
          sed -i "s|\$DB_USER|$DB_USER|g" /etc/nexus-iq-server/config.yml
          sed -i "s|\$DB_PASSWORD|$DB_PASSWORD|g" /etc/nexus-iq-server/config.yml
%{if var.search_engine == "opensearch"}

          # The OpenSearch credentials never pass through the template or
          # through a sed replacement, so no character in them can change the
          # file's structure. They are read from the container app secrets and
          # written as single-quoted YAML scalars, which are literal: a |, &, \
          # or # in a password is only that character. The one character YAML
          # gives meaning to inside single quotes is ' itself, which doubles.
          # That doubling is the only substitution, both its pattern and its
          # replacement are fixed, and the value reaches sed on standard input
          # rather than as part of the script.
          os_user=$(printf '%s' "$OPENSEARCH_USERNAME" | sed "s/'/''/g")
          os_pass=$(printf '%s' "$OPENSEARCH_PASSWORD" | sed "s/'/''/g")

          {
            printf 'search:\n'
            printf '  type: http\n'
            printf '  mode: OPENSEARCH\n'
            printf '  uri: %s\n' '${var.opensearch_use_tls ? "https" : "http"}://${var.opensearch_endpoint}:${var.opensearch_port}'
            printf "  username: '%s'\n" "$os_user"
            printf "  password: '%s'\n" "$os_pass"
            printf 'nexusOne:\n'
            printf '  connection:\n'
            printf '    type: http\n'
            printf '    uri: %s\n' '${var.opensearch_use_tls ? "https" : "http"}://${var.opensearch_endpoint}:${var.opensearch_port}'
            printf "    username: '%s'\n" "$os_user"
            printf "    password: '%s'\n" "$os_pass"
            printf '    nexusOneIndexReplicas: %s\n' '${var.opensearch_index_replicas}'
          } >> /etc/nexus-iq-server/config.yml

          unset os_user os_pass
%{endif}

          echo "Successfully created config.yml with PostgreSQL configuration at /etc/nexus-iq-server/config.yml"
          echo "Generated config file contents, with every password redacted:"
          sed "s/^\([[:space:]]*password:\).*/\1 '***'/" /etc/nexus-iq-server/config.yml


          exec /opt/sonatype/nexus-iq-server/bin/nexus-iq-server server /etc/nexus-iq-server/config.yml
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

      dynamic "env" {
        for_each = var.search_engine == "opensearch" ? [1] : []
        content {
          name        = "OPENSEARCH_USERNAME"
          secret_name = "opensearch-username"
        }
      }

      dynamic "env" {
        for_each = var.search_engine == "opensearch" ? [1] : []
        content {
          name        = "OPENSEARCH_PASSWORD"
          secret_name = "opensearch-password"
        }
      }

      volume_mounts {
        name = "iq-data"
        path = "/sonatype-work"
      }

      volume_mounts {
        name = "config-volume"
        path = "/etc/nexus-iq-server"
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

  dynamic "secret" {
    for_each = var.search_engine == "opensearch" ? [1] : []
    content {
      name  = "opensearch-username"
      value = var.opensearch_username
    }
  }

  dynamic "secret" {
    for_each = var.search_engine == "opensearch" ? [1] : []
    content {
      name  = "opensearch-password"
      value = var.opensearch_password
    }
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


  lifecycle {
    replace_triggered_by = [
      azurerm_container_app_environment_storage.iq_storage
    ]
  }

  tags = merge(var.common_tags, {
    Name = "ca-${var.cluster_name}"
  })

  depends_on = [
    azurerm_postgresql_flexible_server.iq_db,
    azurerm_postgresql_flexible_server_database.iq_database,
    azurerm_container_app_environment_storage.iq_storage
  ]
}