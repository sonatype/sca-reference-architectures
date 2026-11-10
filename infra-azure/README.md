# Sonatype IQ Reference Architecture - Azure Container Apps (Single Instance)

This directory contains Terraform configuration for deploying a **single-instance** Sonatype IQ Server on Azure using Container Apps with Workload Profiles.

---

## Sizing Guide

This single-instance architecture supports sizes **XS**, **S**, and **M**. Choose your size based on application count and daily evaluation volume:

| Size | Applications | Evaluations/Day | Compute | Java Heap | Instance Type | OpenSearch |
|------|:------------:|:---------------:|:-------:|:---------:|:-------------:|:----------:|
| **XS** ¹ | < 500 | < 1,000 | 2 vCPU / 16 GB | 12 GB | Container Apps (2.0 CPU / 16Gi) | Required ² |
| **S** ¹ | 500 - 2,000 | 1,000 - 5,000 | 4 vCPU / 32 GB | 24 GB | Container Apps (4.0 CPU / 32Gi) | Required ² |
| **M** | 2,000 - 10,000 | 5,000 - 10,000 | 8 vCPU / 64 GB | 48 GB | Container Apps (8.0 CPU / 64Gi) | Required ² |

> ¹ XS and S are projected sizing estimates. M has been validated through performance testing.

> ² Required for Advanced Search and the Nexus One index at every size, and not switched on for you: `search_engine` defaults to `lucene` in `variables.tf`, so a deployment that wants either feature sets it to `opensearch` and supplies the cluster's endpoint and credentials. See [OpenSearch](#opensearch) for what it serves, what this architecture does and does not do about it, and the per-size cluster specification.

> **Need more capacity?** For 10,000+ applications or multi-node deployments, use the [High Availability](../infra-azure-ha/) or [Kubernetes](../infra-azure-ha-k8s-helm/) architectures.

### Recommended `terraform.tfvars` by Size

<details>
<summary><strong>Size XS</strong> — Extra Small (< 500 applications)</summary>

```hcl
container_cpu        = 2.0                 # 2 vCPU
container_memory     = "16Gi"              # 16 GB
workload_profile_type = "D4"               # 4 cores, 16 GB per node
iq_docker_image      = "sonatype/nexus-iq-server:latest"
java_opts            = "-Xms12g -Xmx12g -XX:MaxDirectMemorySize=4g -XX:+UseG1GC -XX:+AlwaysPreTouch -Dinsight.threads.monitor=3 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_sku_name          = "GP_Standard_D2ds_v6" # 2 vCores, 8 GB
db_storage_mb        = 65536               # 64 GB
```
</details>

<details>
<summary><strong>Size S</strong> — Small (500 – 2,000 applications)</summary>

```hcl
container_cpu        = 4.0                 # 4 vCPU
container_memory     = "32Gi"              # 32 GB
workload_profile_type = "E4"               # 4 cores, 32 GB per node
iq_docker_image      = "sonatype/nexus-iq-server:latest"
java_opts            = "-Xms24g -Xmx24g -XX:MaxDirectMemorySize=6g -XX:+UseG1GC -XX:+AlwaysPreTouch -Dinsight.threads.monitor=5 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_sku_name          = "MO_Standard_E2ds_v6" # 2 vCores, 16 GB
db_storage_mb        = 131072              # 128 GB
```
</details>

<details>
<summary><strong>Size M</strong> — Medium (2,000 – 10,000 applications)</summary>

```hcl
container_cpu        = 8.0                 # 8 vCPU
container_memory     = "64Gi"              # 64 GB
workload_profile_type = "E8"               # 8 cores, 64 GB per node
iq_docker_image      = "sonatype/nexus-iq-server:latest"
java_opts            = "-Xms48g -Xmx48g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/Java_Heap_logs -XX:+CrashOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_sku_name          = "MO_Standard_E8ds_v6" # 8 vCores, 64 GB
db_storage_mb        = 131072              # 128 GB
file_share_quota     = 500                 # GB
```
</details>

### Database Sizing

