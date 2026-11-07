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

> All sizes validated through performance testing on GCP ARM instances. Expected evaluation throughput with continuous monitoring running: ~310 evals/hour/node (M/L) or ~405 evals/hour/node (XL).

<!-- TO BE UPDATED (CLM-55927): the ~310 and ~405 evals/hour figures above are awaiting a
     re-measurement. Leave the numbers alone until it lands. The qualifier that they are measured with
     continuous monitoring running was added so a reader does not take them as general evaluation
     throughput. -->

> ¹ OpenSearch is part of this architecture at every size, not an optional extra. See [OpenSearch](#opensearch) for what it serves, what this architecture does and does not do about it, and which parts of the per-size cluster specification are not published yet.

> **GCP was the primary test platform.** All performance data was validated on GCP ARM-based instances (Google Axion).

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
db_instance_tier        = "db-custom-8-30720" # 8 vCPU, 30 GB (Enterprise)
db_availability_type    = "REGIONAL"
filestore_tier          = "BASIC_HDD"
filestore_capacity_gb   = 1024             # 1 TiB
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
db_instance_tier        = "db-custom-8-30720" # 8 vCPU, 30 GB (Enterprise)
db_availability_type    = "REGIONAL"
filestore_tier          = "BASIC_HDD"
filestore_capacity_gb   = 2560             # 2.5 TiB
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
db_instance_tier        = "db-custom-16-65536" # 16 vCPU, 64 GB (Enterprise)
db_availability_type    = "REGIONAL"
filestore_tier          = "BASIC_HDD"
filestore_capacity_gb   = 10240            # 10 TiB
```
</details>

> `java_opts` above is not read on this root. The Helm chart renders the pod spec, so the heap each
> pod gets is `iq_server.javaOpts` in `helm-values.yaml`: set the per-size value there, in the same
> shape as the lines above.

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

> BASIC_HDD is the default recommendation. At 10+ TiB, HDD unlocks 5,000 write IOPS (4x observed peak of ~1,212 ops/sec) at roughly the same cost as 2.5 TiB SSD. Enterprise edition Cloud SQL (not Enterprise Plus) is sufficient.

### OpenSearch

IQ Server uses an OpenSearch cluster for Advanced Search and for the Nexus One index behind the Nexus
One list pages, typeahead, and dashboard, and **it is required at every size this architecture
supports.** One cluster serves both features, through a single `search:` block in IQ Server's
`config.yml`: one endpoint, one set of credentials, and nothing extra to switch on per feature.

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
survivable. **IQ Server's own default is 0**, so this architecture sets
`search.nexusOneIndexReplicas` itself rather than inheriting that default:

| Size | OpenSearch data nodes | Replica count |
|------|:---------------------:|:-------------:|
| **M** | more than 1 | Not published yet |
| **L** | more than 1 | Not published yet |
| **XL** | more than 1 | Not published yet |

The rules behind this, including what a yellow index does and does not mean and how to give the
Advanced Search index a matching replica count, are in the
[top-level OpenSearch section](../README.md#replicas-each-architecture-sets-the-count-and-iqs-own-default-is-0).

#### Plan for twice the index during a rebuild

A Nexus One index rebuild builds a complete new set of indices and keeps the old set for 30 minutes
after the cutover, so the cluster holds twice the Nexus One shards and twice the Nexus One disk for the
whole run and for half an hour afterwards. **Judge free storage against the doubled figure, not the
steady state.** A replica is a separate doubling that applies at the same time. The full rules, and why
a rebuild is not a backup, are in the
[top-level OpenSearch section](../README.md#plan-for-twice-the-index-during-a-rebuild).

#### Per-size cluster specification

**Not published yet.** The data node count, node size, JVM heap, and storage for each size are awaiting
a per-size measurement. What is settled is the shape of the requirement: every size this architecture supports runs more than one data node, so
a replica is placeable at all of them.

<!-- TO BE ADDED (CLM-55930): the per-size specification and the replica counts above are CLM-55930's to publish.
     They need measurements that do not exist. The only OpenSearch sizing data today is one estate
     larger than XL's 80,000 application ceiling, all taken at zero replicas, so it is not
     evidence for a number at any published size. Do not derive these values. -->

See the [top-level OpenSearch section](../README.md#opensearch) for the full planning rules.

---

## Deployment Guide

### Step 1: Prerequisites

#### Required Tools
Install these tools on your local machine:

| Tool | Version | Installation | Purpose |
|------|---------|--------------|---------  |
| **Terraform** | >= 1.0 | [Install Guide](https://developer.hashicorp.com/terraform/install) | Infrastructure as Code |
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
- **Database**: Cloud SQL instances (including read replicas), databases, users, SSL certificates
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

2. **Edit `terraform.tfvars` with your values (or leave to get started quickly):**
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
kubernetes_version           = "1.33"
node_instance_type           = "n4a-highmem-8"  # 8 vCPU, 64 GB (ARM)
node_group_min_size          = 2
node_group_max_size          = 5
node_group_desired_size      = 3
node_disk_size               = 100
gke_maintenance_window_start = "03:00"

# PostgreSQL Configuration (Regional HA)
postgres_version                   = "POSTGRES_15"
db_instance_tier                   = "db-custom-8-30720"  # 8 vCPU, 30GB RAM
db_availability_type               = "REGIONAL"
db_disk_size                       = 100
db_max_disk_size                   = 1000
db_max_connections                 = "400"
db_backup_retention_count          = 7
db_deletion_protection             = false
enable_read_replica                = true
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
helm_chart_version      = "195.0.0"
# Not read on this root: set iq_server.javaOpts in helm-values.yaml, which the chart puts on the pods.
java_opts               = "-Xms48g -Xmx48g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/Java_Heap_logs -XX:+CrashOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
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
> | `kubernetes_version` | `1.27` | `1.33` |
> | `filestore_capacity_gb` | 1024 | 2560, and the share cannot shrink |
> | `db_max_disk_size` | 500 | 1000 |
> | `iq_server.resources` in `helm-values.yaml` | 4 to 6 CPU, 16 to 24 GB | 6 to 8 CPU, 48 to 56 GB |
> | `iq_server.javaOpts` in `helm-values.yaml` | 24 GB heap | 48 GB heap |

**Important Settings:**
- **`node_group_min_size = 2`** - Minimum GKE node capacity
- **`node_group_max_size = 5`** - Maximum GKE node capacity
- **`nexus_iq_replica_count = 3`** - Initial number of replicas for HA (minimum 2 recommended, requires HA license)
- **`db_availability_type = "REGIONAL"`** - Regional database with automatic failover
- **`enable_read_replica = true`** - Database read replica for load distribution
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

Every resource name that has to be unique inside a Google Cloud project already derived from
`cluster_name` in this root, which is why it needed no renaming work: the GKE cluster, the VPC, all
four subnets, the router, the Cloud NAT, every firewall rule, the Cloud Armor policy, the ingress
address, the node pool, both Workload Identity service accounts, both Cloud SQL instances,
Filestore, both Secret Manager secrets, the log bucket, sink and metrics. Measured with a plan: 25
of the 27 named attributes moved when `cluster_name` changed.

```hcl
cluster_name = "iq-l"   # a distinct value per deployment
```

Two things were added. `cluster_name` is now validated against what a Google Cloud resource name
accepts, so a bad value fails at plan rather than at apply. And `force-cleanup.sh` now matches on
this deployment's own `cluster_name` rather than the fixed string `nexus-iq-ha`: with several sizes
in one project, a fixed prefix matched all of them, so the script could have deleted another size's
Cloud SQL and Filestore instances.

What does not move, and does not need to: the database name and the database user, which are
scoped to the Cloud SQL instance rather than to the project, and the Filestore share name, which
is scoped to the Filestore instance. The Kubernetes namespace and Helm release name are also
fixed, which is correct because each deployment has its own cluster.

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
the database. Both Workload Identity accounts are recreated by the next apply and both have their
roles and their Kubernetes bindings granted by the same apply, so a normal destroy and rebuild is
fine. What is not fine is deleting an account by hand and expecting to undelete it afterwards:
creating the replacement first makes the original unrecoverable.

**A Cloud SQL instance name carries a random suffix anyway**, `<cluster_name>-db-<suffix>`, and the
suffix is regenerated on every fresh apply because the `random_string` resource has no `keepers`.
That predates this change and made the old reuse window a non-issue; it still means a rebuilt
environment's database has a different name from the one before it.

## Search Backend

Nexus IQ Server ships with a built-in search index and needs nothing else running. Pointing it at
OpenSearch instead moves the index off the pods, which is what the Nexus One features read. On this
architecture it also gives every replica one shared index rather than a copy each.

**Google Cloud has no managed OpenSearch service**, so there is no first-party cluster for this
configuration to create. You run OpenSearch yourself, and this configuration takes the endpoint of
a cluster you have already built. That keeps the cluster, and the index data in it, independent of
Terraform runs here: switching `search_engine` back and forth never destroys an index.

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
backtick or a backslash, and the plan refuses one that does. `render-values.sh` writes it
into a single-quoted YAML scalar in the generated values file, and those five are the only
characters that would break it. Everything else is written through intact, including `|`,
`&`, `: `, ` #` and a leading YAML indicator character.

**Terraform alone does not apply this.** The `search:` block lives in the Helm values, so run
`terraform apply` and then `./helm-install.sh`, or `./helm-upgrade.sh` on an existing release.

### What this writes into `config.yml`

`helm-values.yaml` carries the block with placeholders between two markers,
`# search-block-begin` and `# search-block-end`. `helm-install.sh` fills them from Terraform
outputs, and the Helm chart renders the result as `config.yml` in every pod:

```yaml
    search:
      type: http
      mode: OPENSEARCH
      uri: https://opensearch.internal.example.com:9200
      username: nexusiq
      password: <filled by helm-install.sh>
      nexusOneIndexReplicas: 0
```

Three things about that block are deliberate:

- **`type: http` with basic auth.** Google Cloud has no request signing for OpenSearch, so a user
  name and password are how the pods authenticate.
- **`mode: OPENSEARCH` is stated rather than left out.** Leaving it out defaults to `HYBRID`, which
  writes every batch to the built-in index as well. That costs indexing time and cannot roll an
  index generation back.
- **`nexusOneIndexReplicas` is stated rather than left out.** Nexus IQ Server's own default is 0,
  and stating it keeps the value visible next to the cluster it describes.

**Keep the two markers.** With `search_engine = "lucene"`, `helm-install.sh` deletes everything
between them so the deployment has no `search:` block at all, which is how the built-in index stays
the default. The script then checks that no placeholder survived and refuses to install if one did,
because a literal `OPENSEARCH_URI_PLACEHOLDER` would be read as a host name.

### How the password reaches the pods

`opensearch_password` is read by `helm-install.sh` from a Terraform output and written into
`helm-values-runtime.yaml`, which is gitignored. That is the same route the database password
already takes on this architecture, and it is a different route from the two Compute Engine roots,
which read a Secret Manager secret at boot. The reason is the chart: it renders `config.yml` itself,
so a value has to be in the Helm values rather than fetched by a startup script.

Two consequences worth knowing:

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

Verified against the OpenSearch source at tags `2.19.0` and `3.2.0`.

| | What to run |
|---|---|
| OpenSearch version | 2.19 or later. The 2.19 line is the long-term support release |
| Cluster managers | Three dedicated cluster manager nodes, so losing one leaves a quorum. This architecture is the HA one, and a single cluster manager undoes that |
| Data nodes | At least two, spread across zones, with `opensearch_index_replicas` at 1 or more so a lost node does not lose a shard |
| Heap | Half of each node's RAM, and never above 31 GB, so compressed object pointers stay on |
| Disk | SSD persistent disk. The index is write-heavy during a rebuild |
| Network | Private IP addresses in this VPC, or a VPC you have peered to it. No public address |
| Security | The OpenSearch security plugin, with a user for Nexus IQ Server that can create, read and write indices |
| Snapshots | The `repository-gcs` plugin, on every node |

**Running OpenSearch inside this GKE cluster is a third option** and this configuration does not do
it. It would put the search cluster and the application on the same nodes, so a busy index rebuild
and a busy evaluation queue would compete for the same CPU and the same page cache. Separate node
pools fix that, and at that point the nodes may as well be their own instances. If you do run it in
the cluster, use the OpenSearch Kubernetes operator and its own node pool, and the endpoint here
becomes the operator's service name.

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

With `opensearch_use_tls = true`, the JVM in every pod has to trust the cluster's certificate. A
certificate from a public authority already works and needs nothing below.

A certificate from a private authority needs that authority added to the JVM trust store, and
Nexus IQ Server has no per-connection trust setting, so the whole JVM is affected. **Copy the trust
store and point the JVM at the copy. Replacing the JVM's own trust store breaks Nexus IQ Server's
calls to the Sonatype data service**, which rely on the public authorities already in it.

Pods are replaced often here, so build the copy once and mount it, rather than editing a running
pod:

```bash
# 1. Take the JVM's own trust store out of a running pod.
POD=$(kubectl get pod -n nexus-iq -l name=nexus-iq-server-ha-iq-server -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n nexus-iq "$POD" -- cat /opt/sonatype/nexus-iq-server/lib/security/cacerts > ./cacerts
# The path differs between base images. Find it with:
#   kubectl exec -n nexus-iq "$POD" -- sh -c 'find / -name cacerts -type f 2>/dev/null'
#   kubectl exec -n nexus-iq "$POD" -- sh -c 'find / -name keytool -type f 2>/dev/null'

# 2. Add your certificate authority to the copy. The default password is "changeit".
keytool -importcert -noprompt \
  -keystore ./cacerts -storepass changeit \
  -alias opensearch-ca -file /path/to/ca.pem

# 3. Confirm the authority is in the copy, and that the public ones are still there.
keytool -list -keystore ./cacerts -storepass changeit | grep -c 'trustedCertEntry'
keytool -list -keystore ./cacerts -storepass changeit -alias opensearch-ca

# 4. Put the copy in a secret every pod can mount.
kubectl create secret generic nexus-iq-truststore --from-file=cacerts=./cacerts -n nexus-iq
rm -f ./cacerts
```

**Step 1 reads the file with `cat` rather than `kubectl cp`.** `kubectl cp` runs `tar` inside the
container, and there is no `tar` in `sonatype/nexus-iq-server`: the image is built on
`ubi9-minimal`, which carries none, and nothing in the build adds one. `cat` and `find` are both
present, so the commands above work. Leave `-t` off `kubectl exec`, because a terminal rewrites the
byte stream and a trust store is a binary file. Step 3 is what proves the copy arrived whole:
`keytool -list` fails on a truncated or rewritten file instead of printing a count.

Then mount the secret and name the copy, by adding to `helm-values.yaml`:

```yaml
iq_server:
  extraVolumes:
    - name: truststore
      secret:
        secretName: nexus-iq-truststore
  extraVolumeMounts:
    - name: truststore
      mountPath: /etc/nexus-iq-server/truststore
      readOnly: true
```

and to `javaOpts` in `helm-values.yaml`:

```yaml
iq_server:
  javaOpts: "-Xms24g -Xmx24g -XX:+UseG1GC -Djava.util.prefs.userRoot=/sonatype-work/javaprefs -Djavax.net.ssl.trustStore=/etc/nexus-iq-server/truststore/cacerts -Djavax.net.ssl.trustStorePassword=changeit"
```

**Not to `java_opts` in `terraform.tfvars`.** On this root the Helm chart renders the pod spec, and
nothing here passes `java_opts` into the release, so `iq_server.javaOpts` in `helm-values.yaml` is
the only value the pods read.

Check the chart version in `helm_chart_version` accepts `extraVolumes` and `extraVolumeMounts`
under `iq_server` before relying on those key names, with
`helm show values sonatype/nexus-iq-server-ha --version <your version>`.

**`http` is accepted too**, and skips all of the above. Nexus IQ Server validates the scheme and
takes either one. The cost is that the basic auth password is sent unencrypted on every request.
**Use `https`.** The secret above is a one-time step, and a password on the wire is permanent.
`http` is reasonable only for a short evaluation on a private network you control.

### Snapshots, and the credential they need

**A snapshot repository on Cloud Storage needs no service account JSON key.** The
`repository-gcs` plugin falls back to application default credentials when no `credentials_file` is
in the OpenSearch keystore. On Compute Engine that resolves to the service account attached to the
instance; in GKE, to the Workload Identity service account bound to the pod's Kubernetes service
account.

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
- **Certificate renewal.** Both the cluster's certificate and the secret above.
- **Monitoring.** Cluster status, unassigned shards, JVM heap pressure, rejected write threads.
- **The password.** Rotating it and reinstalling the release.
- **Keeping the cluster manager quorum.** Three managers, and never two.

### Rebuilding the index

Switching `search_engine` to `"opensearch"` points the pods at an empty cluster. The index is built
from the Nexus IQ Server administration pages, not by Terraform and not by Helm, and the build reads
the whole database, so run it when the deployment is otherwise quiet. One pod performs the build and
the rest read the result.

## Security Features

- **Private GKE Cluster**: Nodes in private subnets with no public IPs
- **Workload Identity**: Secure service account access without keys (GCP's equivalent to AWS IRSA)
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
- **Read Replica**: Optional read replica for load distribution
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
- **Database**: Cloud SQL PostgreSQL 15 (regional) for application data
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
