# Sonatype IQ Reference Architecture - GCP with Docker (Single Instance)

This directory contains Terraform configuration for deploying a **single-instance** Sonatype IQ Server on Google Cloud Platform using GCE with Docker containers.

---

## Sizing Guide

This single-instance architecture supports sizes **XS**, **S**, and **M**. Choose your size based on application count and daily evaluation volume:

| Size | Applications | Evaluations/Day | Compute | Java Heap | Machine Type |
|------|:------------:|:---------------:|:-------:|:---------:|:------------:|
| **XS** ¹ | < 500 | < 1,000 | 2 vCPU / 16 GB | 12 GB | n4a-highmem-2 (ARM) |
| **S** ¹ | 500 – 2,000 | 1,000 – 5,000 | 4 vCPU / 32 GB | 24 GB | n4a-highmem-4 (ARM) |
| **M** | 2,000 – 10,000 | 5,000 – 10,000 | 8 vCPU / 64 GB | 48 GB | n4a-highmem-8 (ARM) |

> ¹ XS and S are projected sizing estimates. M has been validated through performance testing on GCP ARM instances.

> **ARM instances recommended.** n4a (Ampere Altra) instances offer 20-30% better price-performance than x86 equivalents.

> **Need more capacity?** For 10,000+ applications or multi-node deployments, use the [High Availability](../infra-gcp-ha/) or [Kubernetes](../infra-gcp-ha-k8s-helm/) architectures.

### Recommended `terraform.tfvars` by Size

<details>
<summary><strong>Size XS</strong> — Extra Small (< 500 applications)</summary>

```hcl
gce_machine_type     = "n4a-highmem-2"     # 2 vCPU, 16 GB (ARM)
iq_docker_image      = "sonatype/nexus-iq-server:latest"
java_opts            = "-Xms12g -Xmx12g -XX:MaxDirectMemorySize=4g -XX:+UseG1GC -XX:+AlwaysPreTouch -Dinsight.threads.monitor=3 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_instance_tier     = "db-custom-2-7680"  # 2 vCPU, 7.5 GB
db_disk_size         = 50                  # GB
```
</details>

<details>
<summary><strong>Size S</strong> — Small (500 – 2,000 applications)</summary>

```hcl
gce_machine_type     = "n4a-highmem-4"     # 4 vCPU, 32 GB (ARM)
iq_docker_image      = "sonatype/nexus-iq-server:latest"
java_opts            = "-Xms24g -Xmx24g -XX:MaxDirectMemorySize=6g -XX:+UseG1GC -XX:+AlwaysPreTouch -Dinsight.threads.monitor=5 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_instance_tier     = "db-custom-2-13312" # 2 vCPU, 13 GB
db_disk_size         = 100                 # GB
```
</details>

<details>
<summary><strong>Size M</strong> — Medium (2,000 – 10,000 applications)</summary>

```hcl
gce_machine_type     = "n4a-highmem-8"     # 8 vCPU, 64 GB (ARM)
iq_docker_image      = "sonatype/nexus-iq-server:latest"
java_opts            = "-Xms48g -Xmx48g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/Java_Heap_logs -XX:+CrashOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_instance_tier     = "db-custom-8-30720" # 8 vCPU, 30 GB (Enterprise)
db_disk_size         = 100                 # GB, auto-resize enabled
filestore_tier       = "BASIC_HDD"         # 1 TiB (600 read / 1,000 write IOPS)
filestore_capacity_gb = 1024               # 1 TiB minimum
```
</details>

### Database Sizing (Cloud SQL PostgreSQL)

| Size | DB Tier | vCPU | Memory | Storage |
|------|:--------|:----:|:------:|:-------:|
| **XS** | db-custom-2-7680 | 2 | 7.5 GB | 50 GB |
| **S** | db-custom-2-13312 | 2 | 13 GB | 100 GB |
| **M** | db-custom-8-30720 (Enterprise) | 8 | 30 GB | 100 GB (auto-resize to 500 GB) |

---

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

> **Upgrading an existing deployment.** These variable defaults changed with the
> published sizing. A deployment whose `terraform.tfvars` does not set a variable
> picks up the new default on its next apply. Set the values your deployment is
> running at in `terraform.tfvars` before applying.
>
> | Variable | Previous default | New default |
> |---|:---:|:---:|
> | `postgres_version` | POSTGRES_17 | POSTGRES_15 |

### Configuration Variables

Edit `terraform.tfvars` to customize your deployment:

```hcl
# General Configuration
gcp_project_id = "your-gcp-project-id"
gcp_region     = "us-central1"
gcp_zone       = "us-central1-a"
environment    = "dev"

# Network Configuration
# This root creates subnets inside an auto-created VPC, so there is no
# VPC-wide CIDR variable. Set the three subnet ranges instead.
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
db_password                         = "CHANGE_ME_STRONG_PASSWORD"  # Change this!
postgres_version                    = "POSTGRES_15"
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
- **Database**: Cloud SQL PostgreSQL 15 for application data
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
