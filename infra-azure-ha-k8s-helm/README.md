# Sonatype IQ Reference Architecture - Azure AKS with Helm (High Availability)

This directory contains Terraform configuration for deploying Sonatype IQ Server on Azure using AKS (Azure Kubernetes Service) with Helm in a **High Availability configuration** with auto-scaling and multi-zone deployment.

---

## Sizing Guide

This AKS HA architecture supports sizes **M**, **L**, and **XL**. Choose your size based on application count and daily evaluation volume:

| Size | Applications | Evaluations/Day | Nodes | Compute (per node) | Java Heap | Instance Type |
|------|:------------:|:---------------:|:-----:|:-------------------:|:---------:|:-------------:|
| **M** | 2,000 – 10,000 | 5,000 – 10,000 | 2 | 8 vCPU / 64 GB | 48 GB | Standard_E8ps_v6 (ARM) |
| **L** | 10,000 – 20,000 | 10,000 – 20,000 | 3 | 8 vCPU / 64 GB | 48 GB | Standard_E8ps_v6 (ARM) |
| **XL** | 20,000 – 80,000 | 20,000+ | 4 | 16 vCPU / 128 GB | 96 GB | Standard_E16ps_v6 (ARM) |

> All sizes validated through performance testing. Expected throughput: ~310 evals/hour/node (M/L) or ~405 evals/hour/node (XL).

> **ARM instances recommended.** Eps_v6 costs 30% less on demand than the x86 equivalent of the same generation, Esv6 (`Standard_E8ps_v6` against `Standard_E8s_v6` in eastus, list prices in November 2026).

> **Smaller deployments?** For < 2,000 applications with a single instance, use the [Single Instance](../infra-azure/) architecture.

### Recommended `terraform.tfvars` by Size

<details>
<summary><strong>Size M</strong> — Medium (2,000 – 10,000 applications, 2 nodes)</summary>

```hcl
node_instance_type   = "Standard_E8ps_v6"  # 8 vCPU, 64 GB (ARM)
node_group_min_size  = 2
node_group_max_size  = 3
node_group_desired_size = 2
nexus_iq_replica_count = 2                 # 2 IQ pods
nexus_iq_memory_request = "48Gi"
nexus_iq_memory_limit   = "56Gi"
nexus_iq_cpu_request    = "6"
nexus_iq_cpu_limit      = "8"
db_sku_name          = "GP_Standard_D8s_v3" # 8 vCores, 32 GB
db_high_availability_mode = "ZoneRedundant"
```
</details>

<details>
<summary><strong>Size L</strong> — Large (10,000 – 20,000 applications, 3 nodes)</summary>

```hcl
node_instance_type   = "Standard_E8ps_v6"  # 8 vCPU, 64 GB (ARM)
node_group_min_size  = 2
node_group_max_size  = 5
node_group_desired_size = 3
nexus_iq_replica_count = 3                 # 3 IQ pods
nexus_iq_memory_request = "48Gi"
nexus_iq_memory_limit   = "56Gi"
nexus_iq_cpu_request    = "6"
nexus_iq_cpu_limit      = "8"
db_sku_name          = "GP_Standard_D8s_v3" # 8 vCores, 32 GB
db_high_availability_mode = "ZoneRedundant"
```
</details>

<details>
<summary><strong>Size XL</strong> — Extra Large (20,000 – 80,000 applications, 4 nodes)</summary>

```hcl
node_instance_type   = "Standard_E16ps_v6" # 16 vCPU, 128 GB (ARM)
node_group_min_size  = 3
node_group_max_size  = 5
node_group_desired_size = 4
nexus_iq_replica_count = 4                 # 4 IQ pods
db_sku_name          = "MO_Standard_E16s_v3" # 16 vCores, 128 GB
db_high_availability_mode = "ZoneRedundant"
storage_account_tier = "Premium"           # Required for NFS with AKS
storage_account_replication_type = "ZRS"
```
</details>

