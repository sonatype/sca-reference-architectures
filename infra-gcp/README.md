# Sonatype IQ Reference Architecture - GCP with Docker (Single Instance)

This directory contains Terraform configuration for deploying a **single-instance** Sonatype IQ Server on GCP, running the IQ Server Docker image on a Compute Engine VM, with Cloud SQL PostgreSQL, Cloud Filestore and, with `search_engine = "opensearch"`, an OpenSearch cluster on Compute Engine VMs.

Sizing, the JVM rules, OpenSearch planning and the shared troubleshooting table are in the [top-level README](../README.md). This page covers what is specific to this architecture.

---

## Sizing Guide

This single-instance architecture supports sizes **XS**, **S**, and **M**:

| Size | Applications | Evaluations per day, hour | Machine type | Java heap / direct memory | Database | Filestore | OpenSearch |
|------|:------------:|:---------------:|:------------:|:-------------------------:|:--------:|:---------:|:----------:|
| **XS** | < 500 | ~2.5k, 100 | n4a-highmem-2 (ARM), 2 vCPU / 16 GB | 10 GB / 3 GB | db-custom-2-7680, 64 GB PD_SSD | 500 GB, 4,000 IOPS | 1 x `c4a-standard-1` |
| **S** | 500 - 2k | ~5k, 150 | n4a-highmem-4 (ARM), 4 vCPU / 32 GB | 20 GB / 4 GB | db-custom-2-13312, 128 GB PD_SSD | 500 GB, 4,000 IOPS | 1 x `c4a-standard-2` |
| **M** | 2k - 10k | ~7.5k, 250 | n4a-standard-8 (ARM), 8 vCPU / 32 GB | 20 GB / 4 GB | db-custom-N4-4-32768, 128 GB Hyperdisk Balanced, 8,000 IOPS, 252 MB/s | 500 GB, 8,000 IOPS | 3 x `c4a-standard-2`, 3 managers |

Evaluations per day, hour are typical figures for the whole cluster on a normal day, a guide for planning,
not a limit, as in the top README's [Sizing Guide](../README.md#sizing-guide).

