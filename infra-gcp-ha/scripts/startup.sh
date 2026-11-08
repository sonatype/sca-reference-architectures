#!/bin/bash
set -euo pipefail

echo "=== Starting Nexus IQ Server HA Docker Installation ==="

# Configuration from Terraform template (using lowercase to match templatefile vars)
IQ_DOCKER_IMAGE="${iq_docker_image}"
DB_HOST="${db_host}"
DB_PORT="${db_port}"
DB_NAME="${db_name}"
DB_USER="${db_user}"
DB_PASSWORD_SECRET="${db_password_secret}"
JAVA_OPTS="${java_opts}"
PROJECT_ID="${gcp_project_id}"
FILESTORE_IP="${filestore_ip}"
%{ if search_engine == "opensearch" ~}
OPENSEARCH_PASSWORD_SECRET="${opensearch_password_secret}"
%{ endif ~}

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a /var/log/nexus-iq-startup.log
}

log "Starting Nexus IQ Server HA Docker setup on $(hostname)"

# ============================================
# SECTION 1: Install Required Packages
# ============================================
log "Installing required packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y \
  docker.io \
  nfs-common \
  jq \
  curl \
  wget

# Install Google Cloud Ops Agent from the official installation script
log "Installing Google Cloud Ops Agent..."
curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
bash add-google-cloud-ops-agent-repo.sh --also-install
rm -f add-google-cloud-ops-agent-repo.sh

# ============================================
# SECTION 2: Mount Cloud Filestore NFS (BEFORE DOCKER)
# ============================================
log "Setting up Cloud Filestore NFS mount..."
MOUNT_POINT="/mnt/filestore"
NFS_SHARE="/nexus_iq_ha_data"

# Create mount point
mkdir -p "$${MOUNT_POINT}"

# Mount the NFS share with retries
# The fstab entry written below survives a reboot, so on a later boot the share may already be
# mounted here. Mounting the same share on the same mount point again is refused with EBUSY, which
# this loop would read as five failed attempts and then exit, so check first.
if mountpoint -q "$${MOUNT_POINT}"; then
  log "$${MOUNT_POINT} is already mounted, leaving it as it is"
else
log "Mounting NFS share from $${FILESTORE_IP}:$${NFS_SHARE} to $${MOUNT_POINT}"
for attempt in {1..5}; do
  if mount -t nfs -o nfsvers=3,hard,intr,rsize=1048576,wsize=1048576,timeo=600,retrans=2 \
      "$${FILESTORE_IP}:$${NFS_SHARE}" "$${MOUNT_POINT}"; then
    log "NFS mounted successfully on attempt $${attempt}"
    break
  else
    log "NFS mount attempt $${attempt}/5 failed, retrying in 10 seconds..."
    sleep 10
  fi

  if [ $attempt -eq 5 ]; then
    log "FATAL: NFS mount failed after 5 attempts"
    exit 1
  fi
done
fi

# Verify mount
if ! mountpoint -q "$${MOUNT_POINT}"; then
  log "FATAL: NFS mount verification failed"
  exit 1
fi
log "NFS mount verified successfully"

# Add to fstab for persistence
if ! grep -q "$${FILESTORE_IP}:$${NFS_SHARE}" /etc/fstab; then
    echo "$${FILESTORE_IP}:$${NFS_SHARE} $${MOUNT_POINT} nfs nfsvers=3,hard,intr,rsize=1048576,wsize=1048576,timeo=600,retrans=2,_netdev 0 0" >> /etc/fstab
    log "Added NFS mount to /etc/fstab"
fi

# ============================================
# SECTION 3: Capture Hostname & Create Directories
# ============================================
# CRITICAL: Capture hostname BEFORE Docker starts (container has different hostname)
INSTANCE_HOSTNAME=$(hostname)
log "Instance hostname: $${INSTANCE_HOSTNAME}"

# Create unique work directory for this instance and shared cluster directory
UNIQUE_WORK_HOST="$${MOUNT_POINT}/clm-server-$${INSTANCE_HOSTNAME}"
CLUSTER_DIR_HOST="$${MOUNT_POINT}/clm-cluster"

log "Creating work directories on NFS..."
mkdir -p "$${UNIQUE_WORK_HOST}"
mkdir -p "$${CLUSTER_DIR_HOST}"
mkdir -p "$${UNIQUE_WORK_HOST}/logs"

# CRITICAL: Set proper ownership for Docker container (UID 0 = root, matching AWS/Azure)
log "Setting permissions for Docker container (root user)..."
chown -R root:root "$${UNIQUE_WORK_HOST}"
chown -R root:root "$${CLUSTER_DIR_HOST}"
chmod -R 755 "$${UNIQUE_WORK_HOST}"
chmod -R 755 "$${CLUSTER_DIR_HOST}"

