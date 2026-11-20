# Sonatype IQ Reference Architecture - GCP GKE with Helm (High Availability)

This directory contains Terraform configuration for deploying Sonatype IQ Server on GCP using GKE with Helm in a **High Availability configuration**, with regional Cloud SQL PostgreSQL, Cloud Filestore on the Regional tier, GKE Ingress, pod and node auto-scaling, and, with `search_engine = "opensearch"`, an OpenSearch cluster on dedicated GKE node pools.

Sizing, the JVM rules, OpenSearch planning, the Helm chart pins and the shared troubleshooting table are in the [top-level README](../README.md). This page covers what is specific to this architecture.

---

## Sizing Guide

This GKE HA architecture supports sizes **M**, **L**, and **XL**:

| Size | Applications | Evaluations per day, hour | Nodes (min / desired / max) | IQ pods, HPA min / max | Node type | Pod limit, heap / direct memory | Database | Filestore |
|------|:------------:|:---------------:|:---------------------------:|:----------------------:|:---------:|:-------------------------------:|:--------:|:---------:|
| **M** | 2k - 10k | ~7.5k, 250 | 2 / 2 / 3 | 2, 2 / 3 | n4a-standard-8 (ARM) | 26 GB, 17 GB / 4 GB | db-custom-N4-4-32768, 128 GB, 8,000 IOPS, 252 MB/s | 500 GB, 8,000 IOPS |
| **L** | 10k - 30k | ~15k, 350 | 2 / 2 / 4 | 2, 2 / 4 | n4a-standard-16 (ARM) | 56 GB, 37 GB / 8 GB | db-custom-N4-8-65536, 256 GB, 8,000 IOPS, 357 MB/s | 1,536 GB, 16,000 IOPS |
| **XL** | 30k - 100k | ~25k, 450 | 3 / 3 / 5 | 3, 3 / 5 | n4a-highmem-16 (ARM) | 110 GB, 73 GB / 8 GB | db-custom-N4-16-131072, 512 GB, 10,000 IOPS, 446 MB/s | 4,096 GB, 24,000 IOPS |

Evaluations per day, hour are typical figures for the whole cluster on a normal day, a guide for planning,
not a limit, as in the top README's [Sizing Guide](../README.md#sizing-guide).

