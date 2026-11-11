# Sonatype IQ Reference Architecture - GCP with Docker (High Availability)

This directory contains Terraform configuration for deploying Sonatype IQ Server on Google Cloud Platform using Managed Instance Groups with Docker containers in a **High Availability configuration** with auto-scaling and multi-zone deployment.

---

## Sizing Guide

This MIG HA architecture supports sizes **M**, **L**, and **XL**. Choose your size based on application count and daily evaluation volume:

| Size | Applications | Evaluations/Day | Nodes | Compute (per node) | Java Heap | Machine Type | OpenSearch |
|------|:------------:|:---------------:|:-----:|:-------------------:|:---------:|:------------:|:----------:|
| **M** | 2,000 - 10,000 | 5,000 - 10,000 | 2 | 8 vCPU / 64 GB | 48 GB | n4a-highmem-8 (ARM) | Required ¹ |
| **L** | 10,000 - 20,000 | 10,000 - 20,000 | 3 | 8 vCPU / 64 GB | 48 GB | n4a-highmem-8 (ARM) | Required ¹ |
| **XL** | 20,000 - 80,000 | 20,000+ | 4 | 16 vCPU / 128 GB | 96 GB | n4a-highmem-16 (ARM) | Required ¹ |

> All sizes validated through performance testing on GCP ARM instances. Evaluations an hour per instance, sustained in testing, not a limit: 2,250 at M on 2 instances. L and XL are not measured.

