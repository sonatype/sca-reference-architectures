# Nexus IQ Server - GCP Single Instance (Docker)

This Terraform configuration deploys Nexus IQ Server on Google Cloud Platform (GCP) using **GCE with Docker containers** in a single-instance architecture.

## Architecture Overview

This implementation deploys Nexus IQ Server using **Docker containers on GCE**, providing easier version management and consistent deployments:

```
┌─────────────────────────────────────────────────────────────┐
│                    Global Load Balancer                      │
│                  (HTTP/HTTPS - Port 80/443)                  │
└────────────────────────────┬────────────────────────────────┘
                             │
                   ┌─────────▼──────────┐
                   │   Instance Group   │
                   └─────────┬──────────┘
                             │
        ┌────────────────────▼────────────────────┐
        │   GCE Instance (e2-standard-8)         │
        │   ┌──────────────────────────────┐     │
        │   │  Docker Container            │     │
        │   │  sonatype/nexus-iq-server    │     │
        │   │  Ports: 8070, 8071           │     │
        │   └──────────────────────────────┘     │
        │   Debian 12 + Docker Engine            │
        └──┬────────────────────────────────┬────┘
           │                                │
  ┌────────▼─────────┐          ┌──────────▼────────┐
  │  Cloud Filestore │          │  Cloud SQL        │
  │  (NFS - 2.5TB)   │          │  PostgreSQL 17    │
  │  /sonatype-work  │          │  ENTERPRISE_PLUS  │
  │  /logs           │          │  8 vCPU           │
  └──────────────────┘          └───────────────────┘
```

### Components:

- **Compute**: GCE e2-standard-8 (8 vCPU, 32 GB RAM) running Docker
- **Container**: Official `sonatype/nexus-iq-server:latest` from Docker Hub
- **Database**: Cloud SQL PostgreSQL 17 (db-perf-optimized-N-8)
- **Storage**: Cloud Filestore BASIC_SSD (2.5 TB) mounted via NFS
- **Load Balancer**: Global HTTP(S) Load Balancer with health checks
- **Network**: Custom VPC with private subnets and Cloud NAT

## Key Differences from Native Installation

| Feature | Native (infra-gcp) | Docker (infra-gcp-docker) |
|---------|-------------------|---------------------------|
| Runtime | Binary installation | Docker container |
| Version management | Download specific version | Docker image tag |
| Updates | Manual re-download | Pull new image |
| Startup | systemd service | Docker container |
| Dependencies | Requires OpenJDK 17 | Bundled in image |

## Prerequisites

1. **GCP Account** with appropriate permissions
2. **Terraform** >= 1.0 installed
3. **gcloud CLI** configured
4. **GCP Project** with billing enabled
5. **APIs Enabled**:
   - Compute Engine API
   - Cloud SQL Admin API
   - Cloud Filestore API
   - Secret Manager API
   - Service Networking API

## Quick Start

### 1. Clone and Configure

```bash
cd infra-gcp-docker
cp terraform.tfvars.example terraform.tfvars
```

### 2. Edit `terraform.tfvars`

```hcl
# Required variables
gcp_project_id = "your-gcp-project-id"
gcp_region     = "us-central1"
db_password    = "YourSecurePassword123!"

# Docker configuration
iq_docker_image = "sonatype/nexus-iq-server:latest"  # or specific version tag
java_opts       = "-Xmx48g -Xms48g -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
```

### 3. Deploy

```bash
# Initialize Terraform
terraform init

# Plan deployment
./gcp-plan.sh

# Apply configuration
./gcp-apply.sh
```

### 4. Access Nexus IQ Server

After deployment completes:

```bash
# Get the load balancer IP
terraform output load_balancer_ip

# Access IQ Server
# http://<load-balancer-ip>
# Default credentials: admin/admin123
```

## Docker Container Details

### Image Information

- **Official Image**: `sonatype/nexus-iq-server:latest`
- **Docker Hub**: https://hub.docker.com/r/sonatype/nexus-iq-server
- **User**: root (0:0)
- **Ports**: 
  - 8070 (application)
  - 8071 (admin)

### Container Configuration

The Docker container is configured via:

1. **Environment Variables**:
   - `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USERNAME`, `DB_PASSWORD`
   - `JAVA_OPTS`
   - `NEXUS_SECURITY_RANDOMPASSWORD=false`

2. **Volume Mounts**:
   - `/sonatype-work` → Filestore NFS mount
   - `/var/log/nexus-iq-server` → Filestore NFS mount

3. **Entrypoint Script**:
   - Creates `config.yml` with database configuration
   - Substitutes environment variables
   - Starts IQ Server

