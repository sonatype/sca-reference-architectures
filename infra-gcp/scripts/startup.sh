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

echo "Successfully created config.yml with database configuration"
echo "Generated config file contents:"
cat /etc/nexus-iq-server/config.yml

export JAVA_OPTS

echo "Starting Nexus IQ Server"
exec /opt/sonatype/nexus-iq-server/bin/nexus-iq-server server /etc/nexus-iq-server/config.yml
ENTRYPOINT_EOF

chmod +x /opt/docker-entrypoint.sh

echo "=== Starting Nexus IQ Server Docker Container ==="
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
  -v /mnt/sonatype-work/sonatype-work:/sonatype-work \
  -v /mnt/sonatype-work/logs:/var/log/nexus-iq-server \
  -v /opt/docker-entrypoint.sh:/docker-entrypoint.sh \
  --entrypoint /docker-entrypoint.sh \
  ${docker_image}

echo "=== Verifying Docker container status ==="
sleep 10
docker ps -a | grep nexus-iq-server
docker logs nexus-iq-server

echo "=== Nexus IQ Server Docker Installation Complete ==="
