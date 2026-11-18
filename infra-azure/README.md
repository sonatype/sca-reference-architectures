# Sonatype IQ Reference Architecture - Azure Container Apps (Single Instance)

This directory contains Terraform configuration for deploying a **single-instance** Sonatype IQ Server on Azure using Container Apps with Workload Profiles, Azure Database for PostgreSQL Flexible Server, Azure Files and, with `search_engine = "opensearch"`, an OpenSearch cluster on Azure virtual machines.

Sizing, the JVM rules, OpenSearch planning and the shared troubleshooting table are in the [top-level README](../README.md). This page covers what is specific to this architecture.

---

## Sizing Guide

This single-instance architecture supports sizes **XS**, **S**, and **M**:

| Size | Applications | Typical evaluations/day | Evaluations an hour per node | Container (workload profile) | Java heap / direct memory | Database | OpenSearch |
|------|:------------:|:---------------:|:----------------------------:|:----------------------------:|:-------------------------:|:--------:|:----------:|
| **XS** | < 500 | ~2.5k | ~100 | 3.5 vCPU / 14 GB (D4) | 8 GB / 2 GB | GP_Standard_D2ds_v6, 64 GB | 1 x `Standard_D2pls_v6` |
| **S** | 500 - 2,000 | ~5k | ~150 | 3.5 vCPU / 30 GB (E4) | 18 GB / 4 GB | MO_Standard_E2ds_v6, 128 GB | 1 x `Standard_D2ps_v6` |
| **M** | 2,000 - 20,000 | ~10k | ~250 | 7.5 vCPU / 30 GB (D8) | 18 GB / 4 GB | MO_Standard_E4ds_v6, 128 GB, grows automatically | 3 x `Standard_D2ps_v6`, 3 managers |

Typical evaluations/day is a normal day for the size, and evaluations an hour per node is a guide for planning,
not a limit, as in the top README's [Sizing Guide](../README.md#sizing-guide).