### Startup Process

The startup process is automated via `scripts/startup.sh`:

1. **System Setup**:
   - GCE instance boots with Debian 12
   - Update packages and install Docker Engine (`docker.io`)
   - Install NFS client utilities
   - Enable and start Docker service

2. **Storage Mount**:
   - Create mount points: `/mnt/sonatype-work`
   - Mount Cloud Filestore via NFS (vers=3)
   - Create subdirectories: `sonatype-work/`, `logs/`
   - Add to `/etc/fstab` for persistence

3. **Docker Configuration**:
   - Create custom entrypoint script at `/opt/docker-entrypoint.sh`
   - Entrypoint generates `config.yml` with database credentials
   - Environment variable substitution for secure config

4. **Container Launch**:
   ```bash
   docker run -d \
     --name nexus-iq-server \
     --restart always \
     --user 0:0 \
     -p 8070:8070 -p 8071:8071 \
     -e DB_HOST=<cloud-sql-ip> \
     -e JAVA_OPTS="-Xmx24g -Xms24g" \
     -v /mnt/sonatype-work/sonatype-work:/sonatype-work \
     -v /mnt/sonatype-work/logs:/var/log/nexus-iq-server \
     sonatype/nexus-iq-server:latest
   ```

5. **Health Verification**:
   - Wait 10 seconds for container startup
   - Check container status with `docker ps`
   - View initial logs with `docker logs`

## Resource Configuration

### Compute Resources

```hcl
# Default configuration
gce_machine_type   = "e2-standard-8"  # 8 vCPU, 32 GB RAM
gce_boot_disk_size = 100              # GB
iq_docker_image    = "sonatype/nexus-iq-server:latest"
```

### Database Resources

```hcl
postgres_version   = "POSTGRES_17"
db_instance_tier   = "db-perf-optimized-N-8"  # 8 vCPU, optimized
db_edition         = "ENTERPRISE_PLUS"
db_disk_size       = 100                       # GB
```

### Storage Resources

```hcl
filestore_tier        = "BASIC_SSD"
filestore_capacity_gb = 1024  # 1 TB minimum
```

## Version Management

### Available Docker Image Tags

Check available versions at: https://hub.docker.com/r/sonatype/nexus-iq-server/tags

Common tags:
- `latest` - Most recent release
- `1.196.0` - Specific version
- `1.196` - Latest patch of minor version

### Updating to a New Version

**Method 1: Terraform (Recommended)**

1. Update `terraform.tfvars`:
   ```hcl
   iq_docker_image = "sonatype/nexus-iq-server:1.197.0"
   ```

2. Apply changes:
   ```bash
   terraform apply
   ```
   This will recreate the GCE instance with the new image.

**Method 2: Rolling Update (Zero Downtime)**

```bash
# SSH to instance
gcloud compute ssh nexus-iq-server --zone us-central1-a

# Pull new image
docker pull sonatype/nexus-iq-server:1.197.0

# Stop and remove old container
docker stop nexus-iq-server
docker rm nexus-iq-server

# Start with new image
docker run -d \
  --name nexus-iq-server \
  --restart always \
  --user 0:0 \
  -p 8070:8070 -p 8071:8071 \
  -e DB_HOST="<db-ip>" -e DB_PORT="5432" \
  -e DB_NAME="nexusiq" -e DB_USERNAME="nexusiq" \
  -e DB_PASSWORD="<password>" \
  -e JAVA_OPTS="-Xmx24g -Xms24g -Djava.util.prefs.userRoot=/sonatype-work/javaprefs" \
  -e NEXUS_SECURITY_RANDOMPASSWORD="false" \
  -v /mnt/sonatype-work/sonatype-work:/sonatype-work \
  -v /mnt/sonatype-work/logs:/var/log/nexus-iq-server \
  -v /opt/docker-entrypoint.sh:/docker-entrypoint.sh \
  --entrypoint /docker-entrypoint.sh \
  sonatype/nexus-iq-server:1.197.0
```

**Method 3: Quick Restart**

```bash
gcloud compute ssh nexus-iq-server --zone us-central1-a
sudo reboot
```
The startup script will automatically pull and run the configured image.

## Monitoring and Logs

### View Docker Container Logs

```bash
# SSH to instance (use --tunnel-through-iap if no external IP)
gcloud compute ssh nexus-iq-server --zone us-central1-a --tunnel-through-iap

# View recent logs
docker logs nexus-iq-server

# Follow logs in real-time
docker logs -f nexus-iq-server

# View last 100 lines
docker logs --tail 100 nexus-iq-server

# Container status and health
docker ps
docker inspect nexus-iq-server | grep -A 5 Health
```

