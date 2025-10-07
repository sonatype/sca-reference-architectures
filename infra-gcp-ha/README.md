# Nexus IQ Server GCP HA Reference Architecture

This directory contains Terraform configurations for deploying Nexus IQ Server in a High Availability (HA) configuration on Google Cloud Platform (GCP) using native cloud services.

## Overview

This HA deployment provides:
- **Multi-zone resilience** with 2-6 Compute Engine instances across availability zones
- **Auto-scaling** based on CPU, memory, and load balancer utilization
- **Regional Cloud SQL** with automatic failover and optional read replicas
- **Global Load Balancer** with SSL/TLS termination and health checks
- **Shared persistent storage** with regional persistent disks
- **Comprehensive monitoring** with Cloud Operations Suite
- **Enterprise security** with VPC, firewall rules, and Cloud Armor

## Architecture

The HA deployment uses Compute Engine Managed Instance Groups (MIG) instead of Cloud Run to provide true equivalency with the AWS ECS HA architecture, ensuring stable hostnames and persistent clustering coordination.

### Key Components

- **Compute Engine MIG**: 2-6 Container-Optimized OS instances running Docker containers
- **Cloud SQL Regional**: PostgreSQL with automatic failover and optional read replicas  
- **Regional Persistent Disk**: Multi-zone shared storage for `/sonatype-work` clustering
- **Global Load Balancer**: HTTP(S) load balancing with health checks and Cloud Armor protection
- **VPC Networking**: Private subnets, Cloud NAT, and firewall rules
- **Monitoring**: Cloud Operations Suite with dashboards and alerting

### HA Architecture Highlights

- **True Multi-Zone**: Regional persistent disk with replicas across availability zones
- **Clustering Support**: Each instance gets unique work directory (`/sonatype-work/clm-server-{hostname}`) with shared cluster coordination (`/sonatype-work/clm-cluster`)
- **AWS Equivalency**: Mirrors proven AWS ECS HA pattern with stable hostnames and persistent storage

## Prerequisites

Before deploying, ensure you have:

1. **Google Cloud SDK** installed and configured
   ```bash
   gcloud --version
   gcloud auth login
   gcloud auth application-default login
   ```

2. **Terraform** (>= 1.0) installed
   ```bash
   terraform --version
   ```

3. **GCP Project** with billing enabled
   ```bash
   gcloud projects create your-project-id
   gcloud config set project your-project-id
   ```

4. **Required APIs** will be enabled automatically by Terraform:
   - Compute Engine API
   - Cloud SQL Admin API
   - Cloud Logging API
   - Cloud Monitoring API
   - Secret Manager API

## Quick Start

### 1. Clone and Configure

```bash
# Navigate to the GCP HA directory
cd infra-gcp-ha

# Copy the example configuration
cp terraform.tfvars.example terraform.tfvars

# Edit the configuration
nano terraform.tfvars
```

### 2. Required Configuration

Edit `terraform.tfvars` and set at minimum:

```hcl
# Required
gcp_project_id = "your-gcp-project-id"
db_password    = "your-secure-database-password"

# Recommended
gcp_region     = "us-central1"
domain_name    = "nexus-iq.yourdomain.com"  # Optional
```

### 3. Deploy

```bash
# Plan the deployment
./gcp-ha-plan.sh

# Review the plan and apply
./gcp-ha-apply.sh
```

### 4. Access

After deployment (5-10 minutes for full startup):

1. **Application URL**: Check the `load_balancer_url` output
2. **Default Credentials**: `admin` / `admin123` (change immediately)
3. **Health Check**: Instances may take 5-10 minutes to be fully ready

## Configuration

### Environment Sizing

#### Development
```hcl
iq_min_instances    = 1
iq_max_instances    = 2
iq_target_instances = 1
db_instance_tier    = "db-custom-1-3840"
db_availability_type = "ZONAL"
enable_read_replica  = false
```

#### Production
```hcl
iq_min_instances    = 3
iq_max_instances    = 10
iq_target_instances = 3
db_instance_tier    = "db-custom-4-15360"
db_availability_type = "REGIONAL"
enable_read_replica  = true
```

### Auto Scaling

Configure auto-scaling behavior:

```hcl
cpu_target_utilization     = 0.7   # 70% CPU target
scale_in_cooldown_seconds  = 300   # 5 minutes
scale_out_cooldown_seconds = 60    # 1 minute
```

### Security

Network security is configured with:
- Private subnets for compute instances
- Cloud NAT for outbound internet access
- Firewall rules for load balancer and health checks
- Cloud Armor for DDoS protection
- VPC isolation for database access

