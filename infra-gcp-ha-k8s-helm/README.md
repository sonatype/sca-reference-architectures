# Sonatype IQ Reference Architecture - GCP GKE with Helm (High Availability)

This directory contains Terraform configuration for deploying Sonatype IQ Server on GCP using GKE (Google Kubernetes Engine) with Helm in a **High Availability configuration** with auto-scaling and multi-zone deployment.

---

## Sizing Guide

This GKE HA architecture supports sizes **M**, **L**, and **XL**. Choose your size based on application count and daily evaluation volume:

| Size | Applications | Evaluations/Day | Nodes | Compute (per node) | Java Heap | Machine Type | OpenSearch |
|------|:------------:|:---------------:|:-----:|:-------------------:|:---------:|:------------:|:----------:|
| **M** | 2,000 - 10,000 | 5,000 - 10,000 | 2 | 8 vCPU / 64 GB | 48 GB | n4a-highmem-8 (ARM) | Required ¹ |
| **L** | 10,000 - 20,000 | 10,000 - 20,000 | 3 | 8 vCPU / 64 GB | 48 GB | n4a-highmem-8 (ARM) | Required ¹ |
| **XL** | 20,000 - 80,000 | 20,000+ | 4 | 16 vCPU / 128 GB | 96 GB | n4a-highmem-16 (ARM) | Required ¹ |

> All sizes validated through performance testing on GCP ARM instances. Evaluations an hour per instance, measured on `infra-gcp-ha` and sustained in testing, not a limit: 2,250 at M on 2 instances. L and XL are not measured.

> ¹ Required for Advanced Search and the Nexus One index at every size, and not switched on for you: `search_engine` defaults to `lucene` in `variables.tf`, so a deployment that wants either feature sets it to `opensearch` and supplies the cluster's endpoint and credentials. See [OpenSearch](#opensearch) for what it serves, what this architecture does and does not do about it, and the per-size cluster specification.

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
db_instance_tier        = "db-custom-N4-8-65536" # 8 vCPU, 64 GB, N4 series (Enterprise)
db_disk_provisioned_iops = 8000
db_availability_type    = "REGIONAL"
db_disk_size            = 128              # GB
db_max_disk_size        = 500
filestore_tier          = "BASIC_HDD"
filestore_capacity_gb   = 1024             # 1 TiB
```
In `helm-values.yaml`:

```yaml
iq_server:
  resources:
    requests:
      cpu: "6"
      memory: "48Gi"
    limits:
      cpu: "8"
      memory: "56Gi"
  javaOpts: "-Xms48g -Xmx48g -XX:MaxDirectMemorySize=4g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/Java_Heap_logs -XX:+CrashOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
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
db_instance_tier        = "db-custom-N4-8-65536" # 8 vCPU, 64 GB, N4 series (Enterprise)
db_disk_provisioned_iops = 8000
db_availability_type    = "REGIONAL"
db_disk_size            = 256              # GB
db_max_disk_size        = 1000
filestore_tier          = "BASIC_HDD"
filestore_capacity_gb   = 2560             # 2.5 TiB
```
In `helm-values.yaml`:

```yaml
iq_server:
  resources:
    requests:
      cpu: "6"
      memory: "48Gi"
    limits:
      cpu: "8"
      memory: "56Gi"
  javaOpts: "-Xms48g -Xmx48g -XX:MaxDirectMemorySize=4g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/Java_Heap_logs -XX:+CrashOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
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
db_instance_tier        = "db-custom-N4-16-131072" # 16 vCPU, 128 GB, N4 series (Enterprise)
db_disk_provisioned_iops = 10000
db_availability_type    = "REGIONAL"
db_disk_size            = 512              # GB
db_max_disk_size        = 2000
filestore_tier          = "BASIC_HDD"
filestore_capacity_gb   = 10240            # 10 TiB
```
In `helm-values.yaml`:

```yaml
iq_server:
  resources:
    requests:
      cpu: "12"
      memory: "96Gi"
    limits:
      cpu: "16"
      memory: "110Gi"
  javaOpts: "-Xms96g -Xmx96g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/Java_Heap_logs -XX:+CrashOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