| Size | DB SKU | vCores | Memory | Storage |
|------|:-------|:------:|:------:|:-------:|
| **XS** | GP_Standard_D2ds_v6 | 2 | 8 GB | 64 GB |
| **S** | MO_Standard_E2ds_v6 | 2 | 16 GB | 128 GB |
| **M** | MO_Standard_E8ds_v6 | 8 | 64 GB | 128 GB (auto-grow enabled) |

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

#### Seven indices in one shared cluster

A deployment running both features holds **seven indices on one cluster**: six for the Nexus One index
and one for Advanced Search. The index list, what each one holds, the one-primary-shard default, and
why a shard count can only be set when an index is created are the same on every cloud, so they are
stated once in the [top-level OpenSearch section](../README.md#opensearch) rather than repeated here.

#### Replicas

A replica is a full second copy of every shard, and it is what makes losing a data node
survivable. This architecture writes `nexusOneIndexReplicas` itself. When IQ Server is not
given a count, it uses 1:

| Size | OpenSearch data nodes | Replica count |
|------|:---------------------:|:-------------:|
| **XS** | 1 | `0` |
| **S** | 1 | `0` |
| **M** | 3 | `1` |

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
[cluster table](#specifying-the-cluster) below. At M the component, violation and vulnerability indices are
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
| **Terraform** | >= 1.2 | [Install Guide](https://developer.hashicorp.com/terraform/install) | Infrastructure as Code |
| **Azure CLI** | >= 2.0 | [Install Guide](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) | Azure API access |

#### Azure Account Requirements
- Azure subscription with Contributor access
- Ability to create: Resource Groups, Virtual Networks, Container Apps, PostgreSQL
- Key Vault access for secrets management

#### Required Azure Permissions
Your Azure account needs permissions for these services:
- **Resource Groups**: Create and manage resource groups
- **Compute**: Container Apps, Container App Environments, Container App Environment Storage
- **Networking**: Virtual Networks, subnets, Network Security Groups, Private DNS Zones
- **Database**: Azure Database for PostgreSQL Flexible Server, databases, firewall rules
- **Storage**: Storage Accounts, File Shares
- **Security**: Key Vault, Key Vault access policies, Managed Identities (system-assigned)
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
   cd /path/to/sca-example-terraform/infra-azure
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
   - Initial startup can take 5-10 minutes
   - Database migrations, if needed, run on first boot

2. **Access the web UI:**

   Use the application URL displayed at the end of the deployment.

   Example: `https://ca-ref-arch-iq.<environment domain>.westus2.azurecontainerapps.io`, the Container App's own address

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

> **PostgreSQL version.** Minimum PostgreSQL 15. Recommended, and the default for new
> deployments, PostgreSQL 18. An existing deployment sets `postgres_version` in
> `terraform.tfvars` to the version it runs today. Upgrading is the deployer's decision.

> **Upgrading an existing deployment.** These variable defaults changed. A deployment whose
> `terraform.tfvars` does not set a variable picks up the new default on its next apply. Set the
> values your deployment is running at in `terraform.tfvars` before applying.
>
> | Variable | Previous default | New default |
> |---|:---:|:---:|
> | `container_cpu` | 4.0 | 8.0 |
> | `container_memory` | `8Gi` | `64Gi` |
> | `java_opts` | 6 GB heap | 48 GB heap |
> | `db_sku_name` | `GP_Standard_D8s_v3` | `MO_Standard_E8ds_v6` |
> | `db_storage_mb` | 524288 | 131072 for a new server. An existing server keeps its size |
> | `workload_profile_type` | `D4`, fixed | `E8` |
>
> The Application Gateway, its public IP and the `app_gateway_*` variables are removed, so the
> next apply deletes them. IQ Server is then reached on the Container App's own HTTPS address,
> the `application_url` output, and the `application_gateway_*` outputs are gone.

### Configuration Variables

Edit `terraform.tfvars` to customize your deployment:

```hcl
# General Configuration
azure_region = "West US 2"  # Use West US 2 to avoid GP tier quota restrictions in East US
cluster_name = "ref-arch-iq" # Name prefix for every resource; change it to run several in one subscription

# Network Configuration
vnet_cidr           = "10.0.0.0/16"
public_subnet_cidr  = "10.0.1.0/24"
private_subnet_cidr = "10.0.8.0/23"
db_subnet_cidr      = "10.0.30.0/24"

# Container App Configuration
container_cpu         = 8.0           # 8 vCPU, Size M
container_memory      = "64Gi"        # 64 GB, Size M
workload_profile_type = "E8"          # 8 cores, 64 GB per node
iq_docker_image       = "sonatype/nexus-iq-server:latest"
java_opts             = "-Xms48g -Xmx48g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/Java_Heap_logs -XX:+CrashOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"

# Database Configuration
db_name                          = "nexusiq"
db_username                      = "nexusiq"
db_password                      = "CHANGE_ME_STRONG_PASSWORD"  # Change this!
postgres_version                 = "18"
db_sku_name                      = "MO_Standard_E8ds_v6"   # Memory Optimized (8 vCores, 64 GB), the Size M value
db_storage_mb                    = 131072                 # 128 GB, the Size M value
db_auto_grow_enabled             = true
db_backup_retention_days         = 7
db_geo_redundant_backup_enabled  = false
db_high_availability_enabled     = false

# Storage Configuration
storage_account_tier             = "Standard"
storage_account_replication_type = "LRS"
file_share_quota                 = 500

# Monitoring Configuration
log_retention_days = 30
enable_monitoring  = true

# Search Backend (optional) - see "Advanced Search with OpenSearch" below
search_engine = "lucene"

# Tags merged into every resource
common_tags = {
  owner      = "CHANGE_ME_EMAIL"
  project    = "CHANGE_ME_PROJECT"
  subproject = "CHANGE_ME_SUBPROJECT"
  department = "CHANGE_ME_DEPARTMENT"
  team       = "CHANGE_ME_TEAM"
}
```

**Important Settings:**
- **Single Instance** - Container App configured for exactly 1 replica (Sonatype IQ single instance requirement)
- **`db_password`** - Use a strong, unique password (required change)
- **`db_high_availability_enabled = false`** - Set to `true` for production to enable zone-redundant database
- **`db_geo_redundant_backup_enabled = false`** - Set to `true` for production for geo-redundant backups
- **Resource Names** - All Azure resources follow naming conventions (e.g., "rg-ref-arch-iq")

## Security Features

- **VNet Isolation**: Application runs in private subnets
- **Database Security**: PostgreSQL in isolated database subnet with private DNS
- **Secrets Management**: Database credentials stored in Azure Key Vault
- **Encryption**:
  - Azure File Share encrypted at rest
  - PostgreSQL encrypted at rest
  - HTTPS on the Container App's own address, with a certificate Azure manages. Plain HTTP is redirected to HTTPS
- **Network Security Groups**: Least-privilege network access
- **Managed Identity**: Container Apps use system-assigned identity for secure access

## Reliability and Backup

This is a **single instance** deployment.
- **Single Instance**: One Container App replica running Sonatype IQ Server (runs in one zone at a time)
- **Single Zone Database**: PostgreSQL Flexible Server runs in one availability zone (unless HA enabled)
- **Zone Redundancy Available**: Infrastructure can be made zone-redundant (database HA)
- **Automatic Restart**: Container Apps automatically restarts the container if it fails (may restart in different zone, causing brief downtime)
- **Database Backups**: Automated PostgreSQL backups with 7-day retention (configurable)
- **File Share Persistence**: Application data stored on Azure File Share survives container restarts

## Monitoring and Logging

- **Log Analytics**: Application logs centralized in Log Analytics workspace
- **Container App Logs**: Application and system logs with structured logging
- **Azure Monitor**: Optional monitoring and alerting

## Persistent Storage

- **Azure File Share**: Shared storage for `/sonatype-work` directory using SMB protocol
- **Database**: PostgreSQL Flexible Server for application data. Minimum PostgreSQL 15. Recommended, and the default for new deployments, PostgreSQL 18
- **Auto-scaling Storage**: PostgreSQL storage scales automatically

## Networking

### Subnets
- **Public Subnet**: Created with its NSG; nothing in this architecture is deployed into it
- **Private Subnet**: Container Apps (delegated to Container Apps infrastructure)
- **Database Subnet**: PostgreSQL Flexible Server (delegated to PostgreSQL)

### Security Groups
- **Public NSG**: Allows HTTP (80), HTTPS (443) from internet
- **Private NSG**: Allows HTTP/HTTPS traffic and Azure Load Balancer health probes
- **Database NSG**: Allows PostgreSQL (5432) from private subnet only

### Running several sizes in one subscription

Every resource name is built from `cluster_name`, so two deployments coexist in one Azure
subscription as long as they use different values:

```hcl
cluster_name = "iq-m"   # one deployment
cluster_name = "iq-l"   # another, in the same subscription
```

**The default reproduces the names this configuration has always used**, so a customer who sets
nothing sees no change.

Two Azure limits constrain the value, and the variable rejects a value that would break either:

- **A storage account name is globally unique across Azure**, lowercase alphanumeric only, and capped
  at 24 characters. The hyphens in `cluster_name` are stripped when it is built.
- **A Key Vault name is globally unique and capped at 24 characters.**

Both carry a random suffix, so the global uniqueness is handled already and only the length matters.
That is why the variable is capped at 14 characters rather than at Azure's 24.

**Two names do not move with `cluster_name`, and neither needs to.** The subnet names
(`snet-public`, `snet-private`, `snet-database`) and the network security group names are scoped
inside the virtual network and the resource group, which do move, so they cannot collide across
deployments. The private DNS zone `privatelink.postgres.database.azure.com` is Azure's own fixed name
for that zone and is shared by design.

## Advanced Search with OpenSearch

Sonatype IQ Server can keep its Advanced Search index in OpenSearch instead of the embedded Lucene
index. Pointing it at OpenSearch is what turns the Nexus One index on: the `search:` block alone does
it, and no other configuration key is involved.

Azure has no first-party managed OpenSearch service, so **OpenSearch here is a cluster you run
yourself on Azure Virtual Machines**. This configuration does not build that cluster. You build it,
then supply its endpoint and credentials, which keeps the cluster's lifecycle and its indexed data
independent of Terraform runs here.

### Turning it on

Set these in `terraform.tfvars`:

```hcl
search_engine             = "opensearch"
opensearch_endpoint       = "opensearch.internal.example.com"
opensearch_port           = 9200
opensearch_use_tls        = true
opensearch_username       = "iq-server"
opensearch_password       = "<strong password>"
opensearch_index_replicas = 0
```

| Variable | Default | What it does |
|---|---|---|
| `search_engine` | `lucene` | `lucene` writes no `search:` block at all. `opensearch` writes one and creates the credential secrets |
| `opensearch_endpoint` | `""` | Host name or IP of the cluster's client endpoint, no scheme and no port. Required when `search_engine` is `opensearch` |
| `opensearch_port` | `9200` | The port the cluster listens on |
| `opensearch_use_tls` | `true` | `true` builds an `https://` URI, `false` builds `http://` |
| `opensearch_username` | `""` | The user IQ Server authenticates as. Mandatory on this connection type |
| `opensearch_password` | `""` | That user's password. Delivered to the container app as a secret rather than a plain environment variable, the route `db_password` already takes. `sensitive` keeps it out of CLI output only, so it is plain text in `terraform.tfstate` |
| `opensearch_index_replicas` | `0` | Written as `nexusOne.connection.nexusOneIndexReplicas`. Bounds-checked 0 to 10 by IQ Server |

Leave `search_engine` at `lucene` and nothing changes: no secrets are created, and `config.yml` is
byte-identical to a deployment that never knew about this section.

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
    uri: https://opensearch.internal.example.com:9200
    username: 'iq-server'
    password: '<from the container app secret>'
    nexusOneIndexReplicas: 0
```

The two credentials are single-quoted, and the entrypoint appends them with `printf` rather than
substituting them into the template with `sed`. A single-quoted YAML scalar is literal, so a `|`,
`&`, `\` or ` #` in the password is only that character, and nothing in the value can change the
file's structure. The one character YAML gives meaning to inside single quotes is `'` itself, which
doubles. The entrypoint also prints the generated file with every `password:` line redacted, so
neither credential reaches Log Analytics.

Three things about that block are deliberate:

- **`type: http` with basic auth.** The `aws` connection type signs each request with an AWS
  credential, and Azure has nothing to sign with, so the HTTP type with a user name and a password is
  the only option. Both fields are mandatory and IQ Server refuses to start without them.
- **`mode: OPENSEARCH` is written explicitly.** Omitting `mode` defaults to `HYBRID`, which writes
  every batch to the embedded Lucene index as well and cannot revert an index generation.
- **A `nexusOne.connection` block naming the same cluster.** The Nexus One index builds its
  connection from this block alone, and `nexusOneIndexReplicas` is read from it.

### Specifying the cluster

**M and L are measured on Azure; XS, S and XL are not.** The data node types at M and L are the
measured types, `Standard_D2ps_v6` and `Standard_D4ps_v6`. XS uses `Standard_D2pls_v6`, S uses
`Standard_D2ps_v6` and XL `Standard_E8ps_v6`, which give the same memory as the AWS and GCP data
nodes at those sizes. At XS that is one more vCPU, since `Standard_D2pls_v6` is the smallest Dplsv6
size. Storage per node is the published size, chosen at or above the measured use. The measurements are on [the OpenSearch sizing pages](https://sonatype.atlassian.net/wiki/spaces/INSIGHT/pages/2866971307). The cluster
managers are measured at M and L on `Standard_D2pls_v6`; the XL managers are `Standard_D2ps_v6`, chosen
at the AWS equivalent, `m8g.large.search`. Every manager has a 30 GiB P4 Premium SSD OS disk, as the
measured VMs had, and takes half its RAM as heap.

| Size | Data nodes | Data node | Storage per node | Cluster managers | Shards ¹ | `opensearch_index_replicas` |
|---|---|---|---|---|---|---|
| XS | 1 | `Standard_D2pls_v6`, 2 vCPU, 4 GB | 25 GB, on a P4 Premium SSD of 32 GiB | none | 1 | `0` |
| S | 1 | `Standard_D2ps_v6`, 2 vCPU, 8 GB | 50 GB, on a P6 Premium SSD of 64 GiB | none | 1 | `0` |
| M | 3 | `Standard_D2ps_v6`, 2 vCPU, 8 GB | 100 GB, on a P10 Premium SSD of 128 GiB | 3 x `Standard_D2pls_v6`, 2 vCPU, 4 GB, 2 GB heap, 30 GiB P4 Premium SSD OS disk | 3 | `1` |
| L | 3 | `Standard_D4ps_v6`, 4 vCPU, 16 GB | 150 GB, on a P15 Premium SSD of 256 GiB | 3 x `Standard_D2pls_v6`, 2 vCPU, 4 GB, 2 GB heap, 30 GiB P4 Premium SSD OS disk | 3 | `1` |
| XL | 3 | `Standard_E8ps_v6`, 8 vCPU, 64 GB | 250 GB, on a P15 Premium SSD of 256 GiB | 3 x `Standard_D2ps_v6`, 2 vCPU, 8 GB, 4 GB heap, 30 GiB P4 Premium SSD OS disk | 3 | `1` |

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

**`0` is the only workable value at XS and S**, because a single data node cannot place a replica:
the shard stays unassigned and the cluster sits yellow for ever. At M, L and XL use `1`, so a lost
data node leaves a complete copy of the index on the others.

Other things the cluster needs, none of which this configuration sets for you:

- **OpenSearch 2.x**, with the security plugin on, so basic auth and a password-protected user exist.
- **A user IQ Server owns**, with permission to create and write its own indices. Do not reuse the
  bootstrap admin.
- **Heap at half of RAM and no more than about 31 GB**, set in `jvm.options`, which is the standard
  OpenSearch guidance: 2 GB on `Standard_D2pls_v6`, 4 GB on `Standard_D2ps_v6`, 8 GB on `Standard_D4ps_v6`, and about 31 GB on
  `Standard_E8ps_v6`, where half its RAM would pass the cap.
- **Three dedicated cluster managers** at M and above, one per availability zone, holding no data, so
  losing one leaves a quorum. XS and S run none: one data node is its own cluster manager.
- **One node per availability zone** at M and above, so a zone outage costs one node rather than the
  cluster.
- **A private subnet**, reachable from the subnet IQ Server runs in and from nowhere else. A network
  security group on the OpenSearch subnet is what enforces that, since Azure allows outbound traffic
  from the IQ Server subnet by default.
- **Snapshots to a storage account**, through the `repository-azure` plugin. Nothing here backs the
  index up, and a lost index means a full rebuild at the cost quoted above.

**Put a Standard SKU internal load balancer in front of the data nodes at M, L and XL**, and set
`opensearch_endpoint` to its frontend private IP, so IQ Server reaches one endpoint and replacing a data
node does not change its configuration. This is how the Azure M and L measurements ran. Create:

- **The load balancer** on the OpenSearch subnet, with a private frontend IP and a backend pool of the
  data nodes' NICs. The cluster managers stay out of the pool.
- **A TCP health probe on port 9200**, and a rule forwarding TCP 9200 to the pool through it. A TCP
  probe rather than HTTPS, because the cluster's certificate is from a private authority the probe would
  not trust.
- **An NSG rule allowing the `AzureLoadBalancer` service tag on TCP 9200**, at a higher priority than
  the subnet's deny-all rule. Without it the probes are refused and every backend reads as down.
- **Outbound internet access for the OpenSearch VMs**, which they need to install and update packages.
  A VM in a Standard internal load balancer's backend pool has no default outbound access, so the
  measurements attached a NAT gateway to the OpenSearch subnet.
- **With `opensearch_use_tls = true`, a data node certificate that names the load balancer's
  address.** The load balancer passes TLS through to the nodes, so IQ Server checks each node's
  certificate against `opensearch_endpoint`, and that address has to be in its subject alternative
  names.

Microsoft describes a Standard internal load balancer's backends and the NAT gateway they need for
outbound access in [What is Azure NAT Gateway?](https://learn.microsoft.com/en-us/azure/nat-gateway/nat-overview).

At XS and S, with one data node, `opensearch_endpoint` can name that node directly.

### TLS, and the JVM trust store

**IQ Server has no per-connection trust setting.** A certificate signed by a private certificate
authority is trusted only if that authority is in the trust store the JVM loads, and the way to name
one is the `javax.net.ssl.trustStore` system property.

**Copy the JVM's own trust store and add to the copy. Never replace it.** The same store serves IQ
Server's calls to the Sonatype data service, so a store holding only your private authority breaks
policy and vulnerability data while fixing OpenSearch.

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
java_opts = "-Xms48g -Xmx48g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/Java_Heap_logs -XX:+CrashOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs -Djavax.net.ssl.trustStore=/opt/sonatype/iq-truststore.jks -Djavax.net.ssl.trustStorePassword=changeit"
```

The store is part of the image, so every container started from it has it. It is kept out of
`/sonatype-work`, because the Azure Files share is mounted over that path when the container runs
and would hide anything the image put there.

This configuration passes no registry credentials, so the derived image has to be pullable without
them. `infra-azure-ha` takes `container_registry_server`, `container_registry_username` and
`container_registry_password` for a private registry.

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

The admin port 8071 is configured within the IQ Server container but **not exposed externally**. The Container App's ingress reaches only the main application port 8070, over HTTPS on port 443.

**Admin port access** is available through Container App console/exec sessions if needed for troubleshooting.

