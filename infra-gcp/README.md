# Sonatype IQ Reference Architecture - GCP with Docker (Single Instance)

This directory contains Terraform configuration for deploying a **single-instance** Sonatype IQ Server on Google Cloud Platform using GCE with Docker containers.

---

## Sizing Guide

This single-instance architecture supports sizes **XS**, **S**, and **M**. Choose your size based on application count and daily evaluation volume:

| Size | Applications | Evaluations/Day | Compute | Java Heap | Machine Type |
|------|:------------:|:---------------:|:-------:|:---------:|:------------:|
| **XS** ¹ | < 500 | < 1,000 | 2 vCPU / 16 GB | 12 GB | n4a-highmem-2 (ARM) |
| **S** ¹ | 500 – 2,000 | 1,000 – 5,000 | 4 vCPU / 32 GB | 24 GB | n4a-highmem-4 (ARM) |
| **M** | 2,000 – 10,000 | 5,000 – 10,000 | 8 vCPU / 64 GB | 48 GB | n4a-highmem-8 (ARM) |

> ¹ XS and S are projected sizing estimates. M has been validated through performance testing on GCP ARM instances.

> **ARM instances recommended.** n4a costs 15% less on demand than the x86 n4 equivalent (`n4a-highmem-8` against `n4-highmem-8` in us-central1, list prices in November 2026).

> **Need more capacity?** For 10,000+ applications or multi-node deployments, use the [High Availability](../infra-gcp-ha/) or [Kubernetes](../infra-gcp-ha-k8s-helm/) architectures.

### Recommended `terraform.tfvars` by Size

<details>
<summary><strong>Size XS</strong> — Extra Small (< 500 applications)</summary>

```hcl
gce_machine_type     = "n4a-highmem-2"     # 2 vCPU, 16 GB (ARM)
iq_docker_image      = "sonatype/nexus-iq-server:latest"
java_opts            = "-Xms12g -Xmx12g -XX:MaxDirectMemorySize=4g -XX:+UseG1GC -XX:+AlwaysPreTouch -Dinsight.threads.monitor=3 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_instance_tier     = "db-custom-2-7680"  # 2 vCPU, 7.5 GB
db_disk_size         = 64                  # GB
```
</details>

<details>
<summary><strong>Size S</strong> — Small (500 – 2,000 applications)</summary>

```hcl
gce_machine_type     = "n4a-highmem-4"     # 4 vCPU, 32 GB (ARM)
iq_docker_image      = "sonatype/nexus-iq-server:latest"
java_opts            = "-Xms24g -Xmx24g -XX:MaxDirectMemorySize=6g -XX:+UseG1GC -XX:+AlwaysPreTouch -Dinsight.threads.monitor=5 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_instance_tier     = "db-custom-2-13312" # 2 vCPU, 13 GB
db_disk_size         = 128                 # GB
```
</details>

<details>
<summary><strong>Size M</strong> — Medium (2,000 – 10,000 applications)</summary>

```hcl
gce_machine_type     = "n4a-highmem-8"     # 8 vCPU, 64 GB (ARM)
iq_docker_image      = "sonatype/nexus-iq-server:latest"
java_opts            = "-Xms48g -Xmx48g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/Java_Heap_logs -XX:+CrashOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_instance_tier     = "db-custom-8-30720" # 8 vCPU, 30 GB (Enterprise)
db_disk_size         = 128                 # GB, auto-resize enabled
filestore_tier       = "BASIC_HDD"         # 1 TiB (600 read / 1,000 write IOPS)
filestore_capacity_gb = 1024               # 1 TiB minimum
```
</details>

### Database Sizing (Cloud SQL PostgreSQL)

| Size | DB Tier | vCPU | Memory | Storage |
|------|:--------|:----:|:------:|:-------:|
| **XS** | db-custom-2-7680 | 2 | 7.5 GB | 64 GB |
| **S** | db-custom-2-13312 | 2 | 13 GB | 128 GB |
| **M** | db-custom-8-30720 (Enterprise) | 8 | 30 GB | 128 GB (auto-resize to 500 GB) |