```
</details>

> The Helm chart renders the pod spec, so each pod's CPU, memory and heap come from
> `iq_server.resources` and `iq_server.javaOpts` in `helm-values.yaml`, which ships with the M and L
> values. The heap and `-XX:MaxDirectMemorySize` together stay under the memory limit, so metaspace,
> thread stacks and code cache have room: 4 GB of the `56Gi` limit at M and L, and 6 GB of the
> `110Gi` limit at XL, which fits under the memory an `n4a-highmem-16` node leaves for pods.

### Database Sizing (Cloud SQL PostgreSQL)

| Size | DB Tier | vCPU | Memory | Storage | Availability |
|------|:--------|:----:|:------:|:-------:|:------------:|
| **M** | db-custom-N4-8-65536 (Enterprise) | 8 | 64 GB | 128 GB Hyperdisk Balanced, 8,000 IOPS (auto-resize to 500 GB) | Regional |
| **L** | db-custom-N4-8-65536 (Enterprise) | 8 | 64 GB | 256 GB Hyperdisk Balanced, 8,000 IOPS, auto-resize to 1 TB | Regional |
| **XL** | db-custom-N4-16-131072 (Enterprise) | 16 | 128 GB | 512 GB Hyperdisk Balanced, 10,000 IOPS, auto-resize to 2 TB | Regional |

The tiers are on the N4 series, 64 GB at M and L and 128 GB at XL, because the classic `db-custom` tiers allow at most 6.5 GB per vCPU. N4 takes only Hyperdisk Balanced storage, whose default is 4,000 IOPS for a disk up to 256 GB and 7,000 up to 512 GB, so the IOPS are set to 8,000 at M and L and 10,000 at XL, above the peak measured at Size M. Throughput is left at the Hyperdisk default for the disk size.

### Shared Storage (Cloud Filestore)

| Size | Tier | Capacity | Read IOPS | Write IOPS |
|------|:-----|:--------:|:---------:|:----------:|
| **M** | BASIC_HDD | 1 TiB | 600 | 1,000 |
| **L** | BASIC_HDD | 2.5 TiB | 600 | 1,000 |
| **XL** | BASIC_HDD | 10 TiB | 1,000 | 5,000 |

> BASIC_HDD is the default recommendation. At 10+ TiB, HDD unlocks 5,000 write IOPS at roughly the same cost as 2.5 TiB SSD. Enterprise edition Cloud SQL (not Enterprise Plus) is sufficient.

### OpenSearch

IQ Server uses an OpenSearch cluster for Advanced Search and for the Nexus One index behind the Nexus
One list pages, typeahead, and dashboard, and **it is required at every size this architecture
supports.** One cluster serves both features, through a `search:` block and a `nexusOne.connection` block in IQ Server's
`config.yml` that name the same endpoint and credentials, with nothing extra to switch on per
feature.

Google Cloud has no first-party managed OpenSearch service, so the cluster is **self-managed
OpenSearch on Compute Engine instances** and IQ Server authenticates with a username and password. That
means you also choose the OpenSearch server version and own upgrades, snapshots, and node replacement.
Use `https` on the cluster's REST layer: with no IAM to sign with, that password is the only thing
protecting the index, and on plain `http` it crosses the network in clear text on every request.

**The templates do not turn it on for you.** `search_engine` defaults to `lucene` in `variables.tf`, so
a deployment that wants either feature sets `search_engine = "opensearch"` and supplies
`opensearch_endpoint`, `opensearch_username` and `opensearch_password`. Every variable and its default
is in [Search Backend](#search-backend) below.

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
[cluster table](#the-cluster-to-build) below. At M, L and XL the component, violation and vulnerability indices are
created with 3 primary shards and every other index with 1. The
shard counts are set through the configuration API before the first build, as shown there.

See the [top-level OpenSearch section](../README.md#opensearch) for the full planning rules.

---

## Deployment Guide

### Step 1: Prerequisites

#### Required Tools
Install these tools on your local machine:

| Tool | Version | Installation | Purpose |
|------|---------|--------------|---------  |
| **Terraform** | >= 1.2 | [Install Guide](https://developer.hashicorp.com/terraform/install) | Infrastructure as Code |
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
- **Database**: Cloud SQL instances, databases, users, SSL certificates
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

2. **Edit `terraform.tfvars` with your values (set `search_engine = "opensearch"` and your cluster's details, see [Search Backend](#search-backend)):**
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

> **PostgreSQL version.** Minimum PostgreSQL 16. Recommended, and the default for new
> deployments, PostgreSQL 18. An existing deployment sets `postgres_version` in
> `terraform.tfvars` to the version it runs today, and one still on PostgreSQL 15 is below
> the minimum. Upgrading is the deployer's decision.

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
node_instance_type           = "n4a-highmem-8"  # 8 vCPU, 64 GB (ARM)
node_group_min_size          = 2
node_group_max_size          = 5
node_group_desired_size      = 3
node_disk_size               = 100
gke_maintenance_window_start = "03:00"

# PostgreSQL Configuration (Regional HA)
postgres_version                   = "POSTGRES_18"
db_instance_tier                   = "db-custom-N4-8-65536"  # 8 vCPU, 64 GB, the Size L value
db_edition                         = "ENTERPRISE"
db_disk_type                       = "HYPERDISK_BALANCED"
db_disk_provisioned_iops           = 8000                    # 10000 at Size XL
db_availability_type               = "REGIONAL"
db_disk_size                       = 256
db_max_disk_size                   = 1000
db_max_connections                 = "400"
db_backup_retention_count          = 8
db_deletion_protection             = false
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
helm_chart_version      = "201.0.0"
# Search Backend, needed for Advanced Search and the Nexus One index at every size
# "lucene" (default) uses the built-in index. "opensearch" needs a cluster you run yourself:
# see "Search Backend" below.
search_engine = "lucene"
# opensearch_endpoint                 = "opensearch.internal.example.com"
# opensearch_port                     = 9200
# opensearch_use_tls                  = true
# opensearch_username                 = "nexusiq"
# opensearch_password                 = "CHANGE_ME_STRONG_PASSWORD"
# opensearch_index_replicas = 1
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
>
> These defaults changed as well. Set the values your deployment runs at before applying.
>
> | Setting | Previous default | New default |
> |---|:---:|:---:|
> | `node_instance_type` | `n2-standard-8` | `n4a-highmem-8` |
> | `filestore_capacity_gb` | 1024 | 2560, and the share cannot shrink |
> | `db_max_disk_size` | 500 | 1000 |
> | `db_disk_size` | 100 | 256, and the disk cannot shrink |
> | `db_instance_tier` | db-custom-8-30720 | db-custom-N4-8-65536, see the note below |
> | `db_disk_type` | PD_SSD, fixed in `database.tf` | HYPERDISK_BALANCED, now a variable |
> | `db_edition` | ENTERPRISE, the provider 5.x default | ENTERPRISE, now a variable |
> | `db_disk_provisioned_iops` | none | 8000, used only on HYPERDISK_BALANCED |
> | `enable_read_replica` | true | removed, so the next apply deletes an existing read replica. The regional primary and its standby stay |
> | `iq_server.resources` in `helm-values.yaml` | 4 to 6 CPU, 16 to 24 GB | 6 to 8 CPU, 48 to 56 GB |
> | `iq_server.javaOpts` in `helm-values.yaml` | 24 GB heap | 48 GB heap |

> **Existing deployments and the N4 database tiers.** The M, L and XL database defaults moved from `db-custom-8-30720` and `db-custom-16-65536` on `PD_SSD` to `db-custom-N4-8-65536` and `db-custom-N4-16-131072` on `HYPERDISK_BALANCED`, and the google provider moved from `~> 5.0` to `~> 8.0`, so run `terraform init -upgrade` first. On provider 8.x a change to the tier or the disk type is an update to the existing instance, not a replacement. Google migrates the storage from SSD to Hyperdisk Balanced as part of that change and says it generally needs minimal downtime; moving back from Hyperdisk to SSD later can incur significant downtime. Whether to move is your decision. To stay on the current shape, set `db_instance_tier` to the tier you run today and `db_disk_type = "PD_SSD"` in `terraform.tfvars`; `db_disk_provisioned_iops` is then ignored.

**Important Settings:**
- **`node_group_min_size = 2`** - Minimum GKE node capacity
- **`node_group_max_size = 5`** - Maximum GKE node capacity
- **`nexus_iq_replica_count = 3`** - Initial number of replicas for HA (minimum 2 recommended, requires HA license)
- **`db_availability_type = "REGIONAL"`** - Regional database with automatic failover
- **`filestore_capacity_gb = 2560`** - 2.5 TiB, the Size L capacity. Size M uses 1024 and Size XL uses 10240
- **`gcp_project_id`** - Your GCP project ID (required)
- **`db_password`** - Use a strong, unique password (required change)
- **`db_deletion_protection = false`** - Set to `true` for production to prevent accidental database deletion
- **Resource Names** - Controlled by `cluster_name` variable

### Clustering Solution

This deployment leverages Kubernetes and Helm for IQ Server clustering:

- **Pod Distribution**: Kubernetes pod anti-affinity ensures replicas run on different nodes across availability zones
- **Shared Storage**: Cloud Filestore (BASIC_HDD) provides consistent storage across all replicas with ReadWriteMany access
- **Database Sharing**: All replicas connect to the shared regional Cloud SQL cluster via Kubernetes secrets
- **Service Discovery**: Kubernetes service provides stable DNS and load balancing
- **Horizontal Pod Autoscaler**: IQ pods scale between the minimum and maximum for your size. Size M is 2 to 3, Size L is 2 to 4, Size XL is 3 to 5

**Important**: Ensure your Sonatype IQ Server license supports clustering for HA deployments.

## Running Several Sizes in One Project

Every resource name that has to be unique inside a Google Cloud project derives from
`cluster_name`: the GKE cluster, the VPC, all four subnets, the router, the Cloud NAT, every firewall
rule, the Cloud Armor policy, the ingress address, the node pool, both Workload Identity service
accounts, the Cloud SQL instance, Filestore, both Secret Manager secrets, the log bucket, sink and
metrics.

```hcl
cluster_name = "iq-l"   # a distinct value per deployment
```

`force-cleanup.sh` matches on this deployment's own `cluster_name`, so it cannot delete another
deployment's Cloud SQL and Filestore instances in the same project.

These are not renamed, and do not need to be: the database name and the database user, which are
scoped to the Cloud SQL instance rather than to the project, and the Filestore share name, which
is scoped to the Filestore instance. The Kubernetes namespace and Helm release name are also
fixed, which is correct because each deployment has its own cluster.

### What a name may contain, and what cannot be reused

**`cluster_name` is validated at plan time**: lowercase letters, numbers and hyphens, starting with
a letter and ending with a letter or number, 1 to 19 characters. A service account id allows 30, and
the longest suffix added to this prefix is 11 characters.

| Name | Reuse after deletion |
|---|---|
| Cloud SQL instance | Immediate |
| Service account | **Immediate, with a consequence.** A new account with the same name is a separate identity: it inherits none of the deleted account's roles, and it blocks undeleting the original for the 30 days during which that would otherwise be possible |
| Everything else here | Immediate |

A normal destroy and rebuild recreates both Workload Identity accounts and grants their roles and
Kubernetes bindings in the same apply. **Do not delete an account by hand and expect to undelete
it**: creating the replacement makes the original unrecoverable.

A Cloud SQL instance name carries a random suffix, `<cluster_name>-db-<suffix>`, regenerated on every
fresh apply, so a rebuilt environment's database has a different name.

## Search Backend

This configuration takes the endpoint of an OpenSearch cluster you run yourself and does not create
one, so switching `search_engine` never destroys an index. Every replica shares the one index.

### Turning it on

```hcl
search_engine                       = "opensearch"
opensearch_endpoint                 = "opensearch.internal.example.com"  # host only, no scheme
opensearch_port                     = 9200
opensearch_use_tls                  = true
opensearch_username                 = "nexusiq"
opensearch_password                 = "CHANGE_ME_STRONG_PASSWORD"
opensearch_index_replicas = 1
```

All of `opensearch_endpoint`, `opensearch_username` and `opensearch_password` are required once
`search_engine` is `"opensearch"`, and the plan fails naming whichever is missing.

`opensearch_username` may not hold a single quote, a double quote, a dollar sign, a backtick or a
backslash, and the plan refuses one that does.

**Terraform alone does not apply this.** The `search:` block lives in the Helm values, so run
`terraform apply` and then `./helm-install.sh`, or `./helm-upgrade.sh` on an existing release.

### What this writes into `config.yml`

`helm-values.yaml` carries a `search:` block and a `nexusOne.connection` block naming the same
cluster, with placeholders between two markers,
`# search-block-begin` and `# search-block-end`. `helm-install.sh` fills them from Terraform
outputs, and the Helm chart renders the result as `config.yml` in every pod:

```yaml
    search:
      type: http
      mode: OPENSEARCH
      uri: https://opensearch.internal.example.com:9200
      username: nexusiq
      password: <filled by helm-install.sh>
    nexusOne:
      connection:
        type: http
        mode: OPENSEARCH
        uri: https://opensearch.internal.example.com:9200
        username: nexusiq
        password: <filled by helm-install.sh>
        nexusOneIndexReplicas: 1
```

- **`type: http` with basic auth.** A user name and password are how the pods authenticate.
- **`mode: OPENSEARCH`.** Left out, it defaults to `HYBRID`, which also writes every batch to the
  built-in index.
- **`nexusOne.connection`.** The Nexus One index reads its connection, and `nexusOneIndexReplicas`,
  from this block alone. Without it, enabling the `nexus-one` feature is refused.
- **`nexusOneIndexReplicas`.** Left out, it is 1.

**Keep the two markers.** With `search_engine = "lucene"`, `helm-install.sh` deletes everything
between them so the deployment has no `search:` or `nexusOne:` block at all, which is how the built-in index stays
the default. The script then checks that no placeholder survived and refuses to install if one did,
because a literal `OPENSEARCH_URI_PLACEHOLDER` would be read as a host name.

### How the password reaches the pods

`opensearch_password` is read by `helm-install.sh` from a Terraform output and written into
`helm-values-runtime.yaml`, which is gitignored, the same route the database password takes. The
chart renders `config.yml` itself, so the value has to be in the Helm values.