> ¹ Required for Advanced Search and the Nexus One index at every size, and not switched on for you: `search_engine` defaults to `lucene` in `variables.tf`, so a deployment that wants either feature sets it to `opensearch` and supplies the cluster's endpoint and credentials. See [OpenSearch](#opensearch) for what it serves, what this architecture does and does not do about it, and the per-size cluster specification.

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
db_instance_tier     = "db-custom-N4-8-65536" # 8 vCPU, 64 GB, N4 series (Enterprise)
db_disk_provisioned_iops = 8000
db_availability_type = "REGIONAL"
db_disk_size         = 128                 # GB
db_max_disk_size     = 500
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
db_instance_tier     = "db-custom-N4-8-65536" # 8 vCPU, 64 GB, N4 series (Enterprise)
db_disk_provisioned_iops = 8000
db_availability_type = "REGIONAL"
db_disk_size         = 256                 # GB
db_max_disk_size     = 1000
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
db_instance_tier     = "db-custom-N4-16-131072" # 16 vCPU, 128 GB, N4 series (Enterprise)
db_disk_provisioned_iops = 10000
db_availability_type = "REGIONAL"
db_disk_size         = 512                 # GB
db_max_disk_size     = 2000
filestore_tier       = "BASIC_HDD"         # 10 TiB (1,000 read / 5,000 write IOPS)
filestore_capacity_gb = 10240
```
</details>

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

> BASIC_HDD is the default recommendation. At 10+ TiB, HDD unlocks 5,000 write IOPS at roughly the same cost as 2.5 TiB SSD.

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

#### GCP Account Requirements
- GCP account with appropriate permissions
- GCP Project with billing enabled
- Ability to create: Compute Engine, Cloud SQL, Cloud Filestore, Global Load Balancers
- Zone-redundant resource support in target region (default: us-central1)

#### Required GCP Permissions
Your GCP account needs permissions for these services:
- **Compute Engine**: Instances, instance templates, regional managed instance groups, health checks, routers, regional autoscalers, security policies (Cloud Armor)
- **Networking**: VPC, subnets, firewall rules, Cloud NAT, Global Load Balancers, backend services, URL maps, target proxies, global forwarding rules, global addresses
- **Database**: Cloud SQL instances, databases, users, SSL certificates
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

2. **Edit `terraform.tfvars` with your values (set `search_engine = "opensearch"` and your cluster's details, see [Search Backend](#search-backend)):**
   ```bash
   vi terraform.tfvars
   ```

   **Required changes:**
   - `gcp_project_id` - Your GCP project ID
   - `db_password` - Strong, unique password
   - `search_engine` - `"opensearch"`, with your cluster's details, see [Search Backend](#search-backend)

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

> **Your OpenSearch cluster is not part of this.** This architecture never creates the cluster, so `./gcp-ha-destroy.sh` does not delete it or its indices. Remove it separately when you no longer need it.

**WARNING: This will delete ALL infrastructure and data!**

1. **Destroy all resources:**
   ```bash
   terraform destroy
   ```

   > **Keep the terminal open** - If you close it mid-destroy, the process will potentially stop and leave resources partially deleted.

---

## Configuration

> **PostgreSQL version.** Minimum PostgreSQL 16. Recommended, and the default for new
> deployments, PostgreSQL 18. An existing deployment sets `postgres_version` in
> `terraform.tfvars` to the version it runs today, and one still on PostgreSQL 15 is below
> the minimum. Upgrading is the deployer's decision.

> **Upgrading an existing deployment.** These variable defaults changed with the
> published sizing. A deployment whose `terraform.tfvars` does not set a variable
> picks up the new default on its next apply. Set the values your deployment is
> running at in `terraform.tfvars` before applying.
>
> | Variable | Previous default | New default | Applies to |
> |---|:---:|:---:|---|
> | `iq_target_instances` | 2 | 3 | new deployments only, see below |
> | `iq_max_instances` | 6 | 4 | every deployment |
> | `db_disk_size` | 100 | 256 | every deployment, and the disk cannot shrink |
> | `enable_read_replica` | true | removed, so the next apply deletes an existing read replica. The regional primary and its standby stay | every deployment |
> | `filestore_capacity_gb` | 1024 | 2560 | every deployment, and the share cannot shrink |
> | `java_opts` | 48 GB heap, no direct memory cap | the Size M and L `java_opts` above | every deployment, and it rolls the group |
> | `db_instance_tier` | db-custom-8-30720 | db-custom-N4-8-65536 | every deployment, see the note below |
> | `db_disk_type` | PD_SSD | HYPERDISK_BALANCED | every deployment, see the note below |
> | `db_disk_provisioned_iops` | none | 8000, used only on HYPERDISK_BALANCED | every deployment |
>
> `iq_target_instances` reaches a group only when it is created: `compute.tf` sets
> `ignore_changes = [target_size]` on the instance group manager, so an existing
> deployment keeps the size it is running at and an apply will not resize it. Change the
> size with `gcloud compute instance-groups managed resize`, or by removing that
> lifecycle block.

> **Existing deployments and the N4 database tiers.** The M, L and XL database defaults moved from `db-custom-8-30720` and `db-custom-16-65536` on `PD_SSD` to `db-custom-N4-8-65536` and `db-custom-N4-16-131072` on `HYPERDISK_BALANCED`, and the google provider moved from `~> 5.0` to `~> 8.0`, so run `terraform init -upgrade` first. On provider 8.x a change to the tier or the disk type is an update to the existing instance, not a replacement. Google migrates the storage from SSD to Hyperdisk Balanced as part of that change and says it generally needs minimal downtime; moving back from Hyperdisk to SSD later can incur significant downtime. Whether to move is your decision. To stay on the current shape, set `db_instance_tier` to the tier you run today and `db_disk_type = "PD_SSD"` in `terraform.tfvars`; `db_disk_provisioned_iops` is then ignored.

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

# Resource Naming
# Empty reproduces the published names. Set it per deployment when several sizes share a project.
cluster_name = ""

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
postgres_version       = "POSTGRES_18"
db_instance_tier      = "db-custom-N4-8-65536" # 8 vCPU, 64 GB, the Size L value
db_edition            = "ENTERPRISE"
db_disk_type          = "HYPERDISK_BALANCED"
db_disk_provisioned_iops = 8000                 # 10000 at Size XL
db_availability_type  = "REGIONAL"          # REGIONAL for HA
db_disk_size          = 256
db_max_disk_size      = 1000
db_max_connections    = "200"
db_backup_retention_count  = 8
db_deletion_protection     = true

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

**Important Settings:**
- **`iq_min_instances = 2`** - Minimum instances, the Size M and L value. Size XL uses 3, and every size must be at least 2 for HA. Requires an HA license
- **`iq_max_instances = 4`** - Maximum auto scaling capacity, the Size L value. Size M uses 3 and Size XL uses 5
- **`iq_target_instances = 3`** - Initial number of instances, the Size L value. Size M uses 2 and Size XL uses 4
- **`db_availability_type = "REGIONAL"`** - Multi-AZ database with automatic failover
- **`filestore_capacity_gb = 2560`** - 2.5 TiB, the Size L capacity. Size M uses 1024 and Size XL uses 10240
- **`gcp_project_id`** - Your GCP project ID (required)
- **`db_password`** - Use a strong, unique password (required change)
- **`db_deletion_protection = true`** - Set to `false` only for testing to allow database deletion
- **`iq_docker_image`** - Use specific version tag for production (e.g., `sonatype/nexus-iq-server:1.196.0`). An image in Artifact Registry in the same project is pulled with the instances' service account, which holds `roles/artifactregistry.reader`
- **`db_edition` and `db_disk_type`** - `ENTERPRISE` and `HYPERDISK_BALANCED` suit the N4 tiers, and `PD_SSD` suits the classic `db-custom-*` tiers. The newer Cloud SQL series need `ENTERPRISE_PLUS`, and `db-c4a-highmem-*` also needs `HYPERDISK_BALANCED`
- **`db_disk_provisioned_iops = 8000`** - IOPS for the Hyperdisk Balanced data disk, the Size M and L value. Size XL uses 10000. Ignored on `PD_SSD`
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

## Running Several Sizes in One Project

Every resource name that has to be unique inside a Google Cloud project derives from one variable,
`cluster_name`, so two sizes of this architecture can live in one project without colliding.

```hcl
cluster_name = "iq-m"   # a distinct value per deployment
```

**The default is empty, which keeps the default names**, so nothing is renamed or replaced. Setting
it renames the VPC, all three private subnets, the public and database subnets, the router, the Cloud NAT, the
reserved address, all eight firewall rules, the load balancer and its proxies and forwarding rules,
the Cloud Armor policy, both health checks, the instance template, the managed instance group and
its base instance name, the autoscaler, Filestore, both service accounts, the Cloud SQL instance,
the client certificate, all three Secret Manager secrets, the log bucket and sink, both log metrics,
the log view and both alert policy display names.

These are not renamed, and do not need to be: the database name and the database user, which are
scoped to the Cloud SQL instance rather than to the project, and the Filestore share name, which
is scoped to the Filestore instance.

### What a name may contain, and what cannot be reused

**`cluster_name` is validated at plan time**: lowercase letters, numbers and hyphens, starting with
a letter and ending with a letter or number, 1 to 19 characters. A service account id allows 30, and
the longest suffix added to this prefix is 11 characters.

| Name | Reuse after deletion |
|---|---|
| Cloud SQL instance | Immediate |
| Service account | **Immediate, with a consequence.** A new account with the same name is a separate identity: it inherits none of the deleted account's roles, and it blocks undeleting the original for the 30 days during which that would otherwise be possible |
| Everything else here | Immediate |

A normal destroy and rebuild recreates both service accounts and grants their roles in the same
apply. **Do not delete an account by hand and expect to undelete it**: creating the replacement makes
the original unrecoverable.

A Cloud SQL instance name carries a random suffix, `<cluster_name>-db-<suffix>`, regenerated on every
fresh apply, so a rebuilt environment's database has a different name.

## Search Backend

This configuration takes the endpoint of an OpenSearch cluster you run on Compute Engine and does
not create one, so switching `search_engine` never destroys an index. Every instance in the group
shares the one index.

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

Changing any of these replaces the instance template, so the managed instance group rolls every
instance. Plan it as a restart of the whole group.

### What this writes into `config.yml`

`scripts/startup.sh` adds a `search:` block and a `nexusOne.connection` block naming the same
cluster. Every instance writes the same two blocks, so they share one index:

```yaml
search:
  type: http
  mode: OPENSEARCH
  uri: https://opensearch.internal.example.com:9200
  username: nexusiq
  password: <read from Secret Manager at boot>
