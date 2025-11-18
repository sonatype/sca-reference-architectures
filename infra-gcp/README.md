# Sonatype IQ Reference Architecture - GCP with Docker (Single Instance)

This directory contains Terraform configuration for deploying a **single-instance** Sonatype IQ Server on Google Cloud Platform using GCE with Docker containers.

## Deployment Guide

### Step 1: Prerequisites

#### Required Tools
Install these tools on your local machine:

| Tool | Version | Installation | Purpose |
|------|---------|--------------|---------|
| **Terraform** | >= 1.0 | [Install Guide](https://developer.hashicorp.com/terraform/install) | Infrastructure as Code |
| **gcloud CLI** | Latest | [Install Guide](https://cloud.google.com/sdk/docs/install) | GCP API access |

#### GCP Account Requirements
- GCP account with appropriate permissions
- GCP Project with billing enabled
- Ability to create: Compute Engine, Cloud SQL, Cloud Filestore, Load Balancer

#### Required GCP Permissions
Your GCP account needs permissions for these services:
- **Compute Engine**: Instances, instance groups, health checks, routers
- **Networking**: VPC, subnets, firewall rules, Cloud NAT, Global Load Balancers, backend services, URL maps, target proxies, global forwarding rules, global addresses
- **Database**: Cloud SQL instances, databases, users, SSL certificates
- **Storage**: Cloud Filestore instances, NFS shares
- **Security**: Secret Manager secrets and secret versions, managed SSL certificates
- **IAM**: Service accounts, IAM policy bindings (roles assignment)
- **Service Networking**: Private service connections, VPC peering for Cloud SQL

#### Required GCP APIs
Enable these APIs in your project:
- Compute Engine API (compute.googleapis.com)
- Cloud SQL Admin API (sqladmin.googleapis.com)
- Cloud Filestore API (file.googleapis.com)
- Secret Manager API (secretmanager.googleapis.com)
- Cloud Logging API (logging.googleapis.com)
- Cloud Monitoring API (monitoring.googleapis.com)
- Cloud Resource Manager API (cloudresourcemanager.googleapis.com)
- IAM API (iam.googleapis.com)
- Service Networking API (servicenetworking.googleapis.com)

### Step 2: Configure GCP Credentials

**The provided scripts use gcloud CLI for authentication.**

1. **Login to GCP:**
   ```bash
   gcloud auth login
   ```

2. **Set your project:**
   ```bash
   gcloud config set project YOUR_PROJECT_ID
   ```

3. **Enable required APIs:**
   ```bash
   gcloud services enable compute.googleapis.com sqladmin.googleapis.com file.googleapis.com secretmanager.googleapis.com logging.googleapis.com monitoring.googleapis.com cloudresourcemanager.googleapis.com iam.googleapis.com servicenetworking.googleapis.com
   ```

### Step 3: Configure Terraform Variables

1. **Copy the example configuration:**
   ```bash
   cd /path/to/sca-example-terraform/infra-gcp
   cp terraform.tfvars.example terraform.tfvars
   ```

2. **Edit `terraform.tfvars` with your values:**
   ```bash
   vi terraform.tfvars
   ```

   **Required changes:**
   - `gcp_project_id` - Your GCP project ID
   - `db_password` - Strong, unique password

### Step 4: Deploy Infrastructure

1. **Initialize Terraform:**
   ```bash
   terraform init
   ```

   This downloads required providers (Google Cloud, etc.)

2. **Review the deployment plan:**
   ```bash
   ./gcp-plan.sh
   ```

   This shows what resources will be created without actually deploying them.

3. **Deploy the infrastructure:**
   ```bash
   ./gcp-apply.sh
   ```

   The script will display the application URL when complete.

### Step 5: Access Sonatype IQ Server

1. **Wait for service to be ready:**
   - Initial startup can take 5-10 minutes
   - Docker container pulls image and starts IQ Server
   - Database migrations, if needed, run on first boot

2. **Access the web UI:**

   Use the application URL displayed at the end of the deployment.

   Example: `http://<load-balancer-ip>`

3. **Login credentials:**
   - **Username:** `admin`
   - **Password:** `admin123` (change immediately!)

---

## Teardown / Cleanup

**WARNING: This will delete ALL infrastructure and data!**

1. **Destroy all resources:**
   ```bash
   ./destroy.sh
   ```

   > **Keep the terminal open** - If you close it mid-destroy, the process will potentially stop and leave resources partially deleted.

---

## Configuration

### Configuration Variables

Edit `terraform.tfvars` to customize your deployment:

```hcl
# General Configuration
gcp_project_id = "your-gcp-project-id"
gcp_region     = "us-central1"
gcp_zone       = "us-central1-a"
environment    = "dev"

# Network Configuration
vpc_cidr            = "10.100.0.0/16"
public_subnet_cidr  = "10.100.1.0/24"
private_subnet_cidr = "10.100.10.0/24"
db_subnet_cidr      = "10.100.20.0/24"

# GCE with Docker Configuration
gce_machine_type   = "e2-standard-8"      # 8 vCPU, 32 GB RAM
gce_boot_image     = "debian-cloud/debian-12"
gce_boot_disk_size = 100
iq_desired_count   = 1                    # Single instance
iq_docker_image    = "sonatype/nexus-iq-server:latest"
java_opts          = "-Xmx48g -Xms48g -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"

# Database Configuration
db_name                             = "nexusiq"
db_username                         = "nexusiq"
db_password                         = "YourSecurePassword123!"  # Change this!
postgres_version                    = "POSTGRES_17"
db_instance_tier                    = "db-perf-optimized-N-8"  # 8 vCPU, optimized
db_edition                          = "ENTERPRISE_PLUS"
db_availability_type                = "ZONAL"
db_disk_size                        = 100
db_max_disk_size                    = 1000
db_backup_retention_count           = 7
db_deletion_protection              = false

# Storage Configuration
filestore_zone        = "us-central1-a"
filestore_tier        = "BASIC_SSD"
filestore_capacity_gb = 1024  # 1 TB minimum

# Load Balancer Configuration
enable_ssl  = false  # Set to true and provide domain_name for HTTPS
domain_name = ""     # Required if enable_ssl is true (e.g., "iq.example.com")
```

**Important Settings:**
- **Single Instance** - GCE instance with Docker container (iq_desired_count = 1)
- **`gcp_project_id`** - Your GCP project ID (required)
- **`db_password`** - Use a strong, unique password (required change)
- **`db_deletion_protection = false`** - Set to `true` for production to prevent accidental database deletion
- **`db_availability_type = "ZONAL"`** - Set to `"REGIONAL"` for production for high availability
- **`iq_docker_image`** - Use specific version tag for production (e.g., `sonatype/nexus-iq-server:1.196.0`)

### Docker Container Deployment

This deployment uses Docker containers on GCE for easier version management:

- **Official Image**: `sonatype/nexus-iq-server` from Docker Hub
- **Automated Startup**: Startup script installs Docker, mounts NFS, and launches container
- **Volume Mounts**: `/sonatype-work` and `/var/log/nexus-iq-server` mounted from Cloud Filestore
- **Database Configuration**: Generated dynamically from environment variables
- **Automatic Restart**: Container configured with `--restart always`

## Security Features

- **VPC Isolation**: Application runs in private subnets
- **Database Security**: Cloud SQL in isolated subnet with private IP
- **Secrets Management**: Database credentials stored in Google Secret Manager
- **Encryption**:
  - Cloud Filestore encrypted at rest
  - Cloud SQL encrypted at rest and in transit (ENCRYPTED_ONLY mode)
  - HTTPS support with managed SSL certificates (requires domain name configuration)
- **Firewall Rules**: Least-privilege network access
- **Service Account**: GCE instance uses service account with minimal permissions

## Reliability and Backup

This is a **single instance** deployment.
- **Single Instance**: One GCE instance running Docker container (runs in one zone)
- **Single Zone Database**: Cloud SQL instance runs in one zone (unless REGIONAL configured)
- **Automatic Restart**: Docker container automatically restarts on failure
- **Instance Auto-Healing**: Managed instance group can recreate failed instances
- **Database Backups**: Automated Cloud SQL backups with 7-day retention (configurable)
- **File Store Persistence**: Application data stored on Cloud Filestore survives instance restarts

## Monitoring and Logging

- **Cloud Logging**: Container logs automatically sent to Cloud Logging
- **Serial Console**: Startup script logs available via serial console
- **Docker Logs**: Access via `docker logs` command on instance
- **Persistent Logs**: Logs stored on Cloud Filestore at `/var/log/nexus-iq-server`
- **Health Checks**: Load balancer performs health checks on `/ping` endpoint

## Persistent Storage

- **Cloud Filestore**: NFS-mounted shared storage for `/sonatype-work` directory (1 TB minimum)
- **Database**: Cloud SQL PostgreSQL 17 for application data
- **Auto-scaling Storage**: Cloud SQL storage scales automatically up to configured limit

## Networking

### Subnets
- **Public Subnet**: Load balancer and Cloud NAT
- **Private Subnet**: GCE instance (no external IP by default)
- **Database Subnet**: Cloud SQL instance

### Firewall Rules
- **Load Balancer**: Allows HTTP (80), HTTPS (443) from internet
- **GCE Instance**: Allows traffic from load balancer health checks and internal VPC
- **Cloud SQL**: Allows PostgreSQL (5432) from private subnet only

## Important: Admin Port 8071 Not Exposed

The admin port 8071 is configured within the IQ Server container but **not exposed externally** through the Load Balancer. Only the main application port 8070 is accessible via port 80.

**Admin port access** is available through SSH to the GCE instance and Docker exec if needed for troubleshooting.