- **`helm-values-runtime.yaml` holds the password in clear while it exists.** Both
  `helm-install.sh` and `helm-upgrade.sh` render it from the current Terraform outputs at the start
  of a run and remove it on exit, however the run ends, so nothing is left behind to delete by hand.
- **The password is in Terraform state**, because `opensearch_password` is an input variable. Keep
  the state backend private.

To rotate the password, change it in `terraform.tfvars`, then:

```bash
terraform apply
./helm-upgrade.sh
```

`helm-upgrade.sh` renders the values file itself, so it carries whatever `terraform apply` has just
put in the state. `helm-install.sh` refuses to run once the release exists, which is why the
rotation goes through the upgrade.

### Firewall

Google Cloud denies all ingress that no rule allows. This root declares no egress rule, so egress
needs nothing added and only ingress to the cluster does:

- **Ingress.** `search.tf` adds a rule letting the pod range and the node subnet reach instances
  tagged `nexus-iq-opensearch` on `opensearch_port`. **Tag each OpenSearch node
  `nexus-iq-opensearch`** or the cluster is unreachable from the pods.
- **Both source ranges are needed.** This GKE cluster is VPC-native, so a pod's own alias address
  from `gke_pods_cidr` is the source of traffic it sends, while anything running on the node itself
  uses the node's address from the node subnet.

