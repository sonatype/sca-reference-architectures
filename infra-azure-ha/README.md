# Sonatype IQ Reference Architecture - Azure Container Apps (High Availability)

This directory contains Terraform configuration for deploying Sonatype IQ Server on Azure using Container Apps in a **High Availability configuration** with auto-scaling and multi-zone deployment.

---

## Sizing Guide

This HA architecture supports sizes **M**, **L**, and **XL**. Choose your size based on application count and daily evaluation volume:

| Size | Applications | Evaluations/Day | Nodes | Compute (per node) | Java Heap | Instance Type | OpenSearch |
|------|:------------:|:---------------:|:-----:|:-------------------:|:---------:|:-------------:|:----------:|
| **M** | 2,000 - 10,000 | 5,000 - 10,000 | 2 | 8 vCPU / 64 GB | 48 GB | E8 workload profile | Required ¹ |
| **L** | 10,000 - 20,000 | 10,000 - 20,000 | 3 | 8 vCPU / 64 GB | 48 GB | E8 workload profile | Required ¹ |
| **XL** | 20,000 - 80,000 | 20,000+ | 4 | 15.5 vCPU / 120 GB | 96 GB | E16 workload profile | Required ¹ |

> Evaluations an hour per replica, sustained in testing, not a limit: 890 at M on 2 replicas and 2,070 at L on 3 replicas.

> ¹ Required for Advanced Search and the Nexus One index at every size, and not switched on for you: `search_engine` defaults to `lucene` in `variables.tf`, so a deployment that wants either feature sets it to `opensearch` and supplies the cluster's endpoint and credentials. See [OpenSearch](#opensearch) for what it serves, what this architecture does and does not do about it, and the per-size cluster specification.