---

## Deployment Guide

### Step 1: Prerequisites

#### Required Tools
Install these tools on your local machine:

| Tool | Version | Installation | Purpose |
|------|---------|--------------|---------|
| **Terraform** | >= 1.2 | [Install Guide](https://developer.hashicorp.com/terraform/install) | Infrastructure as Code |
| **gcloud CLI** | Latest | [Install Guide](https://cloud.google.com/sdk/docs/install) | GCP API access |

#### GCP Account Requirements
- GCP account with appropriate permissions
- GCP Project with billing enabled
- Ability to create: Compute Engine, Cloud SQL, Cloud Filestore, Load Balancer

#### Required GCP Permissions
Your GCP account needs permissions for these services:
- **Compute Engine**: Instances, instance groups, health checks, routers
- **Networking**: VPC, subnets, firewall rules, Cloud NAT, Global Load Balancers, backend services, URL maps, target proxies, global forwarding rules, global addresses
- **Database**: Cloud SQL instances, databases, users, SSL certificates
- **Storage**: Cloud Filestore instances, NFS shares
- **Security**: Secret Manager secrets and secret versions, managed SSL certificates
- **IAM**: Service accounts, IAM policy bindings (roles assignment)
- **Service Networking**: Private service connections, VPC peering for Cloud SQL

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
   cd /path/to/sca-example-terraform/infra-gcp
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
   ./gcp-plan.sh
   ```

   This shows what resources will be created without actually deploying them.

3. **Deploy the infrastructure:**
   ```bash
   ./gcp-apply.sh
   ```

   The script will display the application URL when complete.

### Step 5: Access Sonatype IQ Server

1. **Wait for service to be ready:**
   - Initial startup can take 5-10 minutes
   - Docker container pulls image and starts IQ Server
   - Database migrations, if needed, run on first boot

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
   ./destroy.sh
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
> | `postgres_version` | POSTGRES_17 | POSTGRES_18 |
> | `db_disk_size` | 100 | 128, and the disk cannot shrink |
> | `db_max_disk_size` | 1000 | 500. An instance already above 500 GB keeps its size here |
> | `java_opts` | 48 GB heap, no direct memory cap | the Size M `java_opts` above |
> | `gce_boot_image` | `debian-cloud/debian-12` | empty, which picks `debian-12-arm64` on an Arm machine type |
>
> The server log rolls hourly, and logback deletes only names the hourly pattern
> produces, so the daily archives an earlier version wrote stay in the log
> directory. Delete them once, on the VM:
> `sudo rm /mnt/sonatype-work/logs/clm-server-????-??-??.log.gz`. That name
> never matches an hourly archive.

### Configuration Variables

Edit `terraform.tfvars` to customize your deployment:

```hcl
# General Configuration
gcp_project_id = "your-gcp-project-id"
gcp_region     = "us-central1"
gcp_zone       = "us-central1-a"
environment    = "dev"

# Resource Naming
# Empty reproduces the published names. Set it per deployment when several sizes share a project.
cluster_name = ""

# Network Configuration
# This root creates subnets inside an auto-created VPC, so there is no
# VPC-wide CIDR variable. Set the three subnet ranges instead.
public_subnet_cidr  = "10.100.1.0/24"
private_subnet_cidr = "10.100.10.0/24"
db_subnet_cidr      = "10.100.20.0/24"

# GCE with Docker Configuration
gce_machine_type   = "n4a-highmem-8"      # 8 vCPU, 64 GB (ARM)
gce_boot_image     = ""                     # Empty picks Debian 12 for the machine type's architecture
gce_boot_disk_size = 100
iq_desired_count   = 1                    # Single instance
iq_docker_image    = "sonatype/nexus-iq-server:latest"
java_opts          = "-Xms48g -Xmx48g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/Java_Heap_logs -XX:+CrashOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"

# Database Configuration
db_name                             = "nexusiq"
db_username                         = "nexusiq"
db_password                         = "CHANGE_ME_STRONG_PASSWORD"  # Change this!
postgres_version                    = "POSTGRES_18"
db_instance_tier                    = "db-custom-8-30720"  # 8 vCPU, 30 GB (Enterprise)
db_edition                          = "ENTERPRISE"
db_availability_type                = "ZONAL"
db_disk_size                        = 128
db_max_disk_size                    = 500
db_backup_retention_count           = 8
db_deletion_protection              = false

# Storage Configuration
filestore_zone        = "us-central1-a"
filestore_tier        = "BASIC_HDD"
filestore_capacity_gb = 1024  # 1 TB minimum

# Load Balancer Configuration
enable_ssl  = false  # Set to true and provide domain_name for HTTPS
domain_name = ""     # Required if enable_ssl is true (e.g., "iq.example.com")

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
- **Single Instance** - GCE instance with Docker container (iq_desired_count = 1)
- **`gcp_project_id`** - Your GCP project ID (required)
- **`db_password`** - Use a strong, unique password (required change)
- **`db_deletion_protection = false`** - Set to `true` for production to prevent accidental database deletion
- **`db_availability_type = "ZONAL"`** - Set to `"REGIONAL"` for production for high availability
- **`iq_docker_image`** - Use specific version tag for production (e.g., `sonatype/nexus-iq-server:1.196.0`)

### Docker Container Deployment

This deployment uses Docker containers on GCE for easier version management:

- **Official Image**: `sonatype/nexus-iq-server` from Docker Hub
- **Automated Startup**: Startup script installs Docker, mounts NFS, and launches container
- **Volume Mounts**: `/sonatype-work` and `/var/log/nexus-iq-server` mounted from Cloud Filestore
- **Database Configuration**: Generated dynamically from environment variables
- **Automatic Restart**: Container configured with `--restart always`

## Running Several Sizes in One Project

Every resource name that has to be unique inside a Google Cloud project derives from one variable,
`cluster_name`, so two sizes of this architecture can live in one project without colliding.

```hcl
cluster_name = "iq-xs"   # a distinct value per deployment
```

**The default is empty, which reproduces the names this architecture has always published**, so a
customer who sets nothing sees nothing renamed. That includes the two
firewall rules that have always carried no prefix at all, `allow-egress-gce` and
`allow-google-apis`: an empty `cluster_name` adds nothing to either, and a set one prefixes them
like everything else.

**The first apply after upgrading still replaces the VM**, because `scripts/startup.sh` is the
instance's startup script and it changes in this version. The instance is destroyed before its
replacement is created, so IQ Server is down until the new VM has started, and the data on
Filestore and Cloud SQL is kept.

Setting it moves the
VPC, both subnets, the router, the Cloud NAT, the reserved address, every firewall rule, the load
balancer and its proxies and forwarding rules, the health check, the instance, the instance group,
Filestore, both service accounts, the Cloud SQL instance, the client certificate and both Secret
Manager secrets. Measured with a plan: 30 of the 32 named attributes moved.

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
| Cloud SQL instance | **Immediate.** Google's own documentation now states "the deleted instance name can be reused immediately to create a new instance" |
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
OpenSearch instead moves the index off the server, which is what the Nexus One features read.

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
opensearch_index_replicas = 0  # 1 at M, where the cluster has three data nodes
```

All of `opensearch_endpoint`, `opensearch_username` and `opensearch_password` are required once
`search_engine` is `"opensearch"`, and the plan fails naming whichever is missing.

`opensearch_username` may not hold a single quote, a double quote, a dollar sign, a
backtick or a backslash, and the plan refuses one that does. The startup script writes it
into a single-quoted YAML scalar inside a double-quoted shell string, and those five are the
only characters that would break one or the other. Everything else is written through
intact, including `|`, `&`, `: `, ` #` and a leading YAML indicator character.

### What this writes into `config.yml`

`scripts/startup.sh` adds a `search:` block and a `nexusOne.connection` block naming the same
cluster:

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
    nexusOneIndexReplicas: 0
```

Four things about these blocks are deliberate:

- **`type: http` with basic auth.** Google Cloud has no request signing for OpenSearch, so a user
  name and password are how the server authenticates.
- **`mode: OPENSEARCH` is stated rather than left out.** Leaving it out defaults to `HYBRID`, which
  writes every batch to the built-in index as well. That costs indexing time and cannot roll an
  index generation back.
- **A `nexusOne.connection` block naming the same cluster.** The Nexus One index builds its
  connection from this block alone, and reads `nexusOneIndexReplicas` from it. With `search:` set
  and this block absent, enabling the `nexus-one` feature is refused.
- **`nexusOneIndexReplicas` is stated rather than left out.** When Nexus IQ Server is not given a
  count, it uses 1. Stating it keeps the value visible next to the cluster it describes.

### How the password reaches the server

`opensearch_password` is written to a Secret Manager secret named
`<cluster_name>-opensearch-password`, or `nexus-iq-opensearch-password` when `cluster_name` is
left empty. The instance reads it at boot with `gcloud secrets versions access`, so the password is
never written into instance metadata, where anyone who can describe the instance could read it. The
GCE service account already holds `roles/secretmanager.secretAccessor`, so no further grant is
needed.

To rotate the password, add a new secret version and restart the instance. Both names come from
Terraform outputs, so this works whatever `cluster_name` is set to:

```bash
SECRET=$(terraform output -raw opensearch_password_secret_name)
printf '%s' 'NEW_PASSWORD' | gcloud secrets versions add "$SECRET" --data-file=-
gcloud compute instances reset "$(terraform output -raw instance_name)" --zone <your-zone>
```

The reset re-runs `scripts/startup.sh`, which reads the newest secret version and then removes and
recreates the container, so the new password is the one the container starts with. Two things in
that script are what make the rotation take, and both only matter from the second boot onward:

- **The container is removed first.** `docker run --name nexus-iq-server` fails on a name clash, and
  the script runs under `set -e`, so without the removal the script would stop there and
  `--restart always` would bring the old container back on the old password.
- **The Filestore mount tolerates an already-mounted share.** The script writes an fstab entry, so
  on a later boot systemd has usually mounted the share before the script runs, and mounting it
  again on the same mount point is refused. Unconditionally, that ended the boot before the
  container was recreated.

The secret value also lives in Terraform state, because `opensearch_password` is an input variable.
Keep the state backend private.

### Firewall

Google Cloud denies all ingress that no rule allows, and allows all egress unless a deny rule says
otherwise. Two rules follow from that:

- **Ingress.** `search.tf` adds a rule letting instances tagged `nexus-iq-server` reach instances
  tagged `nexus-iq-opensearch` on `opensearch_port`. **Tag each OpenSearch node
  `nexus-iq-opensearch`** or the cluster is unreachable from the server. The rule matches on the
  network tag, not on the service account, so **anything in this VPC tagged `nexus-iq-server`
  reaches the cluster's port**, not only this instance.
- **Egress.** `opensearch_port` is added to the `allow-egress-gce` rule, which carries no
  `cluster_name` prefix on the default and `-<cluster_name>` when one is set. That rule is an allow
  rule, so today it changes nothing on its own, but it states the intent and keeps working if you
  add an egress deny rule of your own. **This root has no 5432 egress rule**, unlike
  `infra-gcp-ha`, which is the clearest sign that egress here is permissive.

A cluster outside this VPC is reached over whatever path you have built to it, and neither rule
affects it.

### The cluster to build

Verified against the OpenSearch source at tags `2.19.0` and `3.2.0`.

| | What to run |
|---|---|
| OpenSearch version | 2.19 or later. The 2.19 line is the long-term support release |
| Data nodes | One is enough for XS and S. More than one needs `opensearch_index_replicas` raised to at least 1, or a lost node loses a shard |
| Heap | Half of each node's RAM, and never above 31 GB, so compressed object pointers stay on |
| Disk | Hyperdisk Balanced on C4A, or SSD persistent disk on a series that takes it. The index is write-heavy during a rebuild |
| Network | Private IP addresses in this VPC, or a VPC you have peered to it. No public address |
| Security | The OpenSearch security plugin, with a user for Nexus IQ Server that can create, read and write indices |
| Snapshots | The `repository-gcs` plugin, on every node |

Per size:

| Size | Data nodes | Machine type | Storage per node | Cluster managers | Shards ¹ | `opensearch_index_replicas` |
|------|:----------:|:------------:|:----------------:|:----------------:|:--------:|:---------------------------:|
| **XS** | 1 | `c4a-standard-1`, 1 vCPU, 4 GB | 25 GB Hyperdisk Balanced | none | 1 | `0`. One data node cannot place a replica |
| **S** | 1 | `c4a-standard-2`, 2 vCPU, 8 GB | 50 GB Hyperdisk Balanced | none | 1 | `0`. One data node cannot place a replica |
| **M** | 3 | `c4a-standard-2`, 2 vCPU, 8 GB | 100 GB Hyperdisk Balanced | 3 x `c4a-standard-1`, 1 vCPU, 4 GB, 2 GB heap, 20 GB Hyperdisk Balanced boot disk | 3 | `1` |

C4A is Arm and takes Hyperdisk only, so each data node needs an arm64 image and a Hyperdisk Balanced
volume. **At M, the machine type and node count are the measured values**, and so is the replica
count. That measurement ran 1 shard per index, so the 3 shards at M are not measured on GCP.
Storage per node is the published size, chosen at or above the measured use. XS and S are not
measured on GCP. The measurements are on [the OpenSearch sizing pages](https://sonatype.atlassian.net/wiki/spaces/INSIGHT/pages/2866971307).

At M the cluster managers are dedicated, so they hold no data and take no search traffic, and
three of them keep a quorum when one is lost. They are `c4a-standard-1`, the same vCPU and memory
as the AWS equivalent, `m8g.medium.search`, and take half their RAM as heap, as the data nodes do.
The GCP M measurement ran them on `c4a-standard-2`. XS and S run none: one data node is its own cluster manager.

**Put an internal passthrough Network Load Balancer in front of the data nodes at M**, and set
`opensearch_endpoint` to its address, so Nexus IQ Server reaches one endpoint and replacing a data
node does not change its configuration. This is how the GCP M measurement ran. Create:

- **A regional TCP health check on port 9200.**
- **A regional backend service** with `--load-balancing-scheme INTERNAL --protocol TCP` and that
  health check, whose backends are one unmanaged instance group per zone holding that zone's data
  nodes. The cluster managers stay out of it.
- **A forwarding rule on a reserved private IP address** in this VPC, for TCP port 9200.
- **A firewall rule allowing TCP 9200 from Google's health check ranges** `35.191.0.0/16` and
  `130.211.0.0/22` to the `nexus-iq-opensearch` tag. Without it the backends never turn healthy.

At XS and S, with one data node, `opensearch_endpoint` can name that node directly.

Google describes the load balancer in
[Internal passthrough Network Load Balancer overview](https://cloud.google.com/load-balancing/docs/internal).

¹ Primary shards for the component, violation and vulnerability indices. Every other index keeps 1.
Shard counts are held in Nexus IQ Server's database, not in `config.yml`, and only take effect when
an index is created, so **at M set them before the Nexus One index is first built**, with
one request to the configuration API as an administrator:

```bash
curl -u admin -X PUT -H 'Content-Type: application/json' \
  -d '{"nexusOneIndexComponentShards": 3, "nexusOneIndexViolationShards": 3, "nexusOneIndexVulnerabilityShards": 3}' \
  https://<your IQ Server URL>/api/v2/config
```

An index built before the change keeps its count until it is rebuilt.

### Trusting a private certificate authority

With `opensearch_use_tls = true`, the server's JVM has to trust the cluster's certificate. A
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

Terraform stores it in a Secret Manager secret named `<cluster_name>-opensearch-ca`, or
`nexus-iq-opensearch-ca` when `cluster_name` is left empty, which the
instance reads at boot with the service account's existing `roles/secretmanager.secretAccessor`.
The startup script mounts it into the container, and at every container start the entrypoint
copies the image's JVM trust store to `/tmp/opensearch-cacerts`, adds the authority with the
image's own `keytool`, and adds `-Djavax.net.ssl.trustStore` to `JAVA_OPTS`. Nothing has to be
added to `java_opts`. To change the certificate, apply and then reset the instance, as for a
password rotation below, so the startup script reads the new secret version.

**`http` is accepted too**, and skips all of the above. Nexus IQ Server validates the scheme and
takes either one. The cost is that the basic auth password is sent unencrypted on every request.
**Use `https`.** The copy above is one variable, and a password on the wire is permanent. `http`
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

### What running the cluster yourself costs you

None of this is handled by this configuration, and all of it has to be handled by someone:

- **Upgrades.** Rolling restarts, version by version, with the cluster kept green between steps.
- **Snapshots and restore drills.** A snapshot nobody has restored is not a backup.
- **Capacity.** Disk watermarks block writes before they fill the disk, and a blocked write is how
  an index rebuild stalls.
- **Certificate renewal.** Both the cluster's certificate and the trust store copy above.
- **Monitoring.** Cluster status, unassigned shards, JVM heap pressure, rejected write threads.
- **The password.** Rotating it in Secret Manager and restarting the server.

### Rebuilding the index

Switching `search_engine` to `"opensearch"` points the server at an empty cluster. The index is
built from the Nexus IQ Server administration pages, not by Terraform, and the build reads the whole
database, so run it when the server is otherwise quiet.

## Security Features

- **VPC Isolation**: Application runs in private subnets
- **Database Security**: Cloud SQL in isolated subnet with private IP
- **Secrets Management**: Database credentials stored in Google Secret Manager
- **Encryption**:
  - Cloud Filestore encrypted at rest
  - Cloud SQL encrypted at rest and in transit (ENCRYPTED_ONLY mode)
  - HTTPS support with managed SSL certificates (requires domain name configuration)
- **Firewall Rules**: Least-privilege network access
- **Service Account**: GCE instance uses service account with minimal permissions

## Reliability and Backup

This is a **single instance** deployment.
- **Single Instance**: One GCE instance running Docker container (runs in one zone)
- **Single Zone Database**: Cloud SQL instance runs in one zone (unless REGIONAL configured)
- **Automatic Restart**: Docker container automatically restarts on failure
- **Instance Auto-Healing**: Managed instance group can recreate failed instances
- **Database Backups**: Automated Cloud SQL backups with 7-day retention (configurable)
- **File Store Persistence**: Application data stored on Cloud Filestore survives instance restarts

## Monitoring and Logging

- **Cloud Logging**: Container logs automatically sent to Cloud Logging
- **Serial Console**: Startup script logs available via serial console
- **Docker Logs**: Access via `docker logs` command on instance
- **Persistent Logs**: Logs stored on Cloud Filestore at `/var/log/nexus-iq-server`
- **Health Checks**: Load balancer performs health checks on `/ping` endpoint

## Persistent Storage

- **Cloud Filestore**: NFS-mounted shared storage for `/sonatype-work` directory (1 TB minimum)
- **Database**: Cloud SQL PostgreSQL for application data. Minimum PostgreSQL 15. Recommended, and the default for new deployments, PostgreSQL 18
- **Auto-scaling Storage**: Cloud SQL storage scales automatically up to configured limit

## Networking

### Subnets
- **Public Subnet**: Load balancer and Cloud NAT
- **Private Subnet**: GCE instance (no external IP by default)
- **Database Subnet**: Cloud SQL instance

### Firewall Rules
- **Load Balancer**: Allows HTTP (80), HTTPS (443) from internet
- **GCE Instance**: Allows traffic from load balancer health checks and internal VPC
- **Cloud SQL**: Allows PostgreSQL (5432) from private subnet only

## Important: Admin Port 8071 Not Exposed

The admin port 8071 is configured within the IQ Server container but **not exposed externally** through the Load Balancer. Only the main application port 8070 is accessible via port 80.

**Admin port access** is available through SSH to the GCE instance and Docker exec if needed for troubleshooting.