## Management

### Scaling

```bash
# Manual scaling
gcloud compute instance-groups managed resize nexus-iq-ha-mig \
  --size=4 --region=us-central1

# Check current size
gcloud compute instance-groups managed describe nexus-iq-ha-mig \
  --region=us-central1 --format="value(targetSize)"
```

### Monitoring

```bash
# View instance group status
gcloud compute instance-groups managed list-instances nexus-iq-ha-mig \
  --region=us-central1

# Check logs
gcloud logging read 'resource.type="gce_instance" AND resource.labels.instance_name=~"nexus-iq-ha-.*"' \
  --limit=50 --format=json
```

### Database Operations

```bash
# Connect to database (requires Cloud SQL Proxy)
gcloud sql connect nexus-iq-ha-db-XXXXXXXX --user=nexusiq

# Create manual backup
gcloud sql backups create --instance=nexus-iq-ha-db-XXXXXXXX
```

## Troubleshooting

### Common Issues

1. **Instances not starting**
   ```bash
   # Check instance logs
   gcloud compute instances get-serial-port-output INSTANCE_NAME \
     --zone=us-central1-a
   ```

2. **Load balancer health check failures**
   ```bash
   # Check backend service health
   gcloud compute backend-services get-health BACKEND_SERVICE_NAME \
     --global
   ```

3. **Database connection issues**
   ```bash
   # Test database connectivity from instance
   gcloud compute ssh INSTANCE_NAME --zone=us-central1-a \
     --command="curl -v telnet://DB_PRIVATE_IP:5432"
   ```

### Health Checks

The deployment includes multiple health checks:
- **Instance health check**: HTTP GET to `:8070/`
- **Load balancer health check**: HTTP GET to `:8070/`
- **Auto healing**: Automatic instance replacement on failure
- **Uptime monitoring**: External monitoring with alerting

## Cost Optimization

### Cost Factors

- **Compute Engine instances**: Primary cost driver
- **Cloud SQL**: Regional instances cost more than zonal
- **Load balancer**: Global load balancer has fixed costs
- **Persistent disk**: Regional disks cost more than zonal
- **Data transfer**: Minimal for typical usage

### Optimization Tips

1. **Right-size instances**: Start with `e2-standard-2` and monitor
2. **Use preemptible instances**: For non-production environments
3. **Schedule scaling**: Scale down during off-hours
4. **Zonal vs Regional**: Use ZONAL database for non-production

## Backup and Recovery

### Automated Backups

- **Database**: Continuous backup with 7-day retention
- **Persistent disk**: Snapshot schedules (configure separately)
- **Configuration**: Terraform state backup during deployment

### Manual Backup

```bash
# Database backup
gcloud sql backups create --instance=INSTANCE_NAME

# Disk snapshot
gcloud compute disks snapshot DISK_NAME --zone=ZONE
```

### Recovery

1. **Database**: Point-in-time recovery available
2. **Application data**: Restore from disk snapshots
3. **Infrastructure**: Redeploy from Terraform

## Cleanup

To destroy the infrastructure:

```bash
# Interactive destroy
./gcp-ha-destroy.sh

# Auto-approve destroy
./gcp-ha-destroy.sh --auto-approve

# Force destroy (disables deletion protection)
./gcp-ha-destroy.sh --force
```

## Support

### Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md) - Detailed architecture documentation
- [Terraform GCP Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Nexus IQ Server Documentation](https://help.sonatype.com/iqserver)

### Monitoring

- **Dashboards**: Cloud Monitoring dashboard created automatically
- **Alerts**: Configure notification channels for production use
- **Logs**: Centralized logging in Cloud Logging

### Security

- **Secrets**: Database credentials stored in Secret Manager
- **Network**: Private subnets with firewall rules
- **SSL/TLS**: Managed certificates for custom domains
- **IAM**: Least-privilege service accounts

## Migration

### From Single Instance

1. **Backup**: Create full backup of single instance
2. **Deploy HA**: Deploy this HA architecture
3. **Migrate data**: Restore data to HA environment
4. **Test**: Verify functionality
5. **Cutover**: Update DNS to point to HA load balancer

### From AWS HA

This architecture provides equivalent functionality to the AWS HA deployment with native GCP services.

## Contributing

When modifying this infrastructure:

1. **Test changes** in a development environment first
2. **Update documentation** for any architectural changes
3. **Follow naming conventions** with `ref-arch-iq-ha-` prefix
4. **Validate** with `terraform validate` and `terraform plan`

---

For detailed architecture information, see [ARCHITECTURE.md](ARCHITECTURE.md).