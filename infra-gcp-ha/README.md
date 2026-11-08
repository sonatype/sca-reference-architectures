# Sonatype IQ Reference Architecture - GCP with Docker (High Availability)

This directory contains Terraform configuration for deploying Sonatype IQ Server on Google Cloud Platform using Managed Instance Groups with Docker containers in a **High Availability configuration** with auto-scaling and multi-zone deployment.

---

## Sizing Guide

This MIG HA architecture supports sizes **M**, **L**, and **XL**. Choose your size based on application count and daily evaluation volume:

| Size | Applications | Evaluations/Day | Nodes | Compute (per node) | Java Heap | Machine Type |
|------|:------------:|:---------------:|:-----:|:-------------------:|:---------:|:------------:|
| **M** | 2,000 – 10,000 | 5,000 – 10,000 | 2 | 8 vCPU / 64 GB | 48 GB | n4a-highmem-8 (ARM) |
| **L** | 10,000 – 20,000 | 10,000 – 20,000 | 3 | 8 vCPU / 64 GB | 48 GB | n4a-highmem-8 (ARM) |
| **XL** | 20,000 – 80,000 | 20,000+ | 4 | 16 vCPU / 128 GB | 96 GB | n4a-highmem-16 (ARM) |

> All sizes validated through performance testing on GCP ARM instances. Expected throughput: ~310 evals/hour/node (M/L) or ~405 evals/hour/node (XL).

> **GCP was the primary test platform.** All performance data was validated on GCP ARM-based instances (Google Axion).

> **Smaller deployments?** For < 2,000 applications with a single instance, use the [Single Instance](../infra-gcp/) architecture.

### Recommended `terraform.tfvars` by Size

<details>
<summary><strong>Size M</strong> — Medium (2,000 – 10,000 applications, 2 nodes)</summary>

```hcl
instance_machine_type = "n4a-highmem-8"    # 8 vCPU, 64 GB (ARM)
iq_target_instances  = 2                   # 2 instances across zones
iq_min_instances     = 2
iq_max_instances     = 3
iq_docker_image      = "sonatype/nexus-iq-server:latest"
java_opts            = "-Xms48g -Xmx48g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/Java_Heap_logs -XX:+CrashOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_instance_tier     = "db-custom-8-30720" # 8 vCPU, 30 GB (Enterprise)
db_availability_type = "REGIONAL"
filestore_tier       = "BASIC_HDD"         # 1 TiB (600 read / 1,000 write IOPS)
filestore_capacity_gb = 1024
```
</details>

<details>
<summary><strong>Size L</strong> — Large (10,000 – 20,000 applications, 3 nodes)</summary>

```hcl
instance_machine_type = "n4a-highmem-8"    # 8 vCPU, 64 GB (ARM)
iq_target_instances  = 3                   # 3 instances across zones
iq_min_instances     = 2
iq_max_instances     = 4
iq_docker_image      = "sonatype/nexus-iq-server:latest"
java_opts            = "-Xms48g -Xmx48g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/Java_Heap_logs -XX:+CrashOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_instance_tier     = "db-custom-8-30720" # 8 vCPU, 30 GB (Enterprise)
db_availability_type = "REGIONAL"
filestore_tier       = "BASIC_HDD"         # 2.5 TiB
filestore_capacity_gb = 2560
```
</details>

<details>
<summary><strong>Size XL</strong> — Extra Large (20,000 – 80,000 applications, 4 nodes)</summary>

```hcl
instance_machine_type = "n4a-highmem-16"   # 16 vCPU, 128 GB (ARM)
iq_target_instances  = 4                   # 4 instances across zones
iq_min_instances     = 3
iq_max_instances     = 5
iq_docker_image      = "sonatype/nexus-iq-server:latest"
java_opts            = "-Xms96g -Xmx96g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/Java_Heap_logs -XX:+CrashOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_instance_tier     = "db-custom-16-65536" # 16 vCPU, 64 GB (Enterprise)
db_availability_type = "REGIONAL"
filestore_tier       = "BASIC_HDD"         # 10 TiB (1,000 read / 5,000 write IOPS)
filestore_capacity_gb = 10240
```
</details>

### Database Sizing (Cloud SQL PostgreSQL)

