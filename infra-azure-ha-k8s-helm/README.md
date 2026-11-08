# Sonatype IQ Reference Architecture - Azure AKS with Helm (High Availability)

This directory contains Terraform configuration for deploying Sonatype IQ Server on Azure using AKS (Azure Kubernetes Service) with Helm in a **High Availability configuration** with auto-scaling and multi-zone deployment.

---

## Sizing Guide

This AKS HA architecture supports sizes **M**, **L**, and **XL**. Choose your size based on application count and daily evaluation volume:

| Size | Applications | Evaluations/Day | Nodes | Compute (per node) | Java Heap | Instance Type | OpenSearch |
|------|:------------:|:---------------:|:-----:|:-------------------:|:---------:|:-------------:|:----------:|
| **M** | 2,000 - 10,000 | 5,000 - 10,000 | 2 | 8 vCPU / 64 GB | 48 GB | Standard_E8ps_v6 (ARM) | Required ¹ |
| **L** | 10,000 - 20,000 | 10,000 - 20,000 | 3 | 8 vCPU / 64 GB | 48 GB | Standard_E8ps_v6 (ARM) | Required ¹ |
| **XL** | 20,000 - 80,000 | 20,000+ | 4 | 16 vCPU / 128 GB | 96 GB | Standard_E16ps_v6 (ARM) | Required ¹ |

> All sizes validated through performance testing. Expected evaluation throughput with continuous monitoring running: ~310 evals/hour/node (M/L) or ~405 evals/hour/node (XL).

<!-- TO BE UPDATED (CLM-55927): the ~310 and ~405 evals/hour figures above are awaiting a
     re-measurement. Leave the numbers alone until it lands. The qualifier that they are measured with
     continuous monitoring running was added so a reader does not take them as general evaluation
     throughput. -->

> ¹ Required for Advanced Search and the Nexus One index at every size, and not switched on for you: `search_engine` defaults to `lucene` in `variables.tf`, so a deployment that wants either feature sets it to `opensearch` and supplies the cluster's endpoint and credentials. See [OpenSearch](#opensearch) for what it serves, what this architecture does and does not do about it, and the per-size cluster specification.

> **ARM instances recommended.** Eps_v6 costs 47% less on demand than the x86 equivalent Esv7 (`Standard_E8ps_v6` against `Standard_E8s_v7` in eastus, list prices in November 2026).

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
db_sku_name          = "GP_Standard_D8ds_v6" # 8 vCores, 32 GB
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
db_sku_name          = "GP_Standard_D8ds_v6" # 8 vCores, 32 GB
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
db_sku_name          = "MO_Standard_E16ds_v6" # 16 vCores, 128 GB
db_high_availability_mode = "ZoneRedundant"
storage_account_tier = "Premium"           # Required for NFS with AKS
storage_account_replication_type = "ZRS"
```
</details>

### Database Sizing

| Size | DB SKU | vCores | Memory | Storage |
|------|:-------|:------:|:------:|:-------:|
| **M** | GP_Standard_D8ds_v6 | 8 | 32 GB | 100 GB (auto-grow) |
| **L** | GP_Standard_D8ds_v6 | 8 | 32 GB | 200 GB to 1 TB (auto-grow) |
| **XL** | MO_Standard_E16ds_v6 | 16 | 128 GB | 500 GB to 2 TB (auto-grow) |

### Shared Storage (Azure Files Premium ZRS)

| Size | Tier | Protocol | Estimated Capacity |
|------|:-----|:--------:|:------------------:|
| **M** | Premium | SMB/NFS | 100 – 500 GB |
| **L** | Premium | SMB/NFS | 500 GB – 1.5 TB |
| **XL** | Premium | NFS (required) | 1.5 TB – 4 TB |

> Premium SSD with ZRS redundancy is recommended for AKS deployments requiring NFS access mode (ReadWriteMany).

### OpenSearch

IQ Server uses an OpenSearch cluster for Advanced Search and for the Nexus One index behind the Nexus
One list pages, typeahead, and dashboard, and **both features need it at every size this architecture
supports.** One cluster serves both, through a single `search:` block in IQ Server's `config.yml`: one
endpoint, one set of credentials, and nothing extra to switch on per feature.

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

#### Seven indices in one shared cluster

A deployment running both features holds **seven indices on one cluster**: six for the Nexus One index
and one for Advanced Search. The index list, what each one holds, the one-primary-shard default, and
why a shard count can only be set when an index is created are the same on every cloud, so they are
stated once in the [top-level OpenSearch section](../README.md#opensearch) rather than repeated here.

#### Replicas

A replica is a full second copy of every shard, and it is what makes losing a data node
survivable. **IQ Server's own default depends on the release.** Releases that include
CLM-55924 use 1 replica, or 0 on a cluster with exactly one data node. Earlier releases use 0.
So this architecture sets `nexusOneIndexReplicas` itself rather than inheriting that
default:

| Size | OpenSearch data nodes | Replica count |
|------|:---------------------:|:-------------:|
| **M** | 3 | `1` |
| **L** | 3 | `1` |
| **XL** | 3 | `1` |

The rules behind this, including what a yellow index does and does not mean and how to give the
Advanced Search index a matching replica count, are in the
[top-level OpenSearch section](../README.md#replicas-each-architecture-sets-the-count).

#### Plan for twice the index during a rebuild

A Nexus One index rebuild builds a complete new set of indices and keeps the old set for 30 minutes
after the cutover, so the cluster holds twice the Nexus One shards and twice the Nexus One disk for the
whole run and for half an hour afterwards. **Judge free storage against the doubled figure, not the
steady state.** A replica is a separate doubling that applies at the same time. The full rules, and why
a rebuild is not a backup, are in the
[top-level OpenSearch section](../README.md#plan-for-twice-the-index-during-a-rebuild).

#### Per-size cluster specification

The data node type and count, storage per node, shards and replicas for each size are in the
[cluster table](#specifying-the-cluster) below. At M, L and XL the component, violation and vulnerability indices are
created with 3 primary shards and every other index with 1; at XS and S every index has 1. The
shard counts are set through the configuration API before the first build, as shown there.

See the [top-level OpenSearch section](../README.md#opensearch) for the full planning rules.

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
- Zone-redundant resource support in target region (default: East US 2)

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

   Example: `http://nexus-iq-ha-abc123.eastus2.cloudapp.azure.com`