### View Startup Logs

```bash
# View serial console output (startup script logs)
gcloud compute instances get-serial-port-output nexus-iq-server \
  --zone us-central1-a | grep -E "(Docker|nexus-iq)"

# View systemd startup logs
sudo journalctl -u google-startup-scripts
```

### Cloud Logging

```bash
# View logs in GCP Console
gcloud logging read "resource.type=gce_instance AND \
  resource.labels.instance_id=nexus-iq-server" \
  --limit 50 --format json
```

### View Persistent Logs

Logs are stored on Filestore:

```bash
# On GCE instance
ls -la /mnt/sonatype-work/logs/
```

## Troubleshooting

### Container Not Starting

```bash
# SSH to instance
gcloud compute ssh nexus-iq-server --zone us-central1-a --tunnel-through-iap

# Check container status (look for exit codes)
docker ps -a

# View container logs for errors
docker logs nexus-iq-server 2>&1 | tail -50

# Inspect container configuration
docker inspect nexus-iq-server

# Check if Docker service is running
sudo systemctl status docker

# Check startup script execution
sudo journalctl -u google-startup-scripts -n 100

# Verify Docker image was pulled
docker images | grep nexus-iq-server

# Manual container restart
docker restart nexus-iq-server
```

### Database Connection Issues

```bash
# Check if IQ Server can reach the database
docker exec nexus-iq-server cat /etc/nexus-iq-server/config.yml | grep -A 5 database

# Test database connectivity from container
docker exec -it nexus-iq-server /bin/bash
# Inside container:
apt-get update && apt-get install -y postgresql-client telnet
psql -h <db-private-ip> -U nexusiq -d nexusiq

# Test from host
telnet <db-private-ip> 5432

# Check database instance status
gcloud sql instances describe $(terraform output -raw database_instance_name)

# View database logs
gcloud sql operations list --instance=$(terraform output -raw database_instance_name)

# Check database credentials in Secret Manager
gcloud secrets versions access latest --secret=nexus-iq-db-credentials
```

### Filestore Mount Issues

```bash
# Check NFS mount
mount | grep filestore

# Test NFS connectivity
showmount -e <filestore-ip>

# Remount if needed
sudo mount -t nfs -o vers=3 <filestore-ip>:/nexus_iq_data /mnt/sonatype-work
```

## Cleanup

To destroy all resources:

```bash
./destroy.sh
```

**Warning**: This will delete all resources including the database. Ensure you have backups if needed.

## Cost Considerations

Estimated monthly costs (us-central1) based on current configuration:

| Resource | Configuration | Estimated Cost |
|----------|--------------|----------------|
| GCE Instance | e2-standard-8 (8 vCPU, 32GB) | ~$240/month |
| Cloud SQL | db-perf-optimized-N-8, 100GB | ~$350/month |
| Cloud Filestore | BASIC_SSD 2.5TB | ~$500/month |
| Load Balancer | Global HTTP(S) LB | ~$20/month |
| Network Egress | Estimated traffic | ~$50/month |
| **Total** | | **~$1,160/month** |

**Cost Optimization Tips:**
- Use smaller Filestore (minimum 1TB): ~$200/month
- Reduce GCE to e2-standard-4: ~$120/month
- Use ZONAL availability instead of REGIONAL for DB: ~$175/month
- Schedule instance stop during non-business hours: 50% savings on compute

**Note**: Actual costs may vary based on usage, region, and commitment discounts.

## Security Best Practices

1. **Change default passwords** in `terraform.tfvars`
2. **Restrict SSH access** via `allowed_ssh_cidrs`
3. **Enable SSL** with `enable_ssl = true` and configure `domain_name`
4. **Use Secret Manager** for sensitive data (already configured)
5. **Enable database encryption** (configured by default)
6. **Regular backups** (automated daily backups enabled)

## Outputs

After deployment:

```bash
terraform output
```

Key outputs:
- `load_balancer_ip` - Public IP for accessing IQ Server
- `nexus_iq_url` - Full URL to access IQ Server
- `database_instance_name` - Cloud SQL instance name
- `filestore_ip_address` - NFS mount IP

## Support

For issues with:
- **Terraform configuration**: Check this README and Terraform docs
- **GCP resources**: Consult GCP documentation
- **Nexus IQ Server**: Visit https://help.sonatype.com/
- **Docker image**: Check https://hub.docker.com/r/sonatype/nexus-iq-server

## License

This Terraform configuration is provided as-is for deploying Nexus IQ Server. Nexus IQ Server requires a valid license from Sonatype.