> XL's replica is smaller than its `E16` node, because Container Apps keeps part of every node for itself
> ([workload profiles](https://learn.microsoft.com/en-us/azure/container-apps/workload-profiles-overview#resource-consumption-and-scaling)).
> M and L replicas are 8 vCPU and 64 GB on `E8`.

> **Note:** For XL scale, [AKS](../infra-azure-ha-k8s-helm/) is recommended over Container Apps.

> **Smaller deployments?** For < 2,000 applications with a single instance, use the [Single Instance](../infra-azure/) architecture.

### Recommended `terraform.tfvars` by Size

> **Heap dumps.** At M, L and XL the first out-of-memory error on any node writes a heap dump to
> `/sonatype-work/heap-dump.hprof`, one file on the shared storage, and the JVM exits; a later one
> skips the dump while that file exists, so delete it to allow another.

<details>
<summary><strong>Size M</strong> — Medium (2,000 – 10,000 applications, 2 nodes)</summary>

```hcl
container_cpu        = 8.0                 # 8 vCPU
container_memory     = "64Gi"              # 64 GB
workload_profile_type = "E8"               # 8 cores, 64 GB per node
iq_min_replicas      = 2                   # 2 replicas for HA
iq_max_replicas      = 3
iq_docker_image      = "sonatype/nexus-iq-server:latest"
java_opts            = "-Xms48g -Xmx48g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/heap-dump.hprof -XX:+ExitOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_sku_name          = "MO_Standard_E8ds_v6" # 8 vCores, 64 GB
db_storage_mb        = 131072              # 128 GB, grows automatically
db_high_availability_mode = "ZoneRedundant"
file_share_quota_gb  = 500
```
</details>

<details>
<summary><strong>Size L</strong> — Large (10,000 – 20,000 applications, 3 nodes)</summary>

```hcl
container_cpu        = 8.0                 # 8 vCPU
container_memory     = "64Gi"              # 64 GB
workload_profile_type = "E8"               # 8 cores, 64 GB per node
iq_min_replicas      = 2
iq_max_replicas      = 4
iq_docker_image      = "sonatype/nexus-iq-server:latest"
java_opts            = "-Xms48g -Xmx48g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/heap-dump.hprof -XX:+ExitOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_sku_name          = "MO_Standard_E8ds_v6" # 8 vCores, 64 GB
db_storage_mb        = 262144              # 256 GB, grows automatically
db_storage_tier      = "P15"
db_high_availability_mode = "ZoneRedundant"
file_share_quota_gb  = 1536
storage_account_tier             = "Standard"
storage_account_replication_type = "ZRS"
```
</details>

<details>
<summary><strong>Size XL</strong> — Extra Large (20,000 – 80,000 applications, 4 nodes)</summary>

```hcl
container_cpu        = 15.5                # 15.5 vCPU, leaving 0.5 of the node
container_memory     = "120Gi"             # 120 GB, leaving 8 GB of the node
workload_profile_type = "E16"              # 16 cores, 128 GB per node
iq_min_replicas      = 3
iq_max_replicas      = 5
iq_docker_image      = "sonatype/nexus-iq-server:latest"
java_opts            = "-Xms96g -Xmx96g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/heap-dump.hprof -XX:+ExitOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_sku_name          = "MO_Standard_E16ds_v6" # 16 vCores, 128 GB
db_storage_mb        = 524288              # 512 GB, grows automatically
db_storage_tier      = "P20"
db_high_availability_mode = "ZoneRedundant"
file_share_quota_gb  = 4096
storage_account_tier             = "Premium"  # The quota is the provisioned and billed size
storage_account_replication_type = "ZRS"
```
</details>

### Database Sizing

| Size | DB SKU | vCores | Memory | Storage |
|------|:-------|:------:|:------:|:-------:|
| **M** | MO_Standard_E8ds_v6 | 8 | 64 GB | 128 GB (auto-grow) |
| **L** | MO_Standard_E8ds_v6 | 8 | 64 GB | 256 GB, auto-grow to 1 TB |
| **XL** | MO_Standard_E16ds_v6 | 16 | 128 GB | 512 GB, auto-grow to 2 TB |

### Shared Storage (Azure Files)

| Size | Tier | Protocol | Redundancy | Share quota (`file_share_quota_gb`) |
|------|:-----|:--------:|:----------:|:------------------:|
| **M** | Standard HDD | SMB 3.0 | ZRS | 500 GB |
| **L** | Standard HDD | SMB 3.0 | ZRS | 1,536 GB |
| **XL** | Premium SSD | SMB | ZRS | 4,096 GB, billed as provisioned |

> Standard HDD is the default recommendation. Use Premium SSD when NFS protocol is required or high sustained write volume exceeds transaction-based pricing.

### OpenSearch

IQ Server uses an OpenSearch cluster for Advanced Search and for the Nexus One index behind the Nexus
One list pages, typeahead, and dashboard, and **both features need it at every size this architecture
supports.** One cluster serves both, through a `search:` block and a `nexusOne.connection` block in IQ Server's
`config.yml` that name the same endpoint and credentials, with nothing extra to switch on per
feature.

**The templates do not turn it on for you.** `search_engine` defaults to `lucene` in `variables.tf`, so
a deployment that wants either feature sets `search_engine = "opensearch"` and supplies
`opensearch_endpoint`, `opensearch_username` and `opensearch_password`. Every variable and its default
is in [Advanced Search with OpenSearch](#advanced-search-with-opensearch) below.

Azure has no first-party managed OpenSearch service, so the cluster is **self-managed OpenSearch on
Azure virtual machines** and IQ Server authenticates with a username and password. That means you also
choose the OpenSearch server version and own upgrades, snapshots, and node replacement. Use `https` on
the cluster's REST layer: with no IAM to sign with, that password is the only thing protecting the
index, and on plain `http` it crosses the network in clear text on every request.

**This architecture does not create the cluster.** It takes an endpoint and points IQ Server at it, so
the cluster's lifecycle and its indexed data stay independent of this deployment. Two consequences: the
cluster has to exist before the deployment is useful, and `terraform destroy` here cannot delete your
index.

#### Replicas

A replica is a full second copy of every shard, and it is what makes losing a data node
survivable. Set `opensearch_index_replicas` per size:

| Size | OpenSearch data nodes | Replica count |
|------|:---------------------:|:-------------:|
| **M** | 3 | `1` |
| **L** | 3 | `1` |
| **XL** | 3 | `1` |

When to use `0`, and how to give the Advanced Search index the same count, are in the
[top-level OpenSearch section](../README.md#replicas-each-architecture-sets-the-count).

#### Plan for twice the index during a rebuild

**Plan free disk for twice the Nexus One index, because a rebuild needs room for a second copy.** A
replica is a separate doubling that applies at the same time. The full rules, and why
a rebuild is not a backup, are in the
[top-level OpenSearch section](../README.md#plan-for-twice-the-index-during-a-rebuild).

#### Per-size cluster specification

The data node type and count, storage per node, shards and replicas for each size are in the
[cluster table](#specifying-the-cluster) below. At M, L and XL the component, violation and vulnerability indices are
created with 3 primary shards and every other index with 1. The
shard counts are set through the configuration API before the first build, as shown there.

See the [top-level OpenSearch section](../README.md#opensearch) for the full planning rules.

---

## Deployment Guide

### Step 1: Prerequisites

#### Required Tools
Install these tools on your local machine:

| Tool | Version | Installation | Purpose |
|------|---------|--------------|---------|
| **Terraform** | >= 1.2 | [Install Guide](https://developer.hashicorp.com/terraform/install) | Infrastructure as Code |
| **Azure CLI** | >= 2.0 | [Install Guide](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) | Azure API access |

#### Azure Account Requirements
- Azure subscription with Contributor access
- Ability to create: Resource Groups, Virtual Networks, Container Apps, PostgreSQL, Application Gateway
- Key Vault access for secrets management
- Zone-redundant resource support in target region (default: East US)
- PostgreSQL Flexible Server cores are a quota per subscription and per region. Check the region's
  usage before applying, and request a quota increase if the server's vCores do not fit. `az rest`
  fills in `{subscriptionId}` from the signed-in account; replace `eastus` with the region's short name:

  ```bash
  az rest --method get --url "https://management.azure.com/subscriptions/{subscriptionId}/providers/Microsoft.DBforPostgreSQL/locations/eastus/resourceType/flexibleServers/usages?api-version=2024-08-01" --query "value[?name.value=='cores'].{used:currentValue, limit:limit}" -o table
  ```

#### Required Azure Permissions
Your Azure account needs permissions for these services:
- **Resource Groups**: Create and manage resource groups
- **Compute**: Container Apps, Container App Environments, Container App Environment Storage
- **Networking**: Virtual Networks, subnets (multi-zone), Network Security Groups, Application Gateways (zone-redundant), Public IPs, Private DNS Zones
- **Database**: Azure Database for PostgreSQL Flexible Server (zone-redundant with HA mode), databases, firewall rules, server configurations
- **Storage**: Storage Accounts (Standard ZRS at M and L, Premium ZRS at XL), File Shares, Blob Storage
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

2. **Edit `terraform.tfvars` with your values (set `search_engine = "opensearch"` and your cluster's details, see [Advanced Search with OpenSearch](#advanced-search-with-opensearch)):**
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

   This shows what resources will be created without actually deploying them. The plan script
   stops before Terraform runs if an uncommented line in `terraform.tfvars` still holds
   `CHANGE_ME`, and Terraform rejects a `CHANGE_ME` value too, so deploy through the scripts
   rather than plain `terraform apply`.

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

> **Your OpenSearch cluster is not part of this.** This architecture never creates the cluster, so `./tf-destroy.sh` does not delete it or its indices. Remove it separately when you no longer need it.

**WARNING: This will delete ALL infrastructure and data!**

1. **Destroy all resources:**
   ```bash
   ./tf-destroy.sh
   ```

   > **Keep the terminal open** - If you close it mid-destroy, the process will potentially stop and leave resources partially deleted.

---

## Configuration

> **PostgreSQL version.** Minimum PostgreSQL 16.9 or later on 16, or 17.5 or later on 17. Recommended, and the default for new
> deployments, PostgreSQL 18. An existing deployment sets `postgres_version` in
> `terraform.tfvars` to the version it runs today, and one still on PostgreSQL 15 is below
> the minimum. Upgrading is the deployer's decision.

> **Upgrading an existing deployment.** These variable defaults changed with the
> published sizing. A deployment whose `terraform.tfvars` does not set a variable
> picks up the new default on its next apply. Set the values your deployment is
> running at in `terraform.tfvars` before applying.
>
> | Variable | Previous default | New default |
> |---|:---:|:---:|
> | `iq_min_replicas` | 3 | 2 |
> | `iq_max_replicas` | 5 | 4 |
> | `container_cpu` | 4.0 | 8.0 |
> | `container_memory` | `8Gi` | `64Gi` |
> | `java_opts` | 6 GB heap | 48 GB heap |
> | `db_sku_name` | `GP_Standard_D8s_v3` | `MO_Standard_E8ds_v6` |
> | `db_storage_mb` | 65536, fixed | 131072 for a new server, then grows automatically. An existing server keeps its size |
> | `file_share_quota_gb` | 200 | 500 |
> | workload profile | `D4`, 1 to 3 nodes | `workload_profile_type`, default `E8`, `iq_min_replicas` to `iq_max_replicas` nodes |
> | `azure_region` | East US 2 | East US. A region change replaces every resource, so an existing deployment sets its region here |
>
> **Earlier versions did not read `cluster_name`**, though the example file set it. A deployment whose
> `terraform.tfvars` sets it to anything other than `ref-arch-iq-ha` would have every resource renamed,
> which replaces the resource group, the PostgreSQL server and the storage account, and the data in
> them. Remove that line, or set it to `ref-arch-iq-ha`, before applying.

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
container_cpu      = 8.0      # vCPU per replica, the Size M and L value
container_memory   = "64Gi"   # Memory per replica, the Size M and L value
workload_profile_type = "E8"  # 8 cores, 64 GB per node
iq_min_replicas    = 2        # Minimum replicas, the Size L value (must be >= 2)
iq_max_replicas    = 4        # Maximum replicas for auto-scaling, the Size L value
iq_docker_image    = "sonatype/nexus-iq-server:latest"
java_opts          = "-Xms48g -Xmx48g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/heap-dump.hprof -XX:+ExitOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"

# Auto Scaling Configuration
scale_rule_concurrent_requests = 100  # Concurrent requests threshold for HTTP scaling

# Zone-Redundant Database Configuration (HA)
db_name                         = "nexusiq"
db_username                     = "nexusiq"
db_password                     = "CHANGE_ME_STRONG_PASSWORD"  # Change this!
postgres_version               = "18"
db_sku_name                    = "MO_Standard_E8ds_v6"      # Memory Optimized: 8 vCores, 64 GB, the Size M and L value
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
file_share_quota_gb              = 500        # File share size in GB, the Size M value

# Monitoring and Logging
enable_monitoring         = true
log_retention_days       = 30
enable_container_insights = true

# Backup Configuration
enable_backup = true

# Search Backend, needed at every size - see "Advanced Search with OpenSearch" below
search_engine = "lucene"

# Tags merged into every resource
common_tags = {
  Environment    = "production"
  Terraform      = "true"
  DeploymentType = "high-availability"
  CostCenter     = "engineering"

  owner      = "CHANGE_ME_EMAIL"
  project    = "CHANGE_ME_PROJECT"
  subproject = "CHANGE_ME_SUBPROJECT"
  department = "CHANGE_ME_DEPARTMENT"
  team       = "CHANGE_ME_TEAM"
}
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

- **Multiple Replicas**: 2 to 5 Container App replicas by size, one per workload profile node, distributed across availability zones
- **Unique Work Directories**: Each replica gets isolated `/sonatype-work/clm-server-${HOSTNAME}`
- **Shared Cluster Directory**: Coordination through `/sonatype-work/clm-cluster`
- **Database Sharing**: All replicas connect to the shared zone-redundant PostgreSQL cluster
- **Shared Storage**: Azure Files (ZRS) provides consistent storage across all replicas, Standard at M and L and Premium at XL

**Important**: Ensure your Sonatype IQ Server license supports clustering for HA deployments.

## Security Features

- **VNet Isolation**: Application runs in private subnets across multiple availability zones
- **Database Security**: Zone-redundant PostgreSQL in isolated database subnet with private DNS
- **Secrets Management**: Database credentials stored in Azure Key Vault
- **Encryption**:
  - Azure File Share (ZRS) encrypted at rest
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
- **Zone-Redundant Storage**: Azure Files (ZRS) provides 99.9999999999% durability
- **Load Balancing**: Application Gateway distributes traffic with health probes
- **Database Backups**: Automated PostgreSQL backups with 7-day retention (configurable)
- **Geo-Redundant Backups**: Optional geo-redundant backups for disaster recovery
- **File Share Persistence**: Application data stored on Azure Files survives replica restarts

## Monitoring and Logging

- **Log Analytics**: Application logs centralized in Log Analytics workspace
- **Container App Logs**: Application and system logs with structured logging from all replicas
- **Application Gateway Logs**: Access logs and diagnostic information
- **Application Insights**: Optional APM monitoring for performance metrics
- **Azure Monitor**: Container Insights for container-level metrics

## Persistent Storage

- **Azure File Share (ZRS)**: Shared storage for `/sonatype-work` directory with zone redundancy
- **Database**: PostgreSQL Flexible Server (zone-redundant) for application data. Minimum PostgreSQL 16.9 or later on 16, or 17.5 or later on 17. Recommended, and the default for new deployments, PostgreSQL 18
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

### Running several sizes in one subscription

Every resource name is built from `cluster_name`, so two deployments coexist in one Azure
subscription as long as they use different values:

```hcl
cluster_name = "iq-m-ha"   # one deployment
cluster_name = "iq-l-ha"   # another, in the same subscription
```

**The default keeps the default names**, so nothing changes when it is not set.

Two Azure limits constrain the value, and the variable rejects a value that would break either:

- **A storage account name is globally unique across Azure**, lowercase alphanumeric only, and capped
  at 24 characters. The hyphens in `cluster_name` are stripped when it is built.
- **A Key Vault name is globally unique and capped at 24 characters.**

Both carry an 8-character random suffix, so the global uniqueness is handled already and only the
length matters. That is why the variable is capped at 14 characters rather than at Azure's 24.

**Some names do not move with `cluster_name`, and none of them needs to.** The subnet names
(`snet-public-N`, `snet-private-N`, `snet-database`), the network security group names and the
private DNS zone link are scoped inside the virtual network and the resource group, which do move, so
they cannot collide across deployments. The private DNS zone
`privatelink.postgres.database.azure.com` is Azure's own fixed name for that zone and is shared by
design.

## Advanced Search with OpenSearch

Sonatype IQ Server can keep its Advanced Search index in OpenSearch instead of the embedded Lucene
index, and the same cluster serves the Nexus One index.

**OpenSearch here is a cluster you run yourself on Azure Virtual Machines.** This configuration does
not build it: you supply its endpoint and credentials, so its indexed data is independent of
Terraform runs here.

### Turning it on

Set these in `terraform.tfvars`:

```hcl
search_engine             = "opensearch"
opensearch_endpoint       = "CHANGE_ME-opensearch.internal.example.com"
opensearch_port           = 9200
opensearch_use_tls        = true
opensearch_username       = "iq-server"
opensearch_password       = "<strong password>"
opensearch_index_replicas = 1
```

| Variable | Default | What it does |
|---|---|---|
| `search_engine` | `lucene` | `lucene` writes no `search:` block at all. `opensearch` writes one and creates the credential secrets |
| `opensearch_endpoint` | `""` | Host name or IP of the cluster's client endpoint, no scheme and no port. Required when `search_engine` is `opensearch` |
| `opensearch_port` | `9200` | The port the cluster listens on |
| `opensearch_use_tls` | `true` | `true` builds an `https://` URI, `false` builds `http://` |
| `opensearch_username` | `""` | The user IQ Server authenticates as. Mandatory on this connection type |
| `opensearch_password` | `""` | That user's password. Delivered to the container app as a secret rather than a plain environment variable, and also written to Key Vault beside the four database secrets. `sensitive` keeps it out of CLI output only, so it is plain text in `terraform.tfstate` |
| `opensearch_index_replicas` | `1` | Written as `nexusOne.connection.nexusOneIndexReplicas`. Accepts 0 to 10 |
| `opensearch_ca_pem` | `""` | Base64 certificate of a private authority that signed the cluster's certificate. The entrypoint adds it to a copy of the JVM trust store, see below |

Leave `search_engine` at `lucene` and nothing changes: no secrets are created, and `config.yml` has no
`search:` block.

### What reaches `config.yml`

```yaml
search:
  type: http
  mode: OPENSEARCH
  uri: https://opensearch.internal.example.com:9200
  username: 'iq-server'
  password: '<from the container app secret>'
nexusOne:
  connection:
    type: http
    mode: OPENSEARCH
    uri: https://opensearch.internal.example.com:9200
    username: 'iq-server'
    password: '<from the container app secret>'
    nexusOneIndexReplicas: 1
```

The two credentials are single-quoted, so any character is safe in the password, and the startup
output redacts every `password:` line, so neither credential reaches Log Analytics.

Three things about that block are deliberate:

- **`type: http` with basic auth.** A user name and a password are required on this type.
- **`mode: OPENSEARCH` is written explicitly**, rather than left to the default.
- **A `nexusOne.connection` block naming the same cluster.** The Nexus One index needs its own
  connection block, and it carries `nexusOneIndexReplicas`.

### Specifying the cluster

Every cluster manager has a 30 GiB P4 Premium SSD OS disk and takes
half its RAM as heap.

This root covers M, L and XL. XS and S are not deployable here, because `iq_min_replicas` is
validated at two or more, so their rows are in the single-instance root's README instead.

| Size | Data nodes | Data node | Storage per node | Cluster managers | Shards ¹ | `opensearch_index_replicas` |
|---|---|---|---|---|---|---|
| M | 3 | `Standard_D2ps_v6`, 2 vCPU, 8 GB | 100 GB, on a P10 Premium SSD of 128 GiB | 3 x `Standard_D2pls_v6`, 2 vCPU, 4 GB, 2 GB heap, 30 GiB P4 Premium SSD OS disk | 3 | `1` |
| L | 3 | `Standard_D4ps_v6`, 4 vCPU, 16 GB | 150 GB, on a P15 Premium SSD of 256 GiB | 3 x `Standard_D2pls_v6`, 2 vCPU, 4 GB, 2 GB heap, 30 GiB P4 Premium SSD OS disk | 3 | `1` |
| XL | 3 | `Standard_E8ps_v6`, 8 vCPU, 64 GB | 250 GB, on a P15 Premium SSD of 256 GiB | 3 x `Standard_D2ps_v6`, 2 vCPU, 8 GB, 4 GB heap, 30 GiB P4 Premium SSD OS disk | 3 | `1` |

Premium SSD is billed and performs by fixed tiers, so each storage figure sits on the smallest tier
at or above it.

¹ Primary shards for the component, violation and vulnerability indices. Every other index keeps 1.
Shard counts are not set in `config.yml`, and only take effect when an
index is created, so **at M, L and XL set them before the Nexus One index is first built**, with the request in
[Shards](../README.md#shards-3-for-three-indices-at-m-and-above).

An index built before the change keeps its count until it is rebuilt.

**Use `1` replica at every size here**, so a lost data node leaves a complete copy of the index on
the others. Use `0` on a single data node: it cannot place a replica, so `1` would leave the index yellow,
which still serves reads and writes.

Other things the cluster needs, none of which this configuration sets for you:

- **OpenSearch 3.x, and 3.8 recommended**, with the security plugin on, so basic auth and a password-protected user exist.
- **A user IQ Server owns**, with permission to create and write its own indices. Do not reuse the
  bootstrap admin.
- **Heap at half of RAM and no more than about 31 GB**, set in `jvm.options`, which is the standard
  OpenSearch guidance: 4 GB on `Standard_D2ps_v6`, 8 GB on `Standard_D4ps_v6`, and about 31 GB on
  `Standard_E8ps_v6`, where half its RAM would pass the cap.
- **Three dedicated cluster managers** at M and above, one per availability zone, holding no data, so
  losing one leaves a quorum. XS and S run none: one data node is its own cluster manager.
- **One node per availability zone** at M and above, so a zone outage costs one node rather than the
  cluster.
- **A private subnet**, reachable from the subnets IQ Server runs in and from nowhere else. A network
  security group on the OpenSearch subnet is what enforces that, since Azure allows outbound traffic
  from the IQ Server subnets by default.
- **Snapshots to a storage account**, through the `repository-azure` plugin. Nothing here backs the
  index up, and a lost index means a full rebuild.

**Put a Standard SKU internal load balancer in front of the data nodes**, and set
`opensearch_endpoint` to its frontend private IP, so IQ Server reaches one endpoint and replacing a data
node does not change its configuration. Create:

- **The load balancer** on the OpenSearch subnet, with a private frontend IP and a backend pool of the
  data nodes' NICs. The cluster managers stay out of the pool.
- **A TCP health probe on port 9200**, and a rule forwarding TCP 9200 to the pool through it. A TCP
  probe rather than HTTPS, because the cluster's certificate is from a private authority the probe would
  not trust.
- **An NSG rule allowing the `AzureLoadBalancer` service tag on TCP 9200**, at a higher priority than
  the subnet's deny-all rule. Without it the probes are refused and every backend reads as down.
- **Outbound internet access for the OpenSearch VMs**, which they need to install and update packages.
  A VM in a Standard internal load balancer's backend pool has no default outbound access, so attach
  a NAT gateway to the OpenSearch subnet.
- **With `opensearch_use_tls = true`, a data node certificate that names the load balancer's
  address.** The load balancer passes TLS through to the nodes, so IQ Server checks each node's
  certificate against `opensearch_endpoint`, and that address has to be in its subject alternative
  names.

Microsoft describes a Standard internal load balancer's backends and the NAT gateway they need for
outbound access in [What is Azure NAT Gateway?](https://learn.microsoft.com/en-us/azure/nat-gateway/nat-overview).

### TLS, and the JVM trust store

**IQ Server has no per-connection trust setting.** A certificate signed by a private certificate
authority is trusted only if that authority is in the trust store the JVM loads, and the way to name
one is the `javax.net.ssl.trustStore` system property.

**Copy the JVM's own trust store and add to the copy. Never replace it.** The same store serves IQ
Server's calls to the Sonatype data service, so a store holding only your private authority breaks
policy and vulnerability data while fixing OpenSearch.

**Set `opensearch_ca_pem` and the entrypoint does this for you**: it copies the JVM's trust store to
`/tmp/iq-truststore.jks` on the container's own disk, rebuilt at every start, adds the authority, and names the copy with
`javax.net.ssl.trustStore`. To build the store yourself instead, leave `opensearch_ca_pem` empty and
follow these steps.

The steps, run against a copy of the container image or in a build that produces one:

```bash
# The image sets no JAVA_HOME and puts no java or keytool on the PATH, so these
# use the JVM bundled under /opt/sonatype/nexus-iq-server.

# 1. Copy the JVM's trust store, outside the paths a volume is mounted over.
cp /opt/sonatype/nexus-iq-server/lib/security/cacerts /opt/sonatype/iq-truststore.jks

# 2. Add your certificate authority to the copy. The default password is "changeit".
/opt/sonatype/nexus-iq-server/bin/keytool -importcert -noprompt \
  -keystore /opt/sonatype/iq-truststore.jks -storepass changeit \
  -alias opensearch-ca -file /path/to/ca.crt

# 3. Confirm it is there, and that the public authorities still are.
/opt/sonatype/nexus-iq-server/bin/keytool -list -keystore /opt/sonatype/iq-truststore.jks -storepass changeit | grep -c 'trustedCertEntry'
```

Then name the copy in `java_opts`, which this configuration passes to the container as `JAVA_OPTS`:

```hcl
java_opts = "-Xms48g -Xmx48g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/heap-dump.hprof -XX:+ExitOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs -Djavax.net.ssl.trustStore=/opt/sonatype/iq-truststore.jks -Djavax.net.ssl.trustStorePassword=changeit"
```

The store is part of the image, so every container started from it has it. It is kept out of
`/sonatype-work`, because the Azure Files share is mounted over that path when the container runs
and would hide anything the image put there.

**A certificate from a public authority needs none of this**, because the JVM already trusts it. That
is the cheapest answer if your cluster can carry one.

**IQ Server also accepts a plain `http://` URI**, so a cluster in a private subnet can skip TLS
entirely by setting `opensearch_use_tls = false`. That sends the basic-auth password in clear text on
every request, and anything able to read traffic inside that subnet can read it.

**Use TLS with a private certificate authority and a copied trust store.** Use
`opensearch_use_tls = false` only for a proof of concept, and undo it afterwards.

## Important: Admin Port 8071 Not Exposed

The admin port 8071 is configured within the IQ Server container but **not exposed externally** through the Application Gateway. Only the main application port 8070 is accessible via port 80.

**Admin port access** is available through Container App console/exec sessions if needed for troubleshooting.
