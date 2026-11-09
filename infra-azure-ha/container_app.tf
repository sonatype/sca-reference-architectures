
resource "azurerm_log_analytics_workspace" "iq_logs_ha" {
  name                = "log-${var.cluster_name}"
  location            = azurerm_resource_group.iq_rg.location
  resource_group_name = azurerm_resource_group.iq_rg.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days

  tags = merge(var.common_tags, {
    Name = "log-${var.cluster_name}"
  })
}


resource "azurerm_application_insights" "iq_insights_ha" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "appi-${var.cluster_name}"
  location            = azurerm_resource_group.iq_rg.location
  resource_group_name = azurerm_resource_group.iq_rg.name
  workspace_id        = azurerm_log_analytics_workspace.iq_logs_ha.id
  application_type    = "web"

  tags = merge(var.common_tags, {
    Name = "appi-${var.cluster_name}"
  })
}


locals {
  workload_profile_name = "${var.workload_profile_type}-Profile-HA"
  opensearch_enabled    = var.search_engine == "opensearch"
  opensearch_uri        = "${var.opensearch_use_tls ? "https" : "http"}://${var.opensearch_endpoint}:${var.opensearch_port}"
}

resource "azurerm_container_app_environment" "iq_env_ha" {
  name                       = "cae-${var.cluster_name}"
  location                   = azurerm_resource_group.iq_rg.location
  resource_group_name        = azurerm_resource_group.iq_rg.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.iq_logs_ha.id


  infrastructure_subnet_id = azurerm_subnet.private_subnets[0].id


  # One replica at the published sizes occupies one node, so the node count
  # follows the replica count.
  workload_profile {
    name                  = local.workload_profile_name
    workload_profile_type = var.workload_profile_type
    minimum_count         = var.iq_min_replicas
    maximum_count         = var.iq_max_replicas
  }

  tags = merge(var.common_tags, {
    Name = "cae-${var.cluster_name}"
  })
}


resource "azurerm_container_app" "iq_app_ha" {
  name                         = "ca-${var.cluster_name}"
  container_app_environment_id = azurerm_container_app_environment.iq_env_ha.id
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

    min_replicas = var.iq_min_replicas
    max_replicas = var.iq_max_replicas



    http_scale_rule {
      name                = "http-requests"
      concurrent_requests = var.scale_rule_concurrent_requests
    }




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


      command = ["/bin/sh"]
      args = [
        "-c",
        <<-EOF
          set -e
          echo "Starting Nexus IQ Server HA instance - Replica: $HOSTNAME"
          # HeapDumpPath in java_opts names a directory, and the JVM writes the
          # dump as a file of that name when the directory is missing.
          mkdir -p /sonatype-work/Java_Heap_logs
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


          UNIQUE_WORK="/sonatype-work/clm-server-$HOSTNAME"
          CLUSTER_DIR="/sonatype-work/clm-cluster"

          echo "Creating unique work directory: $UNIQUE_WORK"
          mkdir -p "$UNIQUE_WORK"

          echo "Creating shared cluster directory: $CLUSTER_DIR"
          mkdir -p "$CLUSTER_DIR"



          cat > /etc/nexus-iq-server/config.yml << 'CONFIGEOF'
sonatypeWork: $UNIQUE_WORK
clusterDirectory: $CLUSTER_DIR


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


          sed -i "s|\$UNIQUE_WORK|$UNIQUE_WORK|g" /etc/nexus-iq-server/config.yml
          sed -i "s|\$CLUSTER_DIR|$CLUSTER_DIR|g" /etc/nexus-iq-server/config.yml
          sed -i "s|\$DB_HOST|$DB_HOST|g" /etc/nexus-iq-server/config.yml
          sed -i "s|\$DB_PORT|$DB_PORT|g" /etc/nexus-iq-server/config.yml
          sed -i "s|\$DB_NAME|$DB_NAME|g" /etc/nexus-iq-server/config.yml
          sed -i "s|\$DB_USER|$DB_USER|g" /etc/nexus-iq-server/config.yml
          sed -i "s|\$DB_PASSWORD|$DB_PASSWORD|g" /etc/nexus-iq-server/config.yml
          sed -i "s|\$HOSTNAME|$HOSTNAME|g" /etc/nexus-iq-server/config.yml
%{if local.opensearch_enabled}

          # Written from the container app secrets as single-quoted YAML scalars with
          # ' doubled, after the $HOSTNAME sed, so nothing can change the file.
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
            printf '    uri: %s\n' '${local.opensearch_uri}'
            printf "    username: '%s'\n" "$os_user"
            printf "    password: '%s'\n" "$os_pass"
            printf '    nexusOneIndexReplicas: %s\n' '${var.opensearch_index_replicas}'
          } >> /etc/nexus-iq-server/config.yml

          unset os_user os_pass
%{endif}

          echo "Successfully created HA config.yml for replica: $HOSTNAME at /etc/nexus-iq-server/config.yml"
          echo "Generated config file contents, with every password redacted:"
          sed "s/^\([[:space:]]*password:\).*/\1 '***'/" /etc/nexus-iq-server/config.yml


          ls -la /sonatype-work/


          echo "Starting Nexus IQ Server HA replica: $HOSTNAME"
          exec /opt/sonatype/nexus-iq-server/bin/nexus-iq-server server /etc/nexus-iq-server/config.yml
        EOF
      ]


      env {
        name  = "JAVA_OPTS"
        value = var.java_opts
      }

      env {
        name  = "OPENSEARCH_CA_PEM"
        value = var.opensearch_ca_pem
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


      env {
        name  = "CLUSTER_ENABLED"
        value = "true"
      }

      env {
        name  = "CLUSTER_DIRECTORY"
        value = "/sonatype-work/clm-cluster"
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
        name = "iq-data-ha"
        path = "/sonatype-work"
      }

      volume_mounts {
        name = "config-volume-ha"
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
    for_each = local.opensearch_enabled ? [1] : []
    content {
      name  = "opensearch-username"
      value = var.opensearch_username
    }
  }

  dynamic "secret" {
    for_each = local.opensearch_enabled ? [1] : []
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


  dapr {
    app_id       = "nexus-iq-ha"
    app_port     = 8070
    app_protocol = "http"
  }

  lifecycle {
    # Preconditions rather than validations on the variables, because a
    # validation that reads another variable needs Terraform 1.9.
    precondition {
      condition     = var.search_engine != "opensearch" || length(var.opensearch_endpoint) > 0
      error_message = "opensearch_endpoint must be set when search_engine is 'opensearch'."
    }

    precondition {
      condition     = var.search_engine != "opensearch" || length(var.opensearch_username) > 0
      error_message = "opensearch_username must be set when search_engine is 'opensearch'."
    }

    precondition {
      condition     = var.search_engine != "opensearch" || length(var.opensearch_password) > 0
      error_message = "opensearch_password must be set when search_engine is 'opensearch'."
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
    azurerm_postgresql_flexible_server.iq_db_ha,
    azurerm_postgresql_flexible_server_database.iq_database_ha,
    azurerm_container_app_environment_storage.iq_storage_ha
  ]
}