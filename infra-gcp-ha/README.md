# Nexus IQ Server GCP Infrastructure (High Availability)

This directory contains Terraform configuration for deploying Nexus IQ Server on GCP using Docker containers on Compute Engine in a **High Availability configuration** as part of a **Reference Architecture for Enterprise Cloud Deployments**.

## Architecture Overview

This infrastructure deploys a complete, production-ready Nexus IQ Server High Availability environment including:

- **Managed Instance Group (MIG)** - Multiple Docker containerized Nexus IQ Server instances (2-6 instances)
- **Global HTTP(S) Load Balancer** - Load balancer with health checks and auto scaling
- **Cloud SQL PostgreSQL Regional** - Managed database with Multi-AZ failover and optional read replica
- **Cloud Filestore** - Shared NFS storage for clustering support and unique work directories
- **VPC & Networking** - Complete network infrastructure with public/private/database subnets
- **Cloud Armor** - DDoS protection and web application firewall
- **Service Accounts** - Least-privilege IAM roles following GCP best practices
- **Cloud Logging & Monitoring** - Comprehensive logging with log-based metrics and alerts
- **Secret Manager** - Secure database credential storage
- **Auto Scaling** - Dynamic scaling based on CPU utilization
- **Cloud Ops Agent** - Monitoring and logging agent for application logs

```
Internet
    ↓
Global HTTP(S) Load Balancer (Public)
    ↓
Managed Instance Group (2-6 Docker instances, Multi-Zone) ←→ Cloud Filestore (Shared NFS Storage)
    ↓
Cloud SQL PostgreSQL Regional (Database Subnets, Multi-AZ + Read Replica)
```

## Prerequisites

### Required Tools
- **Terraform** >= 1.0
- **Google Cloud SDK** >= 400.0
- **jq** and **curl**

### GCP Account Requirements
- GCP project with billing enabled
- Authenticated gcloud CLI
- Sufficient IAM permissions to create resources

## GCP Configuration Setup

### 1. GCloud CLI Configuration

Authenticate with Google Cloud:

```bash
# Login to Google Cloud
gcloud auth login

# Set your project
gcloud config set project your-project-id

# Configure application default credentials for Terraform
gcloud auth application-default login
```

### 2. Verify Configuration

Test your GCP configuration:
```bash
gcloud config list
gcloud projects list
```

## Quick Start

1. **Navigate to the HA infrastructure directory**:
   ```bash
   cd /path/to/sca-example-terraform/infra-gcp-ha
   ```

2. **Review and customize variables**:
   ```bash
   # Edit terraform.tfvars with your specific values
   vim terraform.tfvars
   ```

3. **Plan the deployment**:
   ```bash
   ./gcp-ha-plan.sh
   ```

4. **Deploy the infrastructure**:
   ```bash
   ./gcp-ha-apply.sh
   ```

5. **Access your Nexus IQ Server**:
   - Get the application URL: `terraform output load_balancer_url`
   - Wait 10-15 minutes for all services to be ready
   - Default credentials: `admin` / `admin123` (change immediately)

## Configuration

### 1. Review Variables in terraform.tfvars

Edit `terraform.tfvars` to customize your deployment:

```hcl
# General Configuration
gcp_project_id = "your-gcp-project-id"
gcp_region     = "us-central1"

# Network Configuration
vpc_cidr               = "10.200.0.0/16"
public_subnet_cidr     = "10.200.1.0/24"
private_subnet_cidrs   = ["10.200.10.0/24", "10.200.11.0/24", "10.200.12.0/24"]
db_subnet_cidr         = "10.200.20.0/24"

# Compute Engine Configuration (Sonatype HA benchmark specs)
instance_machine_type = "n2-standard-8"   # 8 vCPU, 32 GB RAM per instance
iq_min_instances      = 2                 # Minimum instances for HA
iq_max_instances      = 6                 # Maximum auto scaling capacity
iq_target_instances   = 2                 # Initial instance count

# Auto Scaling Configuration
cpu_target_utilization     = 0.7          # 70% CPU utilization target
scale_in_cooldown_seconds  = 300          # 5 minutes
scale_out_cooldown_seconds = 60           # 1 minute

# Database Configuration (Sonatype HA benchmark specs)
db_name                      = "nexusiq"
db_username                  = "nexusiq"
db_password                  = "YourSecurePassword123!"  # Change this!
postgres_version            = "POSTGRES_15"
db_instance_tier            = "db-custom-8-30720"       # 8 vCPU, 30GB RAM
db_availability_type        = "REGIONAL"                 # REGIONAL for HA
db_max_connections          = "400"
enable_read_replica         = true

# Cloud Filestore Configuration
filestore_zone        = "us-central1-a"                  # Same region as instances
filestore_tier        = "BASIC_SSD"                      # Higher performance
filestore_capacity_gb = 2560                             # Minimum for BASIC_SSD (2.5TB)

# Java Configuration (Sonatype HA benchmark: -Xms24g -Xmx24g for 32GB RAM)
java_opts = "-Xms24g -Xmx24g -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"

# SSL/TLS Configuration
enable_ssl  = false                                      # Set true for production
domain_name = ""                                         # e.g., "nexus-iq.example.com"
```