A cluster outside this VPC is reached over whatever path you have built to it, and this rule has no
effect on it.

### The cluster to build

| | What to run |
|---|---|
| OpenSearch version | 2.19 or later. The 2.19 line is the long-term support release |
| Cluster managers | Three dedicated cluster manager nodes, so losing one leaves a quorum |
| Data nodes | At least two, spread across zones, with `opensearch_index_replicas` at 1 or more so a lost node does not lose a shard |
| Heap | Half of each node's RAM, and never above 31 GB, so compressed object pointers stay on |
| Disk | Hyperdisk Balanced on C4A, or SSD persistent disk on a series that takes it. The index is write-heavy during a rebuild |
| Network | Private IP addresses in this VPC, or a VPC you have peered to it. No public address |
| Security | The OpenSearch security plugin, with a user for Nexus IQ Server that can create, read and write indices |
| Snapshots | The `repository-gcs` plugin, on every node |

**OpenSearch can also run inside this GKE cluster**, which this configuration does not do. Use the
OpenSearch Kubernetes operator on its own node pool, so an index rebuild and the evaluation queue do
not compete for CPU, and set the endpoint to the operator's service name.

Per size:

| Size | Data nodes | Machine type | Storage per node | Cluster managers | Shards ¹ | `opensearch_index_replicas` |
|------|:----------:|:------------:|:----------------:|:----------------:|:--------:|:---------------------------:|
| **M** | 3 | `c4a-standard-2`, 2 vCPU, 8 GB | 100 GB Hyperdisk Balanced | 3 x `c4a-standard-1`, 1 vCPU, 4 GB, 2 GB heap, 20 GB Hyperdisk Balanced boot disk | 3 | `1` |
| **L** | 3 | `c4a-standard-4`, 4 vCPU, 16 GB | 150 GB Hyperdisk Balanced | 3 x `c4a-standard-1`, 1 vCPU, 4 GB, 2 GB heap, 20 GB Hyperdisk Balanced boot disk | 3 | `1` |
| **XL** | 3 | `c4a-highmem-8`, 8 vCPU, 64 GB | 250 GB Hyperdisk Balanced | 3 x `c4a-standard-2`, 2 vCPU, 8 GB, 4 GB heap, 20 GB Hyperdisk Balanced boot disk | 3 | `1` |

