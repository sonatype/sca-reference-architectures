#!/bin/bash

# Nexus IQ Server HA Startup Script for Container-Optimized OS
# This script runs on each Compute Engine instance to configure and start the Nexus IQ Server container

set -euo pipefail

# Configuration from Terraform template
DOCKER_IMAGE="${docker_image}"
DB_HOST="${db_host}"
DB_PORT="${db_port}"
DB_NAME="${db_name}"
DB_USER="${db_user}"
DB_PASSWORD_SECRET="${db_password_secret}"
JAVA_OPTS="${java_opts}"
PROJECT_ID="${gcp_project_id}"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a /var/log/nexus-iq-startup.log
}

log "Starting Nexus IQ Server HA setup on $(hostname)"

# Install required packages
log "Installing required packages..."
apt-get update
apt-get install -y curl jq nfs-common

# Install Docker
log "Installing Docker..."
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
systemctl start docker
systemctl enable docker

# Mount Cloud Filestore NFS for persistent shared data
log "Setting up Cloud Filestore NFS mount..."
MOUNT_POINT="/sonatype-work"
NFS_SERVER_IP="${filestore_ip}"
NFS_SHARE="/nexus_iq_ha_data"

# NFS client already installed above

# Create mount point
mkdir -p "$MOUNT_POINT"

# Mount the NFS share
log "Mounting NFS share from $NFS_SERVER_IP:$NFS_SHARE to $MOUNT_POINT"
mount -t nfs -o nfsvers=3,hard,intr,rsize=1048576,wsize=1048576,timeo=600,retrans=2 \
    "$NFS_SERVER_IP:$NFS_SHARE" "$MOUNT_POINT" || {
    log "NFS mount failed, retrying..."
    sleep 10
    mount -t nfs -o nfsvers=3,hard,intr,rsize=1048576,wsize=1048576,timeo=600,retrans=2 \
        "$NFS_SERVER_IP:$NFS_SHARE" "$MOUNT_POINT"
}

# Add to fstab for persistence
if ! grep -q "$NFS_SERVER_IP:$NFS_SHARE" /etc/fstab; then
    echo "$NFS_SERVER_IP:$NFS_SHARE $MOUNT_POINT nfs nfsvers=3,hard,intr,rsize=1048576,wsize=1048576,timeo=600,retrans=2 0 0" >> /etc/fstab
fi

# Set ownership for nexus user (UID 997 in the container)
chown -R 997:997 "$MOUNT_POINT" || log "Failed to set ownership, continuing..."

# Create unique work directory for this instance based on hostname
HOSTNAME=$(hostname)
UNIQUE_WORK_DIR="$MOUNT_POINT/clm-server-$HOSTNAME"
CLUSTER_DIR="$MOUNT_POINT/clm-cluster"

log "Creating work directories..."
mkdir -p "$UNIQUE_WORK_DIR"
mkdir -p "$CLUSTER_DIR"
mkdir -p "$UNIQUE_WORK_DIR/config"
mkdir -p "$UNIQUE_WORK_DIR/logs"

# Set proper ownership
chown -R 997:997 "$UNIQUE_WORK_DIR" "$CLUSTER_DIR"

# Get database password from Secret Manager
log "Retrieving database password from Secret Manager..."
DB_SECRET_JSON=$(gcloud secrets versions access latest --secret="$DB_PASSWORD_SECRET" --project="$PROJECT_ID")
DB_PASSWORD=$(echo "$DB_SECRET_JSON" | jq -r '.password')

# Generate custom config.yml for this instance
log "Generating Nexus IQ Server configuration..."
cat > "$UNIQUE_WORK_DIR/config/config.yml" << EOF
sonatypeWork: $UNIQUE_WORK_DIR
clusterDirectory: $CLUSTER_DIR