### 2. Important HA Settings

- **`iq_min_instances = 2`** - Minimum instances for HA (2-6 supported)
- **`iq_max_instances = 6`** - Maximum auto scaling capacity
- **`cpu_target_utilization = 0.7`** - CPU threshold for auto scaling
- **`db_availability_type = "REGIONAL"`** - Multi-AZ database with automatic failover
- **`enable_read_replica = true`** - Database read replica for load distribution
- **`db_password`** - Use a strong, unique password
- **Resource Names** - All GCP resources are prefixed with "ref-arch-iq-ha" (e.g., "ref-arch-iq-ha-mig")

## Security Features

- **VPC Isolation**: Application runs in private subnets across multiple zones
- **Database Security**: Cloud SQL in isolated subnets with Private IP and Multi-AZ deployment
- **Secrets Management**: Database credentials stored in Google Secret Manager
- **Encryption**:
  - Cloud Filestore encrypted at rest and in transit
  - Cloud SQL encrypted at rest with customer-managed or Google-managed keys
  - Load balancer with optional SSL/TLS termination
- **Firewall Rules**: Least-privilege network access with Cloud Armor protection
- **Work Directory Isolation**: Unique work directories per instance prevent clustering conflicts

## High Availability Features

- **Multi-Zone Deployment**: Instances distributed across multiple availability zones
- **Auto Scaling**: MIG scales from 2-6 instances based on CPU utilization
- **Cloud SQL Regional**: Multi-AZ database deployment with automatic failover
- **Load Balancing**: Global load balancer distributes traffic across healthy instances
- **Rolling Updates**: Zero-downtime updates with controlled rollout
- **Cloud Filestore Clustering**: Shared NFS storage with unique work directories and cluster coordination
- **Health Checks**: Automatic instance replacement on failure

## Docker-Based Deployment

This deployment uses Docker containers on Compute Engine instances:

- **Container Image**: `sonatype/nexus-iq-server:latest`
- **Container Runtime**: Docker on Container-Optimized OS is NOT used, instead Ubuntu 22.04 LTS is used
- **Custom Entrypoint**: Matches AWS/Azure pattern with explicit binary execution
- **Work Directory Management**: Each container gets unique `/sonatype-work/clm-server-${HOSTNAME}` directory
- **Cluster Coordination**: Shared `/sonatype-work/clm-cluster` directory on Cloud Filestore
- **Configuration**: Dynamic `config.yml` generation per instance with proper database configuration

## Custom Clustering Solution

This deployment solves critical IQ Server clustering challenges:

- **Work Directory Conflicts**: Each instance gets unique `/sonatype-work/clm-server-${HOSTNAME}` directory on NFS
- **Database Sharing**: Custom config.yml generation ensures all instances connect to shared Cloud SQL cluster
- **Cluster Coordination**: Shared `/sonatype-work/clm-cluster` directory on Cloud Filestore for coordination
- **Dynamic Configuration**: config.yml generated per instance with proper database configuration
- **Hostname Stability**: Managed Instance Group provides stable instance names for clustering

## Monitoring and Logging

This deployment includes **production-grade logging** with Cloud Operations Suite:

### Cloud Logging Integration
- **Cloud Ops Agent**: Collects logs from Docker containers and file system
- **5 Separate Log Types**: Application, request, audit, policy-violation, and container stderr
- **Centralized Log Bucket**: All logs stored in dedicated Cloud Logging bucket
- **Log-Based Metrics**: Automatic error and warning counters
- **Structured Logging**: Logs include instance identifiers and timestamps

### Cloud Logging Components
- **Log Bucket**: `nexus-iq-ha-logs-{suffix}` with configurable retention
- **Log Sink**: Captures Docker container logs from all instances
- **Log View**: Filtered view for easy log querying
- **Log-Based Metrics**:
  - `nexus-iq-ha-error-count` - Count of ERROR level logs
  - `nexus-iq-ha-warning-count` - Count of WARNING level logs