3. **Login credentials:**
   - **Username:** `admin`
   - **Password:** `admin123` (change immediately!)

---

## Teardown / Cleanup

> **Your OpenSearch cluster is not part of this.** This architecture never creates the cluster, so `./tf-destroy.sh` does not delete it or its indices. Remove it separately when you no longer need it.

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

> **Upgrading an existing deployment.** These variable and value defaults changed. A deployment whose
> `terraform.tfvars` does not set a variable picks up the new default on its next apply, and
> `helm-upgrade.sh` applies the new `helm-values.yaml`. Set the values your deployment is running at
> before applying.
>
> | Setting | Previous default | New default |
> |---|:---:|:---:|
> | `node_instance_type` | `Standard_D8s_v3` | `Standard_E8ps_v6` |
> | `kubernetes_version` | `1.27` | `1.33.3` |
> | `db_sku_name` | `GP_Standard_D8s_v3` | `MO_Standard_E16ds_v6` |
> | `db_storage_mb`, `db_storage_tier` | 65536, `P6`, fixed | 131072, `P10`, grows automatically |
> | `iq_server.resources` in `helm-values.yaml` | 4 to 6 CPU, 16 to 24 GB | 6 to 8 CPU, 48 to 56 GB |
> | `iq_server.javaOpts` in `helm-values.yaml` | 24 GB heap | 48 GB heap |

### Configuration Variables

Edit `terraform.tfvars` to customize your deployment:

```hcl
# Azure Configuration
azure_region = "eastus2"
environment  = "prod"
cluster_name = "nexus-iq-ha"

# Network Configuration
vnet_cidr          = "10.1.0.0/16"
public_subnet_cidr = "10.1.1.0/24"
aks_subnet_cidr    = "10.1.10.0/23"  # /23 provides more IPs for AKS
db_subnet_cidr     = "10.1.20.0/24"

# AKS Configuration
kubernetes_version      = "1.33.3"
node_instance_type      = "Standard_E8ps_v6" # 8 vCPU, 64GB RAM (ARM), Size M and L
node_group_min_size     = 2
node_group_max_size     = 6
node_group_desired_size = 3
node_disk_size          = 50

# PostgreSQL Configuration (Zone-Redundant HA)
postgres_version                 = "15"
db_sku_name                      = "MO_Standard_E16ds_v6" # Memory Optimized: 16 vCores, 128GB RAM
db_high_availability_mode        = "ZoneRedundant"
db_storage_mb                    = 131072 # 128GB, grows automatically
db_storage_tier                  = "P10"
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
nexus_iq_version         = "1.195.0"
nexus_iq_license         = ""
nexus_iq_admin_password  = "admin123"
nexus_iq_replica_count   = 3
nexus_iq_memory_request  = "48Gi"
nexus_iq_memory_limit    = "56Gi"
nexus_iq_cpu_request     = "6"
nexus_iq_cpu_limit       = "8"

# Helm Configuration
helm_chart_version = "195.0.0"
helm_namespace     = "nexus-iq"

# Search Backend (optional) - see "Advanced Search with OpenSearch" below
search_engine = "lucene"

# Tags merged on top of the four this root sets itself
common_tags = {
  owner      = "CHANGE_ME_EMAIL"
  project    = "CHANGE_ME_PROJECT"
  subproject = "CHANGE_ME_SUBPROJECT"
  department = "CHANGE_ME_DEPARTMENT"
  team       = "CHANGE_ME_TEAM"
}
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
- **`node_group_max_size = 6`** - Maximum AKS node capacity
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
- **Database**: PostgreSQL Flexible Server (zone-redundant) for application data
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

### Running several sizes in one subscription

Every resource name is built from `cluster_name`, so two deployments coexist in one Azure
subscription as long as they use different values:

```hcl
cluster_name = "iq-m-aks"   # one deployment
cluster_name = "iq-l-aks"   # another, in the same subscription
```

**The default reproduces the names this configuration has always used**, so a customer who sets
nothing sees no change.

One Azure limit constrains the value, and the variable rejects a value that would break it:

**A storage account name is globally unique across Azure**, lowercase alphanumeric only, and capped
at 24 characters. This root builds it as `st<cluster_name without hyphens>iqha`, so the variable is
capped at 18 characters once its hyphens are removed.

**That name carries no random suffix**, unlike the two Container Apps roots, so the value has to be
one nobody else on Azure has used rather than merely one this subscription has not. An apply fails
with `StorageAccountAlreadyTaken` if it is taken. This root creates no Key Vault.

**The subnet names (`snet-public`, `snet-aks`, `snet-database`) do not move with `cluster_name`, and
do not need to**, because they are scoped inside the virtual network, which does move. The private
DNS zone `privatelink.postgres.database.azure.com` is Azure's own fixed name for that zone and is
shared by design.

## Advanced Search with OpenSearch

Sonatype IQ Server can keep its Advanced Search index in OpenSearch instead of the embedded Lucene
index. Pointing it at OpenSearch is what turns the Nexus One index on: the `search:` block alone does
it, and no other configuration key is involved.

Azure has no first-party managed OpenSearch service, so **OpenSearch here is a cluster you run
yourself on Azure Virtual Machines**. This configuration does not build that cluster. You build it,
then supply its endpoint and credentials, which keeps the cluster's lifecycle and its indexed data
independent of Terraform runs here.

### Turning it on

Set these in `terraform.tfvars`. **`helm-install.sh` and `helm-upgrade.sh` read them out of that
file**, through the shared `search-values.sh`, so they see only what is written there and never a
variable default. Write every one of them:

```hcl
search_engine             = "opensearch"
opensearch_endpoint       = "opensearch.internal.example.com"
opensearch_port           = 9200
opensearch_use_tls        = true
opensearch_username       = "iq-server"
opensearch_password       = "<strong password>"
opensearch_index_replicas = 1
```

| Variable | Default | What it does |
|---|---|---|
| `search_engine` | `lucene` | `lucene` writes no `search:` block at all. `opensearch` writes one on both install and upgrade |
| `opensearch_endpoint` | `""` | Host name or IP of the cluster's client endpoint, no scheme and no port. Required when `search_engine` is `opensearch` |
| `opensearch_port` | `9200` | The port the cluster listens on |
| `opensearch_use_tls` | `true` | `true` builds an `https://` URI, `false` builds `http://` |
| `opensearch_username` | `""` | The user IQ Server authenticates as. Mandatory on this connection type |
| `opensearch_password` | `""` | That user's password. This root has no Key Vault, so `helm-install.sh` and `helm-upgrade.sh` write it into `helm-values-runtime.yaml`, which `.gitignore` excludes. That is the route `database_password` already takes. `sensitive` keeps it out of CLI output only, so it is plain text in `terraform.tfstate` |
| `opensearch_index_replicas` | `1` | Written as `nexusOne.connection.nexusOneIndexReplicas`. Bounds-checked 0 to 10 by IQ Server |

