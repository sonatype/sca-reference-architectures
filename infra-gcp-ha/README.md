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

> **GCP was the primary test platform** — all performance data was validated on GCP ARM-based instances (Ampere Altra).

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
postgres_version       = "POSTGRES_15"
db_instance_tier      = "db-custom-8-30720" # 8 vCPU, 30 GB, the Size L value
db_availability_type  = "REGIONAL"          # REGIONAL for HA
db_disk_size          = 200
db_max_disk_size      = 1000
db_max_connections    = "200"
db_backup_retention_count  = 7
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

# Auto Scaling Configuration
cpu_target_utilization      = 0.7   # 70% CPU utilization target
scale_in_cooldown_seconds   = 300   # 5 minutes
scale_out_cooldown_seconds  = 60    # 1 minute

# Java Configuration
java_opts = "-Xms48g -Xmx48g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/Java_Heap_logs -XX:+CrashOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"

# Search Backend
# "lucene" (default) uses the built-in index. "opensearch" needs a cluster you run yourself:
# see "Search Backend" below.
search_engine = "lucene"
# opensearch_endpoint                 = "opensearch.internal.example.com"
# opensearch_port                     = 9200
# opensearch_use_tls                  = true
# opensearch_username                 = "nexusiq"
# opensearch_password                 = "CHANGE_ME_STRONG_PASSWORD"
# opensearch_index_replicas = 0
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
- **`iq_docker_image`** - Use specific version tag for production (e.g., `sonatype/nexus-iq-server:1.196.0`)

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

**The default is empty, which reproduces the names this architecture has always published**, so a
customer who sets nothing sees no change and nothing is renamed or replaced. Setting it moves the
VPC, all three private subnets, the public and database subnets, the router, the Cloud NAT, the
reserved address, all eight firewall rules, the load balancer and its proxies and forwarding rules,
the Cloud Armor policy, both health checks, the instance template, the managed instance group and
its base instance name, the autoscaler, Filestore, both service accounts, both Cloud SQL
instances, the client certificate, all three Secret Manager secrets, the log bucket and sink, both
log metrics, the log view and both alert policy display names. Measured with a plan: 37 of the 39
named attributes moved.

What does not move, and does not need to: the database name and the database user, which are
scoped to the Cloud SQL instance rather than to the project, and the Filestore share name, which
is scoped to the Filestore instance.

### What a name may contain, and what cannot be reused

**`cluster_name` is validated at plan time** against the narrower of the limits that apply:
lowercase letters, numbers and hyphens, starting with a letter and ending with a letter or number,
1 to 19 characters. A resource name itself allows 63, but a service account id allows only 30 and
the longest suffix added to this prefix is 11 characters, so 19 is what keeps every derived name
legal. A value that breaks the rule fails at plan rather than part way through an apply.

**One name genuinely cannot be reused, and it is not the one usually warned about.**

| Name | Reuse after deletion |
|---|---|
| Cloud SQL instance, and its replica | **Immediate.** Google's own documentation now states "the deleted instance name can be reused immediately to create a new instance" |
| Service account | **Immediate, with a consequence.** A new account with the same name is a separate identity: it inherits none of the deleted account's roles, and it blocks undeleting the original for the 30 days during which that would otherwise be possible |
| Everything else here | Immediate |

So the thing to plan around when a size is torn down and rebuilt is **the service accounts**, not
the database. Both of this root's accounts are recreated by the next apply and both have their
roles granted by the same apply, so a normal destroy and rebuild is fine. What is not fine is
deleting an account by hand and expecting to undelete it afterwards: creating the replacement first
makes the original unrecoverable.

**A Cloud SQL instance name carries a random suffix anyway**, `<cluster_name>-db-<suffix>`, and the
suffix is regenerated on every fresh apply because the `random_string` resource has no `keepers`.
That predates this change and made the old reuse window a non-issue; it still means a rebuilt
environment's database has a different name from the one before it.

## Search Backend

Nexus IQ Server ships with a built-in search index and needs nothing else running. Pointing it at
OpenSearch instead moves the index off the servers, which is what the Nexus One features read. On
this architecture it also gives every instance in the group one shared index rather than a copy
each.

**Google Cloud has no managed OpenSearch service**, so there is no first-party cluster for this
configuration to create. You run OpenSearch yourself on Compute Engine, and this configuration
takes the endpoint of a cluster you have already built. That keeps the cluster, and the index data
in it, independent of Terraform runs here: switching `search_engine` back and forth never destroys
an index.

### Turning it on

```hcl
search_engine                       = "opensearch"
opensearch_endpoint                 = "opensearch.internal.example.com"  # host only, no scheme
opensearch_port                     = 9200
opensearch_use_tls                  = true
opensearch_username                 = "nexusiq"
opensearch_password                 = "CHANGE_ME_STRONG_PASSWORD"
opensearch_index_replicas = 0
```

All of `opensearch_endpoint`, `opensearch_username` and `opensearch_password` are required once
`search_engine` is `"opensearch"`, and the plan fails naming whichever is missing.