### Alert Policies
- **Container Restart**: Alerts when Docker containers restart
- **NFS Mount Failure**: Alerts on Cloud Filestore mount failures
- **High Error Rate**: Alerts on elevated error log counts (optional, enable after deployment)

### Viewing Logs

**Cloud Logging Console**:
Navigate to Cloud Logging in GCP Console and filter by:
- Resource type: `gce_instance`
- Instance name pattern: `nexus-iq-ha-*`

**Command Line**:
```bash
# View all IQ Server logs
gcloud logging read 'resource.type="gce_instance" AND labels."compute.googleapis.com/resource_name"=~"nexus-iq-ha-.*"' \
  --limit=50 --format=json

# View application logs from Filestore
gcloud compute ssh nexus-iq-ha-XXXX --zone=us-central1-a \
  --command="sudo tail -f /mnt/filestore/clm-server-*/logs/clm-server.log"

# View Docker container logs
gcloud compute ssh nexus-iq-ha-XXXX --zone=us-central1-a \
  --command="sudo docker logs nexus-iq-server --tail 50"
```

### Additional Monitoring
- **Cloud Monitoring**: Automatic dashboards for MIG, Cloud SQL, and Load Balancer
- **Cloud SQL Insights**: Query performance monitoring
- **Load Balancer Metrics**: Request rate, latency, and error rates
- **Auto Scaling Metrics**: CPU utilization and instance count tracking

## Persistent Storage

- **Cloud Filestore**: Shared NFS storage (2.5TB minimum for BASIC_SSD tier)
- **Cloud SQL**: PostgreSQL database with continuous backups
- **Auto-scaling Storage**: Cloud SQL storage scales automatically
- **Backup Configuration**: 
  - Database backups retained for 7 days
  - Transaction logs for point-in-time recovery
  - Optional custom backup schedules

## Cost Optimization

- **Compute Engine**: Pay-per-use with auto scaling (scales down to save costs)
- **Cloud SQL**: Right-sized instance with storage auto-scaling
- **Sustained Use Discounts**: Automatic discounts for long-running instances
- **Committed Use Discounts**: Optional for predictable workloads
- **Resource Tagging**: All resources tagged for cost allocation
- **Auto Scaling**: Dynamically adjusts capacity based on demand

**Estimated Monthly Costs** (us-central1, 24/7 operation):
- Compute Engine (2x n2-standard-8): ~$500-600
- Cloud SQL Regional (db-custom-8-30720): ~$1,200
- Cloud SQL Read Replica: ~$600
- Cloud Filestore (2.5TB BASIC_SSD): ~$640
- Load Balancer: ~$18-25
- **Total**: ~$2,960-3,065/month