nexusOne:
  connection:
    type: http
    mode: OPENSEARCH
    uri: https://opensearch.internal.example.com:9200
    username: nexusiq
    password: <read from Secret Manager at boot>
    nexusOneIndexReplicas: 1
```

- **`type: http` with basic auth.** A user name and password are how the servers authenticate.
- **`mode: OPENSEARCH`.** Left out, it defaults to `HYBRID`, which also writes every batch to the
  built-in index.
- **`nexusOne.connection`.** The Nexus One index reads its connection, and `nexusOneIndexReplicas`,
  from this block alone. Without it, enabling the `nexus-one` feature is refused.
- **`nexusOneIndexReplicas`.** Left out, it is 1.

### How the password reaches the servers

`opensearch_password` is written to a Secret Manager secret named
`<cluster_name>-opensearch-password-<suffix>`, or `nexus-iq-ha-opensearch-password-<suffix>` when
`cluster_name` is left empty, alongside the two the database already uses. Each instance reads it
at boot with `gcloud secrets versions access`, so the password is not in the instance template's
metadata, which every instance in the group exposes. The compute service account gets its own
`roles/secretmanager.secretAccessor` grant on the secret.

To rotate the password, add a new secret version and roll the group:

```bash
SECRET=$(terraform output -raw opensearch_password_secret_name)
printf '%s' 'NEW_PASSWORD' | gcloud secrets versions add "$SECRET" --data-file=-
gcloud compute instance-groups managed rolling-action restart \
  "$(terraform output -raw instance_group_manager_name)" --region <your-region>
