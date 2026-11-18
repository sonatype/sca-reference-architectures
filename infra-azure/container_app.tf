
locals {
  opensearch_enabled    = var.search_engine == "opensearch"
  opensearch_uri        = "${var.opensearch_use_tls ? "https" : "http"}://${local.os_endpoint}:${var.opensearch_port}"
  workload_profile_name = "${var.workload_profile_type}-Profile"
}

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
    name                  = local.workload_profile_name
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
  workload_profile_name        = local.workload_profile_name

  identity {
    type = "SystemAssigned"
  }

  dynamic "secret" {
    for_each = var.container_registry_server == "" ? [] : [1]
    content {
      name  = "registry-password"
      value = var.container_registry_password
    }
  }

  dynamic "registry" {
    for_each = var.container_registry_server == "" ? [] : [1]
    content {
      server               = var.container_registry_server
      username             = var.container_registry_username
      password_secret_name = "registry-password"
    }
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
      name         = "iq-logs"
      storage_type = "AzureFile"
      storage_name = azurerm_container_app_environment_storage.iq_logs.name
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
%{if local.opensearch_enabled && var.opensearch_use_tls}

          if [ -n "$OPENSEARCH_CA_PEM" ]; then
            # On the container's own disk, rebuilt every start, so nothing collects on the share.
            TRUST_STORE=/tmp/iq-truststore.jks
            JVM_CACERTS=$(find / \( -path /sonatype-work -o -path /proc -o -path /sys \) -prune -o -name cacerts -path "*lib/security*" -print 2>/dev/null | head -1)
            KEYTOOL=$(find / \( -path /sonatype-work -o -path /proc -o -path /sys \) -prune -o -name keytool -type f -perm -u+x -print 2>/dev/null | head -1)
            if [ -n "$JVM_CACERTS" ] && [ -n "$KEYTOOL" ]; then
              cp "$JVM_CACERTS" "$TRUST_STORE"
              printf '%s' "$OPENSEARCH_CA_PEM" | base64 -d > /tmp/opensearch-ca.crt
              "$KEYTOOL" -importcert -noprompt \
                -keystore "$TRUST_STORE" -storepass changeit \
                -alias opensearch-ca -file /tmp/opensearch-ca.crt
              rm -f /tmp/opensearch-ca.crt
              echo "trust store built, authorities: $("$KEYTOOL" -list -keystore "$TRUST_STORE" -storepass changeit 2>/dev/null | grep -c trustedCertEntry)"
              export JAVA_OPTS="$JAVA_OPTS -Djavax.net.ssl.trustStore=$TRUST_STORE -Djavax.net.ssl.trustStorePassword=changeit"
            else
              echo "REFUSING: cacerts=$JVM_CACERTS keytool=$KEYTOOL, one is missing"
              exit 1
            fi
          fi
%{endif}


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
  level: INFO
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
%{if local.opensearch_enabled}

          # Written from the container app secrets as single-quoted YAML scalars with
          # ' doubled, so no character in the credentials can change the file.
          os_user=$(printf '%s' "$OPENSEARCH_USERNAME" | sed "s/'/''/g")
          os_pass=$(printf '%s' "$OPENSEARCH_PASSWORD" | sed "s/'/''/g")

          {
            printf 'search:\n'
            printf '  type: http\n'
            printf '  mode: OPENSEARCH\n'
            printf '  uri: %s\n' '${local.opensearch_uri}'
            printf "  username: '%s'\n" "$os_user"
            printf "  password: '%s'\n" "$os_pass"
            printf 'nexusOne:\n'
            printf '  connection:\n'
            printf '    type: http\n'
            printf '    mode: OPENSEARCH\n'
            printf '    uri: %s\n' '${local.opensearch_uri}'
            printf "    username: '%s'\n" "$os_user"
            printf "    password: '%s'\n" "$os_pass"
            printf '    nexusOneIndexReplicas: %s\n' '${local.os_replicas}'
          } >> /etc/nexus-iq-server/config.yml

          unset os_user os_pass
%{endif}

          # IQ Server installs this license on start when it has none.
          printf '%s' "$IQ_LICENSE_B64" | base64 -d > /etc/nexus-iq-server/license.lic
          echo "licenseFile: /etc/nexus-iq-server/license.lic" >> /etc/nexus-iq-server/config.yml
          unset IQ_LICENSE_B64

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
        name  = "OPENSEARCH_CA_PEM"
        value = local.os_ca_pem_b64
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
        name        = "NXIQ_INITIAL_ADMIN_PASSWORD"
        secret_name = "iq-admin-initial-password"
      }

      env {
        name        = "IQ_LICENSE_B64"
        secret_name = "iq-license"
      }

      env {
        name  = "NEXUS_SECURITY_RANDOMPASSWORD"
        value = "false"
      }

      dynamic "env" {
        for_each = local.opensearch_enabled ? [1] : []
        content {
          name        = "OPENSEARCH_USERNAME"
          secret_name = "opensearch-username"
        }
      }

      dynamic "env" {
        for_each = local.opensearch_enabled ? [1] : []
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
        name = "iq-logs"
        path = "/var/log/nexus-iq-server"
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

  secret {
    name  = "iq-admin-initial-password"
    value = var.iq_admin_initial_password
  }

  secret {
    name  = "iq-license"
    value = local.iq_license_b64
  }

  dynamic "secret" {
    for_each = local.opensearch_enabled ? [1] : []
    content {
      name  = "opensearch-username"
      value = local.os_username
    }
  }

  dynamic "secret" {
    for_each = local.opensearch_enabled ? [1] : []
    content {
      name  = "opensearch-password"
      value = local.os_password
    }
  }

  ingress {
    external_enabled           = true
    allow_insecure_connections = false
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

    precondition {
      condition     = var.search_engine != "opensearch" || local.os_create || length(var.opensearch_endpoint) > 0
      error_message = "opensearch_endpoint must be set when search_engine is 'opensearch' and opensearch_create is false."
    }

    precondition {
      condition     = var.search_engine != "opensearch" || length(local.os_username) > 0
      error_message = "opensearch_username must be set when search_engine is 'opensearch'."
    }

    precondition {
      condition     = var.search_engine != "opensearch" || local.os_create || length(var.opensearch_password) > 0
      error_message = "opensearch_password must be set when search_engine is 'opensearch' and opensearch_create is false."
    }

    precondition {
      condition     = var.container_registry_server == "" || (length(var.container_registry_username) > 0 && length(var.container_registry_password) > 0)
      error_message = "container_registry_username and container_registry_password must both be set when container_registry_server is set."
    }
  }

  tags = merge(var.common_tags, {
    Name = "ca-${var.cluster_name}"
  })

  depends_on = [
    azurerm_postgresql_flexible_server.iq_db,
    azurerm_postgresql_flexible_server_database.iq_database,
    azurerm_container_app_environment_storage.iq_storage,
    azurerm_container_app_environment_storage.iq_logs,
    azurerm_linux_virtual_machine.opensearch,
  ]
}