log "Host work directory: $${UNIQUE_WORK_HOST}"
log "Host cluster directory: $${CLUSTER_DIR_HOST}"

# ============================================
# SECTION 4: Docker Setup
# ============================================
log "Enabling and starting Docker daemon..."
systemctl enable docker
systemctl start docker

# Wait for Docker to be ready
log "Waiting for Docker daemon to be ready..."
sleep 10
if ! docker info >/dev/null 2>&1; then
  log "FATAL: Docker daemon not ready after 10 seconds"
  exit 1
fi
log "Docker daemon is ready"

# An Artifact Registry image is pulled with the instance's service account, which the metadata
# server supplies once docker is told to ask gcloud for it.
case "$${IQ_DOCKER_IMAGE}" in
  *-docker.pkg.dev/*)
    log "Configuring docker to authenticate to $${IQ_DOCKER_IMAGE%%/*}"
    gcloud auth configure-docker "$${IQ_DOCKER_IMAGE%%/*}" --quiet
    ;;
esac

# Pull Docker image with retries
log "Pulling Nexus IQ Server Docker image ($${IQ_DOCKER_IMAGE})..."
for attempt in {1..3}; do
  if docker pull $${IQ_DOCKER_IMAGE}; then
    log "Docker image pulled successfully"
    break
  fi
  log "Docker pull attempt $${attempt}/3 failed, retrying in 30s..."
  sleep 30
  
  if [ $attempt -eq 3 ]; then
    log "FATAL: Failed to pull Docker image after 3 attempts"
    exit 1
  fi
done

# ============================================
# SECTION 5: Get Database Password from Secret Manager
# ============================================
log "Retrieving database password from Secret Manager..."
DB_PASSWORD=$(gcloud secrets versions access latest \
  --secret="$${DB_PASSWORD_SECRET}" \
  --project="$${PROJECT_ID}")

if [ -z "$DB_PASSWORD" ]; then
  log "FATAL: Failed to retrieve database password from Secret Manager"
  exit 1
fi
log "Database password retrieved successfully"

%{ if search_engine == "opensearch" ~}
log "Retrieving OpenSearch password from Secret Manager..."
OPENSEARCH_PASSWORD=$(gcloud secrets versions access latest \
  --secret="$${OPENSEARCH_PASSWORD_SECRET}" \
  --project="$${PROJECT_ID}")

if [ -z "$OPENSEARCH_PASSWORD" ]; then
  log "FATAL: Failed to retrieve OpenSearch password from Secret Manager"
  exit 1
fi
log "OpenSearch password retrieved successfully"

%{ endif ~}# ============================================
# SECTION 6: Generate config.yml
# ============================================
# CRITICAL: Use CONTAINER PATHS (not host paths)
# Container sees /sonatype-work/* (mapped from /mnt/filestore/* on host)
UNIQUE_WORK_CONTAINER="/sonatype-work/clm-server-$${INSTANCE_HOSTNAME}"
CLUSTER_DIR_CONTAINER="/sonatype-work/clm-cluster"

log "Generating Nexus IQ Server configuration..."
mkdir -p /etc/nexus-iq-server

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
      currentLogFilename: "$UNIQUE_WORK/logs/request.log"
      archivedLogFilenamePattern: "$UNIQUE_WORK/logs/request-%d.log.gz"
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
%{ for logger_name, logger_level in iq_log_levels ~}
    ${logger_name}: ${logger_level}
%{ endfor ~}
    com.sonatype.insight.audit:
      appenders:
      - type: file
        currentLogFilename: "$UNIQUE_WORK/logs/audit.log"
        archivedLogFilenamePattern: "$UNIQUE_WORK/logs/audit-%d.log.gz"
        archivedFileCount: 50
  appenders:
  - type: console
    threshold: INFO
    logFormat: "%d{'yyyy-MM-dd HH:mm:ss,SSSZ'} %level [%thread] %X{username} %logger - INSTANCE:$INSTANCE_HOSTNAME %msg%n"
  - type: file
    threshold: ALL
    currentLogFilename: "$UNIQUE_WORK/logs/clm-server.log"
    archivedLogFilenamePattern: "$UNIQUE_WORK/logs/clm-server-%d.log.gz"
    logFormat: "%d{'yyyy-MM-dd HH:mm:ss,SSSZ'} %level [%thread] %X{username} %logger - INSTANCE:$INSTANCE_HOSTNAME %msg%n"
    archivedFileCount: 50

createSampleData: true
CONFIGEOF

# Replace placeholders with actual values
sed -i "s|\$UNIQUE_WORK|$${UNIQUE_WORK_CONTAINER}|g" /etc/nexus-iq-server/config.yml
sed -i "s|\$CLUSTER_DIR|$${CLUSTER_DIR_CONTAINER}|g" /etc/nexus-iq-server/config.yml
sed -i "s|\$DB_HOST|$${DB_HOST}|g" /etc/nexus-iq-server/config.yml
sed -i "s|\$DB_PORT|$${DB_PORT}|g" /etc/nexus-iq-server/config.yml
sed -i "s|\$DB_NAME|$${DB_NAME}|g" /etc/nexus-iq-server/config.yml
sed -i "s|\$DB_USER|$${DB_USER}|g" /etc/nexus-iq-server/config.yml
sed -i "s|\$DB_PASSWORD|$${DB_PASSWORD}|g" /etc/nexus-iq-server/config.yml
sed -i "s|\$INSTANCE_HOSTNAME|$${INSTANCE_HOSTNAME}|g" /etc/nexus-iq-server/config.yml
%{ if search_engine == "opensearch" ~}

# The search block is appended here rather than written into the heredoc above, so the password
# never passes through sed. A sed replacement reads \ and & specially and ends at the | delimiter,
# so a password containing any of those three is mangled with no error. The password is written as
# a single-quoted YAML scalar, which takes every character literally with an embedded single quote
# written twice, so | & \ ": " " #" and a leading indicator character all survive intact and none
# of them can break the YAML. Top-level keys may appear in any order, so the end of the file is as
# good a place as the middle.
# The user name is written as a single-quoted scalar for the same reason. Its Terraform variable
# refuses the single quote, double quote, dollar, backtick and backslash characters, which are the
# five the quoting here cannot absorb, so | & ": " " #" and a leading indicator all survive intact.
{
  echo "search:"
  echo "  type: http"
  echo "  mode: OPENSEARCH"
  echo "  uri: ${opensearch_uri}"
  echo "  username: '${opensearch_username}'"
  printf "  password: '%s'\n" "$(printf '%s' "$OPENSEARCH_PASSWORD" | sed "s/'/''/g")"
  # The Nexus One index builds its connection from nexusOne.connection alone, and reads
  # nexusOneIndexReplicas from it. Without this block enabling the nexus-one feature is refused.
  echo "nexusOne:"
  echo "  connection:"
  echo "    type: http"
  echo "    mode: OPENSEARCH"
  echo "    uri: ${opensearch_uri}"
  echo "    username: '${opensearch_username}'"
  printf "    password: '%s'\n" "$(printf '%s' "$OPENSEARCH_PASSWORD" | sed "s/'/''/g")"
  echo "    nexusOneIndexReplicas: ${opensearch_index_replicas}"
} >> /etc/nexus-iq-server/config.yml
%{ if opensearch_ca_secret != "" ~}

# A private certificate authority for the cluster: copy the image's JVM trust store onto Filestore,
# add the authority to the copy, and point the JVM at the copy. Replacing the JVM's own store would
# break IQ Server's calls to the Sonatype data services.
log "Building the OpenSearch trust store on Filestore..."
gcloud secrets versions access latest --secret="${opensearch_ca_secret}" --project="$${PROJECT_ID}" > /tmp/opensearch-ca.pem
TRUSTSTORE_HOST="$${MOUNT_POINT}/opensearch-cacerts"
docker run --rm --user 0:0 --entrypoint /bin/sh \
  -e STAGING="opensearch-cacerts.$${INSTANCE_HOSTNAME}" \
  -v "$${MOUNT_POINT}:/sonatype-work" -v /tmp/opensearch-ca.pem:/tmp/opensearch-ca.pem:ro \
  "$${IQ_DOCKER_IMAGE}" -c '
    JVM_CACERTS=$(find / \( -path /sonatype-work -o -path /proc -o -path /sys \) -prune -o -name cacerts -path "*lib/security*" -print 2>/dev/null | head -1)
    KEYTOOL=$(find / \( -path /sonatype-work -o -path /proc -o -path /sys \) -prune -o -name keytool -type f -perm -u+x -print 2>/dev/null | head -1)
    [ -n "$JVM_CACERTS" ] && [ -n "$KEYTOOL" ] || { echo "cacerts=$JVM_CACERTS keytool=$KEYTOOL, one is missing"; exit 1; }
    cp "$JVM_CACERTS" "/sonatype-work/$STAGING" &&
      "$KEYTOOL" -importcert -noprompt -keystore "/sonatype-work/$STAGING" -storepass changeit -alias opensearch-ca -file /tmp/opensearch-ca.pem &&
      mv "/sonatype-work/$STAGING" /sonatype-work/opensearch-cacerts'
[ -s "$${TRUSTSTORE_HOST}" ] || { log "FATAL: the OpenSearch trust store was not written"; exit 1; }
JAVA_OPTS="$${JAVA_OPTS} -Djavax.net.ssl.trustStore=/sonatype-work/opensearch-cacerts -Djavax.net.ssl.trustStorePassword=changeit"
log "Trust store ready at $${TRUSTSTORE_HOST}"
%{ endif ~}
%{ endif ~}

log "Configuration file created at: /etc/nexus-iq-server/config.yml"

# ============================================
# SECTION 7: Configure Cloud Logging Agent
# ============================================
log "Configuring Cloud Logging agent for log collection..."
cat > /etc/google-cloud-ops-agent/config.yaml << 'OPSAGENTEOF'
logging:
  receivers:
    iq_application_log:
      type: files
      include_paths:
      - /mnt/filestore/clm-server-*/logs/clm-server.log
    iq_request_log:
      type: files
      include_paths:
      - /mnt/filestore/clm-server-*/logs/request.log
    iq_audit_log:
      type: files
      include_paths:
      - /mnt/filestore/clm-server-*/logs/audit.log
  service:
    pipelines:
      iq_logs:
        receivers: [iq_application_log, iq_request_log, iq_audit_log]