Each container leaves 0.5 vCPU and 2 GB of its node, because Container Apps keeps part of every node for itself
([workload profiles](https://learn.microsoft.com/en-us/azure/container-apps/workload-profiles-overview#resource-consumption-and-scaling)).
The values for each size are in [`examples/<size>.tfvars`](./examples/), which the top-level `deploy.sh`
applies for you, and in the top README's [Detailed Specifications](../README.md#detailed-specifications).
The heap rule, and why the heap is 8 GB at XS and 18 GB at S and M, are in [JVM Configuration](../README.md#jvm-configuration).

Shared storage is an Azure Files share over SMB, Standard tier and LRS (`storage_account_tier`,
`storage_account_replication_type`), with a 500 GB quota (`file_share_quota`).

> **Need more capacity?** For 20,000+ applications or multi-node deployments, use the [High Availability](../infra-azure-ha/) or [Kubernetes](../infra-azure-ha-k8s-helm/) architectures.

> **HA is recommended at M.** Run M on this single-instance architecture only where downtime for upgrades and restarts is acceptable.

> **Heap dumps.** At M the first out-of-memory error writes a heap dump to `/sonatype-work/heap-dump.hprof`
> and the JVM exits; a later one skips the dump while that file exists, so delete it to allow another.

---

## Advanced Search with OpenSearch

With `search_engine = "opensearch"`, this configuration builds a self-managed **OpenSearch 3.7 cluster on
Azure virtual machines** (`opensearch_version`) and points IQ Server at it. Azure has no first-party
managed OpenSearch service, so you own upgrades, snapshots and node replacement on the cluster. With
`search_engine = "lucene"` nothing is built, `config.yml` carries no `search:` block, and there is no
Nexus One index.

### What Terraform builds

- **Nodes**: `opensearch_data_node_count` data nodes. At one data node, XS and S, the node is its own
  cluster manager. At three, Terraform adds three dedicated cluster manager nodes, and spreads each role
  one node per availability zone (`opensearch_zones`, zones 1, 2 and 3 by default).
- **Subnet and network**: the nodes sit in their own subnet, `opensearch_subnet_cidr`, with a network
  security group that admits port 9200 only from IQ Server's subnet, and a NAT gateway for outbound
  package installs. Node addresses are fixed: data nodes from `.11`, cluster managers from `.21`.
- **Load balancer**: at three data nodes, a Standard SKU internal load balancer at `.100`, with a TCP
  health probe on 9200 and the data nodes in its backend pool. IQ Server connects to its address. At one
  data node, IQ Server connects to the node directly.
- **Disks**: a Premium SSD data disk per data node, `opensearch_data_disk_gb`, sized to the Premium tier
  at or above the published storage figure, and a Premium SSD operating system disk, `opensearch_os_disk_gb`.
- **Security**: the security plugin on, TLS on the REST and transport layers with a certificate authority
  and node certificates Terraform generates, an admin password (`opensearch_admin_password`, generated
  when empty) kept in Key Vault, and an `iq-server` user for IQ Server with a generated password. The
  nodes read their secrets from Key Vault through a user-assigned identity.
- **Heap**: half of each VM's memory, at most 31 GB, unless `opensearch_data_heap_gb` or
  `opensearch_manager_heap_gb` is set.
- **Replicas**: at one data node, the node's setup sets the cluster's default replica count to 0, so every
  index, the Advanced Search index included, is created green. The Nexus One replica count is 1 at three
  data nodes and 0 at one.

IQ Server trusts the generated certificate authority without any image change: the container's
entrypoint copies the JVM's trust store, adds the authority to the copy, and names the copy with
`javax.net.ssl.trustStore`.

| Size | Data nodes | Data node | Data disk | Cluster managers |
|---|---|---|---|---|
| XS | 1 | `Standard_D2pls_v6`, 2 vCPU, 4 GB | 32 GB (P4) | none |
| S | 1 | `Standard_D2ps_v6`, 2 vCPU, 8 GB | 64 GB (P6) | none |
| M | 3 | `Standard_D2ps_v6`, 2 vCPU, 8 GB | 128 GB (P10) | 3 x `Standard_D2pls_v6` |
| L | 3 | `Standard_D4ps_v6`, 4 vCPU, 16 GB | 256 GB (P15) | 3 x `Standard_D2pls_v6` |
| XL | 3 | `Standard_E8ps_v6`, 8 vCPU, 64 GB | 256 GB (P15) | 3 x `Standard_D2ps_v6` |

The deploy sets the shard counts from `opensearch_data_node_count`: 1 at one data node, 3 at three. The
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
for example through a load balancer. The cluster needs OpenSearch 3.x with the security plugin on, and a
user IQ Server owns with permission to create and write its own indices. The password reaches the
container as a Container App secret; `sensitive` keeps it out of CLI output only, so it is plain text in
`terraform.tfstate`.

### What reaches `config.yml`

```yaml
search:
  type: http
  mode: OPENSEARCH
  uri: https://<load balancer, data node, or opensearch_endpoint>:9200
  username: 'iq-server'
  password: '<from the container app secret>'
nexusOne:
  connection:
    type: http
    mode: OPENSEARCH
    uri: https://<the same address>:9200
    username: 'iq-server'
    password: '<from the container app secret>'
    nexusOneIndexReplicas: <1 at three data nodes, 0 at one>
```

The two credentials are single-quoted, so any character is safe in the password, and the startup output
redacts every `password:` line, so neither credential reaches Log Analytics.

### TLS, and the JVM trust store

**IQ Server has no per-connection trust setting.** A certificate signed by a private certificate
authority is trusted only if that authority is in the trust store the JVM loads. For a cluster
Terraform builds, the deploy handles this. For a cluster you bring whose certificate is signed by a
private authority, set `opensearch_ca_pem` to that authority's certificate, base64 encoded:

```hcl
opensearch_ca_pem = "<output of: base64 < ca.pem>"
```

The container's entrypoint copies the JVM's own trust store, adds the authority to the copy, and names
the copy with `javax.net.ssl.trustStore`. **The JVM's own store is never replaced**, because it also serves
IQ Server's calls to the Sonatype data service. A certificate from a public authority needs none of this.

**IQ Server also accepts a plain `http://` URI** with `opensearch_use_tls = false`. That sends the
basic-auth password in clear text on every request, so use it only for a proof of concept.

---

## Deployment Guide

The quickest route is the top-level [guided deploy script](../README.md#option-1-the-guided-deploy-script).
The steps below deploy this directory by hand.

### Step 1: Prerequisites

| Tool | Version | Installation | Purpose |
|------|---------|--------------|---------|
| **Terraform** | >= 1.2 | [Install Guide](https://developer.hashicorp.com/terraform/install) | Infrastructure as Code |
| **Azure CLI** | >= 2.0 | [Install Guide](https://learn.microsoft.com/cli/azure/install-azure-cli) | Azure API access |

You need an Azure subscription with Contributor access, and permission to create resource groups,
virtual networks, network security groups, NAT gateways, private DNS zones, Container Apps, PostgreSQL
Flexible Server, storage accounts, Key Vault and its access policies, managed identities, virtual
machines, disks, internal load balancers, and Log Analytics.

PostgreSQL Flexible Server vCPU count is a quota per subscription and per region. Check the region's usage
before applying, and request a quota increase if the server's vCPU count does not fit. `az rest` fills in
`{subscriptionId}` from the signed-in account; replace `eastus` with the region's short name:

```bash
az rest --method get --url "https://management.azure.com/subscriptions/{subscriptionId}/providers/Microsoft.DBforPostgreSQL/locations/eastus/resourceType/flexibleServers/usages?api-version=2024-08-01" --query "value[?name.value=='cores'].{used:currentValue, limit:limit}" -o table
```

### Step 2: Configure Azure Credentials

```bash
az login
az account set --subscription "<subscription-id-or-name>"
```

### Step 3: Configure Terraform Variables

```bash
cd sca-reference-architectures/infra-azure
cp terraform.tfvars.example terraform.tfvars
# copy in your size's values from examples/<size>.tfvars, then replace every CHANGE_ME
```

`terraform.tfvars.example` carries the Size M values. Every `CHANGE_ME` must be replaced, including
`db_password`, `iq_admin_initial_password` (at least 12 characters, read by IQ Server on its first start
only), `iq_license_file` (the path to your IQ Server license file, which IQ Server installs on its first
start), `search_engine` and the `common_tags` values.

### Step 4: Deploy Infrastructure

```bash
terraform init
./tf-plan.sh
./tf-apply.sh
```

The apply script prints the application URL, then runs `iq-post-deploy.sh`, which sets the shard counts
and chooses the search backend, and installs the license only if IQ Server has none yet. Run
`./iq-post-deploy.sh` again at any time.

### Step 5: Access Sonatype IQ Server

Initial startup can take 5-10 minutes. Open the `application_url` output, the Container App's own HTTPS
address, and log in as `admin` with the password you set in `iq_admin_initial_password`.

---

## Teardown / Cleanup

**WARNING: This will delete ALL infrastructure and data!**

```bash
./tf-destroy.sh
```

Keep the terminal open until it finishes. An OpenSearch cluster this configuration built is deleted with
the rest, indices included. A cluster you brought yourself is not touched.

---

## Configuration

`terraform.tfvars.example` lists every variable with its Size M value. Settings worth knowing:

- **Single replica**: the Container App runs exactly one IQ Server.
- **`iq_docker_image`**: pinned to `sonatype/nexus-iq-server:1.209.0`. To pull from a private registry, set `container_registry_server`, `container_registry_username` and `container_registry_password`; leave all three empty for a public registry.
- **`db_high_availability_enabled`, `db_geo_redundant_backup_enabled`**: `false` by default; set them to `true` for production.
- **`postgres_version`**: `18` by default.
- **`log_share_quota_gb`**: the size of the log share, 128 GB by default.

### Running several sizes in one subscription

Every resource name is built from `cluster_name`, `ref-arch-iq` by default, so two deployments coexist in
one Azure subscription as long as they use different values. A storage account name is lowercase
alphanumeric and capped at 24 characters, and a Key Vault name is capped at 24 characters. Both carry a
random suffix, which is why `cluster_name` is capped at 14 characters.

## Security Features

- **VNet Isolation**: IQ Server and OpenSearch run in private subnets; PostgreSQL in its own delegated subnet with private DNS
- **Secrets Management**: The database, OpenSearch and initial admin passwords are stored in Azure Key Vault and reach the container as Container App secrets
- **Encryption**: Azure Files and PostgreSQL encrypted at rest; TLS between IQ Server and OpenSearch; HTTPS on the Container App's own address, with a certificate Azure manages. Plain HTTP is redirected to HTTPS
- **Network Security Groups**: Least-privilege network access
- **Managed Identity**: the Container App uses a system-assigned identity, and the OpenSearch nodes a user-assigned one

## Reliability and Backup

- **Single Instance**: One Container App replica, in one zone at a time; Container Apps restarts it if it fails
- **Single Zone Database**: unless `db_high_availability_enabled` is set
- **Database Backups**: Automated PostgreSQL backups with 7-day retention (configurable)
- **File Share Persistence**: Application data on the Azure Files share survives container restarts

## Monitoring and Logging

- **Log Analytics**: the container's standard output, including IQ Server's server, request, audit and policy-violation logs
- **Log files**: `clm-server.log`, `request.log` and `audit.log` are written to the `nexus-iq-logs` Azure Files share, mounted at `/var/log/nexus-iq-server`. `clm-server.log` rolls hourly and keeps 24 archives
- **Audit events**: IQ Server writes them to the database by default, see [Logging](../README.md#logging)

## Important: Admin Port 8071 Not Exposed

The admin port 8071 is configured within the IQ Server container but **not exposed externally**. The Container App's ingress reaches only the main application port 8070, over HTTPS on port 443. Admin port access is available through Container App console sessions if needed for troubleshooting.
