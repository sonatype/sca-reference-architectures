#!/bin/bash
set -e

echo "=== Starting Nexus IQ Server Docker Installation ==="

apt-get update
apt-get install -y docker.io curl nfs-common

systemctl enable docker
systemctl start docker

echo "=== Mounting Filestore for persistent data ==="
mkdir -p /mnt/sonatype-work
mkdir -p /mnt/iq-logs

FILESTORE_IP="${filestore_ip}"
FILESTORE_SHARE="nexus_iq_data"

mount -t nfs -o vers=3 $FILESTORE_IP:/$FILESTORE_SHARE /mnt/sonatype-work

mkdir -p /mnt/sonatype-work/sonatype-work
mkdir -p /mnt/sonatype-work/logs

cat >> /etc/fstab << FSTAB_EOF
$FILESTORE_IP:/$FILESTORE_SHARE /mnt/sonatype-work nfs defaults,_netdev 0 0
FSTAB_EOF

%{ if search_engine == "opensearch" ~}
echo "=== Reading the OpenSearch password from Secret Manager ==="
OPENSEARCH_PASSWORD=$(gcloud secrets versions access latest \
  --secret="${opensearch_password_secret}" \
  --project="${gcp_project_id}")

if [ -z "$OPENSEARCH_PASSWORD" ]; then
  echo "FATAL: could not read the OpenSearch password from Secret Manager"
  exit 1
fi
echo "OpenSearch password read successfully"

%{ endif ~}
echo "=== Creating Docker entrypoint script ==="
cat > /opt/docker-entrypoint.sh << 'ENTRYPOINT_EOF'
#!/bin/sh
set -e

echo "Starting Nexus IQ Server with Docker"

mkdir -p /etc/nexus-iq-server

cat > /etc/nexus-iq-server/config.yml << 'CONFIGEOF'
sonatypeWork: /sonatype-work

database:
  type: postgresql
  hostname: $DB_HOST
  port: $DB_PORT
  name: $DB_NAME
  username: $DB_USERNAME
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
    logFormat: "%d{'yyyy-MM-dd HH:mm:ss,SSSZ'} %level [%thread] %X{username} %logger - %msg%n"
  - type: file
    threshold: ALL
    currentLogFilename: "/var/log/nexus-iq-server/clm-server.log"
    archivedLogFilenamePattern: "/var/log/nexus-iq-server/clm-server-%d.log.gz"
    logFormat: "%d{'yyyy-MM-dd HH:mm:ss,SSSZ'} %level [%thread] %X{username} %logger - %msg%n"
    archivedFileCount: 50

createSampleData: true
CONFIGEOF

sed -i "s|\$DB_HOST|$DB_HOST|g" /etc/nexus-iq-server/config.yml
sed -i "s|\$DB_PORT|$DB_PORT|g" /etc/nexus-iq-server/config.yml
sed -i "s|\$DB_NAME|$DB_NAME|g" /etc/nexus-iq-server/config.yml
sed -i "s|\$DB_USERNAME|$DB_USERNAME|g" /etc/nexus-iq-server/config.yml
sed -i "s|\$DB_PASSWORD|$DB_PASSWORD|g" /etc/nexus-iq-server/config.yml
%{ if search_engine == "opensearch" ~}

# The search block is appended here rather than written into the heredoc above, so the password
# never passes through sed. A sed replacement reads \ and & specially and ends at the | delimiter,
# so a password containing any of those three is mangled with no error. The password is written as
# a single-quoted YAML scalar, which takes every character literally with an embedded single quote
# written twice, so | & \ ": " " #" and a leading indicator character all survive intact and none
# of them can break the YAML. Top-level keys may appear in any order, so the end of the file is as
# good a place as the middle.
{
  echo "search:"
  echo "  type: http"
  echo "  mode: OPENSEARCH"
  echo "  uri: ${opensearch_uri}"
  echo "  username: ${opensearch_username}"
  printf "  password: '%s'\n" "$(printf '%s' "$OPENSEARCH_PASSWORD" | sed "s/'/''/g")"
  echo "  nexusOneIndexReplicas: ${opensearch_index_replicas}"
} >> /etc/nexus-iq-server/config.yml
%{ endif ~}

echo "Successfully created config.yml with database configuration"
# Every password line is redacted. This is the container's stdout, and scripts/startup.sh reads it
# back with `docker logs`, so whatever is printed here also reaches the instance serial console and
# Cloud Logging, where anyone holding roles/logging.viewer on the project could read it.
echo "Generated config file contents, with passwords redacted:"
sed 's/^\([[:space:]]*password:\).*/\1 <redacted>/' /etc/nexus-iq-server/config.yml

export JAVA_OPTS

echo "Starting Nexus IQ Server"
exec /opt/sonatype/nexus-iq-server/bin/nexus-iq-server server /etc/nexus-iq-server/config.yml
ENTRYPOINT_EOF

chmod +x /opt/docker-entrypoint.sh

echo "=== Starting Nexus IQ Server Docker Container ==="
# Replace any container left by an earlier boot. `docker run --name` fails on a name clash, and
# under `set -e` the script would end right here with the old container still running on its old
# environment, so a password rotation followed by `gcloud compute instances reset` would not take
# effect. Removing it first makes every boot build the container from current values.
docker stop nexus-iq-server 2>/dev/null || true
docker rm nexus-iq-server 2>/dev/null || true

docker run -d \
  --name nexus-iq-server \
  --restart always \
  --user 0:0 \
  -p 8070:8070 \
  -p 8071:8071 \
  -e DB_HOST="${db_host}" \
  -e DB_PORT="${db_port}" \
  -e DB_NAME="${db_name}" \
  -e DB_USERNAME="${db_username}" \
  -e DB_PASSWORD="${db_password}" \
  -e JAVA_OPTS="${java_opts}" \
  -e NEXUS_SECURITY_RANDOMPASSWORD="false" \
%{ if search_engine == "opensearch" ~}
  -e OPENSEARCH_PASSWORD="$OPENSEARCH_PASSWORD" \
%{ endif ~}
  -v /mnt/sonatype-work/sonatype-work:/sonatype-work \
  -v /mnt/sonatype-work/logs:/var/log/nexus-iq-server \
  -v /opt/docker-entrypoint.sh:/docker-entrypoint.sh \
  --entrypoint /docker-entrypoint.sh \
  ${docker_image}

echo "=== Verifying Docker container status ==="
sleep 10
docker ps -a | grep nexus-iq-server
# This output goes to the instance serial console and on to Cloud Logging, so any password line
# the container happens to print is redacted on the way through.
docker logs nexus-iq-server 2>&1 | sed 's/^\([[:space:]]*password:\).*/\1 <redacted>/'

echo "=== Nexus IQ Server Docker Installation Complete ==="