Leave `search_engine` at `lucene` and nothing changes, and `helm-values-runtime.yaml` is
byte-identical to a deployment that never knew about this section.

### What reaches IQ Server's configuration

IQ Server's configuration on this root comes from `helm-values.yaml` rather than from Terraform, so
`helm-install.sh` and `helm-upgrade.sh` append the block to `helm-values-runtime.yaml` under
`iq_server.config:`. Both call `write_search_block` in `search-values.sh`, so an upgrade writes the
same block an install writes. An upgrade rebuilds that file from `helm-values.yaml` and passes no
`--reuse-values`, so without that shared step the block would be absent from the upgraded release and
IQ Server would fall back to Lucene:

```yaml
iq_server:
  config:
    sonatypeWork: "/sonatype-work/clm-server"
    clusterDirectory: "/sonatype-work/clm-cluster"
    search:
      type: http
      mode: OPENSEARCH
      uri: 'https://opensearch.internal.example.com:9200'
      username: 'iq-server'
      password: '<from terraform.tfvars>'
    nexusOne:
      connection:
        type: http
        uri: 'https://opensearch.internal.example.com:9200'
        username: 'iq-server'
        password: '<from terraform.tfvars>'
        nexusOneIndexReplicas: 1
```

The two credentials are single-quoted, and `write_search_block` appends them with `printf` through a
file rather than through an `awk -v` assignment. A single-quoted YAML scalar is literal, so a `|`,
`&`, `\` or ` #` in the password is only that character, and nothing in the value can change the
file's structure. The one character YAML gives meaning to inside single quotes is `'` itself, which
doubles.

**Nothing about it is committed to `helm-values.yaml`.** That file is rewritten by a `sed` whose
`password: ""` pattern carries no line anchor, so a committed OpenSearch password key would be
overwritten with the database password. The block is appended after that `sed` runs, for the same
reason.

Three things about that block are deliberate:

- **`type: http` with basic auth.** The `aws` connection type signs each request with an AWS
  credential, and Azure has nothing to sign with, so the HTTP type with a user name and a password is
  the only option. Both fields are mandatory and IQ Server refuses to start without them.
- **`mode: OPENSEARCH` is written explicitly.** Omitting `mode` defaults to `HYBRID`, which writes
  every batch to the embedded Lucene index as well and cannot revert an index generation.
- **A `nexusOne.connection` block naming the same cluster.** The Nexus One index builds its
  connection from this block alone, and `nexusOneIndexReplicas` is read from it.

### Specifying the cluster

The one measured sizing study ran an estate larger than this guide's XL ceiling of 80,000
applications, on three AWS OpenSearch data nodes of 8 vCPU and 32 GB each, at zero replicas. It was
measured on AWS rather than on Azure Virtual Machines, so treat the row below as a starting point
and not as a tested figure.

This root covers M, L and XL, so the XS and S rows are in the single-instance root's README instead.

| Size | Data nodes | Per-node starting point | Storage per node | Shards ¹ | `opensearch_index_replicas` |
|---|---|---|---|---|---|
| M | 3 | `Standard_D8ps_v6`, 8 vCPU, 32 GB | 100 GB, on a P10 Premium SSD of 128 GiB | 3 | `1` |
| L | 3 | `Standard_D8ps_v6`, 8 vCPU, 32 GB | 150 GB, on a P15 Premium SSD of 256 GiB | 3 | `1` |
| XL | 3 | `Standard_E8ps_v6`, 8 vCPU, 64 GB | 250 GB, on a P15 Premium SSD of 256 GiB | 3 | `1` |

Premium SSD is billed and performs by fixed tiers, so each storage figure sits on the smallest tier
at or above it.

¹ Primary shards for the component, violation and vulnerability indices. Every other index keeps 1.
Shard counts are held in IQ Server's database, not in `config.yml`, and only take effect when an
index is created, so **at M, L and XL set them before the Nexus One index is first built**, with one
request to the configuration API as an administrator:

```bash
curl -u admin -X PUT -H 'Content-Type: application/json' \
  -d '{"nexusOneIndexComponentShards": 3, "nexusOneIndexViolationShards": 3, "nexusOneIndexVulnerabilityShards": 3}' \
  https://<your IQ Server URL>/api/v2/config
