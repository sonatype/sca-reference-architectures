# Sonatype IQ Reference Architecture - GCP with Docker (High Availability)

This directory contains Terraform configuration for deploying Sonatype IQ Server on GCP in a **High Availability configuration**: a regional Managed Instance Group running the IQ Server Docker image across three zones, regional Cloud SQL PostgreSQL, Cloud Filestore on the Regional tier, a global external Application Load Balancer and, with `search_engine = "opensearch"`, an OpenSearch cluster on Compute Engine VMs.

Sizing, the JVM rules, OpenSearch planning and the shared troubleshooting table are in the [top-level README](../README.md). This page covers what is specific to this architecture.

---

## Sizing Guide

This MIG HA architecture supports sizes **M**, **L**, and **XL**:

| Size | Applications | Evaluations per day, hour | Instances (min / target / max) | Machine type | Java heap / direct memory | Database | Filestore | OpenSearch |
|------|:------------:|:---------------:|:------------------------------:|:------------:|:-------------------------:|:--------:|:---------:|:----------:|
| **M** | 2k - 10k | ~7.5k, 250 | 2 / 2 / 3 | n4a-standard-8 (ARM) | 20 GB / 4 GB | db-custom-N4-4-32768, 128 GB, 8,000 IOPS, 252 MB/s | 500 GB, 8,000 IOPS | 3 x `c4a-standard-2` |
| **L** | 10k - 30k | ~15k, 350 | 2 / 2 / 4 | n4a-standard-16 (ARM) | 42 GB / 8 GB | db-custom-N4-8-65536, 256 GB, 8,000 IOPS, 357 MB/s | 1,536 GB, 16,000 IOPS | 3 x `c4a-standard-4` |
| **XL** | 30k - 100k | ~25k, 450 | 3 / 3 / 5 | n4a-highmem-16 (ARM) | 85 GB / 8 GB | db-custom-N4-16-131072, 512 GB, 10,000 IOPS, 446 MB/s | 4,096 GB, 24,000 IOPS | 3 x `c4a-highmem-8` |

Evaluations per day, hour are typical figures for the whole cluster on a normal day, a guide for planning,
not a limit, as in the top README's [Sizing Guide](../README.md#sizing-guide).