```

Each replacement instance re-runs `scripts/startup.sh`, which reads the newest secret version.

The secret value also lives in Terraform state, because `opensearch_password` is an input variable.
Keep the state backend private.

### Firewall

Google Cloud denies all ingress that no rule allows. This root also denies all ingress at priority
65534 and has no egress deny rule. Two rules follow:

- **Ingress.** `search.tf` adds a rule letting instances tagged `nexus-iq-ha` reach instances
  tagged `nexus-iq-opensearch` on `opensearch_port`. **Tag each OpenSearch node
  `nexus-iq-opensearch`** or the cluster is unreachable from the servers. The rule matches on the
  network tag, not on the service account, so **anything in this VPC tagged `nexus-iq-ha` reaches
  the cluster's port**, not only this instance group.
- **Egress.** `opensearch_port` is added to the `<cluster_name>-allow-outbound` rule. That rule is
  an allow rule, so it keeps working if you add an egress deny rule of your own.

A cluster outside this VPC is reached over whatever path you have built to it, and the ingress rule
has no effect on it. The egress rule still applies.

### The cluster to build

| | What to run |
|---|---|
| OpenSearch version | 2.19 or later. The 2.19 line is the long-term support release |
| Cluster managers | Three dedicated cluster manager nodes, so losing one leaves a quorum |
| Data nodes | At least two, spread across the zones in `availability_zones`, with `opensearch_index_replicas` at 1 or more so a lost node does not lose a shard |
| Heap | Half of each node's RAM, and never above 31 GB, so compressed object pointers stay on |
| Disk | Hyperdisk Balanced on C4A, or SSD persistent disk on a series that takes it. The index is write-heavy during a rebuild |
| Network | Private IP addresses in this VPC, or a VPC you have peered to it. No public address |
| Security | The OpenSearch security plugin, with a user for Nexus IQ Server that can create, read and write indices |
| Snapshots | The `repository-gcs` plugin, on every node |

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

With `opensearch_use_tls = true`, each server's JVM has to trust the cluster's certificate. A
certificate from a public authority already works and needs nothing below.

A certificate from a private authority needs that authority added to the JVM trust store, and
Nexus IQ Server has no per-connection trust setting, so the whole JVM is affected. **Copy the trust
store and point the JVM at the copy. Replacing the JVM's own trust store breaks Nexus IQ Server's
calls to the Sonatype data service**, which rely on the public authorities already in it.

This root does the copy for you. Set the authority's PEM certificate:

```hcl
opensearch_use_tls        = true
opensearch_ca_certificate = <<-EOT
  -----BEGIN CERTIFICATE-----
  ...the authority's PEM certificate...
  -----END CERTIFICATE-----
EOT
```

Terraform stores it in a Secret Manager secret and grants the compute service account
`roles/secretmanager.secretAccessor` on it. At boot each instance copies the image's JVM trust
store to `opensearch-cacerts` on Cloud Filestore, adds the authority with the image's own
`keytool`, and starts IQ Server with `-Djavax.net.ssl.trustStore` pointing at the copy. Nothing
has to be added to `java_opts`. To change the certificate, apply and then restart the group with
`gcloud compute instance-groups managed rolling-action restart`, as for a password rotation, so
every instance reads the new secret version.

**`http` is accepted too**, and skips all of the above. Nexus IQ Server validates the scheme and
takes either one. The cost is that the basic auth password is sent unencrypted on every request.
**Use `https`.** The copy above is one variable, and a password on the wire is permanent. `http`
is reasonable only for a short evaluation on a private subnet you control.

### Snapshots, and the credential they need

**A snapshot repository on Cloud Storage needs no service account JSON key.** The
`repository-gcs` plugin falls back to application default credentials when no `credentials_file` is
in the OpenSearch keystore, and on Compute Engine that resolves to the service account attached to
the instance the node runs on, read from the metadata server.

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
- **Certificate renewal.** Both the cluster's certificate and the trust store copy above.
- **Monitoring.** Cluster status, unassigned shards, JVM heap pressure, rejected write threads.
- **The password.** Rotating it in Secret Manager and rolling the group.
- **Keeping the cluster manager quorum.** Three managers, and never two.

### Rebuilding the index

Switching `search_engine` to `"opensearch"` points the servers at an empty cluster. The index is
built from the Nexus IQ Server administration pages, not by Terraform, and the build reads the whole
database, so run it when the servers are otherwise quiet. One instance performs the build and the
rest read the result.

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

- **Cloud Filestore**: NFS-mounted shared storage for `/sonatype-work` directory (1 TiB minimum on BASIC_HDD)
- **Database**: Cloud SQL PostgreSQL for application data. Minimum PostgreSQL 16. Recommended, and the default for new deployments, PostgreSQL 18
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