```

An index built before the change keeps its count until it is rebuilt.

**Use `1` replica at every size here**, so a lost data node leaves a complete copy of the index on
the others. `0` is the only workable value on a single data node, because that node cannot place a
replica: the shard stays unassigned and the cluster sits yellow for ever.

Other things the cluster needs, none of which this configuration sets for you:

- **OpenSearch 2.x**, with the security plugin on, so basic auth and a password-protected user exist.
- **A user IQ Server owns**, with permission to create and write its own indices. Do not reuse the
  bootstrap admin.
- **Heap at half of RAM and no more than about 31 GB**, set in `jvm.options`, which is the standard
  OpenSearch guidance and the reason the per-node memory above is not larger.
- **One node per availability zone** at M and above, so a zone outage costs one node rather than the
  cluster.
- **A private subnet**, reachable from the AKS subnet and from nowhere else. A network security group
  on the OpenSearch subnet is what enforces that, since Azure allows outbound traffic from the AKS
  subnet by default.
- **Snapshots to a storage account**, through the `repository-azure` plugin. Nothing here backs the
  index up, and a lost index means a full rebuild at the cost quoted above.

### TLS, and the JVM trust store

**IQ Server has no per-connection trust setting.** A certificate signed by a private certificate
authority is trusted only if that authority is in the trust store the JVM loads, and the way to name
one is the `javax.net.ssl.trustStore` system property.

**Copy the JVM's own trust store and add to the copy. Never replace it.** The same store serves IQ
Server's calls to the Sonatype data service, so a store holding only your private authority breaks
policy and vulnerability data while fixing OpenSearch.

The steps, run against a copy of the container image or in a build that produces one:

```bash
# 1. Copy the JVM's trust store out of the image.
cp "$JAVA_HOME/lib/security/cacerts" /sonatype-work/iq-truststore.jks

# 2. Add your certificate authority to the copy. The default password is "changeit".
keytool -importcert -noprompt \
  -keystore /sonatype-work/iq-truststore.jks -storepass changeit \
  -alias opensearch-ca -file /path/to/ca.crt

# 3. Confirm it is there, and that the public authorities still are.
keytool -list -keystore /sonatype-work/iq-truststore.jks -storepass changeit | grep -c 'trustedCertEntry'
```

Then name the copy in `iq_server.javaOpts` in `helm-values.yaml`, which the chart passes to the pod.
This root declares no `java_opts` variable, so the value is edited in that file:

```yaml
iq_server:
  javaOpts: "-Xms24g -Xmx24g -XX:+UseG1GC -Djava.util.prefs.userRoot=/sonatype-work/javaprefs -Djavax.net.ssl.trustStore=/sonatype-work/iq-truststore.jks -Djavax.net.ssl.trustStorePassword=changeit"
```

`/sonatype-work` is the Azure Files share every pod mounts, so one copy of the store serves all of
them and survives a pod being replaced.

**A certificate from a public authority needs none of this**, because the JVM already trusts it. That
is the cheapest answer if your cluster can carry one.

**IQ Server also accepts a plain `http://` URI**, so a cluster in a private subnet can skip TLS
entirely by setting `opensearch_use_tls = false`. That sends the basic-auth password in clear text on
every request, and anything able to read traffic inside that subnet can read it.

**The recommendation is TLS with a private certificate authority and a copied trust store.** The cost
is one `keytool` command and one extra JVM argument, paid once. Plaintext puts a long-lived
credential on the wire on every request, and a subnet is not a confidentiality boundary: a
misconfigured peering, a diagnostic VM, or a later change to the network makes that traffic readable
by something nobody intended. Use `opensearch_use_tls = false` only to get a proof of concept
running, and treat it as a thing to undo.

## Important: Admin Port 8071 Not Exposed

The admin port 8071 is configured within the IQ Server container but **not exposed externally** through the Application Gateway. Only the main application port 8070 is accessible via port 80.

**Admin port access** is available through Kubernetes exec sessions if needed for troubleshooting.