C4A is Arm and takes Hyperdisk only, so each data node needs an arm64 image and a Hyperdisk Balanced
volume.

M is measured, on 1 shard per index. L, XL and the 3 shards at M are not.

The cluster managers are dedicated: they hold no data, take no search traffic, and three of them
keep a quorum when one is lost. Each takes half its RAM as heap.

**Put an internal passthrough Network Load Balancer in front of the data nodes**, and set
`opensearch_endpoint` to its address, so Nexus IQ Server reaches one endpoint and replacing a data
node does not change its configuration. Create:

- **A regional TCP health check on port 9200.**
- **A regional backend service** with `--load-balancing-scheme INTERNAL --protocol TCP` and that
  health check, whose backends are one unmanaged instance group per zone holding that zone's data
  nodes. The cluster managers stay out of it.
- **A forwarding rule on a reserved private IP address** in this VPC, for TCP port 9200.
- **A firewall rule allowing TCP 9200 from Google's health check ranges** `35.191.0.0/16` and
  `130.211.0.0/22` to the `nexus-iq-opensearch` tag. Without it the backends never turn healthy.
- **With `opensearch_use_tls = true`, a data node certificate that names the load balancer's
  address.** The load balancer passes TLS through to the nodes, so IQ Server checks each node's
  certificate against `opensearch_endpoint`, and that address has to be in its subject alternative
  names.