The values for each size are in [`examples/<size>.tfvars`](./examples/), which the top-level `deploy.sh`
applies for you, and in the top README's [Detailed Specifications](../README.md#detailed-specifications).
The heap rule is in [JVM Configuration](../README.md#jvm-configuration).

The database is regional with automatic failover, and its `max_connections` is 500, enough for 5 IQ
Server instances. Shared storage is a Cloud Filestore instance on the Regional tier in `gcp_region`, at
`filestore_capacity_gb` with fixed IOPS `filestore_max_iops`, mounted over NFS v3, so it stays available
through a zone outage.

> **Smaller deployments?** For < 2k applications with a single instance, use the [Single Instance](../infra-gcp/) architecture.

---

## Search Backend

With `search_engine = "opensearch"`, this configuration builds a self-managed **OpenSearch 3.7 cluster on
Compute Engine VMs** (`opensearch_version`) and points IQ Server at it. Google Cloud has no first-party
managed OpenSearch service, so you own upgrades, snapshots and node replacement on the cluster. With
`search_engine = "lucene"` nothing is built, `config.yml` carries no `search:` block, and there is no
Nexus One index.

### What Terraform builds

- **Nodes**: `opensearch_data_node_count` data nodes on Ubuntu 24.04 Arm VMs. At one data node, XS and S,
  the node runs as a single-node cluster. At three, Terraform adds three dedicated cluster manager nodes,
  and spreads each role one node per zone (`opensearch_zones`, this configuration's own zones by default).
- **Disks**: a Hyperdisk Balanced data disk per data node, `opensearch_data_disk_gb`, and a boot disk,
  `opensearch_boot_disk_gb`.
- **Load balancer**: at three data nodes, an internal passthrough Network Load Balancer in front of the
  data nodes, with a TCP health check on 9200 and the firewall rule the health checks need. IQ Server
  connects to its address. At one data node, IQ Server connects to the node directly.
- **Security**: the security plugin on, TLS with a certificate authority and node certificates Terraform
  generates, an admin password (`opensearch_admin_password`, generated when empty), and an `iq-server`
  user for IQ Server with a generated password. Each node reads its key, certificates and passwords from
  Secret Manager with its own service account; nothing secret is in instance metadata.
- **Heap**: half of each VM's memory, at most 31 GB, unless `opensearch_data_heap_gb` or
  `opensearch_manager_heap_gb` is set.
- **Replicas**: at one data node, the node's setup sets the cluster's default replica count to 0, so every
  index, the Advanced Search index included, is created green. The Nexus One replica count is capped at
  the data node count minus one.

IQ Server trusts the generated certificate authority without any image change.

| Size | Data nodes | Data node | Data disk | Cluster managers |
|---|---|---|---|---|
| M | 3 | `c4a-standard-2`, 2 vCPU, 8 GB | 100 GB | 3 x `c4a-standard-1` |
| L | 3 | `c4a-standard-4`, 4 vCPU, 16 GB | 150 GB | 3 x `c4a-standard-1` |
| XL | 3 | `c4a-highmem-8`, 8 vCPU, 64 GB | 250 GB | 3 x `c4a-standard-2` |

When a zone has no capacity for a machine type, the create fails with `ZONE_RESOURCE_POOL_EXHAUSTED`; set
`opensearch_zones` to zones that have capacity and apply again. C4A types can be out of stock in every
zone of a region at once. Then set `opensearch_data_instance_type` (and, at M and above,
`opensearch_manager_instance_type`) to the x86 C4 type with the same vCPUs, such as `c4-standard-2`
for `c4a-standard-2`, or for `c4a-standard-1`, since C4 starts at 2 vCPU. The nodes then boot the x86
Ubuntu image. C4 has less memory per vCPU than C4A (`c4-standard-2` has 7 GB), so also set
`opensearch_data_heap_gb` or `opensearch_manager_heap_gb` to half of it, `3` for `c4-standard-2`. The deploy sets the shard counts from `opensearch_data_node_count`. The
rules for replicas and disk during a rebuild are in the [top-level OpenSearch section](../README.md#opensearch).

### Bringing your own cluster

Set `opensearch_create = false` and give the cluster's details instead:

```hcl
search_engine              = "opensearch"
opensearch_create          = false
opensearch_endpoint        = "CHANGE_ME-opensearch.internal.example.com"
opensearch_port            = 9200
opensearch_use_tls         = true
opensearch_username        = "iq-server"
opensearch_password        = "CHANGE_ME_STRONG_PASSWORD"
opensearch_index_replicas  = 1   # 0 on a single data node
opensearch_data_node_count = 3   # your cluster's data node count, which sets the shard counts
```

`opensearch_endpoint` is a host name or IP with no scheme and no port, and should reach every data node,
for example through a load balancer. The password is stored in Secret Manager and read by the startup
script, so it is not in instance metadata. With a cluster you bring, Terraform adds a firewall rule
allowing IQ Server to reach it on `opensearch_port`.

### What this writes into `config.yml`

```yaml
search:
  type: http
  mode: OPENSEARCH
  uri: https://<load balancer, data node, or opensearch_endpoint>:9200
  username: 'iq-server'
  password: '<from Secret Manager>'
nexusOne:
  connection:
    type: http
    mode: OPENSEARCH
    uri: https://<the same address>:9200
    username: 'iq-server'
    password: '<from Secret Manager>'
    nexusOneIndexReplicas: <opensearch_index_replicas>
```

### Trusting a private certificate authority

For a cluster Terraform builds, the deploy handles this. For a cluster you bring whose certificate is
signed by a private authority, set `opensearch_ca_certificate` to that authority's certificate as PEM
text:

```hcl
opensearch_ca_certificate = <<-EOT
-----BEGIN CERTIFICATE-----
...
-----END CERTIFICATE-----
EOT
```

The startup script copies the JVM's own trust store, adds the authority to the copy, and names the copy
with `javax.net.ssl.trustStore`. **The JVM's own store is never replaced**, because it also serves IQ
Server's calls to the Sonatype data service. A certificate from a public authority needs none of this.

---

## Deployment Guide

The quickest route is the top-level [guided deploy script](../README.md#option-1-the-guided-deploy-script).
The steps below deploy this directory by hand.

### Step 1: Prerequisites

| Tool | Version | Installation | Purpose |
|------|---------|--------------|---------|
| **Terraform** | >= 1.2 | [Install Guide](https://developer.hashicorp.com/terraform/install) | Infrastructure as Code |
| **gcloud CLI** | Latest | [Install Guide](https://cloud.google.com/sdk/docs/install) | GCP API access |

You need a GCP project with billing enabled. The deploying account needs these roles, or equivalent
permissions: Compute Admin, Service Account Admin, Service Account User, Service Networking Admin, Cloud
SQL Admin, Cloud Filestore Editor, Secret Manager Admin, Logging Admin, Monitoring Editor and Service
Usage Admin, plus permission to set IAM policy bindings on the project. The license must support
clustering.

Enable these APIs in your project:

```bash
gcloud services enable compute.googleapis.com sqladmin.googleapis.com file.googleapis.com secretmanager.googleapis.com logging.googleapis.com monitoring.googleapis.com cloudresourcemanager.googleapis.com iam.googleapis.com servicenetworking.googleapis.com
```

### Step 2: Configure GCP Credentials

```bash
gcloud auth login
gcloud auth application-default login
gcloud config set project YOUR_PROJECT_ID
```

### Step 3: Configure Terraform Variables

```bash
cd sca-reference-architectures/infra-gcp-ha
cp terraform.tfvars.example terraform.tfvars
# copy in your size's values from examples/<size>.tfvars, then replace every CHANGE_ME
```

`terraform.tfvars.example` carries the Size M values. Every `CHANGE_ME` must be replaced, including
`gcp_project_id`, `allowed_ssh_cidrs`, `db_password`, `iq_admin_initial_password` (at least 12
characters, read by IQ Server on its first start only), `iq_license_file` (the path to your IQ Server
license file, which IQ Server installs on its first start) and `search_engine`.

### Step 4: Deploy Infrastructure

```bash
terraform init
./gcp-ha-plan.sh
./gcp-ha-apply.sh
```

`gcp-ha-plan.sh` exits 2 when the plan has changes to make, which is the normal result before an apply.
The apply script waits for the instances to become healthy, prints the load balancer URL, then runs
`iq-post-deploy.sh`, which sets the shard counts and chooses the search backend, and installs the license
only if IQ Server has none yet. Run `./iq-post-deploy.sh` again at any time.

### Step 5: Access Sonatype IQ Server

Initial startup can take 5-15 minutes. On its first boot each VM installs the newest Debian kernel and
reboots into it once before IQ Server starts, because Debian 12 kernel 6.1.192-1 can fault in ext4 and
hang the boot disk (Debian bug 1154108, fixed in 6.1.192-2). Open the `load_balancer_url` output, and log in as `admin` with the
password you set in `iq_admin_initial_password`.

---

## Teardown / Cleanup

**WARNING: This will delete ALL infrastructure and data!**

```bash
./gcp-ha-destroy.sh --dry-run   # show what would be destroyed
./gcp-ha-destroy.sh             # destroy, asking for confirmation
```

The database has deletion protection on by default (`db_deletion_protection`); `--force` turns it off for
the destroy, changing only the Cloud SQL instance. Terraform does not delete the IQ database and its user
separately, since deleting the instance removes both, so a destroy also works after a database dump was
restored into it. An OpenSearch cluster this configuration built is deleted with the rest, indices included. A
cluster you brought yourself is not touched.

---

## Configuration

`terraform.tfvars.example` lists every variable with its Size M value. Settings worth knowing:

- **`iq_target_instances`** sets the group size only when the group is created: `compute.tf` sets `ignore_changes = [target_size]` on the instance group manager, so an apply does not resize a running group. Change the size with `gcloud compute instance-groups managed resize`.
- **`iq_min_instances`, `iq_max_instances`, `cpu_target_utilization`**: the autoscaler bounds and its CPU target, 0.7 by default.
- **`iq_docker_image`**: pinned to `sonatype/nexus-iq-server:1.209.0`. The startup script installs Docker, mounts Filestore and runs the container with `--restart always`.
- **`iq_log_levels`**: optional logger levels passed to IQ Server's configuration.
- **Database tier and disk type**: a change to `db_instance_tier` or `db_disk_type` updates the existing instance rather than replacing it. With `db_disk_type = "PD_SSD"`, `db_disk_provisioned_iops` and `db_disk_provisioned_throughput` are ignored.

### Clustering

- **Instance distribution**: the regional instance group spreads instances across `availability_zones`
- **Work directories**: each instance gets its own `/sonatype-work/clm-server-${HOSTNAME}` on Filestore, and shares `/sonatype-work/clm-cluster`
- **Database**: every instance connects to the regional Cloud SQL instance

### Running several sizes in one project

Every resource name that has to be unique inside a Google Cloud project derives from `cluster_name`, so
two sizes can live in one project without colliding. **The default is empty, which keeps the default
names.** `cluster_name` takes lowercase letters, numbers and hyphens, starting with a letter and ending
with a letter or number. A Cloud SQL instance name carries a random suffix, regenerated on every fresh
apply.

## Security Features

- **VPC Isolation**: IQ Server and OpenSearch run in private subnets
- **Database Security**: Cloud SQL on a private IP, encrypted in transit
- **Secrets Management**: The database, OpenSearch and initial admin passwords are stored in Secret Manager and read by the startup script
- **Encryption**: Filestore and Cloud SQL encrypted at rest; TLS between IQ Server and OpenSearch; HTTPS with managed SSL certificates when a domain name is set
- **Firewall Rules**: Least-privilege network access

## Reliability and Backup

- **Multi-Zone Deployment**: instances, the database standby, the Filestore share and the OpenSearch nodes across zones
- **Auto Scaling**: the autoscaler scales between the minimum and maximum instance counts for your size
- **Regional Database**: automatic failover between zones
- **Instance Auto-Healing**: the group recreates failed instances
- **Rolling Updates**: zero-downtime updates with controlled rollout
- **Database Backups**: Automated Cloud SQL backups with transaction logs for point-in-time recovery (configurable)

## Monitoring and Logging

- **Cloud Logging**: the Google Cloud Ops Agent on each instance sends IQ Server's log files to Cloud Logging, with a dedicated log bucket (`log_retention_days`, 30 days by default) and log-based error and warning counters
- **Persistent Logs**: on Filestore at `/var/log/nexus-iq-server`
- **Audit events**: IQ Server writes them to the database by default, see [Logging](../README.md#logging)
- **Cloud Monitoring**: dashboards for the instance group, Cloud SQL and the load balancer

## Networking

- **Public Subnet**: Load balancer and Cloud NAT
- **Private Subnets**: one per zone, for the IQ Server instances and the OpenSearch nodes
- **Database Subnet**: Cloud SQL
- **Firewall**: the load balancer allows 80 and 443 from the internet; health checks from Google's ranges `130.211.0.0/22` and `35.191.0.0/16`; the instances allow 8070 from the load balancer and traffic between instances; OpenSearch allows 9200 from IQ Server

## Important: Admin Port 8071 Not Exposed

The admin port 8071 is configured within the IQ Server container but **not exposed externally** through the load balancer. Admin port access is available through SSH to the instances and `docker exec` if needed for troubleshooting.