The values for each size are in [`examples/<size>.tfvars`](./examples/), which the top-level `deploy.sh`
applies for you, and in the top README's [Detailed Specifications](../README.md#detailed-specifications).
The heap rule is in [JVM Configuration](../README.md#jvm-configuration).

Shared storage is a Cloud Filestore instance on the Regional tier (`filestore_tier = "REGIONAL"`) in
`gcp_region`, at `filestore_capacity_gb` with fixed IOPS `filestore_max_iops`, mounted over NFS v3. The
database is zonal by default (`db_availability_type`).

> **Need more capacity?** For 10k+ applications or multi-node deployments, use the [High Availability](../infra-gcp-ha/) or [Kubernetes](../infra-gcp-ha-k8s-helm/) architectures.

> **HA is recommended at M.** Run M on this single-instance architecture only where downtime for upgrades and restarts is acceptable.

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
| XS | 1 | `c4a-standard-1`, 1 vCPU, 4 GB | 25 GB | none |
| S | 1 | `c4a-standard-2`, 2 vCPU, 8 GB | 50 GB | none |
| M | 3 | `c4a-standard-2`, 2 vCPU, 8 GB | 100 GB | 3 x `c4a-standard-1` |

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
Usage Admin, plus permission to set IAM policy bindings on the project.

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
cd sca-reference-architectures/infra-gcp
cp terraform.tfvars.example terraform.tfvars
# copy in your size's values from examples/<size>.tfvars, then replace every CHANGE_ME
```

`terraform.tfvars.example` carries the Size M values. Every `CHANGE_ME` must be replaced, including
`gcp_project_id`, `db_password`, `iq_admin_initial_password` (at least 12 characters, read by IQ Server
on its first start only), `iq_license_file` (the path to your IQ Server license file, which IQ Server
installs on its first start) and `search_engine`. Narrow `allowed_ssh_cidrs`, which allows SSH from
anywhere by default.

### Step 4: Deploy Infrastructure

```bash
terraform init
./gcp-plan.sh
./gcp-apply.sh
```

`gcp-plan.sh` exits 2 when the plan has changes to make, which is the normal result before an apply. The
apply script checks what it created, prints the application URL, then runs `iq-post-deploy.sh`, which
sets the shard counts and chooses the search backend, and installs the license only if IQ Server has none
yet. Run `./iq-post-deploy.sh` again at any time. `./deploy.sh` in this directory runs the same steps in
one command.

### Step 5: Access Sonatype IQ Server

Initial startup can take 5-10 minutes. On its first boot the VM installs the newest Debian kernel and
reboots into it once before IQ Server starts, because Debian 12 kernel 6.1.192-1 can fault in ext4 and
hang the boot disk (Debian bug 1154108, fixed in 6.1.192-2). Open the application URL, and log in as `admin` with the password
you set in `iq_admin_initial_password`.

---

## Teardown / Cleanup

**WARNING: This will delete ALL infrastructure and data!**

```bash
./destroy.sh
```

The database has deletion protection on by default (`db_deletion_protection`); `./destroy.sh --force`
turns it off for the destroy, changing only the Cloud SQL instance. Terraform does not delete the IQ
database and its user separately, since deleting the instance removes both, so a destroy also works after
a database dump was restored into it. An OpenSearch cluster this configuration built is deleted with the rest,
indices included. A cluster you brought yourself is not touched.

---

## Configuration

`terraform.tfvars.example` lists every variable with its Size M value. Settings worth knowing:

- **`iq_docker_image`**: the IQ Server image and its version tag, set by this variable's default in `variables.tf`, the one place this architecture pins the IQ Server version. Set it in `terraform.tfvars` only to run a different image. The startup script installs Docker, mounts Filestore, and runs the container with `--restart always`, with `/sonatype-work` and `/var/log/nexus-iq-server` on Filestore.
- **`db_max_connections`**: 200, which covers one IQ Server.
- **`gce_machine_type`**: the IQ Server VM. ARM `n4a` types are the default.

### Running several sizes in one project

Every resource name that has to be unique inside a Google Cloud project derives from `cluster_name`, so
two sizes can live in one project without colliding. **The default is empty, which keeps the default
names.** `cluster_name` takes lowercase letters, numbers and hyphens, starting with a letter and ending
with a letter or number, 1 to 19 characters. A Cloud SQL instance name carries a random suffix,
regenerated on every fresh apply.

A service account deleted by hand and created again under the same name is a separate identity: it
inherits none of the deleted account's roles, and it blocks undeleting the original. A normal destroy and
rebuild recreates the service accounts and grants their roles in the same apply.

## Security Features

- **VPC Isolation**: IQ Server and OpenSearch run in private subnets
- **Database Security**: Cloud SQL on a private IP, encrypted in transit (ENCRYPTED_ONLY)
- **Secrets Management**: The database, OpenSearch and initial admin passwords are stored in Secret Manager and read by the startup script
- **Encryption**: Filestore and Cloud SQL encrypted at rest; TLS between IQ Server and OpenSearch; HTTPS with managed SSL certificates when a domain name is set
- **Firewall Rules**: Least-privilege network access

## Reliability and Backup

- **Single Instance**: One VM running the Docker container, in one zone
- **Instance Auto-Healing**: the instance group recreates a failed VM
- **Database Backups**: Automated Cloud SQL backups (configurable)
- **Regional Filestore**: the share stays available through a zone outage

## Monitoring and Logging

- **Cloud Logging**: the Google Cloud Ops Agent on the VM sends `clm-server.log`, `request.log` and `audit.log` to Cloud Logging, under the log names `iq_application_log`, `iq_request_log` and `iq_audit_log`
- **Persistent Logs**: on Filestore at `/var/log/nexus-iq-server`
- **Audit events**: IQ Server writes them to the database by default, see [Logging](../README.md#logging)
- **Serial Console**: startup script logs

## Networking

- **Public Subnet**: Load balancer and Cloud NAT
- **Private Subnet**: the IQ Server VM (no external IP) and the OpenSearch nodes
- **Database Subnet**: Cloud SQL
- **Firewall**: the load balancer allows 80 and 443 from the internet; the VM allows the load balancer's health checks and internal traffic; OpenSearch allows 9200 from IQ Server

## Important: Admin Port 8071 Not Exposed

The admin port 8071 is configured within the IQ Server container but **not exposed externally** through the Load Balancer. Admin port access is available through SSH to the VM and `docker exec` if needed for troubleshooting.