The Terraform values for each size are in [`examples/<size>.tfvars`](./examples/), and the pod's CPU,
memory, heap and autoscaler bounds in `examples/<size>.helm-values.yaml`, which `helm-install.sh --values`
applies after `helm-values.yaml`. The top-level `deploy.sh` uses both. Why the pod heap is lower than on a
whole VM is in [JVM Configuration](../README.md#jvm-configuration).

The database is regional with automatic failover, and its `max_connections` is 500, enough for 5 IQ pods.
Shared storage is a Cloud Filestore instance on the Regional tier in `gcp_region`, at
`filestore_capacity_gb` with fixed IOPS `filestore_max_iops`. `helm-install.sh` mounts it through a static
NFS v3 PersistentVolume, `filestore-pv.yaml` and `filestore-pvc.yaml`, sized from the
`filestore_capacity_gb` output.

> **Heap dumps.** The first out-of-memory error in any pod writes a heap dump to
> `/sonatype-work/clm-cluster/heap-dump.hprof`, one file on the shared storage, and the JVM exits; a later
> one skips the dump while that file exists, so delete it to allow another.

---

## Advanced Search with OpenSearch

With `search_engine = "opensearch"`, this configuration builds a self-managed **OpenSearch 3.7 cluster in
the Kubernetes cluster** (`opensearch_version`), run by the
[OpenSearch Kubernetes Operator](https://github.com/opensearch-project/opensearch-k8s-operator)
(chart `opensearch_operator_chart_version`, `3.0.14`), and points IQ Server at it. You own upgrades,
snapshots and node replacement on the cluster. With `search_engine = "builtin"` nothing is built,
Advanced Search uses the index built into IQ Server, and Nexus One (IQ Server 1.210 and later) can keep
its index in IQ Server's PostgreSQL database, chosen on the Nexus One setup page.

### What Terraform builds

- **Two dedicated node pools**, one for the `opensearch_data_node_count` data nodes and one for three
  cluster managers, each one node per zone at fixed counts (`opensearch_data_instance_type`,
  `opensearch_manager_instance_type`). The pools are tainted `dedicated=opensearch:NoSchedule` and
  labeled, so only OpenSearch runs there, and `vm.max_map_count` is set on their nodes.
- **The operator and the cluster**, in their own namespace, `nexus-iq-opensearch`, with the operator's
  admission webhook off. Each role's pods require a different node, are spread across zones, and carry a
  disruption budget.
- **Storage**: a persistent volume per data node, `opensearch_data_disk_gb`, and per manager,
  `opensearch_manager_disk_gb`, from a storage class this configuration creates. Volumes are deleted with
  the cluster.
- **Security**: TLS with a certificate authority and certificates Terraform generates, an admin password
  (`opensearch_admin_password`, generated when empty), and an `iq-server` user for IQ Server with a
  generated password, created by a job after the cluster is up.
- **The endpoint**: a ClusterIP Service, `nexus-iq-opensearch-data-http`, that selects only the data node
  pods, so IQ Server's requests never go to the cluster managers. IQ Server reaches
  `https://nexus-iq-opensearch-data-http.nexus-iq-opensearch.svc.cluster.local:9200`, and the HTTP
  certificate names that address.
- **Pod size and heap**: each pod gets what its node has left after GKE's own reservations. The node
  reports about 95% of the machine type's memory; GKE keeps part of the machine's memory for the kubelet
  (25% of the first 4 GB, 20% of the next 4, 10% of the next 8, 6% of the next 112, 2% above) and
  100 MB for eviction, and its own daemon pods take about 900 MB and 0.55 vCPU on every node. The
  heap is half the machine's memory, at most 31 GB, at most three quarters of the pod, and leaves at
  least 640 MB of the pod outside the heap, unless `opensearch_data_heap_gb` or
  `opensearch_manager_heap_gb` is set. The `opensearch_pod_sizing` output shows what a deployment gets.

`helm-install.sh` reads the endpoint, the `iq-server` credentials, the replica count and the certificate
authority from the Terraform outputs, and IQ Server's entrypoint adds the authority to a copy of the JVM's
trust store.

| Size | Data nodes | Data node | Data pod, heap | Data volume | Cluster managers | Manager pod, heap |
|---|---|---|---|---|---|---|
| M | 3 | `c4a-standard-2` | 1.38 vCPU, 4.8 GB, heap 3.6 GB | 100 GB | 3 x `c4a-standard-1` | 0.39 vCPU, 1.8 GB, heap 1.1 GB |
| L | 3 | `c4a-standard-4` | 3.37 vCPU, 12 GB, heap 8 GB | 150 GB | 3 x `c4a-standard-1` | 0.39 vCPU, 1.8 GB, heap 1.1 GB |
| XL | 3 | `c4a-highmem-8` | 7.36 vCPU, 54 GB, heap 31 GB | 250 GB | 3 x `c4a-standard-2` | 1.38 vCPU, 4.8 GB, heap 3.6 GB |

The machine types are the same as on the GCP virtual machines; only the pod and the heap are smaller.

The deploy sets the shard counts from `opensearch_data_node_count`, 3. The rules for replicas and disk
during a rebuild are in the [top-level OpenSearch section](../README.md#opensearch).

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
opensearch_index_replicas  = 1
opensearch_data_node_count = 3   # your cluster's data node count, which sets the shard counts
```

With a cluster you bring, Terraform adds a firewall rule allowing the GKE nodes to reach it on
`opensearch_port`.

### What reaches IQ Server's configuration

IQ Server's configuration on this root comes from the Helm values rather than from Terraform.
`render-values.sh`, called by `helm-install.sh` and `helm-upgrade.sh`, writes the search block into the
runtime values file, so an upgrade keeps it. The block is the `type: http` form shown in the
[top-level OpenSearch section](../README.md#what-iq-servers-configuration-carries).

### Trusting a private certificate authority

For a cluster Terraform builds, the install handles this. For a cluster you bring whose certificate is
signed by a private authority, set `opensearch_ca_certificate` to that authority's certificate as PEM
text:

```hcl
opensearch_ca_certificate = <<-EOT
  -----BEGIN CERTIFICATE-----
  ...the authority's PEM certificate...
  -----END CERTIFICATE-----
EOT
```

`helm-install.sh` or `helm-upgrade.sh` stores it in the Kubernetes Secret `nexus-iq-opensearch-ca` and
keeps the two blocks between the `# opensearch-ca-begin` and `# opensearch-ca-end` markers in
`helm-values.yaml`. Each pod adds the certificate to a copy of its JVM trust store at start; **the JVM's
own store is never replaced**, because it also serves IQ Server's calls to the Sonatype data service.
Keep the markers. To change the certificate, apply, run `helm-upgrade.sh`, and restart the pods with
`kubectl rollout restart deployment -n nexus-iq`, since a pod reads the Secret only when it starts.

---

## Deployment Guide

The quickest route is the top-level [guided deploy script](../README.md#option-1-the-guided-deploy-script).
The steps below deploy this directory by hand.

### Step 1: Prerequisites

| Tool | Version | Installation | Purpose |
|------|---------|--------------|---------|
| **Terraform** | >= 1.2 | [Install Guide](https://developer.hashicorp.com/terraform/install) | Infrastructure as Code |
| **gcloud CLI** | Latest | [Install Guide](https://cloud.google.com/sdk/docs/install) | GCP API access |
| **kubectl** | Latest | [Install Guide](https://kubernetes.io/docs/tasks/tools/) | Kubernetes cluster management |
| **Helm** | >= 3.9.3 | [Install Guide](https://helm.sh/docs/intro/install/) | Application deployment |

You need a GCP project with billing enabled. The deploying account needs Kubernetes Engine Admin, Compute
Admin, Service Account Admin, Service Account User, Service Networking Admin, Cloud SQL Admin, Cloud
Filestore Editor, Logging Admin, Monitoring Editor and Service Usage Admin, or equivalent permissions.
`./check-permissions.sh` checks them, and [PERMISSIONS_NEEDED.md](./PERMISSIONS_NEEDED.md) lists what a
custom role needs. The license must support clustering.

Enable these APIs in your project:

```bash
gcloud services enable container.googleapis.com compute.googleapis.com sqladmin.googleapis.com file.googleapis.com secretmanager.googleapis.com logging.googleapis.com monitoring.googleapis.com cloudresourcemanager.googleapis.com iam.googleapis.com servicenetworking.googleapis.com
```

### Step 2: Configure GCP Credentials

```bash
gcloud auth login
gcloud auth application-default login
gcloud config set project YOUR_PROJECT_ID
```

### Step 3: Configure Terraform Variables

```bash
cd sca-reference-architectures/infra-gcp-ha-k8s-helm
cp terraform.tfvars.example terraform.tfvars
# copy in your size's values from examples/<size>.tfvars, then replace every CHANGE_ME
```

`terraform.tfvars.example` carries the Size M values. Every `CHANGE_ME` must be replaced, including
`gcp_project_id`, `db_password`, `iq_admin_initial_password` (at least 12 characters, read by IQ Server
on its first start only), `iq_license_file` (the path to your IQ Server license file, which IQ Server
installs on its first start) and `search_engine`.

### Step 4: Deploy Infrastructure and Application

```bash
terraform init
./tf-plan.sh
./tf-apply.sh                     # GKE, the OpenSearch node pools and cluster, Cloud SQL, Filestore and networking
./helm-install.sh --values examples/<size>.helm-values.yaml
```

`helm-install.sh` configures kubectl for the cluster, creates the initial admin password secret from
`iq_admin_initial_password` and the license secret from `iq_license_file`, which every pod installs on
its first start, writes the search configuration, installs the chart version in `helm_chart_version` with
the IQ Server release it carries, and then runs `iq-post-deploy.sh`, which sets the shard counts and chooses the search
backend, and installs the license only if IQ Server has none yet. Run `./iq-post-deploy.sh` again at any
time.

### Step 5: Access Sonatype IQ Server

Initial startup can take 10-15 minutes. Open the URL the install printed, and log in as `admin` with the
password you set in `iq_admin_initial_password`.

### Database migration in `helm-upgrade.sh`

`./helm-upgrade.sh` takes the same `--values` files. It runs the database migration only when the IQ
Server image changes, and then only with `MIGRATE_DATABASE=yes` set. Back up the database before setting
it. The script scales IQ Server to zero for the migration, starts it again afterwards, and exits non-zero
if the migration or the rollout fails.

---

## Teardown / Cleanup

**WARNING: This will delete ALL infrastructure and data!**

```bash
./helm-uninstall.sh
./tf-destroy.sh
```

`tf-destroy.sh` removes the OpenSearch cluster first and waits for its volumes to go, so the destroy
leaves no disks behind. A cluster you brought yourself is not touched. If the destroy stops on "Producer
services are still using this connection", see [CLEANUP_INSTRUCTIONS.md](./CLEANUP_INSTRUCTIONS.md).

---

## Configuration

`terraform.tfvars.example` lists every variable with its Size M value. Settings worth knowing:

- **`nexus_iq_replica_count`**: the initial number of IQ pods.
- **`hpa.minReplicas`, `hpa.maxReplicas`**: the pod autoscaler bounds, set per size in `examples/<size>.helm-values.yaml`. Every size keeps at least 2 for HA.
- **`helm_chart_version`**: the `nexus-iq-server-ha` chart version, set by this variable's default in `variables.tf`, the one place this architecture pins the IQ Server version. The chart sets the IQ Server image, so this also sets the IQ Server version.
- **`cluster_name`**: the base name for every resource, `nexus-iq-ha` by default. Give each deployment its own value to run more than one in a project.

## Security Features

- **VPC Isolation**: GKE nodes and OpenSearch run in private subnets
- **Database Security**: Cloud SQL on a private IP
- **Secrets**: the database password reaches the pods through a Kubernetes secret, and the initial admin password through `nexus-iq-initial-admin-password`, named in `iq_server.initialAdminPasswordSecret`
- **Encryption**: Filestore and Cloud SQL encrypted at rest; TLS between IQ Server and OpenSearch
- **Workload Identity**: pod-level access to Google Cloud APIs
- **Cloud Armor**: rate limiting on the ingress (`cloud_armor_rate_limit_threshold`)

## Reliability and Backup

- **Multi-Zone Deployment**: GKE nodes, pods, OpenSearch nodes, the database and the Filestore share across zones
- **Horizontal Pod Autoscaler and Cluster Autoscaler**: pods and nodes scale between the minimum and maximum for your size. The IQ Server node pool uses 2 zones at Size M and L and 3 at Size XL, one node in each at start
- **Regional Database**: automatic failover between zones
- **Database Backups**: Automated Cloud SQL backups with transaction logs for point-in-time recovery (configurable)

## Monitoring and Logging

- **Cloud Logging**: GKE collects every container's standard output, including IQ Server's server, request, audit and policy-violation logs
- **Log files**: each pod also writes its logs to `/sonatype-work/clm-cluster/log/` on Filestore
- **Audit events**: IQ Server writes them to the database by default, see [Logging](../README.md#logging)
- **Cloud Monitoring**: GKE cluster monitoring, with alert policies when `enable_monitoring_alerts` is set

## Networking

- **Public Subnet**: the load balancer GKE Ingress creates
- **Private Subnets**: GKE nodes and pods, including the OpenSearch node pools, across zones
- **Database**: Cloud SQL on a private service connection

## Important: Admin Port 8071 Not Exposed

The admin port 8071 is configured within the IQ Server container but **not exposed externally** through the load balancer. Admin port access is available through Kubernetes exec sessions if needed for troubleshooting.