| Size | DB Tier | vCPU | Memory | Storage | Availability |
|------|:--------|:----:|:------:|:-------:|:------------:|
| **M** | db-custom-8-30720 (Enterprise) | 8 | 30 GB | 100 GB (auto-resize to 500 GB) | Regional |
| **L** | db-custom-8-30720 (Enterprise) | 8 | 30 GB | 200 GB – 1 TB (auto-resize) | Regional |
| **XL** | db-custom-16-65536 (Enterprise) | 16 | 64 GB | 500 GB – 2 TB (auto-resize) | Regional |

### Shared Storage (Cloud Filestore)

| Size | Tier | Capacity | Read IOPS | Write IOPS |
|------|:-----|:--------:|:---------:|:----------:|
| **M** | BASIC_HDD | 1 TiB | 600 | 1,000 |
| **L** | BASIC_HDD | 2.5 TiB | 600 | 1,000 |
| **XL** | BASIC_HDD | 10 TiB | 1,000 | 5,000 |

> BASIC_HDD is the default recommendation. At 10+ TiB, HDD unlocks 5,000 write IOPS (4x observed peak of ~1,212 ops/sec) at roughly the same cost as 2.5 TiB SSD.

---

## Deployment Guide

### Step 1: Prerequisites

#### Required Tools
Install these tools on your local machine:

| Tool | Version | Installation | Purpose |
|------|---------|--------------|---------  |
| **Terraform** | >= 1.0 | [Install Guide](https://developer.hashicorp.com/terraform/install) | Infrastructure as Code |
| **gcloud CLI** | Latest | [Install Guide](https://cloud.google.com/sdk/docs/install) | GCP API access |

#### GCP Account Requirements
- GCP account with appropriate permissions
- GCP Project with billing enabled
- Ability to create: Compute Engine, Cloud SQL, Cloud Filestore, Global Load Balancers
- Zone-redundant resource support in target region (default: us-central1)

#### Required GCP Permissions
Your GCP account needs permissions for these services:
- **Compute Engine**: Instances, instance templates, regional managed instance groups, health checks, routers, regional autoscalers, security policies (Cloud Armor)
- **Networking**: VPC, subnets, firewall rules, Cloud NAT, Global Load Balancers, backend services, URL maps, target proxies, global forwarding rules, global addresses
- **Database**: Cloud SQL instances (including read replicas), databases, users, SSL certificates
- **Storage**: Cloud Filestore instances, NFS shares
- **Security**: Secret Manager secrets and secret versions, managed SSL certificates, IAM bindings for secrets
- **IAM**: Service accounts, IAM policy bindings (roles assignment)
- **Service Networking**: Private service connections, VPC peering for Cloud SQL
- **Logging**: Log buckets, log sinks, log views, log-based metrics
- **Monitoring**: Alert policies, notification channels

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
   cd /path/to/sca-example-terraform/infra-gcp-ha
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
   terraform plan
   ```

   This shows what resources will be created without actually deploying them.

3. **Deploy the infrastructure:**
   ```bash
   terraform apply
   ```

   The script will display the application URL when complete.

### Step 5: Access Sonatype IQ Server

1. **Wait for service to be ready:**
   - Initial startup can take 10-15 minutes
   - All instances must complete database migrations and clustering setup

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
   terraform destroy
   ```

   > **Keep the terminal open** - If you close it mid-destroy, the process will potentially stop and leave resources partially deleted.

---

## Configuration

> **Upgrading an existing deployment.** These variable defaults changed with the
> published sizing. A deployment whose `terraform.tfvars` does not set a variable
> picks up the new default on its next apply. Set the values your deployment is
> running at in `terraform.tfvars` before applying.
>
> | Variable | Previous default | New default | Applies to |
> |---|:---:|:---:|---|
> | `iq_target_instances` | 2 | 3 | new deployments only, see below |
> | `iq_max_instances` | 6 | 4 | every deployment |
>
> `iq_target_instances` reaches a group only when it is created: `compute.tf` sets
> `ignore_changes = [target_size]` on the instance group manager, so an existing
> deployment keeps the size it is running at and an apply will not resize it. Change the
> size with `gcloud compute instance-groups managed resize`, or by removing that
> lifecycle block.

### Configuration Variables

Edit `terraform.tfvars` to customize your deployment:

```hcl
# GCP Project Configuration
gcp_project_id = "your-gcp-project-id"
gcp_region     = "us-central1"

# Availability zones for multi-zone deployment
availability_zones = ["us-central1-a", "us-central1-b", "us-central1-c"]

# Environment
environment = "prod"

# Network Configuration
# This root creates subnets inside an auto-created VPC, so there is no
# VPC-wide CIDR variable. Set the three subnet ranges instead.
public_subnet_cidr     = "10.200.1.0/24"
private_subnet_cidrs   = ["10.200.10.0/24", "10.200.11.0/24", "10.200.12.0/24"]
db_subnet_cidr         = "10.200.20.0/24"

# Sonatype IQ Server Configuration
iq_docker_image = "sonatype/nexus-iq-server:latest"

# Compute Engine Instance Configuration
instance_machine_type = "n4a-highmem-8"  # 8 vCPU, 64 GB (ARM), the Size L value

# High Availability Configuration
iq_min_instances    = 2  # Minimum for HA, the Size L value
iq_max_instances    = 4  # Maximum for scaling, the Size L value
iq_target_instances = 3  # Initial target, the Size L value

# Database Configuration
db_name     = "nexusiq"
db_username = "nexusiq"
db_password = "your-secure-database-password"  # Change this!

# Database settings
postgres_version       = "POSTGRES_15"
db_instance_tier      = "db-custom-8-30720" # 8 vCPU, 30 GB, the Size L value
db_edition            = "ENTERPRISE"
db_disk_type          = "PD_SSD"
db_availability_type  = "REGIONAL"          # REGIONAL for HA
db_disk_size          = 200
db_max_disk_size      = 1000
db_max_connections    = "200"
db_backup_retention_count  = 8
db_deletion_protection     = true

# Enable read replica for load distribution
enable_read_replica = true

# Cloud Filestore Configuration
filestore_zone        = "us-central1-a"
filestore_tier        = "BASIC_HDD"
filestore_capacity_gb = 2560  # 2.5 TiB, the Size L capacity

# Load Balancer and SSL Configuration
enable_ssl  = false  # Set to true and provide domain_name for HTTPS
domain_name = ""     # Required if enable_ssl is true (e.g., "iq.example.com")
lb_backend_timeout_sec = 30

# Auto Scaling Configuration
cpu_target_utilization      = 0.7   # 70% CPU utilization target
scale_in_cooldown_seconds   = 300   # 5 minutes
scale_out_cooldown_seconds  = 60    # 1 minute

# Java Configuration
java_opts = "-Xms48g -Xmx48g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/Java_Heap_logs -XX:+CrashOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
```

**Important Settings:**
- **`iq_min_instances = 2`** - Minimum instances, the Size M and L value. Size XL uses 3, and every size must be at least 2 for HA. Requires an HA license
- **`iq_max_instances = 4`** - Maximum auto scaling capacity, the Size L value. Size M uses 3 and Size XL uses 5
- **`iq_target_instances = 3`** - Initial number of instances, the Size L value. Size M uses 2 and Size XL uses 4
- **`db_availability_type = "REGIONAL"`** - Multi-AZ database with automatic failover
- **`enable_read_replica = true`** - Database read replica for load distribution
- **`filestore_capacity_gb = 2560`** - 2.5 TiB, the Size L capacity. Size M uses 1024 and Size XL uses 10240
- **`gcp_project_id`** - Your GCP project ID (required)
- **`db_password`** - Use a strong, unique password (required change)
- **`db_deletion_protection = true`** - Set to `false` only for testing to allow database deletion
- **`iq_docker_image`** - Use specific version tag for production (e.g., `sonatype/nexus-iq-server:1.196.0`). An image in Artifact Registry in the same project is pulled with the instances' service account, which holds `roles/artifactregistry.reader`
- **`db_edition` and `db_disk_type`** - `ENTERPRISE` and `PD_SSD` suit the `db-custom-*` tiers. The newer Cloud SQL series need `ENTERPRISE_PLUS`, and `db-c4a-highmem-*` also needs `HYPERDISK_BALANCED`
- **`lb_backend_timeout_sec = 30`** - Seconds the load balancer waits for IQ Server before answering 502. Raise it if large scan uploads or report exports run longer
- **`iq_log_levels`** - Extra logger levels written to `config.yml`, empty by default

### Docker Container Deployment

This deployment uses Docker containers on Compute Engine for easier version management:

- **Official Image**: `sonatype/nexus-iq-server` from Docker Hub
- **Automated Startup**: Startup script installs Docker, mounts NFS, and launches container
- **Volume Mounts**: `/sonatype-work` and `/var/log/nexus-iq-server` mounted from Cloud Filestore
- **Database Configuration**: Generated dynamically from environment variables
- **Automatic Restart**: Container configured with `--restart always`

### Clustering Solution

This deployment uses Managed Instance Groups for IQ Server clustering:

- **Instance Distribution**: MIG spreads instances across multiple availability zones (us-central1-a and us-central1-b)
- **Unique Work Directories**: Each instance gets isolated `/sonatype-work/clm-server-${HOSTNAME}` directory on Cloud Filestore
- **Shared Cluster Directory**: Coordination through `/sonatype-work/clm-cluster` on Cloud Filestore
- **Database Sharing**: All instances connect to the shared regional Cloud SQL cluster via Kubernetes secrets
- **Auto Scaling**: MIG autoscaler scales between the minimum and maximum instance counts for your size, based on CPU utilization (70%) and load balancer utilization (80%). Size M is 2 to 3, Size L is 2 to 4, Size XL is 3 to 5

**Important**: Ensure your Sonatype IQ Server license supports clustering for HA deployments.

## Security Features

- **VPC Isolation**: Application runs in private subnets across multiple availability zones
- **Database Security**: Regional Cloud SQL in isolated database subnet with private DNS and Multi-AZ deployment
- **Secrets Management**: Database credentials stored in Google Secret Manager
- **Encryption**:
  - Cloud Filestore encrypted at rest
  - Cloud SQL encrypted at rest and in transit (ENCRYPTED_ONLY mode)
  - HTTPS support with managed SSL certificates (requires domain name configuration)
- **Firewall Rules**: Least-privilege network access
- **Service Account**: GCE instances use service account with minimal permissions
- **Work Directory Isolation**: Unique work directories per instance prevent clustering conflicts

## Reliability and Backup

This is a **High Availability** deployment with comprehensive reliability features:

- **Multi-Zone Deployment**: MIG distributes instances across 2 availability zones (us-central1-a and us-central1-b)
- **Auto Scaling**: MIG autoscaler scales between the minimum and maximum instance counts for your size, based on CPU utilization and load balancer utilization. Size M is 2 to 3, Size L is 2 to 4, Size XL is 3 to 5
- **Regional Database**: Cloud SQL with REGIONAL availability type provides automatic failover (~30 seconds) between zones
- **Read Replica**: Optional read replica for load distribution
- **Automatic Restart**: Docker container automatically restarts on failure
- **Instance Auto-Healing**: MIG recreates failed instances automatically (15-minute initial delay for startup)
- **Load Balancing**: Global load balancer distributes traffic across healthy instances
- **Rolling Updates**: Zero-downtime updates with controlled rollout (max surge: 3, max unavailable: 0)
- **Database Backups**: Automated Cloud SQL backups with 7-day retention (configurable)
- **File Store Persistence**: Application data stored on Cloud Filestore survives instance restarts

## Monitoring and Logging

- **Cloud Logging**: Container logs automatically sent to Cloud Logging with structured logging
- **Log Buckets**: Dedicated log bucket with configurable retention (30 days default)
- **Log-Based Metrics**: Automatic error and warning counters
- **Cloud Monitoring**: Automatic dashboards for MIG, Cloud SQL, and Global Load Balancer
- **Cloud SQL Insights**: Query performance monitoring
- **Load Balancer Metrics**: Request rate, latency, and error rates
- **Auto Scaling Metrics**: CPU utilization and instance count tracking
- **Health Checks**: Load balancer performs health checks on `/ping` endpoint

## Persistent Storage

- **Cloud Filestore**: NFS-mounted shared storage for `/sonatype-work` directory (2.5 TB minimum for BASIC_SSD tier)
- **Database**: Cloud SQL PostgreSQL 15 for application data
- **Auto-scaling Storage**: Cloud SQL storage scales automatically up to configured limit
- **Backup Configuration**: Database backups retained for 7 days with transaction logs for point-in-time recovery

## Networking

### Subnets
- **Public Subnet**: Load balancer and Cloud NAT
- **Private Subnets**: GCE instances across multiple zones (no external IP by default)
- **Database Subnet**: Cloud SQL instance

### Firewall Rules
- **Load Balancer**: Allows HTTP (80), HTTPS (443) from internet
- **Health Checks**: Allows health check traffic from Google ranges (130.211.0.0/22, 35.191.0.0/16)
- **GCE Instances**: Allows traffic from load balancer on port 8070 and inter-instance communication
- **Cloud SQL**: Allows PostgreSQL (5432) from private subnets only

## Important: Admin Port 8071 Not Exposed

The admin port 8071 is configured within the IQ Server container but **not exposed externally** through the Global Load Balancer. Only the main application port 8070 is accessible via port 80.

**Admin port access** is available through SSH to the GCE instances and Docker exec if needed for troubleshooting.