# Database configuration for PostgreSQL
database:
  type: postgresql
  hostname: $DB_HOST
  port: $DB_PORT
  name: $DB_NAME
  username: $DB_USER
  password: "$DB_PASSWORD"

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
      currentLogFilename: "$UNIQUE_WORK_DIR/logs/request.log"
      archivedLogFilenamePattern: "$UNIQUE_WORK_DIR/logs/request-%d.log.gz"
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
        currentLogFilename: "$UNIQUE_WORK_DIR/logs/audit.log"
        archivedLogFilenamePattern: "$UNIQUE_WORK_DIR/logs/audit-%d.log.gz"
        archivedFileCount: 50
  appenders:
  - type: console
    threshold: INFO
    logFormat: "%d{'yyyy-MM-dd HH:mm:ss,SSSZ'} %level [%thread] %X{username} %logger - %msg%n"
  - type: file
    threshold: ALL
    currentLogFilename: "$UNIQUE_WORK_DIR/logs/clm-server.log"
    archivedLogFilenamePattern: "$UNIQUE_WORK_DIR/logs/clm-server-%d.log.gz"
    logFormat: "%d{'yyyy-MM-dd HH:mm:ss,SSSZ'} %level [%thread] %X{username} %logger - %msg%n"
    archivedFileCount: 5

createSampleData: true
EOF

# Set proper ownership for config file
chown 997:997 "$UNIQUE_WORK_DIR/config/config.yml"

log "Configuration file created at: $UNIQUE_WORK_DIR/config/config.yml"

# Pull Docker image
log "Pulling Docker image: $DOCKER_IMAGE"
docker pull "$DOCKER_IMAGE"

# Stop any existing container
docker stop nexus-iq-server 2>/dev/null || true
docker rm nexus-iq-server 2>/dev/null || true

# Create log directory for container
mkdir -p "$UNIQUE_WORK_DIR/logs"
chown -R 997:997 "$UNIQUE_WORK_DIR/logs"

# Start Nexus IQ Server container using config.yml file
log "Starting Nexus IQ Server container with config file..."
docker run -d \
  --name nexus-iq-server \
  --restart unless-stopped \
  -p 8070:8070 \
  -p 8071:8071 \
  -v "$MOUNT_POINT:$MOUNT_POINT" \
  -v "$UNIQUE_WORK_DIR/config/config.yml:/etc/nexus-iq-server/config.yml" \
  -v "$UNIQUE_WORK_DIR/logs:/var/log/nexus-iq-server" \
  -e JAVA_OPTS="$JAVA_OPTS" \
  -e NEXUS_SECURITY_RANDOMPASSWORD=false \
  --user 997:997 \
  "$DOCKER_IMAGE"

# Add random startup delay to stagger container starts and reduce resource contention
STARTUP_DELAY=$((RANDOM % 60 + 30))  # Random delay between 30-90 seconds
log "Adding startup delay of $STARTUP_DELAY seconds to stagger container starts..."
sleep $STARTUP_DELAY

# Wait for container to start
log "Waiting for Nexus IQ Server to start..."
sleep 30

# Health check - wait longer for database initialization
log "Waiting for Nexus IQ Server to start (this may take up to 10 minutes for database initialization)..."
for i in {1..60}; do
    if curl -f http://localhost:8070/assets/index.html >/dev/null 2>&1; then
        log "Nexus IQ Server is healthy and ready"
        break
    elif curl -f http://localhost:8070/ >/dev/null 2>&1; then
        log "Nexus IQ Server is responding but not fully ready"
    fi
    log "Attempt $i: Waiting for Nexus IQ Server to be ready..."
    sleep 10
done

# Log container status
docker ps | grep nexus-iq-server || log "Container not running!"
docker logs nexus-iq-server | tail -20

log "Nexus IQ Server HA startup completed on $(hostname)"

# Configure log rotation for startup log
cat > /etc/logrotate.d/nexus-iq-startup << EOF
/var/log/nexus-iq-startup.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
}
EOF

exit 0