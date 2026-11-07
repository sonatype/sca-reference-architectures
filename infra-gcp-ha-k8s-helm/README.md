# Sonatype IQ Reference Architecture - GCP GKE with Helm (High Availability)

This directory contains Terraform configuration for deploying Sonatype IQ Server on GCP using GKE (Google Kubernetes Engine) with Helm in a **High Availability configuration** with auto-scaling and multi-zone deployment.

---

## Sizing Guide

This GKE HA architecture supports sizes **M**, **L**, and **XL**. Choose your size based on application count and daily evaluation volume:

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
node_instance_type      = "n4a-highmem-8"  # 8 vCPU, 64 GB (ARM)
node_group_min_size     = 2
node_group_max_size     = 3
node_group_desired_size = 2
nexus_iq_replica_count  = 2                # 2 IQ pods
db_instance_tier        = "db-custom-8-30720" # 8 vCPU, 30 GB (Enterprise)
db_availability_type    = "REGIONAL"
filestore_tier          = "BASIC_HDD"
filestore_capacity_gb   = 1024             # 1 TiB
```
</details>

<details>
<summary><strong>Size L</strong> — Large (10,000 – 20,000 applications, 3 nodes)</summary>

```hcl
node_instance_type      = "n4a-highmem-8"  # 8 vCPU, 64 GB (ARM)
node_group_min_size     = 2
node_group_max_size     = 5
node_group_desired_size = 3
nexus_iq_replica_count  = 3                # 3 IQ pods
db_instance_tier        = "db-custom-8-30720" # 8 vCPU, 30 GB (Enterprise)
db_availability_type    = "REGIONAL"
filestore_tier          = "BASIC_HDD"
filestore_capacity_gb   = 2560             # 2.5 TiB
```
</details>

<details>
<summary><strong>Size XL</strong> — Extra Large (20,000 – 80,000 applications, 4 nodes)</summary>

```hcl
node_instance_type      = "n4a-highmem-16" # 16 vCPU, 128 GB (ARM)
node_group_min_size     = 3
node_group_max_size     = 5
node_group_desired_size = 4
nexus_iq_replica_count  = 4                # 4 IQ pods
db_instance_tier        = "db-custom-16-65536" # 16 vCPU, 64 GB (Enterprise)
db_availability_type    = "REGIONAL"
filestore_tier          = "BASIC_HDD"
filestore_capacity_gb   = 10240            # 10 TiB
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

> BASIC_HDD is the default recommendation. At 10+ TiB, HDD unlocks 5,000 write IOPS (4x observed peak of ~1,212 ops/sec) at roughly the same cost as 2.5 TiB SSD. Enterprise edition Cloud SQL (not Enterprise Plus) is sufficient.

---

## Deployment Guide

### Step 1: Prerequisites

#### Required Tools
Install these tools on your local machine:

| Tool | Version | Installation | Purpose |
|------|---------|--------------|---------  |
| **Terraform** | >= 1.0 | [Install Guide](https://developer.hashicorp.com/terraform/install) | Infrastructure as Code |
| **gcloud CLI** | Latest | [Install Guide](https://cloud.google.com/sdk/docs/install) | GCP API access |
| **kubectl** | Latest | [Install Guide](https://kubernetes.io/docs/tasks/tools/) | Kubernetes cluster management |
| **Helm** | >= 3.9.3 | [Install Guide](https://helm.sh/docs/intro/install/) | Application deployment |

#### GCP Account Requirements
- GCP account with appropriate permissions
- GCP Project with billing enabled
- Ability to create: GKE, Cloud SQL, Cloud Filestore, Cloud Load Balancer
- Sufficient vCPU quota (48+ vCPUs required for production HA setup)
- Zone-redundant resource support in target region (default: us-central1)

#### Required GCP Permissions
Your GCP account needs permissions for these services:
- **Compute Engine**: Routers, security policies (Cloud Armor)
- **Networking**: VPC, subnets, firewall rules, Cloud NAT, global addresses
- **Kubernetes Engine**: GKE clusters, node pools, cluster addons (HTTP load balancing, HPA, network policy, GCE persistent disk CSI driver), workload identity configurations
- **Database**: Cloud SQL instances (including read replicas), databases, users, SSL certificates
- **Storage**: Cloud Filestore instances, NFS shares
- **Security**: Secret Manager secrets and secret versions, IAM bindings for secrets (secretAccessor)
- **IAM**: Service accounts, project-level IAM policy bindings (roles assignment), service account IAM bindings (Workload Identity user)
- **Service Networking**: Private service connections, VPC peering for Cloud SQL
- **Logging**: Log buckets, log sinks, log-based metrics
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
- Kubernetes Engine API (container.googleapis.com)

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
   gcloud services enable compute.googleapis.com sqladmin.googleapis.com file.googleapis.com secretmanager.googleapis.com logging.googleapis.com monitoring.googleapis.com cloudresourcemanager.googleapis.com iam.googleapis.com servicenetworking.googleapis.com container.googleapis.com
   ```

### Step 3: Configure Terraform Variables

1. **Copy the example configuration:**
   ```bash
   cd /path/to/sca-example-terraform/infra-gcp-ha-k8s-helm
   cp terraform.tfvars.example terraform.tfvars
   ```

2. **Edit `terraform.tfvars` with your values (or leave to get started quickly):**
   ```bash
   vi terraform.tfvars
   ```

### Step 4: Deploy Infrastructure and Application

1. **Initialize Terraform:**
   ```bash
   terraform init
   ```

   This downloads required providers (Google Cloud, Kubernetes, Helm, etc.)

2. **Review the deployment plan:**
   ```bash
   ./tf-plan.sh
   ```

   This shows what resources will be created without actually deploying them.

3. **Deploy the infrastructure:**
   ```bash
   ./tf-apply.sh
   ```

   This creates the GKE cluster, PostgreSQL database, Cloud Filestore, and networking.

4. **Install IQ Server using Helm:**
   ```bash
   ./helm-install.sh
   ```

   This script:
   - Configures kubectl to access the GKE cluster
   - Retrieves database credentials
   - Installs the official Sonatype Helm chart
   - Configures ingress and load balancer

### Step 5: Access Sonatype IQ Server

1. **Wait for service to be ready:**
   - Initial startup can take 10-15 minutes
   - All pods must complete database migrations and clustering setup

2. **Access the web UI:**

   Use the application URL displayed at the end of the Helm deployment.

   Example: `http://nexus-iq-ha-<ip>.nip.io`

3. **Login credentials:**
   - **Username:** `admin`
   - **Password:** `admin123` (change immediately!)

---

## Teardown / Cleanup

**WARNING: This will delete ALL infrastructure and data!**

1. **Uninstall the Helm deployment:**
   ```bash
   ./helm-uninstall.sh
   ```

2. **Destroy all infrastructure:**
   ```bash
   ./tf-destroy.sh
   ```

   > **Keep the terminal open** - If you close it mid-destroy, the process will potentially stop and leave resources partially deleted.

---

## Configuration

### Configuration Variables

Edit `terraform.tfvars` to customize your deployment:

```hcl
# GCP Configuration
gcp_project_id = "your-gcp-project-id"
gcp_region     = "us-central1"
environment    = "prod"
cluster_name   = "nexus-iq-ha"

# Network Configuration
public_subnet_cidr   = "10.100.1.0/24"
private_subnet_cidrs = ["10.100.10.0/24", "10.100.11.0/24", "10.100.12.0/24"]
gke_pods_cidr        = "10.101.0.0/16"
gke_services_cidr    = "10.102.0.0/16"
gke_master_cidr      = "172.16.0.0/28"

# GKE Configuration
kubernetes_version           = "1.27"
node_instance_type           = "n2-standard-8"  # 8 vCPU, 32GB RAM
node_group_min_size          = 2
node_group_max_size          = 5
node_group_desired_size      = 3
node_disk_size               = 100
gke_maintenance_window_start = "03:00"

# PostgreSQL Configuration (Regional HA)
postgres_version                   = "POSTGRES_15"
db_instance_tier                   = "db-custom-8-30720"  # 8 vCPU, 30GB RAM
db_availability_type               = "REGIONAL"
db_disk_size                       = 100
db_max_disk_size                   = 1000
db_max_connections                 = "400"
db_backup_retention_count          = 7
db_deletion_protection             = false
enable_read_replica                = true
db_name                            = "nexusiq"
db_username                        = "nexusiq"
db_password                        = "CHANGE_ME_STRONG_PASSWORD"  # Change this!

# Cloud Filestore Configuration (Shared Storage)
filestore_zone        = "us-central1-a"
filestore_tier        = "BASIC_HDD"
filestore_capacity_gb = 2560  # 2.5 TiB, the Size L capacity

# Sonatype IQ Server HA Configuration
nexus_iq_replica_count  = 3
nexus_iq_admin_password = "admin123"
helm_chart_version      = "195.0.0"
```

Pod count and pod autoscaling are Helm chart values, set in `helm-values.yaml`:

```yaml
iq_server:
  replicas: 3          # Set from nexus_iq_replica_count in terraform.tfvars. Size L. Size M uses 2 and Size XL uses 4
hpa:
  enabled: true
  minReplicas: 2       # Size L. Size M uses 2 and Size XL uses 3
  maxReplicas: 4       # Size L. Size M uses 3 and Size XL uses 5
```

> **Upgrading an existing deployment.** Earlier installs ran 2 pods with no autoscaler. The next
> `helm-upgrade.sh` moves them to the values above, so before upgrading, set `nexus_iq_replica_count`
> in `terraform.tfvars` and the `hpa` block in `helm-values.yaml` to what the deployment runs.

**Important Settings:**
- **`node_group_min_size = 2`** - Minimum GKE node capacity
- **`node_group_max_size = 5`** - Maximum GKE node capacity
- **`nexus_iq_replica_count = 3`** - Initial number of replicas for HA (minimum 2 recommended, requires HA license)
- **`db_availability_type = "REGIONAL"`** - Regional database with automatic failover
- **`enable_read_replica = true`** - Database read replica for load distribution
- **`filestore_capacity_gb = 2560`** - 2.5 TiB, the Size L capacity. Size M uses 1024 and Size XL uses 10240
- **`gcp_project_id`** - Your GCP project ID (required)
- **`db_password`** - Use a strong, unique password (required change)
- **`db_deletion_protection = false`** - Set to `true` for production to prevent accidental database deletion
- **Resource Names** - Controlled by `cluster_name` variable

### Clustering Solution

This deployment leverages Kubernetes and Helm for IQ Server clustering:

- **Pod Distribution**: Kubernetes pod anti-affinity ensures replicas run on different nodes across availability zones
- **Shared Storage**: Cloud Filestore (BASIC_SSD) provides consistent storage across all replicas with ReadWriteMany access
- **Database Sharing**: All replicas connect to the shared regional Cloud SQL cluster via Kubernetes secrets
- **Service Discovery**: Kubernetes service provides stable DNS and load balancing
- **Horizontal Pod Autoscaler**: IQ pods scale between the minimum and maximum for your size. Size M is 2 to 3, Size L is 2 to 4, Size XL is 3 to 5

**Important**: Ensure your Sonatype IQ Server license supports clustering for HA deployments.

## Security Features

- **Private GKE Cluster**: Nodes in private subnets with no public IPs
- **Workload Identity**: Secure service account access without keys (GCP's equivalent to AWS IRSA)
- **Database Security**: Regional Cloud SQL in isolated database subnet with private DNS
- **Secrets Management**: Database credentials stored in Kubernetes secrets
- **Encryption**:
  - Cloud Filestore encrypted at rest
  - Cloud SQL encrypted at rest and in transit (ENCRYPTED_ONLY mode)
  - Cloud Load Balancer SSL termination support
- **Network Security Groups**: Least-privilege network access
- **RBAC**: Kubernetes role-based access control
- **Managed Identity**: GKE uses system-assigned identity for secure access

## Reliability and Backup

This is a **High Availability** deployment with comprehensive reliability features:

- **Multi-Zone Deployment**: GKE nodes, pods, and database distributed across multiple availability zones
- **Horizontal Pod Autoscaler (HPA)**: IQ pods scale between the minimum and maximum for your size. Size M is 2 to 3, Size L is 2 to 4, Size XL is 3 to 5
- **Cluster Autoscaler**: GKE nodes scale from 2-5 based on pod resource requests
- **Regional Database**: Cloud SQL with REGIONAL availability type provides automatic failover (~30 seconds) between zones
- **Read Replica**: Optional read replica for load distribution
- **Automatic Restart**: Kubernetes automatically restarts failed pods
- **Pod Disruption Budgets**: Maintains availability during updates and node maintenance
- **Rolling Updates**: Zero-downtime updates with controlled rollout
- **Database Backups**: Automated Cloud SQL backups with 7-day retention (configurable)
- **Cloud Filestore**: Provides 99.9999999999% durability for persistent storage

## Monitoring and Logging

- **Cloud Logging**: Application logs centralized in Cloud Logging via Fluentd
- **Fluentd Aggregator Pattern**: Lightweight log forwarders in each pod with central aggregator
- **Kubernetes Metrics**: Pod CPU/memory usage via `kubectl top`
- **HPA Metrics**: Horizontal Pod Autoscaler metrics
- **Cloud Monitoring**: GKE cluster monitoring with node and pod metrics
- **Cloud Load Balancer Logs**: Access logs and diagnostic information
- **Log-Based Metrics**: Automatic error and warning counters

## Persistent Storage

- **Cloud Filestore (BASIC_SSD)**: Shared storage for `/sonatype-work` directory (2.5 TB minimum)
- **Database**: Cloud SQL PostgreSQL 15 (regional) for application data
- **Auto-scaling Storage**: Cloud SQL storage scales automatically up to configured limit
- **Backup Configuration**: Database backups retained for 7 days with transaction logs for point-in-time recovery

## Networking

### Subnets
- **Public Subnet**: Cloud Load Balancer
- **Private Subnets**: GKE worker nodes and pods (delegated to GKE) across multiple zones
- **Database Subnet**: Cloud SQL instance (delegated to Cloud SQL)

### Security Groups
- **Public Firewall Rules**: Allows HTTP (80), HTTPS (443) from internet
- **GKE Firewall Rules**: Allows traffic from Cloud Load Balancer, inter-node communication
- **Database Firewall Rules**: Allows PostgreSQL (5432) from GKE subnets only

## Important: Admin Port 8071 Not Exposed

The admin port 8071 is configured within the IQ Server container but **not exposed externally** through the Cloud Load Balancer. Only the main application port 8070 is accessible via port 80.

**Admin port access** is available through Kubernetes exec sessions if needed for troubleshooting.
