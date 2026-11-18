# Sonatype IQ Reference Architecture - Azure AKS with Helm (High Availability)

This directory contains Terraform configuration for deploying Sonatype IQ Server on Azure using AKS with Helm in a **High Availability configuration**, with zone-redundant PostgreSQL Flexible Server, Azure Files Premium over NFS, an Application Gateway, pod and node auto-scaling, and, with `search_engine = "opensearch"`, an OpenSearch cluster on dedicated AKS node pools.

Sizing, the JVM rules, OpenSearch planning, the Helm chart pins and the shared troubleshooting table are in the [top-level README](../README.md). This page covers what is specific to this architecture.

---

## Sizing Guide

This AKS HA architecture supports sizes **M**, **L**, and **XL**:

| Size | Applications | Typical evaluations/day | Evaluations an hour per node | Nodes (min / desired / max) | IQ pods, HPA min / max | Node type | Pod limit, heap / direct memory | Database | Share quota |
|------|:------------:|:---------------:|:----------------------------:|:---------------------------:|:----------------------:|:---------:|:-------------------------------:|:--------:|:-----------:|
| **M** | 2k - 20k | ~10k | ~250 | 2 / 2 / 3 | 2, 2 / 3 | Standard_D8ps_v6 (ARM) | 26 GB, 17 GB / 4 GB | MO_Standard_E4ds_v6, 128 GB | 500 GB |
| **L** | 20k - 40k | ~15k | ~350 | 2 / 2 / 4 | 2, 2 / 4 | Standard_D16ps_v6 (ARM) | 56 GB, 37 GB / 8 GB | MO_Standard_E8ds_v6, 256 GB, P15 | 1,536 GB |
| **XL** | 40k - 100k | ~25k | ~450 | 3 / 3 / 5 | 3, 3 / 5 | Standard_E16ps_v6 (ARM) | 110 GB, 73 GB / 8 GB | MO_Standard_E16ds_v6, 512 GB, P20 | 4,096 GB |

Typical evaluations/day is a normal day for the size, and evaluations an hour per node is a guide for planning,
not a limit, as in the top README's [Sizing Guide](../README.md#sizing-guide).

