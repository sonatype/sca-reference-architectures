# Sonatype IQ Reference Architecture - Azure Container Apps (High Availability)

This directory contains Terraform configuration for deploying Sonatype IQ Server on Azure using Container Apps in a **High Availability configuration** with auto-scaling and multi-zone deployment.

---

## Sizing Guide

This HA architecture supports sizes **M**, **L**, and **XL**. Choose your size based on application count and daily evaluation volume:

| Size | Applications | Evaluations/Day | Nodes | Compute (per node) | Java Heap | Instance Type |
|------|:------------:|:---------------:|:-----:|:-------------------:|:---------:|:-------------:|
| **M** | 2,000 – 10,000 | 5,000 – 10,000 | 2 | 8 vCPU / 64 GB | 48 GB | Standard_E8ps_v6 (ARM) |
| **L** | 10,000 – 20,000 | 10,000 – 20,000 | 3 | 8 vCPU / 64 GB | 48 GB | Standard_E8ps_v6 (ARM) |
| **XL** | 20,000 – 80,000 | 20,000+ | 4 | 16 vCPU / 128 GB | 96 GB | Standard_E16ps_v6 (ARM) |

> All sizes validated through performance testing. Expected throughput: ~310 evals/hour/node (M/L) or ~405 evals/hour/node (XL).

> **Note:** For XL scale, [AKS](../infra-azure-ha-k8s-helm/) is recommended over Container Apps.

> **Smaller deployments?** For < 2,000 applications with a single instance, use the [Single Instance](../infra-azure/) architecture.

### Recommended `terraform.tfvars` by Size

<details>
<summary><strong>Size M</strong> — Medium (2,000 – 10,000 applications, 2 nodes)</summary>

```hcl
container_cpu        = 8.0                 # 8 vCPU
container_memory     = "64Gi"              # 64 GB
iq_min_replicas      = 2                   # 2 replicas for HA
iq_max_replicas      = 3
iq_docker_image      = "sonatype/nexus-iq-server:latest"
java_opts            = "-Xms48g -Xmx48g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/Java_Heap_logs -XX:+CrashOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_sku_name          = "GP_Standard_D8s_v3" # 8 vCores, 32 GB
db_high_availability_mode = "ZoneRedundant"
```
</details>

<details>
<summary><strong>Size L</strong> — Large (10,000 – 20,000 applications, 3 nodes)</summary>

```hcl
container_cpu        = 8.0                 # 8 vCPU
container_memory     = "64Gi"              # 64 GB
iq_min_replicas      = 2
iq_max_replicas      = 4
iq_docker_image      = "sonatype/nexus-iq-server:latest"
java_opts            = "-Xms48g -Xmx48g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/Java_Heap_logs -XX:+CrashOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_sku_name          = "GP_Standard_D8s_v3" # 8 vCores, 32 GB
db_high_availability_mode = "ZoneRedundant"
storage_account_tier             = "Standard"
storage_account_replication_type = "ZRS"
```
</details>

<details>
<summary><strong>Size XL</strong> — Extra Large (20,000 – 80,000 applications, 4 nodes)</summary>

```hcl
container_cpu        = 16.0                # 16 vCPU
container_memory     = "128Gi"             # 128 GB
iq_min_replicas      = 3
iq_max_replicas      = 5
iq_docker_image      = "sonatype/nexus-iq-server:latest"
java_opts            = "-Xms96g -Xmx96g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/Java_Heap_logs -XX:+CrashOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_sku_name          = "MO_Standard_E16s_v3" # 16 vCores, 128 GB
db_high_availability_mode = "ZoneRedundant"
storage_account_tier             = "Premium"  # The quota is the provisioned and billed size
storage_account_replication_type = "ZRS"
```
</details>

### Database Sizing