OPSAGENTEOF

systemctl enable google-cloud-ops-agent
systemctl restart google-cloud-ops-agent
log "Cloud Logging agent configured and started"

# ============================================
# SECTION 8: Start Docker Container
# ============================================
log "Starting Nexus IQ Server Docker container..."

# Stop and remove any existing container
docker stop nexus-iq-server 2>/dev/null || true
docker rm nexus-iq-server 2>/dev/null || true

# Run container with custom entrypoint to match AWS/Azure approach
# Override entrypoint to explicitly call the IQ Server binary with server command
# Run as root (UID 0) to match AWS/Azure and have permission to access mounted directories
docker run -d \
  --name nexus-iq-server \
  --restart=unless-stopped \
  --user 0:0 \
  -p 8070:8070 \
  -p 8071:8071 \
  -v "$${MOUNT_POINT}:/sonatype-work" \
  -v /etc/nexus-iq-server/config.yml:/etc/nexus-iq-server/config.yml:ro \
  -e JAVA_OPTS="$${JAVA_OPTS}" \
  --entrypoint /bin/sh \
  $${IQ_DOCKER_IMAGE} \
  -c "exec /opt/sonatype/nexus-iq-server/bin/nexus-iq-server server /etc/nexus-iq-server/config.yml"

if [ $? -ne 0 ]; then
  log "FATAL: Failed to start Docker container"
  docker logs nexus-iq-server 2>&1 | tail -50 | tee -a /var/log/nexus-iq-startup.log
  exit 1