The Terraform values for each size are in [`examples/<size>.tfvars`](./examples/), and the pod's CPU,
memory, heap and autoscaler bounds in `examples/<size>.helm-values.yaml`, which `helm-install.sh --values`
applies after `helm-values.yaml`. The top-level `deploy.sh` uses both. Why the pod heap is lower than on a
whole VM is in [JVM Configuration](../README.md#jvm-configuration).

Terraform creates one Azure Files Premium NFS share, `iq-data-ha`, ZRS, at `storage_share_quota_gb`.
`helm-install.sh` binds IQ's claim, `iq-server-pvc`, to that share through a static PersistentVolume,
`azurefiles-pv.yaml` and `azurefiles-pvc.yaml`, sized from the `storage_share_quota_gb` output. Every IQ pod
mounts it at `/sonatype-work/clm-cluster`.

> **Heap dumps.** The first out-of-memory error in any pod writes a heap dump to
> `/sonatype-work/clm-cluster/heap-dump.hprof`, one file on the Azure Files share, and the JVM exits; a
> later one skips the dump while that file exists, so delete it to allow another.

> **ARM instances are the default.** The x86 equivalents are the Standard_D8s_v6, Standard_D16s_v6 and Standard_E16s_v7 sizes.

---

## Advanced Search with OpenSearch

With `search_engine = "opensearch"`, this configuration builds a self-managed **OpenSearch 3.7 cluster in
the Kubernetes cluster** (`opensearch_version`), run by the
[OpenSearch Kubernetes Operator](https://github.com/opensearch-project/opensearch-k8s-operator)
(chart `opensearch_operator_chart_version`, `3.0.14`), and points IQ Server at it. You own upgrades,
snapshots and node replacement on the cluster. With `search_engine = "lucene"` nothing is built and there
is no Nexus One index.

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
- **Pod size and heap**: each pod gets what its node has left after AKS's own reservations. The node
  reports about 95% of the VM's memory; AKS keeps 750 MB of that for the kubelet and eviction, and its
  own daemon pods, with Container insights and Azure network policy on, take about 1.3 GB. The cluster
  manager nodes keep 300 MB more for the operator's setup jobs. CPU is the VM's vCPUs less 0.75. The
  heap is half the VM's memory, at most 31 GB, at most three quarters of the pod, and leaves at least
  640 MB of the pod outside the heap, unless `opensearch_data_heap_gb` or `opensearch_manager_heap_gb`
  is set. The `opensearch_pod_sizing` output shows what a deployment gets.

`helm-install.sh` reads the endpoint, the `iq-server` credentials, the replica count and the certificate
authority from the Terraform outputs, and IQ Server's entrypoint adds the authority to a copy of the JVM's
trust store.

| Size | Data nodes | Data node | Data pod, heap | Data volume | Cluster managers | Manager pod, heap |
|---|---|---|---|---|---|---|
| M | 3 | `Standard_D2ps_v6` | 1.25 vCPU, 5.6 GB, heap 4 GB | 128 GB | 3 x `Standard_D2pls_v6` | 1.25 vCPU, 1.5 GB, heap 0.9 GB |
| L | 3 | `Standard_D4ps_v6` | 3.25 vCPU, 13 GB, heap 8 GB | 256 GB | 3 x `Standard_D2pls_v6` | 1.25 vCPU, 1.5 GB, heap 0.9 GB |
| XL | 3 | `Standard_E8ps_v6` | 7.25 vCPU, 59 GB, heap 31 GB | 256 GB | 3 x `Standard_D2ps_v6` | 1.25 vCPU, 5.3 GB, heap 4 GB |

The node sizes are the same as on the Azure virtual machines; only the pod and the heap are smaller.

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

### What reaches IQ Server's configuration

IQ Server's configuration on this root comes from the Helm values rather than from Terraform.
`helm-install.sh` and `helm-upgrade.sh` both append the block to `helm-values-runtime.yaml` under
`iq_server.config:`, so an upgrade keeps it. **Do not add OpenSearch keys to `helm-values.yaml`.** The
block is the `type: http` form shown in the
[top-level OpenSearch section](../README.md#what-iq-servers-configuration-carries), with the two
credentials single-quoted, so any character is safe in the password.

### TLS, and the JVM trust store

**IQ Server has no per-connection trust setting.** A certificate signed by a private certificate
authority is trusted only if that authority is in the trust store the JVM loads. For a cluster
Terraform builds, `helm-install.sh` handles this. For a cluster you bring whose certificate is signed by a
private authority, build a derived image with the authority in a copy of the JVM's trust store. **Copy
the JVM's own trust store and add to the copy. Never replace it**, because the same store serves IQ
Server's calls to the Sonatype data service:

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

Then add `-Djavax.net.ssl.trustStore=/opt/sonatype/iq-truststore.jks -Djavax.net.ssl.trustStorePassword=changeit`
to `iq_server.javaOpts` in your size's Helm values file, and point `iq_server.tag` at the derived image.
The chart mounts the Azure Files share only at `/sonatype-work/clm-cluster`, so the store in the image is
not hidden. A certificate from a public authority needs none of this.

---

## Deployment Guide

The quickest route is the top-level [guided deploy script](../README.md#option-1-the-guided-deploy-script).
The steps below deploy this directory by hand.

### Step 1: Prerequisites

| Tool | Version | Installation | Purpose |
|------|---------|--------------|---------|
| **Terraform** | >= 1.2 | [Install Guide](https://developer.hashicorp.com/terraform/install) | Infrastructure as Code |
| **Azure CLI** | >= 2.0 | [Install Guide](https://learn.microsoft.com/cli/azure/install-azure-cli) | Azure API access |
| **kubectl** | Latest | [Install Guide](https://kubernetes.io/docs/tasks/tools/) | Kubernetes cluster management |
| **Helm** | >= 3.9.3 | [Install Guide](https://helm.sh/docs/intro/install/) | Application deployment |

You need an Azure subscription with Contributor access, and permission to create resource groups,
virtual networks, network security groups, AKS clusters and node pools, an Application Gateway,
PostgreSQL Flexible Server, storage accounts, managed identities, disks and Log Analytics. The license
must support clustering. PostgreSQL Flexible Server vCPU count is a quota per subscription and per region,
see the [single instance README](../infra-azure/README.md#step-1-prerequisites) for the command that reads it.

### Step 2: Configure Azure Credentials

```bash
az login
az account set --subscription "<subscription-id-or-name>"
```

### Step 3: Configure Terraform Variables

```bash
cd sca-reference-architectures/infra-azure-ha-k8s-helm
cp terraform.tfvars.example terraform.tfvars
# copy in your size's values from examples/<size>.tfvars, then replace every CHANGE_ME
```

Every `CHANGE_ME` must be replaced, including `database_password`, `iq_admin_initial_password` (at least
12 characters, read by IQ Server on its first start only), `iq_license_file` (the path to your IQ Server
license file, which IQ Server installs on its first start), `search_engine` and the `common_tags` values.

### Step 4: Deploy Infrastructure and Application

```bash
terraform init
./tf-plan.sh
./tf-apply.sh                     # AKS, the OpenSearch node pools and cluster, PostgreSQL, Azure Files and networking
./helm-install.sh --values examples/<size>.helm-values.yaml
```

`helm-install.sh` configures kubectl for the cluster, creates the initial admin password secret from
`iq_admin_initial_password` and the license secret from `iq_license_file`, which every pod installs on
its first start, writes the search configuration, installs chart `209.0.0` (`helm_chart_version`) with IQ
Server `1.209.0`, and then runs `iq-post-deploy.sh`, which sets the shard counts and chooses the search
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

An OpenSearch cluster this configuration built is deleted with the rest, volumes and indices included. A
cluster you brought yourself is not touched.

---

## Configuration

`terraform.tfvars.example` lists every variable with its default value. Settings worth knowing:

- **`nexus_iq_replica_count`**: the initial number of IQ pods. `helm-install.sh` writes it into `iq_server.replicas`.
- **`hpa.minReplicas`, `hpa.maxReplicas`**: the pod autoscaler bounds, set per size in `examples/<size>.helm-values.yaml`. Every size keeps at least 2 for HA.
- **`helm_chart_version`**: `209.0.0`. The IQ Server image is pinned to `1.209.0` in `helm-values.yaml`.
- **`db_high_availability_mode = "ZoneRedundant"`**: a standby in another zone with automatic failover. The server's `max_connections` is 500, enough for 5 IQ pods.
- **`storage_account_tier = "Premium"`**: required, because the share is mounted over NFS.

## Security Features

- **VNet Isolation**: IQ Server and OpenSearch run in private subnets; PostgreSQL in its own delegated subnet with private DNS
- **Secrets**: the database password reaches the pods through a Kubernetes secret, and the initial admin password through `nexus-iq-initial-admin-password`, named in `iq_server.initialAdminPasswordSecret`
- **Encryption**: Azure Files and PostgreSQL encrypted at rest; TLS between IQ Server and OpenSearch; Application Gateway SSL termination support
- **Network Security Groups**: Least-privilege network access
- **Managed Identity**: AKS uses a system-assigned identity

## Reliability and Backup

- **Multi-Zone Deployment**: AKS nodes, pods, OpenSearch nodes, the Application Gateway and the database across availability zones
- **Pod anti-affinity**: IQ pods prefer different nodes
- **Horizontal Pod Autoscaler and Cluster Autoscaler**: IQ pods and the user node pool scale between the minimum and maximum for your size
- **System node pool**: a fixed 2 x `Standard_D2pls_v6` for the AKS system pods only, not counted with IQ Server
- **Zone-Redundant Database**: automatic failover between zones
- **Database Backups**: Automated PostgreSQL backups with 7-day retention (configurable)
- **Zone-Redundant Storage**: Azure Files Premium (ZRS)

## Monitoring and Logging

- **Container insights**: collects every container's standard output, including IQ Server's server, request, audit and policy-violation logs, into the Log Analytics workspace
- **Log files**: each pod also writes its logs to `/sonatype-work/clm-cluster/log/` on the Azure Files share
- **Audit events**: IQ Server writes them to the database by default, see [Logging](../README.md#logging)

## Networking

- **Public Subnet**: Application Gateway
- **AKS Subnet**: AKS nodes and pods, including the OpenSearch node pools
- **Database Subnet**: PostgreSQL Flexible Server (delegated to PostgreSQL)
- **Security groups**: the public NSG allows 80 and 443 from the internet; the database NSG allows 5432 from the AKS subnet only

## Important: Admin Port 8071 Not Exposed

The admin port 8071 is configured within the IQ Server container but **not exposed externally** through the Application Gateway. The chart's admin service is a load balancer on a private address inside the virtual network, set by `adminServiceAnnotations` in `helm-values.yaml`. Admin port access is available through Kubernetes exec sessions if needed for troubleshooting.