### Database Sizing

| Size | DB SKU | vCores | Memory | Storage |
|------|:-------|:------:|:------:|:-------:|
| **M** | GP_Standard_D8s_v3 | 8 | 32 GB | 100 GB (auto-grow) |
| **L** | GP_Standard_D8s_v3 | 8 | 32 GB | 200 GB – 1 TB (auto-grow) |
| **XL** | MO_Standard_E16s_v3 | 16 | 128 GB | 500 GB – 2 TB (auto-grow) |

### Shared Storage (Azure Files Premium ZRS)

| Size | Tier | Protocol | Share quota (`storage_share_quota_gb`) |
|------|:-----|:--------:|:------------------:|
| **M** | Premium | NFS | 500 GB |
| **L** | Premium | NFS | 1,536 GB |
| **XL** | Premium | NFS (required) | 4,096 GB |

On Premium the quota is the provisioned and billed size.

> Premium SSD with ZRS redundancy is recommended for AKS deployments requiring NFS access mode (ReadWriteMany).

---

## Deployment Guide

### Step 1: Prerequisites

#### Required Tools
Install these tools on your local machine:

| Tool | Version | Installation | Purpose |
|------|---------|--------------|---------|
| **Terraform** | >= 1.0 | [Install Guide](https://developer.hashicorp.com/terraform/install) | Infrastructure as Code |
| **Azure CLI** | >= 2.0 | [Install Guide](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) | Azure API access |
| **kubectl** | Latest | [Install Guide](https://kubernetes.io/docs/tasks/tools/) | Kubernetes cluster management |
| **Helm** | >= 3.9.3 | [Install Guide](https://helm.sh/docs/intro/install/) | Application deployment |

#### Azure Account Requirements
- Azure subscription with Contributor access
- Ability to create: Resource Groups, Virtual Networks, AKS, PostgreSQL, Application Gateway
- Sufficient vCPU quota (48+ vCPUs required for production HA setup)
- Zone-redundant resource support in target region (default: East US)

#### Required Azure Permissions
Your Azure account needs permissions for these services:
- **Resource Groups**: Create and manage resource groups
- **Compute**: Azure Kubernetes Service, node pools, system-assigned managed identities
- **Networking**: Virtual Networks, subnets, Network Security Groups, Application Gateways (zone-redundant with auto-scaling), Public IPs, Private DNS Zones
- **Database**: Azure Database for PostgreSQL Flexible Server (zone-redundant with HA mode), databases, firewall rules, server configurations
- **Storage**: Storage Accounts (Premium ZRS), File Shares (multiple shares)
- **Security**: User-assigned managed identities, system-assigned managed identities
- **IAM**: Role assignments (Contributor, Reader, Network Contributor on various resources)
- **Monitoring**: Log Analytics workspaces, Application Insights

### Step 2: Configure Azure Credentials

**The provided scripts use Azure CLI for authentication.**

1. **Login to Azure:**
   ```bash
   az login
   ```

2. **Verify your subscription:**
   ```bash
   az account show
   ```

3. **Set subscription (if you have multiple):**
   ```bash
   az account set --subscription "<subscription-id-or-name>"
   ```

### Step 3: Configure Terraform Variables

1. **Copy the example configuration:**
   ```bash
   cd /path/to/sca-example-terraform/infra-azure-ha-k8s-helm
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

   This downloads required providers (Azure, Kubernetes, Helm, etc.)

2. **Review the deployment plan:**
   ```bash
   ./tf-plan.sh
   ```

   This shows what resources will be created without actually deploying them.

3. **Deploy the infrastructure:**
   ```bash
   ./tf-apply.sh
   ```

   This creates the AKS cluster, PostgreSQL database, Azure Files, and networking.

4. **Install IQ Server using Helm:**
   ```bash
   ./helm-install.sh
   ```

   This script:
   - Configures kubectl to access the AKS cluster
   - Retrieves database credentials
   - Installs the official Sonatype Helm chart
   - Configures ingress and load balancer

### Step 5: Access Sonatype IQ Server

1. **Wait for service to be ready:**
   - Initial startup can take 10-15 minutes
   - All pods must complete database migrations and clustering setup

2. **Access the web UI:**

   Use the application URL displayed at the end of the Helm deployment.

   Example: `http://nexus-iq-ha-abc123.eastus.cloudapp.azure.com`

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

> **PostgreSQL version.** Minimum PostgreSQL 16. Recommended, and the default for new
> deployments, PostgreSQL 18. An existing deployment sets `postgres_version` in
> `terraform.tfvars` to the version it runs today, and one still on PostgreSQL 15 is below
> the minimum. Upgrading is the deployer's decision.

### Configuration Variables

Edit `terraform.tfvars` to customize your deployment:

```hcl
# Azure Configuration
azure_region = "eastus"
environment  = "prod"
cluster_name = "nexus-iq-ha"

# Network Configuration
vnet_cidr          = "10.1.0.0/16"
public_subnet_cidr = "10.1.1.0/24"
aks_subnet_cidr    = "10.1.10.0/23"  # /23 provides more IPs for AKS
db_subnet_cidr     = "10.1.20.0/24"

# AKS Configuration
kubernetes_version      = "1.33.3"
node_instance_type      = "Standard_D8s_v3" # 8 vCPU, 32GB RAM
node_group_min_size     = 2
node_group_max_size     = 5
node_group_desired_size = 3
node_disk_size          = 50

# PostgreSQL Configuration (Zone-Redundant HA)
postgres_version                 = "18"
db_sku_name                      = "MO_Standard_E16s_v3" # Memory Optimized: 16 vCores, 128GB RAM
db_high_availability_mode        = "ZoneRedundant"
db_storage_mb                    = 65536 # 64GB
db_storage_tier                  = "P6"
database_name                    = "nexusiq"
database_username                = "nexusiq"
database_password                = "CHANGE_ME_STRONG_PASSWORD"  # Change this!
backup_retention_period          = 7
db_geo_redundant_backup_enabled  = false # Not supported in all regions

# Azure Files Premium Storage (Zone-Redundant)
storage_account_tier             = "Premium"
storage_account_replication_type = "ZRS"
storage_share_quota_gb           = 512

# Application Gateway Configuration (Zone-Redundant)
app_gateway_sku_name     = "Standard_v2"
app_gateway_sku_tier     = "Standard_v2"
app_gateway_capacity     = 2
app_gateway_min_capacity = 2
app_gateway_max_capacity = 10

# Nexus IQ Server HA Configuration
nexus_iq_license         = ""
nexus_iq_admin_password  = "admin123"
nexus_iq_replica_count   = 3
nexus_iq_memory_request  = "16Gi"
nexus_iq_memory_limit    = "24Gi"
nexus_iq_cpu_request     = "4"
nexus_iq_cpu_limit       = "6"

# Helm Configuration
helm_chart_version = "201.0.0"
helm_namespace     = "nexus-iq"
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
- **`nexus_iq_replica_count = 3`** - Initial number of IQ pods, the Size L value. Size M uses 2 and Size XL uses 4. Requires an HA license
- **`node_group_min_size = 2`** - Minimum AKS node capacity
- **`node_group_max_size = 5`** - Maximum AKS node capacity
- **`db_high_availability_mode = "ZoneRedundant"`** - Zone-redundant PostgreSQL with automatic failover
- **`storage_account_replication_type = "ZRS"`** - Zone-Redundant Storage for file share
- **`database_password`** - Use a strong, unique password (required change)
- **`nexus_iq_license`** - HA-capable license required
- **`db_geo_redundant_backup_enabled = false`** - Set to `true` if region supports geo-redundant backups
- **Resource Names** - Controlled by `cluster_name` variable

### Clustering Solution

This deployment leverages Kubernetes and Helm for IQ Server clustering:

- **Pod Distribution**: Kubernetes pod anti-affinity ensures replicas run on different nodes across AZs
- **Shared Storage**: Azure Files Premium (ZRS) provides consistent storage across all replicas with ReadWriteMany access
- **Database Sharing**: All replicas connect to the shared zone-redundant PostgreSQL cluster via Kubernetes secrets
- **Service Discovery**: Kubernetes service provides stable DNS and load balancing
- **Horizontal Pod Autoscaler**: IQ pods scale between the minimum and maximum for your size. Size M is 2 to 3, Size L is 2 to 4, Size XL is 3 to 5

**Important**: Ensure your Sonatype IQ Server license supports clustering for HA deployments.

## Security Features

- **VNet Isolation**: Application runs in private subnets across multiple availability zones
- **Database Security**: Zone-redundant PostgreSQL in isolated database subnet with private DNS
- **Secrets Management**: Database credentials stored in Kubernetes secrets
- **Encryption**:
  - Azure File Share (Premium ZRS) encrypted at rest
  - PostgreSQL encrypted at rest
  - Application Gateway SSL termination support
- **Network Security Groups**: Least-privilege network access
- **RBAC**: Kubernetes role-based access control
- **Managed Identity**: AKS uses system-assigned identity for secure access

## Reliability and Backup

This is a **High Availability** deployment with comprehensive reliability features:

- **Multi-Zone Deployment**: AKS nodes, pods, Application Gateway, and database distributed across multiple availability zones
- **Horizontal Pod Autoscaler (HPA)**: IQ pods scale between the minimum and maximum for your size. Size M is 2 to 3, Size L is 2 to 4, Size XL is 3 to 5
- **Cluster Autoscaler**: AKS nodes scale from 2-5 based on pod resource requests
- **Zone-Redundant Database**: PostgreSQL Flexible Server with automatic failover (~30 seconds) between zones
- **Automatic Restart**: Kubernetes automatically restarts failed pods
- **Pod Disruption Budgets**: Maintains availability during updates and node maintenance
- **Rolling Updates**: Zero-downtime updates with controlled rollout
- **Database Backups**: Automated PostgreSQL backups with 7-day retention (configurable)
- **Geo-Redundant Backups**: Optional geo-redundant backups for disaster recovery
- **Zone-Redundant Storage**: Azure Files Premium (ZRS) provides 99.9999999999% durability

## Monitoring and Logging

- **Log Analytics**: Application logs centralized in Log Analytics workspace
- **Container Insights**: AKS monitoring with pod and node metrics
- **Application Gateway Logs**: Access logs and diagnostic information
- **Kubernetes Metrics**: Pod CPU/memory usage via `kubectl top`
- **HPA Metrics**: Horizontal Pod Autoscaler metrics

## Persistent Storage

- **Azure File Share (Premium ZRS)**: Shared storage for `/sonatype-work` directory with zone redundancy
- **Database**: PostgreSQL Flexible Server (zone-redundant) for application data. Minimum PostgreSQL 16. Recommended, and the default for new deployments, PostgreSQL 18
- **Auto-scaling Storage**: PostgreSQL storage scales automatically

## Networking

### Subnets
- **Public Subnet**: Application Gateway
- **AKS Subnet**: AKS worker nodes and pods (delegated to AKS)
- **Database Subnet**: PostgreSQL Flexible Server (delegated to PostgreSQL)

### Security Groups
- **Public NSG**: Allows HTTP (80), HTTPS (443) from internet
- **AKS NSG**: Allows traffic from Application Gateway, inter-node communication
- **Database NSG**: Allows PostgreSQL (5432) from AKS subnet only

## Important: Admin Port 8071 Not Exposed

The admin port 8071 is configured within the IQ Server container but **not exposed externally** through the Application Gateway. Only the main application port 8070 is accessible via port 80.

**Admin port access** is available through Kubernetes exec sessions if needed for troubleshooting.