Google describes the load balancer in
[Internal passthrough Network Load Balancer overview](https://cloud.google.com/load-balancing/docs/internal).

¹ Primary shards for the component, violation and vulnerability indices. Every other index keeps 1.
Shard counts are held in Nexus IQ Server's database, not in `config.yml`, and only take effect when
an index is created, so **at M, L and XL set them before the Nexus One index is first built**, with the request in
[Shards](../README.md#shards-3-for-three-indices-at-m-and-above).

An index built before the change keeps its count until it is rebuilt.

### Trusting a private certificate authority

With `opensearch_use_tls = true`, the JVM in every pod has to trust the cluster's certificate. A
certificate from a public authority already works and needs nothing below.

A certificate from a private authority needs that authority added to the JVM trust store, and
Nexus IQ Server has no per-connection trust setting, so the whole JVM is affected. **Copy the trust
store and point the JVM at the copy. Replacing the JVM's own trust store breaks Nexus IQ Server's
calls to the Sonatype data service**, which rely on the public authorities already in it.

This root does the copy for you. Set the authority's PEM certificate in `terraform.tfvars`:

```hcl
opensearch_use_tls        = true
opensearch_ca_certificate = <<-EOT
  -----BEGIN CERTIFICATE-----
  ...the authority's PEM certificate...
  -----END CERTIFICATE-----
EOT
```

After `terraform apply`, `helm-install.sh` or `helm-upgrade.sh` stores it in the Kubernetes
Secret `nexus-iq-opensearch-ca` and keeps the two blocks between the `# opensearch-ca-begin` and
`# opensearch-ca-end` markers in `helm-values.yaml`. Those give each pod the certificate as the
`OPENSEARCH_CA_PEM` environment variable, read from the Secret, and a start command that copies
the image's JVM trust store to `/tmp/opensearch-cacerts`, adds the authority with the image's own
`keytool`, adds `-Djavax.net.ssl.trustStore` to `JAVA_OPTS`, and then runs the image's own start
script. Without a certificate both blocks are deleted, and the pods run the image's default
command. Keep the markers. To change the certificate, apply, run `helm-upgrade.sh`, and restart
the pods with `kubectl rollout restart deployment -n nexus-iq`, since a pod reads the Secret only
when it starts.

The Secret reaches the pod as an environment variable rather than a mounted file, so the pod
needs no extra volume and nothing has to be added to `javaOpts`.

**`http` is accepted too**, and skips all of the above. Nexus IQ Server validates the scheme and
takes either one. The cost is that the basic auth password is sent unencrypted on every request.
**Use `https`.** The copy above is one variable, and a password on the wire is permanent.
`http` is reasonable only for a short evaluation on a private network you control.

### Snapshots, and the credential they need

**A snapshot repository on Cloud Storage needs no service account JSON key.** The
`repository-gcs` plugin falls back to application default credentials when no `credentials_file` is
in the OpenSearch keystore. On Compute Engine that resolves to the service account attached to the
instance; in GKE, to the Workload Identity service account bound to the pod's Kubernetes service
account.

**Do not add a key.** A key never expires, sits on every data node, and can write to every backup.

**Confirm it on your own cluster by reading the node log.** The plugin logs this line, at INFO, the
first time it builds a client for the repository:

```
"Application Default Credentials" will be in use
```

Seeing that line means no key was read. Not seeing it means a `credentials_file` is set in the
keystore, so check with `./bin/opensearch-keystore list | grep credentials_file`.

**No key does not mean no permission.** The identity still has to be granted access to the bucket,
or a snapshot fails with a 403 that looks like an authentication problem and is not:

```bash
gcloud storage buckets add-iam-policy-binding gs://your-snapshot-bucket \
  --member="serviceAccount:OPENSEARCH_NODE_SERVICE_ACCOUNT" \
  --role="roles/storage.objectAdmin"
```

`roles/storage.objectAdmin` on the bucket alone, not on the project: a snapshot writes, reads,
lists and deletes objects, which `objectViewer` and `objectCreator` each cover only part of.

Then install the plugin and register the repository with no client credentials at all:

```bash
./bin/opensearch-plugin install repository-gcs   # on every node, then restart

curl -X PUT "https://localhost:9200/_snapshot/nexus-iq-snapshots" -H 'Content-Type: application/json' -d '
{
  "type": "gcs",
  "settings": { "bucket": "your-snapshot-bucket", "base_path": "nexus-iq" }
}'
```

### What running the cluster yourself costs you

None of this is handled by this configuration, and all of it has to be handled by someone:

- **Upgrades.** Rolling restarts, version by version, with the cluster kept green between steps.
- **Snapshots and restore drills.** A snapshot nobody has restored is not a backup.
- **Capacity.** Disk watermarks block writes before they fill the disk, and a blocked write is how
  an index rebuild stalls.
- **Certificate renewal.** Both the cluster's certificate and the secret above.
- **Monitoring.** Cluster status, unassigned shards, JVM heap pressure, rejected write threads.
- **The password.** Rotating it with `terraform apply` and `./helm-upgrade.sh`.
- **Keeping the cluster manager quorum.** Three managers, and never two.

### Rebuilding the index

Switching `search_engine` to `"opensearch"` points the pods at an empty cluster. The index is built
from the Nexus IQ Server administration pages, not by Terraform and not by Helm, and the build reads
the whole database, so run it when the deployment is otherwise quiet. One pod performs the build and
the rest read the result.

## Security Features

- **Private GKE Cluster**: Nodes in private subnets with no public IPs
- **Workload Identity**: Secure service account access without keys
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

- **Cloud Filestore (BASIC_HDD)**: Shared storage for `/sonatype-work` directory (1 TiB minimum)
- **Database**: Cloud SQL PostgreSQL (regional) for application data. Minimum PostgreSQL 16. Recommended, and the default for new deployments, PostgreSQL 18
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