fi

log "Docker container started successfully"

# ============================================
# SECTION 9: Health Check Loop
# ============================================
log "Waiting for Nexus IQ Server to start (this may take several minutes)..."
sleep 30

for i in {1..60}; do
    if docker ps | grep -q nexus-iq-server; then
        if curl -f http://localhost:8070/ >/dev/null 2>&1; then
            log "SUCCESS: Nexus IQ Server is healthy and responding on port 8070"
            break
        fi
    fi
    log "Attempt $${i}/60: Waiting for Nexus IQ Server to be ready..."
    sleep 10
done

# ============================================
# SECTION 10: Status Logging
# ============================================
log "Docker container status:"
docker ps -a | grep nexus-iq-server || true

log "Recent container logs:"
docker logs nexus-iq-server --tail 50 2>&1 || true

log "=== Nexus IQ Server HA Docker startup completed ==="
log "Instance hostname: $${INSTANCE_HOSTNAME}"
log "Host work directory: $${UNIQUE_WORK_HOST}"
log "Container work directory: $${UNIQUE_WORK_CONTAINER}"
log "Cluster directory (host): $${CLUSTER_DIR_HOST}"
log "Cluster directory (container): $${CLUSTER_DIR_CONTAINER}"
log "Application accessible at: http://localhost:8070"

# Configure log rotation for startup log
cat > /etc/logrotate.d/nexus-iq-startup << 'LOGROTATEEOF'
/var/log/nexus-iq-startup.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
}
LOGROTATEEOF

exit 0