`opensearch_username` may not hold a single quote, a double quote, a dollar sign, a
backtick or a backslash, and the plan refuses one that does. The startup script writes it
into a single-quoted YAML scalar inside a double-quoted shell string, and those five are the
only characters that would break one or the other. Everything else is written through
intact, including `|`, `&`, `: `, ` #` and a leading YAML indicator character.

Changing any of these replaces the instance template, so the managed instance group rolls every
instance. Plan it as a restart of the whole group.

### What this writes into `config.yml`

`scripts/startup.sh` adds a `search:` block, which is what turns the Nexus One index on. Every
instance writes the same block, so they share one index:

```yaml
search:
  type: http
  mode: OPENSEARCH
  uri: https://opensearch.internal.example.com:9200
  username: nexusiq
  password: <read from Secret Manager at boot>
  nexusOneIndexReplicas: 0
```

Three things about that block are deliberate:

- **`type: http` with basic auth.** Google Cloud has no request signing for OpenSearch, so a user
  name and password are how the servers authenticate.
- **`mode: OPENSEARCH` is stated rather than left out.** Leaving it out defaults to `HYBRID`, which
  writes every batch to the built-in index as well. That costs indexing time and cannot roll an
  index generation back.
- **`nexusOneIndexReplicas` is stated rather than left out.** Nexus IQ Server's own default is 0,
  and stating it keeps the value visible next to the cluster it describes.

### How the password reaches the servers

`opensearch_password` is written to a Secret Manager secret named
`<cluster_name>-opensearch-password-<suffix>`, or `nexus-iq-ha-opensearch-password-<suffix>` when
`cluster_name` is left empty, alongside the two the database already uses. Each instance reads it
at boot with `gcloud secrets versions access`. That matters more here than on a single instance: a
value in the instance template's metadata is readable on every instance the group creates, and the
group creates them without being asked. The compute service account gets its own
`roles/secretmanager.secretAccessor` grant on the new secret, matching how this root grants the two
database secrets one at a time.

To rotate the password, add a new secret version and roll the group:

```bash
SECRET=$(terraform output -raw opensearch_password_secret_name)
printf '%s' 'NEW_PASSWORD' | gcloud secrets versions add "$SECRET" --data-file=-
gcloud compute instance-groups managed rolling-action restart \
  "$(terraform output -raw instance_group_manager_name)" --region <your-region>
```

Each replacement instance re-runs `scripts/startup.sh`, which reads the newest secret version. The
script writes an fstab entry for the Filestore share, so on an instance that has booted before the
share is usually mounted already by the time the script runs, and mounting it again on the same
mount point is refused. The mount is therefore skipped when the share is already there; without
that, the boot would end at the mount, before the container was recreated on the new password.

The secret value also lives in Terraform state, because `opensearch_password` is an input variable.
Keep the state backend private.

### Firewall

This root denies all ingress at priority 65534 and allows egress only on 80, 443, 5432 and UDP 53.
Both ends therefore need a rule:

- **Ingress.** `search.tf` adds a rule letting instances tagged `nexus-iq-ha` reach instances
  tagged `nexus-iq-opensearch` on `opensearch_port`. **Tag each OpenSearch node
  `nexus-iq-opensearch`** or the cluster is unreachable from the servers. The rule matches on the
  network tag, not on the service account, so **anything in this VPC tagged `nexus-iq-ha` reaches
  the cluster's port**, not only this instance group.
- **Egress.** `opensearch_port` is added to the `<cluster_name>-allow-outbound` rule. **This one is
  required**, not merely declarative: that rule is the only egress rule in the root, so without the
  port the servers cannot reach the cluster at all unless it listens on 80 or 443.

A cluster outside this VPC is reached over whatever path you have built to it, and the ingress rule
has no effect on it. The egress rule still applies.

### The cluster to build

Verified against the OpenSearch source at tags `2.19.0` and `3.2.0`.

| | What to run |
|---|---|
| OpenSearch version | 2.19 or later. The 2.19 line is the long-term support release |
| Cluster managers | Three dedicated cluster manager nodes, so losing one leaves a quorum. This architecture is the HA one, and a single cluster manager undoes that |
| Data nodes | At least two, spread across the zones in `availability_zones`, with `opensearch_index_replicas` at 1 or more so a lost node does not lose a shard |
| Heap | Half of each node's RAM, and never above 31 GB, so compressed object pointers stay on |
| Disk | SSD persistent disk. The index is write-heavy during a rebuild |
| Network | Private IP addresses in this VPC, or a VPC you have peered to it. No public address |
| Security | The OpenSearch security plugin, with a user for Nexus IQ Server that can create, read and write indices |
| Snapshots | The `repository-gcs` plugin, on every node |

The machine shape per size is not published yet. The one measured OpenSearch sizing study ran above
this architecture's ceiling and on a different cloud, so a shape read off it would be a guess rather
than a measurement.

