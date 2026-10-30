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

> ² OpenSearch is part of this architecture at every size, not an optional extra. See [OpenSearch](#opensearch) for what it serves, what this architecture does and does not do about it, and which parts of the per-size cluster specification are not published yet.

> **Need more capacity?** For 10,000+ applications or multi-node deployments, use the [High Availability](../infra-azure-ha/) or [Kubernetes](../infra-azure-ha-k8s-helm/) architectures.

### Recommended `terraform.tfvars` by Size

<details>
<summary><strong>Size XS</strong> — Extra Small (< 500 applications)</summary>

```hcl
container_cpu        = 2.0                 # 2 vCPU
container_memory     = "16Gi"              # 16 GB
iq_docker_image      = "sonatype/nexus-iq-server:latest"
java_opts            = "-Xms12g -Xmx12g -XX:MaxDirectMemorySize=4g -XX:+UseG1GC -XX:+AlwaysPreTouch -Dinsight.threads.monitor=3 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_sku_name          = "B_Standard_B2ms"   # 2 vCores, 8 GB (burstable)
db_storage_mb        = 51200               # 50 GB
```
</details>

<details>
<summary><strong>Size S</strong> — Small (500 – 2,000 applications)</summary>

```hcl
container_cpu        = 4.0                 # 4 vCPU
container_memory     = "32Gi"              # 32 GB
iq_docker_image      = "sonatype/nexus-iq-server:latest"
java_opts            = "-Xms24g -Xmx24g -XX:MaxDirectMemorySize=6g -XX:+UseG1GC -XX:+AlwaysPreTouch -Dinsight.threads.monitor=5 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_sku_name          = "GP_Standard_D2s_v3" # 2 vCores, 8 GB
db_storage_mb        = 102400              # 100 GB
```
</details>

<details>
<summary><strong>Size M</strong> — Medium (2,000 – 10,000 applications)</summary>

```hcl
container_cpu        = 8.0                 # 8 vCPU
container_memory     = "64Gi"              # 64 GB
iq_docker_image      = "sonatype/nexus-iq-server:latest"
java_opts            = "-Xms48g -Xmx48g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/Java_Heap_logs -XX:+CrashOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_sku_name          = "GP_Standard_D8s_v3" # 8 vCores, 32 GB
db_storage_mb        = 102400              # 100 GB
```
</details>

### Database Sizing

| Size | DB SKU | vCores | Memory | Storage |
|------|:-------|:------:|:------:|:-------:|
| **XS** | B_Standard_B2ms (burstable) | 2 | 8 GB | 50 GB |
| **S** | GP_Standard_D2s_v3 | 2 | 8 GB | 100 GB |
| **M** | GP_Standard_D8s_v3 | 8 | 32 GB | 100 GB (auto-grow enabled) |

### OpenSearch

IQ Server uses an OpenSearch cluster for Advanced Search and for the Nexus One index behind the Nexus
One list pages, typeahead, and dashboard, and **it is required at every size this architecture
supports.** One cluster serves both features, through a single `search:` block in IQ Server's
`config.yml`: one endpoint, one set of credentials, and no second switch to turn on.

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
and one for Advanced Search.

| Index | What it holds |
|-------|---------------|
| `application` | Applications |
| `violation` | Policy violations |
| `waiver` | Policy waivers |
| `component` | Components |
| `vulnerability` | Vulnerabilities |
| `entity` | Organizations, application categories, component labels, policies, users, and license threat groups, which share one index |
| Advanced Search | The Advanced Search index, named from your own index configuration |

Each Nexus One index is created with **one primary shard**, which is the recommendation at every
published size. The `component`, `violation`, and `vulnerability` indices can be raised per tenant
through the configuration API, up to a ceiling of 12; `application`, `entity`, and `waiver` have no such
setting. **A shard count applies only when an index is created**, because OpenSearch fixes the primary
shard count at creation and an index cannot be resharded, so raising one has to be followed by a
rebuild.

**The Advanced Search index is the one IQ Server does not size.** It sends no shard count and no replica
count for that index, so the index gets whatever your cluster's default, or a matching index template,
gives it. On a self-managed cluster that default is **yours to choose**, which makes it a setting to pick on
purpose rather than one to inherit, and nothing in IQ Server reports what the index actually got. Read it off the live index with
`GET <index>/_settings`, never off `config.yml`.

#### Replicas

A replica is a full second copy of every shard, and it is what makes losing a data node survivable. It
costs the disk and the indexing work of that second copy.

**IQ Server's own default replica count is 0**, so an architecture that omits
`search.nexusOneIndexReplicas` gets no replica rather than a sensible default. This architecture sets
the value itself:

| Size | OpenSearch data nodes | Replica count |
|------|:---------------------:|:-------------:|
| **XS** | 1 | `0` |
| **S** | 1 | `0` |
| **M** | more than 1 | Not published yet |

**`0` at XS and S is a decision, not an omission.** A one-node cluster has nowhere to place a
replica, so asking for one leaves the index permanently yellow for no benefit, which makes a real
problem indistinguishable from this one. That is not a failure state: a yellow index is created, opens,
takes writes, and returns correct reads, because yellow means every primary shard is assigned and at
least one replica is not, and primaries serve every read and take every write. IQ Server never reads
cluster health, so no OpenSearch color is reported as an error, and the Index Manager's own `HEALTHY`
and `WARNING` bands describe how far behind the index is rather than how the cluster placed its shards.

What a single-node cluster does cost you is plain: **losing that node means rebuilding the index.**
There is nothing to fail over to.

A replica can be added to a live index with `PUT <index>/_settings`, so a first choice is not binding.
Give the Advanced Search index the same replica count through an index template, so both halves of
search survive losing a data node or neither does.

#### Plan for twice the index during a rebuild

A Nexus One index rebuild does not write into the index that is serving. It builds a complete new set of
indices and moves the aliases onto it once every pass has succeeded, then keeps the old set for
**30 minutes** after the cutover so a search already running against it is not destroyed underneath it.
That window is a fixed value in IQ Server with no setting.

So during a rebuild, and for half an hour afterwards, the cluster holds twice the Nexus One shards and
twice the Nexus One disk, plus the Advanced Search index. **Judge free storage against the doubled
figure, not the steady state.** A cluster that fits the index with 40% free is full during its own
rebuild, and a replica is a separate doubling that applies at the same time.

Reading the index size during a rebuild, or in the half hour after it, also gives you the doubled
number rather than what is really serving.

**A rebuild is not a backup.** A full rebuild of a large estate has been measured at about an hour and a
half, with search stale or absent throughout. A self-managed cluster takes whatever snapshots you schedule.

#### Per-size cluster specification

**Not published yet.** The data node count, node size, JVM heap, and storage for each size are awaiting
a per-size measurement. What is settled is the shape of the requirement: XS and S run one data node and M runs more than one, which is what
decides whether a replica can be placed at all.

<!-- TO BE ADDED (CLM-55937): the per-size specification and the M replica count above are CLM-55930's to publish.
     They need measurements that do not exist. The only OpenSearch sizing data today is one estate of
     about 105,700 applications, above XL's 80,000 ceiling, all taken at zero replicas, so it is not
     evidence for a number at any published size. Do not derive these values. -->

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

#### Azure Account Requirements
- Azure subscription with Contributor access
- Ability to create: Resource Groups, Virtual Networks, Container Apps, PostgreSQL, Application Gateway
- Key Vault access for secrets management

#### Required Azure Permissions
Your Azure account needs permissions for these services:
- **Resource Groups**: Create and manage resource groups
- **Compute**: Container Apps, Container App Environments, Container App Environment Storage
- **Networking**: Virtual Networks, subnets, Network Security Groups, Application Gateways, Public IPs, Private DNS Zones
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

   Example: `http://ref-arch-iq-abc123.westus2.cloudapp.azure.com`

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
container_cpu    = 4.0           # 4.0 vCPU
container_memory = "8Gi"         # 8GB RAM
iq_docker_image  = "sonatype/nexus-iq-server:latest"
java_opts        = "-Xms6g -Xmx6g -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"

# Database Configuration
db_name                          = "nexusiq"
db_username                      = "nexusiq"
db_password                      = "CHANGE_ME_STRONG_PASSWORD"  # Change this!
postgres_version                 = "15"
db_sku_name                      = "MO_Standard_E16s_v3"  # Memory Optimized (16 vCores, 128GB RAM)
db_storage_mb                    = 524288                 # 512GB storage
db_auto_grow_enabled             = true
db_backup_retention_days         = 7
db_geo_redundant_backup_enabled  = false
db_high_availability_enabled     = false

# Application Gateway Configuration
app_gateway_sku_name = "Standard_v2"
app_gateway_sku_tier = "Standard_v2"
app_gateway_capacity = 2

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
  - Application Gateway SSL termination support
- **Network Security Groups**: Least-privilege network access
- **Managed Identity**: Container Apps use system-assigned identity for secure access

## Reliability and Backup

This is a **single instance** deployment.
- **Single Instance**: One Container App replica running Sonatype IQ Server (runs in one zone at a time)
- **Single Zone Database**: PostgreSQL Flexible Server runs in one availability zone (unless HA enabled)
- **Zone Redundancy Available**: Infrastructure can be made zone-redundant (Application Gateway, database HA)
- **Automatic Restart**: Container Apps automatically restarts the container if it fails (may restart in different zone, causing brief downtime)
- **Database Backups**: Automated PostgreSQL backups with 7-day retention (configurable)
- **File Share Persistence**: Application data stored on Azure File Share survives container restarts

## Monitoring and Logging

- **Log Analytics**: Application logs centralized in Log Analytics workspace
- **Container App Logs**: Application and system logs with structured logging
- **Application Gateway Logs**: Access logs and diagnostic information
- **Azure Monitor**: Optional monitoring and alerting

## Persistent Storage

- **Azure File Share**: Shared storage for `/sonatype-work` directory using SMB protocol
- **Database**: PostgreSQL Flexible Server for application data
- **Auto-scaling Storage**: PostgreSQL storage scales automatically

## Networking

### Subnets
- **Public Subnet**: Application Gateway
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
| `opensearch_index_replicas` | `0` | Written as `search.nexusOneIndexReplicas`. Bounds-checked 0 to 10 by IQ Server |

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
- **No `nexusOne` block.** None is needed. The `search:` block is the switch.

### Specifying the cluster

The one measured sizing study ran about 105,700 applications on three AWS OpenSearch data nodes of
8 vCPU and 32 GB each, at zero replicas, and rebuilt 68.3 million documents in about 1 hour 30
minutes. That is above this guide's XL ceiling of 80,000 applications, and it was measured on AWS
rather than on Azure Virtual Machines, so treat the row below as a starting point and not as a
tested figure.

| Size | Data nodes | Per-node starting point | `opensearch_index_replicas` |
|---|---|---|---|
| XS | 1 | `Standard_D4s_v5`, 4 vCPU, 16 GB, 256 GB Premium SSD | `0` |
| S | 1 | `Standard_D4s_v5`, 4 vCPU, 16 GB, 512 GB Premium SSD | `0` |
| M | 3 | `Standard_D8s_v5`, 8 vCPU, 32 GB, 1 TB Premium SSD | **not yet published** |
| L | 3 | `Standard_D8s_v5`, 8 vCPU, 32 GB, 1 TB Premium SSD | **not yet published** |
| XL | 3 | `Standard_D8s_v5`, 8 vCPU, 32 GB, 2 TB Premium SSD | **not yet published** |

**`0` is the only workable value at XS and S**, because a single data node cannot place a replica:
the shard stays unassigned and the cluster sits yellow for ever. At M, L and XL the right value is
being measured and is not published yet, so pick `0` to run without redundancy or `1` to pay one
extra copy of the index for it, and expect this table to name a figure later.

Other things the cluster needs, none of which this configuration sets for you:

- **OpenSearch 2.x**, with the security plugin on, so basic auth and a password-protected user exist.
- **A user IQ Server owns**, with permission to create and write its own indices. Do not reuse the
  bootstrap admin.
- **Heap at half of RAM and no more than about 31 GB**, set in `jvm.options`, which is the standard
  OpenSearch guidance and the reason the per-node memory above is not larger.
- **One node per availability zone** at M and above, so a zone outage costs one node rather than the
  cluster.
- **A private subnet**, reachable from the subnet IQ Server runs in and from nowhere else. A network
  security group on the OpenSearch subnet is what enforces that, since Azure allows outbound traffic
  from the IQ Server subnet by default.
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

Then name the copy in `java_opts`, which this configuration passes to the container as `JAVA_OPTS`:

```hcl
java_opts = "-Xms6g -Xmx6g -Djava.util.prefs.userRoot=/sonatype-work/javaprefs -Djavax.net.ssl.trustStore=/sonatype-work/iq-truststore.jks -Djavax.net.ssl.trustStorePassword=changeit"
```

`/sonatype-work` is the Azure Files share, so the store survives a revision replacing the container.

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

**Admin port access** is available through Container App console/exec sessions if needed for troubleshooting.