| Size | DB SKU | vCores | Memory | Storage |
|------|:-------|:------:|:------:|:-------:|
| **M** | GP_Standard_D8s_v3 | 8 | 32 GB | 100 GB (auto-grow) |
| **L** | GP_Standard_D8s_v3 | 8 | 32 GB | 200 GB – 1 TB (auto-grow) |
| **XL** | MO_Standard_E16s_v3 | 16 | 128 GB | 500 GB – 2 TB (auto-grow) |

### Shared Storage (Azure Files)

| Size | Tier | Protocol | Redundancy | Share quota (`file_share_quota_gb`) |
|------|:-----|:--------:|:----------:|:------------------:|
| **M** | Standard HDD | SMB 3.0 | ZRS | 500 GB |
| **L** | Standard HDD | SMB 3.0 | ZRS | 1,536 GB |
| **XL** | Premium SSD | SMB | ZRS | 4,096 GB, billed as provisioned |

> Standard HDD is the default recommendation based on performance testing. Use Premium SSD when NFS protocol is required or high sustained write volume exceeds transaction-based pricing.

---

## Deployment Guide

### Step 1: Prerequisites

#### Required Tools
Install these tools on your local machine:

| Tool | Version | Installation | Purpose |
|------|---------|--------------|---------|
| **Terraform** | >= 1.0 | [Install Guide](https://developer.hashicorp.com/terraform/install) | Infrastructure as Code |
| **Azure CLI** | >= 2.0 | [Install Guide](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) | Azure API access |

#### Azure Account Requirements
- Azure subscription with Contributor access
- Ability to create: Resource Groups, Virtual Networks, Container Apps, PostgreSQL, Application Gateway
- Key Vault access for secrets management
- Zone-redundant resource support in target region (default: East US)

#### Required Azure Permissions
Your Azure account needs permissions for these services:
- **Resource Groups**: Create and manage resource groups
- **Compute**: Container Apps, Container App Environments, Container App Environment Storage
- **Networking**: Virtual Networks, subnets (multi-zone), Network Security Groups, Application Gateways (zone-redundant), Public IPs, Private DNS Zones
- **Database**: Azure Database for PostgreSQL Flexible Server (zone-redundant with HA mode), databases, firewall rules, server configurations
- **Storage**: Storage Accounts (Premium ZRS), File Shares, Blob Storage
- **Security**: Key Vault, Key Vault access policies, Key Vault secrets, Managed Identities (system-assigned)
- **Monitoring**: Log Analytics workspaces, Application Insights, Monitor diagnostic settings
- **Backup**: Data Protection Backup Vaults, Backup Policies (if enabled)

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
   cd /path/to/sca-example-terraform/infra-azure-ha
   cp terraform.tfvars.example terraform.tfvars
   ```

2. **Edit `terraform.tfvars` with your values (or leave to get started quickly):**
   ```bash
   vi terraform.tfvars
   ```

### Step 4: Deploy Infrastructure

1. **Initialize Terraform:**
   ```bash
   terraform init
   ```

   This downloads required providers (Azure, etc.)

2. **Review the deployment plan:**
   ```bash
   ./tf-plan.sh
   ```

   This shows what resources will be created without actually deploying them.

3. **Deploy the infrastructure:**
   ```bash
   ./tf-apply.sh
   ```

   The script will display the application URL when complete.

### Step 5: Access Sonatype IQ Server

1. **Wait for service to be ready:**
   - Initial startup can take 15-20 minutes
   - All replicas must complete database migrations and clustering setup

2. **Access the web UI:**

   Use the application URL displayed at the end of the deployment.

   Example: `http://ref-arch-iq-ha-abc123.eastus.cloudapp.azure.com`

3. **Login credentials:**
   - **Username:** `admin`
   - **Password:** `admin123` (change immediately!)

---

## Teardown / Cleanup

**WARNING: This will delete ALL infrastructure and data!**

1. **Destroy all resources:**
   ```bash
   ./tf-destroy.sh
   ```

   > **Keep the terminal open** - If you close it mid-destroy, the process will potentially stop and leave resources partially deleted.

---

## Configuration

> **PostgreSQL version.** Minimum PostgreSQL 15. Recommended, and the default for new
> deployments, PostgreSQL 18. An existing deployment sets `postgres_version` in
> `terraform.tfvars` to the version it runs today. Upgrading is the deployer's decision.

> **Upgrading an existing deployment.** These variable defaults changed with the
> published sizing. A deployment whose `terraform.tfvars` does not set a variable
> picks up the new default on its next apply. Set the values your deployment is
> running at in `terraform.tfvars` before applying.
>
> | Variable | Previous default | New default |
> |---|:---:|:---:|
> | `iq_min_replicas` | 3 | 2 |
> | `iq_max_replicas` | 5 | 4 |
> | `azure_region` | East US 2 | East US. A region change replaces every resource, so an existing deployment sets its region here |

### Configuration Variables

Edit `terraform.tfvars` to customize your deployment:

```hcl
# General Configuration
azure_region  = "East US"
cluster_name  = "ref-arch-iq-ha"

# Network Configuration (Multi-zone for HA)
vnet_cidr               = "10.0.0.0/16"
public_subnet_cidrs     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]    # Multiple subnets for zone redundancy
private_subnet_cidrs    = ["10.0.10.0/24", "10.0.20.0/24", "10.0.30.0/24"] # Multiple subnets for zone redundancy
db_subnet_cidr          = "10.0.40.0/24"

# High Availability Container App Configuration
container_cpu      = 4.0      # CPU per replica (max for Azure Container Apps)
container_memory   = "8Gi"    # Memory per replica (max for Azure Container Apps)
iq_min_replicas    = 2        # Minimum replicas, the Size L value (must be >= 2)
iq_max_replicas    = 4        # Maximum replicas for auto-scaling, the Size L value
iq_docker_image    = "sonatype/nexus-iq-server:latest"
java_opts          = "-Xms6g -Xmx6g -XX:+UseG1GC -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"

# Auto Scaling Configuration
scale_rule_concurrent_requests = 100  # Concurrent requests threshold for HTTP scaling

# Zone-Redundant Database Configuration (HA)
db_name                         = "nexusiq"
db_username                     = "nexusiq"
db_password                     = "CHANGE_ME_STRONG_PASSWORD"  # Change this!
postgres_version               = "18"
db_sku_name                    = "MO_Standard_E16s_v3"     # Memory Optimized: 16 vCores, 128GB RAM
db_backup_retention_days       = 7
db_geo_redundant_backup_enabled = false                    # Set to true if region supports geo-redundant backups
db_high_availability_mode      = "ZoneRedundant"           # Zone-redundant HA

# Zone-Redundant Application Gateway Configuration (HA)
app_gateway_sku_name    = "Standard_v2"    # v2 required for zone redundancy
app_gateway_sku_tier    = "Standard_v2"    # v2 required for zone redundancy
app_gateway_capacity    = 2                # Number of instances
app_gateway_zones       = ["1", "2", "3"] # Availability zones

# Storage Configuration (HA)
storage_account_tier             = "Standard"
storage_account_replication_type = "ZRS"      # Zone-Redundant Storage
file_share_quota_gb              = 200        # File share size in GB

# Monitoring and Logging
enable_monitoring         = true
log_retention_days       = 30
enable_container_insights = true

# Backup Configuration
enable_backup = true
```

**Important Settings:**
- **`iq_min_replicas = 2`** - Minimum replicas, the Size M and L value. Size XL uses 3, and every size must be at least 2 for HA
- **`iq_max_replicas = 4`** - Maximum auto scaling capacity, the Size L value. Size M uses 3 and Size XL uses 5
- **`db_high_availability_mode = "ZoneRedundant"`** - Zone-redundant PostgreSQL with automatic failover
- **`storage_account_replication_type = "ZRS"`** - Zone-Redundant Storage for file share
- **`app_gateway_zones = ["1", "2", "3"]`** - Multi-zone Application Gateway
- **`db_password`** - Use a strong, unique password (required change)
- **`db_geo_redundant_backup_enabled = false`** - Set to `true` if region supports geo-redundant backups
- **Resource Names** - Controlled by `cluster_name` variable

### Clustering Solution

This deployment uses Azure Container Apps for IQ Server clustering:

- **Multiple Replicas**: 3-5 Container App replicas distributed across availability zones
- **Unique Work Directories**: Each replica gets isolated `/sonatype-work/clm-server-${HOSTNAME}`
- **Shared Cluster Directory**: Coordination through `/sonatype-work/clm-cluster`
- **Database Sharing**: All replicas connect to the shared zone-redundant PostgreSQL cluster
- **Premium Storage**: Azure Files Premium (ZRS) provides consistent storage across all replicas

**Important**: Ensure your Sonatype IQ Server license supports clustering for HA deployments.

## Security Features

- **VNet Isolation**: Application runs in private subnets across multiple availability zones
- **Database Security**: Zone-redundant PostgreSQL in isolated database subnet with private DNS
- **Secrets Management**: Database credentials stored in Azure Key Vault
- **Encryption**:
  - Azure File Share (Premium ZRS) encrypted at rest
  - PostgreSQL encrypted at rest
  - Application Gateway SSL termination support
- **Network Security Groups**: Least-privilege network access
- **Managed Identity**: Container Apps use system-assigned identity for secure access

## Reliability and Backup

This is a **High Availability** deployment with comprehensive reliability features:

- **Multi-Zone Deployment**: Container Apps, Application Gateway, and database distributed across 3 availability zones
- **Auto Scaling**: Container App replicas scale between the minimum and maximum for your size based on concurrent HTTP request load. Size M is 2 to 3, Size L is 2 to 4, Size XL is 3 to 5
- **Zone-Redundant Database**: PostgreSQL Flexible Server with automatic failover (~30 seconds) between zones
- **Automatic Restart**: Container Apps automatically restarts failed replicas
- **Zone-Redundant Storage**: Premium Azure Files (ZRS) provides 99.9999999999% durability
- **Load Balancing**: Application Gateway distributes traffic with health probes
- **Database Backups**: Automated PostgreSQL backups with 7-day retention (configurable)
- **Geo-Redundant Backups**: Optional geo-redundant backups for disaster recovery
- **File Share Persistence**: Application data stored on Premium Azure Files survives replica restarts

## Monitoring and Logging

- **Log Analytics**: Application logs centralized in Log Analytics workspace
- **Container App Logs**: Application and system logs with structured logging from all replicas
- **Application Gateway Logs**: Access logs and diagnostic information
- **Application Insights**: Optional APM monitoring for performance metrics
- **Azure Monitor**: Container Insights for container-level metrics

## Persistent Storage

- **Azure File Share (Premium ZRS)**: Shared storage for `/sonatype-work` directory with zone redundancy
- **Database**: PostgreSQL Flexible Server (zone-redundant) for application data. Minimum PostgreSQL 15. Recommended, and the default for new deployments, PostgreSQL 18
- **Auto-scaling Storage**: PostgreSQL storage scales automatically

## Networking

### Subnets
- **Public Subnets**: Application Gateway (multiple subnets for zone redundancy)
- **Private Subnets**: Container Apps (multiple subnets for zone redundancy, delegated to Container Apps infrastructure)
- **Database Subnet**: PostgreSQL Flexible Server (delegated to PostgreSQL)

### Security Groups
- **Public NSG**: Allows HTTP (80), HTTPS (443) from internet
- **Private NSG**: Allows HTTP/HTTPS traffic and Azure Load Balancer health probes
- **Database NSG**: Allows PostgreSQL (5432) from private subnets only

## Important: Admin Port 8071 Not Exposed

The admin port 8071 is configured within the IQ Server container but **not exposed externally** through the Application Gateway. Only the main application port 8070 is accessible via port 80.

**Admin port access** is available through Container App console/exec sessions if needed for troubleshooting.