*Note: Costs vary by region and usage. Use [GCP Pricing Calculator](https://cloud.google.com/products/calculator) for accurate estimates.*

## Networking

### Subnets
- **Public Subnet**: Load balancer and Cloud NAT
- **Private Subnets**: Compute Engine instances across multiple zones (no direct internet)
- **Database Subnet**: Cloud SQL instances (Private IP, no internet access)

### Firewall Rules
- **Load Balancer**: Allows HTTP (80) and HTTPS (443) from internet
- **Health Checks**: Allows health check traffic from Google ranges
- **Instances**: Allows traffic from load balancer on port 8070
- **NFS**: Allows NFS traffic (2049) to Cloud Filestore
- **Cloud SQL**: Allows PostgreSQL (5432) from instances only

### Cloud Armor
- **DDoS Protection**: Rate limiting and geographic restrictions
- **WAF Rules**: OWASP ModSecurity Core Rule Set support
- **Custom Rules**: Configurable IP allow/deny lists

## Automated Deployment Scripts

This infrastructure includes convenient scripts for deployment:

### Available Scripts

- **`./gcp-ha-plan.sh`** - Preview infrastructure changes with validation
- **`./gcp-ha-apply.sh`** - Deploy infrastructure with automated planning
- **`./gcp-ha-destroy.sh`** - Destroy infrastructure with automatic cleanup

### How the Scripts Work

1. **Automated planning** - Creates timestamped plan files
2. **Validation** - Checks prerequisites and configuration
3. **Progress tracking** - Real-time deployment progress
4. **Health checks** - Post-deployment validation
5. **Backup management** - State backups before changes

### Manual Terraform Commands (Alternative)

If you prefer to run Terraform commands manually:

```bash
# Initialize Terraform
terraform init

# Plan deployment
terraform plan -out=tfplan

# Apply configuration
terraform apply tfplan

# Show outputs
terraform output

# Destroy infrastructure
terraform destroy
```

## Accessing the Application

### 1. Get Deployment Information

```bash
terraform output
```

Example output:
```
load_balancer_url = "http://34.8.109.34"
load_balancer_ip  = "34.8.109.34"
database_connection_name = "project-id:us-central1:nexus-iq-ha-db-xxxxxxxx"
instance_group_manager_name = "ref-arch-iq-ha-mig"
```

### 2. Access the Application

1. **Wait for services to be ready** (10-15 minutes after deployment)
2. **Open the application URL** from terraform output
3. **Default credentials**: `admin` / `admin123`
4. **Complete setup wizard** on first access

### 3. Monitor Deployment Status

Check MIG status:
```bash
gcloud compute instance-groups managed list-instances ref-arch-iq-ha-mig \
  --region=us-central1 \
  --project=your-project-id
```

Check backend health:
```bash
gcloud compute backend-services get-health ref-arch-iq-ha-backend \
  --global \
  --project=your-project-id
```

View application logs:
```bash
gcloud logging read \
  'resource.type="gce_instance" AND labels."compute.googleapis.com/resource_name"=~"nexus-iq-ha-.*"' \
  --limit=50 \
  --project=your-project-id
```

## GCP Console Access

Monitor your HA infrastructure in the GCP Console:

- **Compute Engine MIG**: Compute Engine → Instance groups → `ref-arch-iq-ha-mig`
- **Instances**: Compute Engine → VM instances (filter: `nexus-iq-ha-*`)
- **Database**: SQL → Instances → `nexus-iq-ha-db-*`
- **Load Balancer**: Network Services → Load balancing → `ref-arch-iq-ha-lb`
- **Logs**: Logging → Logs Explorer (filter by instance name)
- **Monitoring**: Monitoring → Dashboards
- **VPC**: VPC Network → VPC networks → `ref-arch-iq-ha-vpc`
- **Filestore**: Filestore → Instances → `nexus-iq-ha-filestore-*`

## File Structure

```
infra-gcp-ha/
├── main.tf                  # Main Terraform configuration and required providers
├── network.tf               # VPC, subnets, Cloud NAT, and networking
├── compute.tf               # Managed Instance Group, instance template, auto scaling
├── database.tf              # Cloud SQL PostgreSQL regional cluster and read replica
├── load_balancer.tf         # Global HTTP(S) Load Balancer and SSL configuration
├── storage.tf               # Cloud Filestore NFS shared storage
├── security.tf              # Firewall rules, Cloud Armor, IAM roles
├── logging.tf               # Cloud Logging, log-based metrics, and alert policies
├── variables.tf             # Input variable definitions
├── outputs.tf               # Output value definitions
├── terraform.tfvars         # Infrastructure configuration (customize this)
├── scripts/
│   └── startup.sh           # Docker-based IQ Server installation script
├── gcp-ha-apply.sh          # Deployment script with validation
├── gcp-ha-plan.sh           # Planning script with validation
├── gcp-ha-destroy.sh        # Destruction script with cleanup
└── README.md                # This file
```

## Troubleshooting

### Common Issues

1. **Instances Not Starting**
   ```bash
   # Check startup script logs
   gcloud compute instances get-serial-port-output nexus-iq-ha-XXXX \
     --zone=us-central1-a --port=1
   
   # Check Docker container logs
   gcloud compute ssh nexus-iq-ha-XXXX --zone=us-central1-a \
     --command="sudo docker logs nexus-iq-server --tail 100"
   ```
   - **NFS mount failures**: Check Cloud Filestore status and network connectivity
   - **Docker issues**: Verify Docker daemon is running
   - **Database connection**: Check Cloud SQL status and Secret Manager credentials

2. **Application Not Accessible**
   - Wait 10-15 minutes for Docker containers to fully start
   - Check load balancer backend health in GCP Console
   - Verify firewall rules allow traffic on port 8070
   - Ensure at least 2 healthy backends are registered

3. **Database Connection Issues**
   - Verify Cloud SQL status in GCP Console
   - Check database credentials in Secret Manager
   - Ensure instances can reach Cloud SQL private IP
   - Verify config.yml includes correct database configuration

4. **Auto Scaling Not Working**
   - Ensure IQ Server cluster directory is set and shared among nodes
   - Ensure IQ Server workspace directory is unique per node (not shared)
   - Ensure IQ Server clustering license compliance

   ```bash
   # Check auto scaler status
   gcloud compute instance-groups managed describe ref-arch-iq-ha-mig \
     --region=us-central1

   # Check auto scaler target CPU
   gcloud compute region-autoscalers describe ref-arch-iq-ha-autoscaler \
     --region=us-central1
   ```

5. **Clustering Issues**
   ```bash
   # Verify unique work directories
   gcloud logging read \
     'resource.type="gce_instance" AND textPayload=~"Creating work directories"' \
     --limit=10

   # Check for work directory conflicts (should be empty)
   gcloud logging read \
     'resource.type="gce_instance" AND textPayload=~"Permission denied.*lock"' \
     --limit=10

   # Verify PostgreSQL connections
   gcloud logging read \
     'resource.type="gce_instance" AND textPayload=~"postgresql"' \
     --limit=10
   ```

6. **Cloud Filestore Mount Issues**
   ```bash
   # Check Filestore status
   gcloud filestore instances describe nexus-iq-ha-filestore-XXXXXX \
     --location=us-central1-a

   # Test NFS connectivity from instance
   gcloud compute ssh nexus-iq-ha-XXXX --zone=us-central1-a \
     --command="showmount -e FILESTORE_IP"
   ```

7. **Load Balancer Errors**
   ```bash
   # Check backend service health
   gcloud compute backend-services get-health ref-arch-iq-ha-backend --global

   # View load balancer logs
   gcloud logging read \
     'resource.type="http_load_balancer"' \
     --limit=50
   ```

### Resource Limits

- **MIG**: Scales from 2-6 instances based on CPU demand
- **Cloud SQL**: Uses db-custom-8-30720 (8 vCPU, 30GB RAM)
- **Cloud Filestore**: 2.5TB minimum for BASIC_SSD tier
- **Concurrent Connections**: Database configured for 400 max connections

## Cleanup

### Complete Infrastructure Removal

Remove all GCP resources:
```bash
./gcp-ha-destroy.sh
```

This will:
- Prompt for confirmation (type 'YES')
- Create backup of terraform state
- Destroy all resources in stages
- Handle database user cleanup automatically
- Remove Cloud Filestore and Cloud SQL

### Partial Cleanup

Stop only the MIG (keeps data):
```bash
terraform destroy -target=google_compute_region_instance_group_manager.iq_mig
```

**Warning**: Complete cleanup will permanently delete all data including the Cloud SQL database. Ensure you have backups if needed.

## Security Features

- **Network Isolation**: Private subnets for instances and Cloud SQL
- **Encryption**: Cloud SQL and Filestore encryption at rest and in transit
- **Secrets Management**: Database credentials stored in Secret Manager
- **IAM**: Least-privilege service accounts with specific resource access
- **Firewall Rules**: Minimal required network access with Cloud Armor
- **VPC**: Isolated network environment with Multi-Zone deployment
- **Private IP**: Cloud SQL accessible only via private IP

## Production Considerations

For production HA deployments, consider:

1. **SSL/TLS Certificate**: Enable SSL and configure managed certificates
2. **Domain Name**: Configure Cloud DNS for custom domain
3. **Backup Strategy**: Review Cloud SQL and Filestore backup settings
4. **Monitoring**: Configure Cloud Monitoring alert notification channels
5. **High Availability Tier**: Use ENTERPRISE Filestore tier for mission-critical workloads
6. **Resource Sizing**: Adjust instance types and auto scaling based on usage
7. **Network Security**: Restrict load balancer access with Cloud Armor rules
8. **Database Protection**: Set `db_deletion_protection = true`
9. **Disaster Recovery**: Consider multi-region deployment strategy
10. **License Management**: Ensure IQ Server clustering license compliance

## Reference Architecture

This HA infrastructure serves as a **Reference Architecture for Enterprise Cloud Deployments** demonstrating:

- **High availability patterns**: Multi-zone deployment, auto scaling, automatic failover
- **Cloud-native clustering**: Custom IQ Server clustering with shared NFS storage
- **Security best practices**: Network isolation, encryption, secrets management
- **Operational excellence**: Centralized logging, monitoring, automation
- **Cost optimization**: Auto scaling, right-sized resources, efficient resource usage
- **Reliability**: Multi-zone deployment, automated backups, health checks

## Support

For issues with this HA infrastructure:
1. Check the troubleshooting section above
2. Review Cloud Logging for error messages
3. Verify GCP permissions and quotas
4. Check MIG and auto scaler configuration
5. Consult the [Nexus IQ Server documentation](https://help.sonatype.com/iqserver)
6. Review [Sonatype Reference Architectures](https://sonatype.atlassian.net/wiki/spaces/~557058a12ee8e6d68d43169ecf1b324b233b2a/pages/1632206850)

For Terraform-specific issues:
- Review the [Terraform Google Provider documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- Check [GCP service documentation](https://cloud.google.com/docs) for specific services
- Verify [Compute Engine Auto Scaling](https://cloud.google.com/compute/docs/autoscaler) configuration