`opensearch_index_replicas` by size:

| Size | `opensearch_index_replicas` |
|------|:--------------------------------------|
| **M** | `0` for now. **Placeholder**: the figure for a multi-node cluster is being measured and is not published yet |
| **L** | `0` for now. **Placeholder**, same reason |
| **XL** | `0` for now. **Placeholder**, same reason |

`0` leaves the index with no redundancy, so a lost data node loses a shard until the index is
rebuilt. Set it to at least 1 once the cluster has more than one data node, which is what this
architecture asks for.

### Trusting a private certificate authority

With `opensearch_use_tls = true`, each server's JVM has to trust the cluster's certificate. A
certificate from a public authority already works and needs nothing below.

A certificate from a private authority needs that authority added to the JVM trust store, and
Nexus IQ Server has no per-connection trust setting, so the whole JVM is affected. **Copy the trust
store and point the JVM at the copy. Replacing the JVM's own trust store breaks Nexus IQ Server's
calls to the Sonatype data service**, which rely on the public authorities already in it.

Prepare the copy once, on Cloud Filestore, so every instance the group creates sees it. **There is
no `keytool` on the instances**: the startup script installs `docker.io`, `nfs-common`, `jq`,
`curl` and `wget` only, and no JDK. Every step below therefore runs `keytool` from inside the
container, which does carry one.

```bash
# On any one instance, once the container is running.
# 1. Copy the JVM's own trust store onto Cloud Filestore. The container sees /mnt/filestore as
#    /sonatype-work, so one copy is reachable from both sides and from every other instance.
docker exec nexus-iq-server cp /opt/sonatype/nexus-iq-server/lib/security/cacerts /sonatype-work/cacerts
# These paths are the ones the published image uses: its Dockerfile installs the server, and
# the jlinked runtime that ships inside it, at /opt/sonatype/nexus-iq-server. Confirm them on
# the image you are running with:
#   docker exec nexus-iq-server sh -c 'find / -name cacerts -type f 2>/dev/null'
#   docker exec nexus-iq-server sh -c 'find / -name keytool -type f 2>/dev/null'

# 2. Put your certificate authority where the container can read it, and add it to the copy.
#    The default trust store password is "changeit".
docker cp /path/to/ca.pem nexus-iq-server:/tmp/ca.pem
docker exec nexus-iq-server /opt/sonatype/nexus-iq-server/bin/keytool -importcert -noprompt \
  -keystore /sonatype-work/cacerts -storepass changeit \
  -alias opensearch-ca -file /tmp/ca.pem

# 3. Confirm the authority is in the copy, and that the public ones are still there.
docker exec nexus-iq-server /opt/sonatype/nexus-iq-server/bin/keytool -list \
  -keystore /sonatype-work/cacerts -storepass changeit | grep -c 'trustedCertEntry'
docker exec nexus-iq-server /opt/sonatype/nexus-iq-server/bin/keytool -list \
  -keystore /sonatype-work/cacerts -storepass changeit -alias opensearch-ca
```

Then make every instance use it. `/mnt/filestore` is already mounted into the container as
`/sonatype-work`, so no new mount is needed, and `java_opts` in `terraform.tfvars` gains:

```
-Djavax.net.ssl.trustStore=/sonatype-work/cacerts -Djavax.net.ssl.trustStorePassword=changeit
```

Changing `java_opts` replaces the instance template and rolls the group, which is the point: every
instance then reads the same copy.

**`http` is accepted too**, and skips all of the above. Nexus IQ Server validates the scheme and
takes either one. The cost is that the basic auth password is sent unencrypted on every request.
**Use `https`.** The copy above is a one-time step, and a password on the wire is permanent. `http`
is reasonable only for a short evaluation on a private subnet you control.

### Snapshots, and the credential they need

**A snapshot repository on Cloud Storage needs no service account JSON key.** The
`repository-gcs` plugin falls back to application default credentials when no `credentials_file` is
in the OpenSearch keystore, and on Compute Engine that resolves to the service account attached to
the instance the node runs on, read from the metadata server.

**Do not add a key back.** Several widely read third-party guides state the opposite, that
application default credentials are "not supported out of the box" and a key file is mandatory.
They are wrong for this plugin, and the source says so. The cost of believing them is a credential
that never expires, sits on every data node, and can write to every backup.

The evidence, read in the OpenSearch source at tags `2.19.0` and `3.2.0`, which are identical here:

- `GoogleCloudStorageClientSettings.loadCredential` returns `null` when
  `gcs.client.<name>.credentials_file` is absent, with its own comment saying this is deliberate so
  that "the default credential can be loaded later when creating the Storage client".
- `GoogleCloudStorageService.createStorageOptions` then calls
  `GoogleApplicationDefaultCredentials.get()`, which calls
  `GoogleCredentials.getApplicationDefault()`.

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

The node log records `"Application Default Credentials" will be in use` when the fallback is taken,
which is how to confirm no key is being read.

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
