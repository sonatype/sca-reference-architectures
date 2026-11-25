# Sonatype IQ Server Infrastructure as Code: AWS, Azure, and GCP Reference Architectures

Production-ready Terraform configurations for deploying Sonatype IQ Server across AWS, Azure, and GCP with Single Instance, High Availability, and Kubernetes deployment patterns.

---

## Responsibility Disclaimer

**WARNING: These reference architectures deploy real cloud resources, and your cloud provider charges for them.**

You are solely responsible for all charges resulting from deploying these configurations. Resources provisioned include compute instances, managed databases, OpenSearch clusters, load balancers, storage volumes, and networking components, all of which accrue charges while active.

- **Check your cloud provider's pricing** for every service before deployment
- **Set billing alerts** to avoid unexpected charges
- **Destroy resources** promptly when no longer needed using the provided cleanup scripts
- **Monitor usage** through your cloud provider's billing tools

Sonatype provides these configurations as reference examples. You are responsible for reviewing and customizing them to meet your organization's security, compliance, and operational requirements.

---

## What This Provides

### 9 Reference Architectures

| | AWS | Azure | GCP |
|---|---|---|---|
| **Single Instance** | ECS Fargate + RDS | Container Apps + PostgreSQL | GCE Docker + Cloud SQL |
| **High Availability** | ECS Fargate + Aurora + EFS | Container Apps + Zone-Redundant DB | MIG + Regional Cloud SQL + Filestore |
| **Kubernetes** | EKS + Helm | AKS + Helm | GKE + Helm |

Every architecture runs with one of two search backends, chosen with `search_engine`, which covers both of IQ Server's search features, the Nexus One index and Advanced Search. With `opensearch`, Terraform also creates an OpenSearch cluster that serves both: an Amazon OpenSearch Service domain on AWS, and a self-managed OpenSearch 3.7 cluster on Azure and GCP. With `builtin`, no OpenSearch is created: Nexus One keeps its index in IQ Server's PostgreSQL database, which supports up to 10,000 applications (sizes XS, S and M), and Advanced Search uses IQ Server's built-in index. See [Choosing the search backend](#choosing-the-search-backend).

### Key Features

- A guided deploy script that asks for every choice and value, or runs unattended from an answers file
- Production-grade Terraform with security best practices
- Multi-AZ/Zone deployments for high availability
- Auto-scaling (CPU, memory, and load-based)
- Managed PostgreSQL databases with automated backups and failover
- Two search backends: OpenSearch for the Nexus One index and Advanced Search, created by Terraform on every cloud at every size, or, with `search_engine = "builtin"`, IQ Server's PostgreSQL database for the Nexus One index on estates of up to 10,000 applications, with Advanced Search on IQ Server's built-in index
- Encrypted storage and secrets management, including the initial admin password
- Load balancing with health checks
- Official Sonatype Helm chart, pinned to a released version (Kubernetes deployments)
- ARM instance support (see [Cross-Provider Instance Comparison](#cross-provider-instance-comparison))

### Official Documentation

- [IQ Server Documentation](https://help.sonatype.com/en/sonatype-lifecycle.html)
- [IQ Server Installation Guide](https://help.sonatype.com/en/install-self-hosted-iq-server.html)
- [IQ Server Helm chart source and README](https://github.com/sonatype/nexus-iq-server-ha/tree/main/chart), also listed on [Artifact Hub](https://artifacthub.io/packages/helm/sonatype/nexus-iq-server-ha)

---

## Prerequisites

### Cloud Account Setup

You need an active cloud account with permissions to create:
- VPC/VNet and networking resources
- Compute containers or instances (ECS, Container Apps, GCE, EKS/AKS/GKE)
- Managed database instances (RDS, Azure Database, Cloud SQL)
- OpenSearch domains (AWS), or virtual machines, Kubernetes node pools and internal load balancers (Azure and GCP)
- Load balancers and storage volumes
- IAM roles, service accounts, security groups and secrets

### Tools Installation

| Tool | Version | Required For |
|------|---------|--------------|
| [Terraform](https://developer.hashicorp.com/terraform/install) | >= 1.2 | All deployments |
| [AWS CLI](https://aws.amazon.com/cli/) | Latest | AWS deployments |
| [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) | Latest | Azure deployments |
| [Google Cloud CLI](https://cloud.google.com/sdk/docs/install) | Latest | GCP deployments |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | Latest | Kubernetes deployments only |
| [Helm](https://helm.sh/docs/intro/install/) | >= 3.9.3 | Kubernetes deployments only |

### IQ Server Requirements

- **Docker Image**: `sonatype/nexus-iq-server` ([Docker Hub](https://hub.docker.com/r/sonatype/nexus-iq-server)), with its version pinned in one place per architecture: the default of `iq_docker_image` in `variables.tf`, or of `helm_chart_version` on the three Kubernetes architectures. `scripts/bump-iq-version.sh <version>` sets it in all nine
- **License**: Standard license for single instance; HA-capable license for multi-node deployments. Every architecture requires the license file, named by `iq_license_file`: Terraform keeps it in the cloud's secret store, or a Kubernetes secret, and every IQ Server node installs it on its first start. An unlicensed IQ Server runs one node only, and choosing OpenSearch as the search backend needs a license
- **PostgreSQL**: a major version the PostgreSQL project still supports, under its [versioning policy](https://www.postgresql.org/support/versioning/), which today means 15 or later, on its latest minor release. 18 is recommended, and the default for new deployments. Provisioned automatically by Terraform. With `search_engine = "builtin"`, it also holds the Nexus One index
- **OpenSearch**: Needed only with `search_engine = "opensearch"`, the backend for estates above 10,000 applications and an option at every size. A reachable OpenSearch cluster then serves Advanced Search and the Nexus One index. Terraform creates it on every cloud: on AWS as an Amazon OpenSearch Service domain, and on Azure and GCP, which have no managed OpenSearch service, as a self-managed OpenSearch 3.x cluster (3.7 recommended). To use a cluster you already run, give Terraform its endpoint and credentials instead. With `builtin`, no OpenSearch is created, and Nexus One keeps its index in the PostgreSQL database above. See [OpenSearch](#opensearch).

### SSL Certificate (Optional)

For HTTPS access, prepare:
- **AWS**: ACM certificate ARN
- **Azure**: a custom domain certificate on the Container App or Application Gateway
- **GCP**: Google-managed or self-managed SSL certificate

---

## Quick Start

### Sizing Guide

Choose your deployment size based on your application count and daily evaluation volume:

| Size | Applications | Evaluations per day, hour ² | IQ Server nodes | Compute (per node) | Database (AWS) | HA Required | Search backend ³ | OpenSearch data nodes (AWS) |
|------|:------------:|:---------------:|:---------------:|:------------------:|:--------------:|:-----------:|:----------------:|:---------------------:|
| **XS** | < 500 | ~2.5k, 100 | 1 | 2 vCPU / 16 GB | db.m8g.large (2 vCPU / 8 GB) | No | `builtin` or `opensearch` | 1 x m8g.medium.search ¹ |
| **S** | 500 - 2k | ~5k, 150 | 1 | 4 vCPU / 32 GB | db.r8g.large (2 vCPU / 16 GB) | No | `builtin` or `opensearch` | 1 x m8g.large.search ¹ |
| **M** | 2k - 10k | ~7.5k, 250 | 2 to 3 | 8 vCPU / 32 GB | db.r8g.xlarge (4 vCPU / 32 GB) | Recommended | `builtin` or `opensearch` | 3 x m8g.large.search ¹ |
| **L** | 10k - 30k | ~15k, 350 | 2 to 4 | 16 vCPU / 64 GB | db.r8g.2xlarge (8 vCPU / 64 GB) | Required | `opensearch` | 3 x m8g.xlarge.search ¹ |
| **XL** | 30k - 100k | ~25k, 450 | 3 to 5 | 16 vCPU / 128 GB | db.r8g.4xlarge (16 vCPU / 128 GB) | Required | `opensearch` | 3 x r8g.2xlarge.search ¹ |

> ¹ With `search_engine = "opensearch"`, Terraform creates OpenSearch at every size. The per-size cluster specification, meaning data node count, node size, storage, shards and replicas, is in [Per-size cluster specification](#per-size-cluster-specification). With `search_engine = "builtin"`, no OpenSearch is created: see [Choosing the search backend](#choosing-the-search-backend).

> ² Evaluations per day, hour are typical figures for the whole cluster on a normal day, a guide for planning, not a limit.

> ³ `builtin` keeps the Nexus One index in IQ Server's PostgreSQL database, which supports estates of up to 10,000 applications, so L and XL need `opensearch`. An estate you expect to grow past 10,000 applications should start on `opensearch`, since IQ Server keeps the first backend chosen.

The generic IQ Server sizing and deployment guidance is in Sonatype's [reference architecture help pages](https://help.sonatype.com/en/sonatype-platform-reference-architectures.html).

The Database and OpenSearch columns give the AWS types. Azure uses a database class with the same vCPU and memory at every size, and GCP does at M, L and XL; at XS and S the GCP class has the same vCPU and less memory, 7.5 GB and 13 GB against 8 GB and 16 GB. The classes are listed in [Database Instance Comparison](#database-instance-comparison) for M, L and XL and in [Detailed Specifications](#detailed-specifications) for XS and S, and their OpenSearch node types are in [Per-size cluster specification](#per-size-cluster-specification). The Java heap for each platform is in [JVM Configuration](#jvm-configuration).

### Option 1: The Guided Deploy Script

The quickest route is `deploy.sh` at the top of the repository. It asks for:

1. The cloud: AWS, Azure or GCP
2. The architecture: Single Instance, High Availability, or Kubernetes
3. The size, from those the architecture offers
4. The search backend: `opensearch`, or `builtin` for the Nexus One index in IQ Server's PostgreSQL database, up to 10,000 applications
5. Every value the architecture's example file marks `CHANGE_ME`, such as the database password, the initial admin password and the license file, which `--license-file` or `license_file` in the answers file also answers

The region comes from the example file. `deploy.sh` shows it before asking you to continue, and `--set aws_region=...`, `--set azure_region=...` or `--set gcp_region=...` changes it.

It then writes `terraform.tfvars` from the example file and that size's values in `examples/<size>.tfvars`, runs the plan and the apply, installs the Helm chart on the Kubernetes architectures, and sets up search on IQ Server.

```bash
git clone https://github.com/sonatype/sca-reference-architectures.git
cd sca-reference-architectures
./deploy.sh --license-file /path/to/your-license.lic   # asks each question in turn
./deploy.sh --help                                     # lists every option and the answers file format
```

To run it unattended, give the same answers as options or in an answers file of `key=value` lines:

```bash
./deploy.sh --answers-file my-deployment.answers --license-file /path/to/your-license.lic --yes
./deploy.sh --dry-run --answers-file my-deployment.answers   # prints terraform.tfvars and the commands, changes nothing
./deploy.sh --destroy --answers-file my-deployment.answers   # removes what it deployed
```

### Option 2: Manual Terraform

#### Step 1: Choose Your Reference Architecture

1. **Determine your size** from the table above
2. **Select your cloud provider** (AWS, Azure, or GCP)
3. **Select your deployment pattern**:

| Pattern | Best For | HA License |
|---------|----------|:----------:|
| **Single Instance** | XS/S sizes, development, testing, or small production | No |
| **High Availability** | M/L/XL production workloads requiring uptime guarantees | Yes |
| **Kubernetes** | Teams with existing K8s infrastructure and expertise | Yes |

Then navigate to the corresponding directory:

| | Single Instance | High Availability | Kubernetes |
|---|---|---|---|
| **AWS** | [`infra-aws`](./infra-aws/) | [`infra-aws-ha`](./infra-aws-ha/) | [`infra-aws-ha-k8s-helm`](./infra-aws-ha-k8s-helm/) |
| **Azure** | [`infra-azure`](./infra-azure/) | [`infra-azure-ha`](./infra-azure-ha/) | [`infra-azure-ha-k8s-helm`](./infra-azure-ha-k8s-helm/) |
| **GCP** | [`infra-gcp`](./infra-gcp/) | [`infra-gcp-ha`](./infra-gcp-ha/) | [`infra-gcp-ha-k8s-helm`](./infra-gcp-ha-k8s-helm/) |

#### Step 2: Choose the Search Backend

Choose `opensearch` or `builtin`; [Choosing the search backend](#choosing-the-search-backend) compares them. With `search_engine = "opensearch"`, Terraform creates the OpenSearch cluster for the Nexus One index and Advanced Search on every cloud, at the shape the size's example file sets: an Amazon OpenSearch Service domain on AWS; OpenSearch 3.7 on virtual machines with an internal load balancer on the Azure and GCP single instance and High Availability architectures; and OpenSearch 3.7 on dedicated node pools, run by the OpenSearch Kubernetes Operator, on AKS and GKE. To use a cluster you already run instead, set its endpoint and credentials in `terraform.tfvars`. See [OpenSearch](#opensearch). With `search_engine = "builtin"`, no OpenSearch is created: Nexus One keeps its index in IQ Server's PostgreSQL database, for estates of up to 10,000 applications (sizes XS, S and M), and Advanced Search uses IQ Server's built-in index.

#### Step 3: Configure Your Deployment

```bash
git clone https://github.com/sonatype/sca-reference-architectures.git
cd sca-reference-architectures/<your-chosen-architecture>

# Start from the example file, then copy in your size's values from examples/<size>.tfvars
cp terraform.tfvars.example terraform.tfvars
# Replace every CHANGE_ME with your values: region, passwords, and so on.
# Set iq_admin_initial_password to the password IQ Server's admin user starts with.
# Set iq_license_file to the path of your IQ Server license file.
# Set search_engine to "opensearch" for an OpenSearch cluster, or "builtin" for the Nexus One index in PostgreSQL (up to 10,000 applications).
```

#### Step 4: Deploy

```bash
terraform init
./tf-plan.sh                                            # Review the execution plan
./tf-apply.sh                                           # Deploy infrastructure
```

On GCP the scripts are `./gcp-plan.sh` and `./gcp-apply.sh` in `infra-gcp`, and `./gcp-ha-plan.sh` and
`./gcp-ha-apply.sh` in `infra-gcp-ha`. Every plan script stops if an uncommented line in
`terraform.tfvars` still holds `CHANGE_ME`, and Terraform rejects a `CHANGE_ME` value too.

For **Kubernetes deployments**, also run:

```bash
./helm-install.sh                                       # Deploy IQ Server via Helm chart
# with deploy.sh's size values: ./helm-install.sh --values examples/<size>.helm-values.yaml
```

Every IQ Server node installs the license from `iq_license_file` on its first start. On Kubernetes,
`helm-install.sh` installs the release with no IQ Server pod, so the database migration Job runs alone,
then starts one pod, which creates the Advanced Search index, and then scales to the configured count.
Once IQ Server answers, the apply or install runs `iq-post-deploy.sh`. With `search_engine = "opensearch"`
it sets the OpenSearch shard counts from the number of data nodes, chooses OpenSearch as the search
backend on IQ Server versions that ask for that choice, and installs the license only if IQ Server has
none yet; with `"builtin"` it has nothing to set, and you choose PostgreSQL on the Nexus One setup
page. Behind a load balancer it retries a 502, 503 or 504 for up to 10 minutes
(`IQ_GATEWAY_RETRY_SECONDS`), since one IQ Server node can answer while another is still starting. Run
`./iq-post-deploy.sh` again at any time; it changes only what is not yet set.

#### Step 5: Get Your Access Information

```bash
terraform output
```

This displays the application URL, database endpoint, and other access details.

#### Step 6: Access IQ Server

1. Navigate to the application URL from the Terraform outputs
2. Wait 5-15 minutes for the application to initialize
3. Log in as `admin`, with the password you set in `iq_admin_initial_password`
4. With `search_engine = "opensearch"`, start the first Nexus One index build in the Index Manager. With `"builtin"`, choose PostgreSQL on the Nexus One setup page, which keeps the Nexus One index in IQ Server's PostgreSQL database

---
## Reference Architectures: Detailed Specifications

The three cloud tables carry the same rows. XS and S are single instance sizes; their values are in
[Detailed Specifications](#detailed-specifications) below.

### AWS Reference Architectures

|  | **Size M** | **Size L** | **Size XL** |
|--|-----------|-----------|------------|
| **Applications** | 2k - 10k | 10k - 30k | 30k - 100k |
| **Number of IQ Server nodes** | 2 to 3 | 2 to 4 | 3 to 5 |
| **Deployment type** | HA recommended; single instance only where downtime is acceptable | HA required | HA required |
| **Evaluations per day, hour** | ~7.5k, 250 | ~15k, 350 | ~25k, 450 |
| **Compute** | | | |
| Instance type | Fargate: 8 vCPU, 32 GB task. EKS: m8g.2xlarge (ARM) or m8i.2xlarge (x86) node | Fargate: 16 vCPU, 64 GB task. EKS: m8g.4xlarge (ARM) or m8i.4xlarge (x86) node | Fargate: 16 vCPU, 120 GB task. EKS: r9g.4xlarge (ARM) or r8i.4xlarge (x86) node |
| Memory for IQ Server | 32 GB Fargate task, 26 GB EKS pod | 64 GB Fargate task, 56 GB EKS pod | 120 GB Fargate task, 112 GB EKS pod |
| Java heap | 20 GB on Fargate, 17 GB on EKS, see [JVM Configuration](#jvm-configuration) | 42 GB on Fargate, 37 GB on EKS | 80 GB on Fargate, 74 GB on EKS |
| Deployment option | Amazon ECS on Fargate or EKS | Amazon ECS on Fargate or EKS | Amazon ECS on Fargate or EKS |
| **Database** | | | |
| Service | RDS PostgreSQL or Aurora PostgreSQL | Aurora PostgreSQL (recommended) | Aurora PostgreSQL (strongly recommended) |
| PostgreSQL version | A version PostgreSQL still supports, 15 or later today (18 recommended, and the default) | A version PostgreSQL still supports, 15 or later today (18 recommended, and the default) | A version PostgreSQL still supports, 15 or later today (18 recommended, and the default) |
| Instance type | db.r8g.xlarge (4 vCPU, 32 GB) | db.r8g.2xlarge (8 vCPU, 64 GB) | db.r8g.4xlarge (16 vCPU, 128 GB) |
| Storage | 128 GB gp3 on RDS, auto-scaling to 500 GB; Aurora grows on its own | Aurora, grows on its own, expected to grow to about 1 TB | Aurora, grows on its own, expected to grow to about 2 TB |
| IOPS and throughput | gp3 baseline on RDS; managed by Aurora | Managed by Aurora | Managed by Aurora |
| High availability | Multi-AZ recommended | Multi-AZ required | Multi-AZ with automatic failover |
| **Storage** | | | |
| Service and tier | Amazon EFS, General Purpose, Elastic throughput | Amazon EFS, General Purpose, Elastic throughput | Amazon EFS, General Purpose, Elastic throughput |
| Protocol | NFS v4.1 | NFS v4.1 | NFS v4.1 |
| Redundancy | Regional, across Availability Zones | Regional, across Availability Zones | Regional, across Availability Zones |
| Capacity | Grows with use, plan for 200 GB - 500 GB | Grows with use, plan for 500 GB - 1.5 TB | Grows with use, plan for 1.5 TB - 4 TB |
| IOPS | Scales on its own, by default up to 250,000 read and 50,000 write | Same | Same |
| Throughput | Scales on its own | Scales on its own | Scales on its own |
| **OpenSearch** | | | |
| Service | Amazon OpenSearch Service, OpenSearch 3.7, created by Terraform | Amazon OpenSearch Service, OpenSearch 3.7, created by Terraform | Amazon OpenSearch Service, OpenSearch 3.7, created by Terraform |
| Data nodes | 3 x m8g.large.search, 100 GB each | 3 x m8g.xlarge.search, 150 GB each | 3 x r8g.2xlarge.search, 250 GB each |
| Cluster managers | 3 x m8g.medium.search | 3 x m8g.medium.search | 3 x m8g.large.search |
| **Load balancer** | Application Load Balancer | Application Load Balancer | Application Load Balancer |
| **Terraform Templates** | [Single Instance](./infra-aws) &#124; [High Availability](./infra-aws-ha) &#124; [HA Kubernetes](./infra-aws-ha-k8s-helm) | [High Availability](./infra-aws-ha) &#124; [HA Kubernetes](./infra-aws-ha-k8s-helm) | [High Availability](./infra-aws-ha) &#124; [HA Kubernetes](./infra-aws-ha-k8s-helm) |

On EKS the Application Load Balancer is created by the AWS Load Balancer Controller.

---

### Azure Reference Architectures

|  | **Size M** | **Size L** | **Size XL** |
|--|-----------|-----------|------------|
| **Applications** | 2k - 10k | 10k - 30k | 30k - 100k |
| **Number of IQ Server nodes** | 2 to 3 | 2 to 4 | 3 to 5 |
| **Deployment type** | HA recommended; single instance only where downtime is acceptable | HA required | HA required |
| **Evaluations per day, hour** | ~7.5k, 250 | ~15k, 350 | ~25k, 450 |
| **Compute** | | | |
| Instance type | Container Apps: D8 workload profile, 8 vCPU, 32 GB. AKS: Standard_D8ps_v6 (ARM) or Standard_D8s_v6 (x86) node | Container Apps: D16 workload profile, 16 vCPU, 64 GB. AKS: Standard_D16ps_v6 (ARM) or Standard_D16s_v6 (x86) node | Container Apps: E16 workload profile, 16 vCPU, 128 GB. AKS: Standard_E16ps_v6 (ARM) or Standard_E16s_v7 (x86) node |
| Memory for IQ Server | 30 GB replica, 26 GB AKS pod | 62 GB replica, 56 GB AKS pod | 126 GB replica, 110 GB AKS pod |
| Java heap | 18 GB on `infra-azure`, 20 GB on `infra-azure-ha`, 17 GB on AKS, see [JVM Configuration](#jvm-configuration) | 41 GB on Container Apps, 37 GB on AKS | 80 GB, 73 GB on AKS |
| Deployment option | Azure Container Apps or AKS | Azure Container Apps or AKS | AKS recommended at this scale |
| **Database** | | | |
| Service | Azure Database for PostgreSQL, Flexible Server | Azure Database for PostgreSQL, Flexible Server | Azure Database for PostgreSQL, Flexible Server |
| PostgreSQL version | A version PostgreSQL still supports, 15 or later today (18 recommended, and the default) | A version PostgreSQL still supports, 15 or later today (18 recommended, and the default) | A version PostgreSQL still supports, 15 or later today (18 recommended, and the default) |
| Instance type | MO_Standard_E4ds_v6 (4 vCPU, 32 GB) | MO_Standard_E8ds_v6 (8 vCPU, 64 GB) | MO_Standard_E16ds_v6 (16 vCPU, 128 GB) |
| Storage | 128 GB, grows automatically | 256 GB, grows automatically, expected to grow to about 1 TB | 512 GB, grows automatically, expected to grow to about 2 TB |
| IOPS and throughput | Set by the storage tier, P10 | P15 tier | P20 tier |
| High availability | Zone redundancy recommended | Zone redundancy required | Zone redundant with automatic failover |
| **Storage** | | | |
| Service and tier | Azure Files, Standard HDD on Container Apps, Premium SSD on AKS | Azure Files, Standard HDD on Container Apps, Premium SSD on AKS | Azure Files, Premium SSD |
| Protocol | SMB 3.0 on Container Apps, NFS v4.1 on AKS | SMB 3.0 on Container Apps, NFS v4.1 on AKS | SMB 3.0 on Container Apps, NFS v4.1 on AKS |
| Redundancy | LRS on `infra-azure`, ZRS on the HA architectures | ZRS | ZRS |
| Capacity | 500 GB share quota | 1,536 GB share quota | 4,096 GB share quota |
| IOPS | Standard: up to 20,000 a share, not provisioned. Premium: 3,500 baseline, bursting to 10,000 | Standard: up to 20,000 a share. Premium: 4,536 baseline, bursting to 10,000 | Premium: 7,096 baseline, bursting to 12,288 |
| Throughput | Standard: up to the storage account's limit, 60 MB/s a file. Premium: 150 MB/s | Standard: as M. Premium: 255 MB/s | Premium: 510 MB/s |
| **OpenSearch** | | | |
| Service | Self-managed OpenSearch 3.7, created by Terraform: virtual machines on Container Apps, the OpenSearch Kubernetes Operator on dedicated node pools on AKS | Same | Same |
| Data nodes | 3 x Standard_D2ps_v6, 128 GB each | 3 x Standard_D4ps_v6, 256 GB each | 3 x Standard_E8ps_v6, 256 GB each |
| Cluster managers | 3 x Standard_D2pls_v6 | 3 x Standard_D2pls_v6 | 3 x Standard_D2ps_v6 |
| OpenSearch endpoint | Standard SKU internal load balancer on Container Apps; a Service selecting the data nodes on AKS | Same | Same |
| **Load balancer** | Application Gateway; Container Apps ingress on `infra-azure` | Application Gateway | Application Gateway |
| **Terraform Templates** | [Single Instance](./infra-azure) &#124; [High Availability](./infra-azure-ha) &#124; [HA Kubernetes](./infra-azure-ha-k8s-helm) | [High Availability](./infra-azure-ha) &#124; [HA Kubernetes](./infra-azure-ha-k8s-helm) | [High Availability](./infra-azure-ha) &#124; [HA Kubernetes](./infra-azure-ha-k8s-helm) |

> **Note on Azure storage tiers:** Container Apps mounts the share over SMB, so Standard HDD serves M and L there. AKS mounts it over NFS, which needs Premium SSD, so the Kubernetes architecture uses Premium at every size, and XL uses Premium everywhere. Premium SSD performs by fixed tiers, so the OpenSearch data disks are the smallest Premium tier at or above each storage figure in the [Per-size cluster specification](#per-size-cluster-specification).

---

### GCP Reference Architectures

|  | **Size M** | **Size L** | **Size XL** |
|--|-----------|-----------|------------|
| **Applications** | 2k - 10k | 10k - 30k | 30k - 100k |
| **Number of IQ Server nodes** | 2 to 3 | 2 to 4 | 3 to 5 |
| **Deployment type** | HA recommended; single instance only where downtime is acceptable | HA required | HA required |
| **Evaluations per day, hour** | ~7.5k, 250 | ~15k, 350 | ~25k, 450 |
| **Compute** | | | |
| Instance type | n4a-standard-8 (ARM Google Axion), 8 vCPU, 32 GB | n4a-standard-16 (ARM Google Axion), 16 vCPU, 64 GB | n4a-highmem-16 (ARM Google Axion), 16 vCPU, 128 GB |
| Memory for IQ Server | 32 GB VM, 26 GB GKE pod | 64 GB VM, 56 GB GKE pod | 128 GB VM, 110 GB GKE pod |
| Java heap | 20 GB on a VM, 17 GB on GKE, see [JVM Configuration](#jvm-configuration) | 42 GB, 37 GB on GKE | 85 GB, 73 GB on GKE |
| Deployment option | GCE with Docker or GKE | GCE with Docker or GKE | GCE with Docker or GKE |
| **Database** | | | |
| Service | Cloud SQL PostgreSQL, Enterprise edition | Cloud SQL PostgreSQL, Enterprise edition | Cloud SQL PostgreSQL, Enterprise edition |
| PostgreSQL version | A version PostgreSQL still supports, 15 or later today (18 recommended, and the default) | A version PostgreSQL still supports, 15 or later today (18 recommended, and the default) | A version PostgreSQL still supports, 15 or later today (18 recommended, and the default) |
| Instance type | db-custom-N4-4-32768 (4 vCPU, 32 GB) | db-custom-N4-8-65536 (8 vCPU, 64 GB) | db-custom-N4-16-131072 (16 vCPU, 128 GB) |
| Storage | 128 GB Hyperdisk Balanced, auto-resize to 500 GB | 256 GB Hyperdisk Balanced, auto-resize to 1 TB | 512 GB Hyperdisk Balanced, auto-resize to 2 TB |
| IOPS and throughput | 8,000 IOPS, 252 MB/s | 8,000 IOPS, 357 MB/s | 10,000 IOPS, 446 MB/s |
| High availability | Regional on the HA architectures, zonal on `infra-gcp` | Regional, automatic failover | Regional, automatic failover |
| **Storage** | | | |
| Service and tier | Cloud Filestore, Regional tier | Cloud Filestore, Regional tier | Cloud Filestore, Regional tier |
| Protocol | NFS v3 | NFS v3 | NFS v3 |
| Redundancy | Regional, across zones | Regional, across zones | Regional, across zones |
| Capacity | 500 GB | 1,536 GB | 4,096 GB |
| IOPS | 8,000 provisioned | 16,000 provisioned | 24,000 provisioned |
| Throughput | Follows the provisioned IOPS | Follows the provisioned IOPS | Follows the provisioned IOPS |
| **OpenSearch** | | | |
| Service | Self-managed OpenSearch 3.7, created by Terraform: Compute Engine VMs on GCE and MIG, the OpenSearch Kubernetes Operator on dedicated node pools on GKE | Same | Same |
| Data nodes | 3 x c4a-standard-2, 100 GB each | 3 x c4a-standard-4, 150 GB each | 3 x c4a-highmem-8, 250 GB each |
| Cluster managers | 3 x c4a-standard-1 | 3 x c4a-standard-1 | 3 x c4a-standard-2 |
| OpenSearch endpoint | Internal passthrough Network Load Balancer on GCE and MIG; a Service selecting the data nodes on GKE | Same | Same |
| **Load balancer** | Global external Application Load Balancer; GKE Ingress on GKE | Global external Application Load Balancer; GKE Ingress on GKE | Global external Application Load Balancer; GKE Ingress on GKE |
| **Terraform Templates** | [Single Instance](./infra-gcp) &#124; [High Availability](./infra-gcp-ha) &#124; [HA Kubernetes](./infra-gcp-ha-k8s-helm) | [High Availability](./infra-gcp-ha) &#124; [HA Kubernetes](./infra-gcp-ha-k8s-helm) | [High Availability](./infra-gcp-ha) &#124; [HA Kubernetes](./infra-gcp-ha-k8s-helm) |

> **Note on the GCP database tiers:** M, L and XL use the N4 series, because the classic `db-custom` tiers allow at most 6.5 GB per vCPU. N4 takes only Hyperdisk Balanced storage, with the IOPS and throughput set per size.

> **Note on Filestore:** the Regional tier keeps the share available through a zone outage. At XS and S, `infra-gcp` provisions 500 GB at 4,000 IOPS.

---

### Cross-Provider Instance Comparison

The following tables provide equivalent instance types across cloud providers for quick cross-reference.

#### Size M (8 vCPU / 32 GB)

| Cloud Provider | Instance Type | Architecture |
|----------------|---------------|--------------|
| **GCP** | n4a-standard-8 | ARM (Google Axion) |
| **AWS** | m8g.2xlarge | ARM (Graviton4) |
| **AWS** | m8i.2xlarge | x86_64 |
| **Azure** | Standard_D8ps_v6 | ARM (Azure Cobalt 100) |
| **Azure** | Standard_D8s_v6 | x86_64 |

#### Size L (16 vCPU / 64 GB)

| Cloud Provider | Instance Type | Architecture |
|----------------|---------------|--------------|
| **GCP** | n4a-standard-16 | ARM (Google Axion) |
| **AWS** | m8g.4xlarge | ARM (Graviton4) |
| **AWS** | m8i.4xlarge | x86_64 |
| **Azure** | Standard_D16ps_v6 | ARM (Azure Cobalt 100) |
| **Azure** | Standard_D16s_v6 | x86_64 |

#### Size XL (16 vCPU / 128 GB)

| Cloud Provider | Instance Type | Architecture |
|----------------|---------------|--------------|
| **GCP** | n4a-highmem-16 | ARM (Google Axion) |
| **AWS** | r8g.4xlarge or newer, r9g.4xlarge on EKS | ARM (Graviton4 or newer) |
| **AWS** | r8i.4xlarge | x86_64 |
| **Azure** | Standard_E16ps_v6 | ARM (Azure Cobalt 100) |
| **Azure** | Standard_E16s_v7 | x86_64 |

#### Database Instance Comparison

| Size | GCP | AWS | Azure |
|------|-----|-----|-------|
| **M** (2 to 3 nodes) | db-custom-N4-4-32768 Enterprise (4 vCPU, 32 GB) | db.r8g.xlarge (4 vCPU, 32 GB) | MO_Standard_E4ds_v6 (4 vCPU, 32 GB) |
| **L** (2 to 4 nodes) | db-custom-N4-8-65536 Enterprise (8 vCPU, 64 GB) | db.r8g.2xlarge (8 vCPU, 64 GB) | MO_Standard_E8ds_v6 (8 vCPU, 64 GB) |
| **XL** (3 to 5 nodes) | db-custom-N4-16-131072 Enterprise (16 vCPU, 128 GB) | db.r8g.4xlarge (16 vCPU, 128 GB) | MO_Standard_E16ds_v6 (16 vCPU, 128 GB) |

> **ARM instances are the default.** Every architecture names an ARM instance first. If you use the x86_64 equivalent instead, verify its performance is similar for your workload.

---

### Detailed Specifications

Each size below shows the values that change with size, copied from each architecture's
`examples/<size>.tfvars` and, on Kubernetes, `examples/<size>.helm-values.yaml`. The guided deploy script
lays the first over `terraform.tfvars.example` and passes the second to `helm-install.sh`. Every
deployment also needs the values the example file marks `CHANGE_ME`, including
`iq_admin_initial_password` and `search_engine`.

#### Size XS: Extra Small (< 500 applications)

Single instance for development, testing, or very small production environments.

**AWS (ECS Fargate, Single Instance):**
```hcl
# infra-aws/examples/xs.tfvars
ecs_cpu              = 2048  # 2 vCPU
ecs_memory           = 16384 # 16 GB
iq_desired_count     = 1
java_opts            = "-Xms10g -Xmx10g -XX:MaxDirectMemorySize=3g -XX:+UseG1GC -XX:+AlwaysPreTouch -Dinsight.threads.monitor=3 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_instance_class    = "db.m8g.large" # 2 vCPU, 8 GB
db_allocated_storage = 64

# One OpenSearch data node, set here because the defaults are the Size M shape
opensearch_instance_type           = "m8g.medium.search"
opensearch_instance_count          = 1
opensearch_volume_size_gb          = 25
opensearch_availability_zone_count = 1
opensearch_index_replicas          = 0

# The IQ Server license, as in terraform.tfvars.example.
iq_license_file = "CHANGE_ME" # path to your IQ Server license file (.lic)
```

**Azure (Container Apps, Single Instance):**
```hcl
# infra-azure/examples/xs.tfvars
container_cpu         = 3.5    # 3.5 vCPU, leaving 0.5 of the node
container_memory      = "14Gi" # 14 GB, leaving 2 GB of the node
workload_profile_type = "D4"   # 4 vCPU, 16 GB per node
java_opts             = "-Xms8g -Xmx8g -XX:MaxDirectMemorySize=2g -XX:+UseG1GC -XX:+AlwaysPreTouch -Dinsight.threads.monitor=3 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_sku_name           = "GP_Standard_D2ds_v6" # 2 vCPU, 8 GB
db_storage_mb         = 65536                 # 64 GB

# OpenSearch cluster built when search_engine = "opensearch"
opensearch_data_node_count    = 1
opensearch_data_instance_type = "Standard_D2pls_v6"
opensearch_data_disk_gb       = 32

# The IQ Server license, as in terraform.tfvars.example.
iq_license_file = "CHANGE_ME" # path to your IQ Server license file (.lic)
```

**GCP (GCE Docker, Single Instance):**
```hcl
# infra-gcp/examples/xs.tfvars
gce_machine_type      = "n4a-highmem-2" # 2 vCPU, 16 GB (ARM)
java_opts             = "-Xms10g -Xmx10g -XX:MaxDirectMemorySize=3g -XX:+UseG1GC -XX:+AlwaysPreTouch -Dinsight.threads.monitor=3 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_instance_tier      = "db-custom-2-7680" # 2 vCPU, 7.5 GB
db_disk_type          = "PD_SSD"           # the db-custom-2-* tiers take PD_SSD, not Hyperdisk
db_disk_size          = 64                 # GB
filestore_capacity_gb = 500
filestore_max_iops    = 4000

# OpenSearch cluster built when search_engine = "opensearch"
opensearch_data_node_count    = 1
opensearch_data_instance_type = "c4a-standard-1"
opensearch_data_disk_gb       = 25

# The IQ Server license, as in terraform.tfvars.example.
iq_license_file = "CHANGE_ME" # path to your IQ Server license file (.lic)
```

---

#### Size S: Small (500 - 2k applications)

Single instance for small production environments.

**AWS (ECS Fargate, Single Instance):**
```hcl
# infra-aws/examples/s.tfvars
ecs_cpu              = 4096  # 4 vCPU
ecs_memory           = 30720 # 30 GB, the maximum at 4 vCPU
iq_desired_count     = 1
java_opts            = "-Xms20g -Xmx20g -XX:MaxDirectMemorySize=4g -XX:+UseG1GC -XX:+AlwaysPreTouch -Dinsight.threads.monitor=5 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_instance_class    = "db.r8g.large" # 2 vCPU, 16 GB
db_allocated_storage = 128

# One OpenSearch data node, set here because the defaults are the Size M shape
opensearch_instance_type           = "m8g.large.search"
opensearch_instance_count          = 1
opensearch_volume_size_gb          = 50
opensearch_availability_zone_count = 1
opensearch_index_replicas          = 0

# The IQ Server license, as in terraform.tfvars.example.
iq_license_file = "CHANGE_ME" # path to your IQ Server license file (.lic)
```

**Azure (Container Apps, Single Instance):**
```hcl
# infra-azure/examples/s.tfvars
container_cpu         = 3.5    # 3.5 vCPU, leaving 0.5 of the node
container_memory      = "30Gi" # 30 GB, leaving 2 GB of the node
workload_profile_type = "E4"   # 4 vCPU, 32 GB per node
java_opts             = "-Xms18g -Xmx18g -XX:MaxDirectMemorySize=4g -XX:+UseG1GC -XX:+AlwaysPreTouch -Dinsight.threads.monitor=5 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_sku_name           = "MO_Standard_E2ds_v6" # 2 vCPU, 16 GB
db_storage_mb         = 131072                # 128 GB

# OpenSearch cluster built when search_engine = "opensearch"
opensearch_data_node_count    = 1
opensearch_data_instance_type = "Standard_D2ps_v6"
opensearch_data_disk_gb       = 64

# The IQ Server license, as in terraform.tfvars.example.
iq_license_file = "CHANGE_ME" # path to your IQ Server license file (.lic)
```

**GCP (GCE Docker, Single Instance):**
```hcl
# infra-gcp/examples/s.tfvars
gce_machine_type      = "n4a-highmem-4" # 4 vCPU, 32 GB (ARM)
java_opts             = "-Xms20g -Xmx20g -XX:MaxDirectMemorySize=4g -XX:+UseG1GC -XX:+AlwaysPreTouch -Dinsight.threads.monitor=5 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_instance_tier      = "db-custom-2-13312" # 2 vCPU, 13 GB
db_disk_type          = "PD_SSD"            # the db-custom-2-* tiers take PD_SSD, not Hyperdisk
db_disk_size          = 128                 # GB
filestore_capacity_gb = 500
filestore_max_iops    = 4000

# OpenSearch cluster built when search_engine = "opensearch"
opensearch_data_node_count    = 1
opensearch_data_instance_type = "c4a-standard-2"
opensearch_data_disk_gb       = 50

# The IQ Server license, as in terraform.tfvars.example.
iq_license_file = "CHANGE_ME" # path to your IQ Server license file (.lic)
```

---

#### Size M: Medium (2k - 10k applications)

Production deployment. HA (2 to 3 nodes) is recommended. A single instance fits only where downtime for upgrades and restarts is acceptable.

**AWS (ECS Fargate, Single Instance):**
```hcl
# infra-aws/examples/m.tfvars
ecs_cpu              = 8192  # 8 vCPU
ecs_memory           = 32768 # 32 GB
iq_desired_count     = 1
java_opts            = "-Xms20g -Xmx20g -XX:MaxDirectMemorySize=4g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/heap-dump.hprof -XX:+ExitOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_instance_class    = "db.r8g.xlarge" # 4 vCPU, 32 GB
db_allocated_storage = 128             # auto-scales to 500 GB

# The M domain: three data nodes across three zones, which needs a third
# private subnet, and a third public one so the load balancer reaches a task in
# that zone. 10.0.30.0/24 is already db_subnet_cidrs[0].
public_subnet_cidrs                = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
private_subnet_cidrs               = ["10.0.10.0/24", "10.0.20.0/24", "10.0.50.0/24"]
opensearch_instance_type           = "m8g.large.search"
opensearch_instance_count          = 3
opensearch_volume_size_gb          = 100
opensearch_availability_zone_count = 3
opensearch_index_replicas          = 1

# The IQ Server license, as in terraform.tfvars.example.
iq_license_file = "CHANGE_ME" # path to your IQ Server license file (.lic)
```

**AWS (ECS Fargate, High Availability):**
```hcl
# infra-aws-ha/examples/m.tfvars
ecs_cpu                = 8192  # 8 vCPU
ecs_memory             = 32768 # 32 GB
ecs_memory_reservation = 24576 # 24 GB soft limit, the 20 GB heap plus 4 GB direct memory
iq_desired_count       = 2     # 2 tasks at start, the minimum
iq_min_count           = 2
iq_max_count           = 3
java_opts              = "-Xms20g -Xmx20g -XX:MaxDirectMemorySize=4g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/heap-dump.hprof -XX:+ExitOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
aurora_instance_class  = "db.r8g.xlarge" # 4 vCPU, 32 GB
aurora_instances       = 2               # Multi-AZ

opensearch_instance_type           = "m8g.large.search"
opensearch_instance_count          = 3
opensearch_volume_size_gb          = 100
opensearch_availability_zone_count = 3
opensearch_index_replicas          = 1

# The IQ Server license, as in terraform.tfvars.example.
iq_license_file = "CHANGE_ME" # path to your IQ Server license file (.lic)
```

**AWS (EKS + Helm):**
```hcl
# infra-aws-ha-k8s-helm/examples/m.tfvars
node_instance_type      = "m8g.2xlarge" # 8 vCPU, 32 GB (ARM)
node_group_desired_size = 2
node_group_min_size     = 2
node_group_max_size     = 3
nexus_iq_replica_count  = 2               # 2 IQ pods at start, the minimum
aurora_instance_class   = "db.r8g.xlarge" # 4 vCPU, 32 GB
aurora_instance_count   = 2

opensearch_instance_type           = "m8g.large.search"
opensearch_instance_count          = 3
opensearch_volume_size_gb          = 100
opensearch_availability_zone_count = 3
opensearch_index_replicas          = 1

# The IQ Server license, as in terraform.tfvars.example.
iq_license_file = "CHANGE_ME" # path to your IQ Server license file (.lic)
```

```yaml
# infra-aws-ha-k8s-helm/examples/m.helm-values.yaml
iq_server:
  resources:
    requests:
      cpu: "6"
      memory: "25Gi"
    limits:
      cpu: "8"
      memory: "26Gi"
  javaOpts: "-Xms17g -Xmx17g -XX:MaxDirectMemorySize=4g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/clm-cluster/heap-dump.hprof -XX:+ExitOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"

hpa:
  minReplicas: 2
  maxReplicas: 3
```

**Azure (Container Apps, Single Instance):**
```hcl
# infra-azure/examples/m.tfvars
container_cpu         = 7.5    # 7.5 vCPU, leaving 0.5 of the node
container_memory      = "30Gi" # 30 GB, leaving 2 GB of the node
workload_profile_type = "D8"   # 8 vCPU, 32 GB per node
java_opts             = "-Xms18g -Xmx18g -XX:MaxDirectMemorySize=4g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/heap-dump.hprof -XX:+ExitOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_sku_name           = "MO_Standard_E4ds_v6" # 4 vCPU, 32 GB
db_storage_mb         = 131072                # 128 GB
file_share_quota      = 500                   # GB

# OpenSearch cluster built when search_engine = "opensearch"
opensearch_data_node_count       = 3
opensearch_data_instance_type    = "Standard_D2ps_v6"
opensearch_manager_instance_type = "Standard_D2pls_v6"
opensearch_data_disk_gb          = 128

# The IQ Server license, as in terraform.tfvars.example.
iq_license_file = "CHANGE_ME" # path to your IQ Server license file (.lic)
```

**Azure (Container Apps, High Availability):**
```hcl
# infra-azure-ha/examples/m.tfvars
container_cpu             = 7.5    # 7.5 vCPU, leaving 0.5 of the node
container_memory          = "30Gi" # 30 GB, leaving 2 GB of the node
workload_profile_type     = "D8"   # 8 vCPU, 32 GB per node
iq_min_replicas           = 2      # 2 replicas at start, the minimum
iq_max_replicas           = 3
java_opts                 = "-Xms20g -Xmx20g -XX:MaxDirectMemorySize=4g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/heap-dump.hprof -XX:+ExitOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_sku_name               = "MO_Standard_E4ds_v6" # 4 vCPU, 32 GB
db_storage_mb             = 131072                # 128 GB, grows automatically
db_high_availability_mode = "ZoneRedundant"
file_share_quota_gb       = 500

# OpenSearch cluster built when search_engine = "opensearch"
opensearch_data_node_count       = 3
opensearch_data_instance_type    = "Standard_D2ps_v6"
opensearch_manager_instance_type = "Standard_D2pls_v6"
opensearch_data_disk_gb          = 128

# The IQ Server license, as in terraform.tfvars.example.
iq_license_file = "CHANGE_ME" # path to your IQ Server license file (.lic)
```

**Azure (AKS + Helm):**
```hcl
# infra-azure-ha-k8s-helm/examples/m.tfvars
node_instance_type        = "Standard_D8ps_v6" # 8 vCPU, 32 GB (ARM)
node_group_min_size       = 2
node_group_max_size       = 3
node_group_desired_size   = 2
nexus_iq_replica_count    = 2                     # 2 IQ pods at start, the minimum
db_sku_name               = "MO_Standard_E4ds_v6" # 4 vCPU, 32 GB
db_storage_mb             = 131072                # 128 GB, grows automatically
db_high_availability_mode = "ZoneRedundant"
storage_share_quota_gb    = 500

# OpenSearch cluster built when search_engine = "opensearch"
opensearch_data_node_count       = 3
opensearch_data_instance_type    = "Standard_D2ps_v6"
opensearch_manager_instance_type = "Standard_D2pls_v6"
opensearch_data_disk_gb          = 128

# The IQ Server license, as in terraform.tfvars.example.
iq_license_file = "CHANGE_ME" # path to your IQ Server license file (.lic)
```

```yaml
# infra-azure-ha-k8s-helm/examples/m.helm-values.yaml
iq_server:
  resources:
    requests:
      cpu: "6"
      memory: "25Gi"
    limits:
      cpu: "8"
      memory: "26Gi"
  javaOpts: "-Xms17g -Xmx17g -XX:MaxDirectMemorySize=4g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/clm-cluster/heap-dump.hprof -XX:+ExitOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"

hpa:
  minReplicas: 2
  maxReplicas: 3
```

**GCP (GCE Docker, Single Instance):**
```hcl
# infra-gcp/examples/m.tfvars
gce_machine_type               = "n4a-standard-8" # 8 vCPU, 32 GB (ARM)
java_opts                      = "-Xms20g -Xmx20g -XX:MaxDirectMemorySize=4g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/heap-dump.hprof -XX:+ExitOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_instance_tier               = "db-custom-N4-4-32768" # 4 vCPU, 32 GB, N4 series (Enterprise)
db_disk_type                   = "HYPERDISK_BALANCED"   # the only storage the N4 tiers take
db_disk_provisioned_iops       = 8000                   # read and write combined
db_disk_provisioned_throughput = 240                    # 252 MB/s, given to the API in MiB/s
db_disk_size                   = 128                    # GB, auto-resize enabled
filestore_capacity_gb          = 500
filestore_max_iops             = 8000

# OpenSearch cluster built when search_engine = "opensearch"
opensearch_data_node_count       = 3
opensearch_data_instance_type    = "c4a-standard-2"
opensearch_manager_instance_type = "c4a-standard-1"
opensearch_data_disk_gb          = 100

# The IQ Server license, as in terraform.tfvars.example.
iq_license_file = "CHANGE_ME" # path to your IQ Server license file (.lic)
```

**GCP (MIG, High Availability):**
```hcl
# infra-gcp-ha/examples/m.tfvars
instance_machine_type          = "n4a-standard-8" # 8 vCPU, 32 GB (ARM)
iq_target_instances            = 2                # 2 instances at start, the minimum
iq_min_instances               = 2
iq_max_instances               = 3
java_opts                      = "-Xms20g -Xmx20g -XX:MaxDirectMemorySize=4g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/heap-dump.hprof -XX:+ExitOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_instance_tier               = "db-custom-N4-4-32768" # 4 vCPU, 32 GB, N4 series (Enterprise)
db_disk_provisioned_iops       = 8000
db_disk_provisioned_throughput = 240 # 252 MB/s, given to the API in MiB/s
db_availability_type           = "REGIONAL"
db_disk_size                   = 128 # GB
db_max_disk_size               = 500
filestore_capacity_gb          = 500
filestore_max_iops             = 8000

# OpenSearch cluster built when search_engine = "opensearch"
opensearch_data_node_count       = 3
opensearch_data_instance_type    = "c4a-standard-2"
opensearch_manager_instance_type = "c4a-standard-1"
opensearch_data_disk_gb          = 100

# The IQ Server license, as in terraform.tfvars.example.
iq_license_file = "CHANGE_ME" # path to your IQ Server license file (.lic)
```

**GCP (GKE + Helm):**
```hcl
# infra-gcp-ha-k8s-helm/examples/m.tfvars
node_instance_type             = "n4a-standard-8" # 8 vCPU, 32 GB (ARM)
node_group_min_size            = 2
node_group_max_size            = 3
node_group_desired_size        = 2
nexus_iq_replica_count         = 2                      # 2 IQ pods at start, the minimum
db_instance_tier               = "db-custom-N4-4-32768" # 4 vCPU, 32 GB, N4 series (Enterprise)
db_disk_provisioned_iops       = 8000
db_disk_provisioned_throughput = 240 # 252 MB/s, given to the API in MiB/s
db_availability_type           = "REGIONAL"
db_disk_size                   = 128 # GB
db_max_disk_size               = 500
filestore_capacity_gb          = 500
filestore_max_iops             = 8000

# OpenSearch cluster built when search_engine = "opensearch"
opensearch_data_node_count       = 3
opensearch_data_instance_type    = "c4a-standard-2"
opensearch_manager_instance_type = "c4a-standard-1"
opensearch_data_disk_gb          = 100

# The IQ Server license, as in terraform.tfvars.example.
iq_license_file = "CHANGE_ME" # path to your IQ Server license file (.lic)
```

```yaml
# infra-gcp-ha-k8s-helm/examples/m.helm-values.yaml
iq_server:
  resources:
    requests:
      cpu: "6"
      memory: "25Gi"
    limits:
      cpu: "8"
      memory: "26Gi"
  javaOpts: "-Xms17g -Xmx17g -XX:MaxDirectMemorySize=4g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/clm-cluster/heap-dump.hprof -XX:+ExitOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"

hpa:
  minReplicas: 2
  maxReplicas: 3
```

---

#### Size L: Large (10k - 30k applications)

High-availability production deployment. Runs 2 to 4 nodes.

**AWS (ECS Fargate, High Availability):**
```hcl
# infra-aws-ha/examples/l.tfvars
ecs_cpu                = 16384 # 16 vCPU
ecs_memory             = 65536 # 64 GB
ecs_memory_reservation = 51200 # 50 GB soft limit, the 42 GB heap plus 8 GB direct memory
iq_desired_count       = 2     # 2 tasks at start, the minimum
iq_min_count           = 2
iq_max_count           = 4
java_opts              = "-Xms42g -Xmx42g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/heap-dump.hprof -XX:+ExitOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
aurora_instance_class  = "db.r8g.2xlarge" # 8 vCPU, 64 GB
aurora_instances       = 2                # Multi-AZ with failover

opensearch_instance_type           = "m8g.xlarge.search"
opensearch_instance_count          = 3
opensearch_volume_size_gb          = 150
opensearch_availability_zone_count = 3
opensearch_index_replicas          = 1

# The IQ Server license, as in terraform.tfvars.example.
iq_license_file = "CHANGE_ME" # path to your IQ Server license file (.lic)
```

**AWS (EKS + Helm):**
```hcl
# infra-aws-ha-k8s-helm/examples/l.tfvars
node_instance_type      = "m8g.4xlarge" # 16 vCPU, 64 GB (ARM)
node_group_desired_size = 2
node_group_min_size     = 2
node_group_max_size     = 4
nexus_iq_replica_count  = 2                # 2 IQ pods at start, the minimum
aurora_instance_class   = "db.r8g.2xlarge" # 8 vCPU, 64 GB
aurora_instance_count   = 2

opensearch_instance_type           = "m8g.xlarge.search"
opensearch_instance_count          = 3
opensearch_volume_size_gb          = 150
opensearch_availability_zone_count = 3
opensearch_index_replicas          = 1

# The IQ Server license, as in terraform.tfvars.example.
iq_license_file = "CHANGE_ME" # path to your IQ Server license file (.lic)
```

```yaml
# infra-aws-ha-k8s-helm/examples/l.helm-values.yaml
iq_server:
  resources:
    requests:
      cpu: "12"
      memory: "49Gi"
    limits:
      cpu: "16"
      memory: "56Gi"
  javaOpts: "-Xms37g -Xmx37g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/clm-cluster/heap-dump.hprof -XX:+ExitOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"

hpa:
  minReplicas: 2
  maxReplicas: 4
```

**Azure (Container Apps, High Availability):**
```hcl
# infra-azure-ha/examples/l.tfvars
container_cpu                    = 15.5   # 15.5 vCPU, leaving 0.5 of the node
container_memory                 = "62Gi" # 62 GB, leaving 2 GB of the node
workload_profile_type            = "D16"  # 16 vCPU, 64 GB per node
iq_min_replicas                  = 2
iq_max_replicas                  = 4
java_opts                        = "-Xms41g -Xmx41g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/heap-dump.hprof -XX:+ExitOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_sku_name                      = "MO_Standard_E8ds_v6" # 8 vCPU, 64 GB
db_storage_mb                    = 262144                # 256 GB, grows automatically
db_storage_tier                  = "P15"
db_high_availability_mode        = "ZoneRedundant"
file_share_quota_gb              = 1536
storage_account_tier             = "Standard"
storage_account_replication_type = "ZRS"

# OpenSearch cluster built when search_engine = "opensearch"
opensearch_data_node_count       = 3
opensearch_data_instance_type    = "Standard_D4ps_v6"
opensearch_manager_instance_type = "Standard_D2pls_v6"
opensearch_data_disk_gb          = 256

# The IQ Server license, as in terraform.tfvars.example.
iq_license_file = "CHANGE_ME" # path to your IQ Server license file (.lic)
```

**Azure (AKS + Helm):**
```hcl
# infra-azure-ha-k8s-helm/examples/l.tfvars
node_instance_type        = "Standard_D16ps_v6" # 16 vCPU, 64 GB (ARM)
node_group_min_size       = 2
node_group_max_size       = 4
node_group_desired_size   = 2
nexus_iq_replica_count    = 2                     # 2 IQ pods at start, the minimum
db_sku_name               = "MO_Standard_E8ds_v6" # 8 vCPU, 64 GB
db_storage_mb             = 262144                # 256 GB, grows automatically
db_storage_tier           = "P15"
db_high_availability_mode = "ZoneRedundant"
storage_share_quota_gb    = 1536

# OpenSearch cluster built when search_engine = "opensearch"
opensearch_data_node_count       = 3
opensearch_data_instance_type    = "Standard_D4ps_v6"
opensearch_manager_instance_type = "Standard_D2pls_v6"
opensearch_data_disk_gb          = 256

# The IQ Server license, as in terraform.tfvars.example.
iq_license_file = "CHANGE_ME" # path to your IQ Server license file (.lic)
```

```yaml
# infra-azure-ha-k8s-helm/examples/l.helm-values.yaml
iq_server:
  resources:
    requests:
      cpu: "12"
      memory: "49Gi"
    limits:
      cpu: "16"
      memory: "56Gi"
  javaOpts: "-Xms37g -Xmx37g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/clm-cluster/heap-dump.hprof -XX:+ExitOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"

hpa:
  minReplicas: 2
  maxReplicas: 4
```

**GCP (MIG, High Availability):**
```hcl
# infra-gcp-ha/examples/l.tfvars
instance_machine_type          = "n4a-standard-16" # 16 vCPU, 64 GB (ARM)
iq_target_instances            = 2                 # 2 instances at start, the minimum
iq_min_instances               = 2
iq_max_instances               = 4
java_opts                      = "-Xms42g -Xmx42g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/heap-dump.hprof -XX:+ExitOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_instance_tier               = "db-custom-N4-8-65536" # 8 vCPU, 64 GB, N4 series (Enterprise)
db_disk_provisioned_iops       = 8000
db_disk_provisioned_throughput = 340 # 357 MB/s, given to the API in MiB/s
db_availability_type           = "REGIONAL"
db_disk_size                   = 256 # GB
db_max_disk_size               = 1000
filestore_capacity_gb          = 1536
filestore_max_iops             = 16000

# OpenSearch cluster built when search_engine = "opensearch"
opensearch_data_node_count       = 3
opensearch_data_instance_type    = "c4a-standard-4"
opensearch_manager_instance_type = "c4a-standard-1"
opensearch_data_disk_gb          = 150

# The IQ Server license, as in terraform.tfvars.example.
iq_license_file = "CHANGE_ME" # path to your IQ Server license file (.lic)
```

**GCP (GKE + Helm):**
```hcl
# infra-gcp-ha-k8s-helm/examples/l.tfvars
node_instance_type             = "n4a-standard-16" # 16 vCPU, 64 GB (ARM)
node_group_min_size            = 2
node_group_max_size            = 4
node_group_desired_size        = 2
nexus_iq_replica_count         = 2                      # 2 IQ pods at start, the minimum
db_instance_tier               = "db-custom-N4-8-65536" # 8 vCPU, 64 GB, N4 series (Enterprise)
db_disk_provisioned_iops       = 8000
db_disk_provisioned_throughput = 340 # 357 MB/s, given to the API in MiB/s
db_availability_type           = "REGIONAL"
db_disk_size                   = 256 # GB
db_max_disk_size               = 1000
filestore_capacity_gb          = 1536
filestore_max_iops             = 16000

# OpenSearch cluster built when search_engine = "opensearch"
opensearch_data_node_count       = 3
opensearch_data_instance_type    = "c4a-standard-4"
opensearch_manager_instance_type = "c4a-standard-1"
opensearch_data_disk_gb          = 150

# The IQ Server license, as in terraform.tfvars.example.
iq_license_file = "CHANGE_ME" # path to your IQ Server license file (.lic)
```

```yaml
# infra-gcp-ha-k8s-helm/examples/l.helm-values.yaml
iq_server:
  resources:
    requests:
      cpu: "12"
      memory: "49Gi"
    limits:
      cpu: "16"
      memory: "56Gi"
  javaOpts: "-Xms37g -Xmx37g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/clm-cluster/heap-dump.hprof -XX:+ExitOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"

hpa:
  minReplicas: 2
  maxReplicas: 4
```

---

#### Size XL: Extra Large (30k - 100k applications)

Enterprise-scale HA deployment. Runs 3 to 5 nodes with larger instances.

**AWS (ECS Fargate, High Availability):**
```hcl
# infra-aws-ha/examples/xl.tfvars
ecs_cpu                = 16384  # 16 vCPU
ecs_memory             = 122880 # 120 GB, the maximum at 16 vCPU
ecs_memory_reservation = 90112  # 88 GB soft limit, the 80 GB heap plus 8 GB direct memory
iq_desired_count       = 3      # 3 tasks at start, the minimum
iq_min_count           = 3
iq_max_count           = 5
java_opts              = "-Xms80g -Xmx80g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/heap-dump.hprof -XX:+ExitOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
aurora_instance_class  = "db.r8g.4xlarge" # 16 vCPU, 128 GB
aurora_instances       = 2                # Multi-AZ with automatic failover

opensearch_instance_type           = "r8g.2xlarge.search"
opensearch_instance_count          = 3
opensearch_volume_size_gb          = 250
opensearch_availability_zone_count = 3
opensearch_dedicated_master_type   = "m8g.large.search"
opensearch_index_replicas          = 1

# The IQ Server license, as in terraform.tfvars.example.
iq_license_file = "CHANGE_ME" # path to your IQ Server license file (.lic)
```

**AWS (EKS + Helm):**
```hcl
# infra-aws-ha-k8s-helm/examples/xl.tfvars
node_instance_type      = "r9g.4xlarge" # 16 vCPU, 128 GB (ARM)
node_group_desired_size = 3
node_group_min_size     = 3
node_group_max_size     = 5
nexus_iq_replica_count  = 3                # 3 IQ pods at start, the minimum
aurora_instance_class   = "db.r8g.4xlarge" # 16 vCPU, 128 GB
aurora_instance_count   = 2

opensearch_instance_type           = "r8g.2xlarge.search"
opensearch_instance_count          = 3
opensearch_volume_size_gb          = 250
opensearch_availability_zone_count = 3
opensearch_dedicated_master_type   = "m8g.large.search"
opensearch_index_replicas          = 1

# The IQ Server license, as in terraform.tfvars.example.
iq_license_file = "CHANGE_ME" # path to your IQ Server license file (.lic)
```

```yaml
# infra-aws-ha-k8s-helm/examples/xl.helm-values.yaml
iq_server:
  resources:
    requests:
      cpu: "12"
      memory: "86Gi"
    limits:
      cpu: "16"
      memory: "112Gi"
  javaOpts: "-Xms74g -Xmx74g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/clm-cluster/heap-dump.hprof -XX:+ExitOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"

hpa:
  minReplicas: 3
  maxReplicas: 5
```

**Azure (Container Apps, High Availability):**
```hcl
# infra-azure-ha/examples/xl.tfvars
container_cpu                    = 15.5    # 15.5 vCPU, leaving 0.5 of the node
container_memory                 = "126Gi" # 126 GB, leaving 2 GB of the node
workload_profile_type            = "E16"   # 16 vCPU, 128 GB per node
iq_min_replicas                  = 3
iq_max_replicas                  = 5
java_opts                        = "-Xms80g -Xmx80g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/heap-dump.hprof -XX:+ExitOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_sku_name                      = "MO_Standard_E16ds_v6" # 16 vCPU, 128 GB
db_storage_mb                    = 524288                 # 512 GB, grows automatically
db_storage_tier                  = "P20"
db_high_availability_mode        = "ZoneRedundant"
file_share_quota_gb              = 4096
storage_account_tier             = "Premium"
storage_account_replication_type = "ZRS"

# OpenSearch cluster built when search_engine = "opensearch"
opensearch_data_node_count       = 3
opensearch_data_instance_type    = "Standard_E8ps_v6"
opensearch_manager_instance_type = "Standard_D2ps_v6"
opensearch_data_disk_gb          = 256

# The IQ Server license, as in terraform.tfvars.example.
iq_license_file = "CHANGE_ME" # path to your IQ Server license file (.lic)
```

**Azure (AKS + Helm):**
```hcl
# infra-azure-ha-k8s-helm/examples/xl.tfvars
node_instance_type               = "Standard_E16ps_v6" # 16 vCPU, 128 GB (ARM)
node_group_min_size              = 3
node_group_max_size              = 5
node_group_desired_size          = 3
nexus_iq_replica_count           = 3                      # 3 IQ pods at start, the minimum
db_sku_name                      = "MO_Standard_E16ds_v6" # 16 vCPU, 128 GB
db_storage_mb                    = 524288                 # 512 GB, grows automatically
db_storage_tier                  = "P20"
db_high_availability_mode        = "ZoneRedundant"
storage_account_tier             = "Premium" # Required for NFS with AKS
storage_share_quota_gb           = 4096
storage_account_replication_type = "ZRS"

# OpenSearch cluster built when search_engine = "opensearch"
opensearch_data_node_count       = 3
opensearch_data_instance_type    = "Standard_E8ps_v6"
opensearch_manager_instance_type = "Standard_D2ps_v6"
opensearch_data_disk_gb          = 256

# The IQ Server license, as in terraform.tfvars.example.
iq_license_file = "CHANGE_ME" # path to your IQ Server license file (.lic)
```

```yaml
# infra-azure-ha-k8s-helm/examples/xl.helm-values.yaml
iq_server:
  resources:
    requests:
      cpu: "12"
      memory: "85Gi"
    limits:
      cpu: "16"
      memory: "110Gi"
  javaOpts: "-Xms73g -Xmx73g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/clm-cluster/heap-dump.hprof -XX:+ExitOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"

hpa:
  minReplicas: 3
  maxReplicas: 5
```

**GCP (MIG, High Availability):**
```hcl
# infra-gcp-ha/examples/xl.tfvars
instance_machine_type          = "n4a-highmem-16" # 16 vCPU, 128 GB (ARM)
iq_target_instances            = 3                # 3 instances at start, the minimum
iq_min_instances               = 3
iq_max_instances               = 5
java_opts                      = "-Xms85g -Xmx85g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/heap-dump.hprof -XX:+ExitOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_instance_tier               = "db-custom-N4-16-131072" # 16 vCPU, 128 GB, N4 series (Enterprise)
db_disk_provisioned_iops       = 10000
db_disk_provisioned_throughput = 425 # 446 MB/s, given to the API in MiB/s
db_availability_type           = "REGIONAL"
db_disk_size                   = 512 # GB
db_max_disk_size               = 2000
filestore_capacity_gb          = 4096
filestore_max_iops             = 24000

# OpenSearch cluster built when search_engine = "opensearch"
opensearch_data_node_count       = 3
opensearch_data_instance_type    = "c4a-highmem-8"
opensearch_manager_instance_type = "c4a-standard-2"
opensearch_data_disk_gb          = 250

# The IQ Server license, as in terraform.tfvars.example.
iq_license_file = "CHANGE_ME" # path to your IQ Server license file (.lic)
```

**GCP (GKE + Helm):**
```hcl
# infra-gcp-ha-k8s-helm/examples/xl.tfvars
node_instance_type             = "n4a-highmem-16" # 16 vCPU, 128 GB (ARM)
node_group_min_size            = 3
node_group_max_size            = 5
node_group_desired_size        = 3
nexus_iq_replica_count         = 3                        # 3 IQ pods at start, the minimum
db_instance_tier               = "db-custom-N4-16-131072" # 16 vCPU, 128 GB, N4 series (Enterprise)
db_disk_provisioned_iops       = 10000
db_disk_provisioned_throughput = 425 # 446 MB/s, given to the API in MiB/s
db_availability_type           = "REGIONAL"
db_disk_size                   = 512 # GB
db_max_disk_size               = 2000
filestore_capacity_gb          = 4096
filestore_max_iops             = 24000

# OpenSearch cluster built when search_engine = "opensearch"
opensearch_data_node_count       = 3
opensearch_data_instance_type    = "c4a-highmem-8"
opensearch_manager_instance_type = "c4a-standard-2"
opensearch_data_disk_gb          = 250

# The IQ Server license, as in terraform.tfvars.example.
iq_license_file = "CHANGE_ME" # path to your IQ Server license file (.lic)
```

```yaml
# infra-gcp-ha-k8s-helm/examples/xl.helm-values.yaml
iq_server:
  resources:
    requests:
      cpu: "12"
      memory: "85Gi"
    limits:
      cpu: "16"
      memory: "110Gi"
  javaOpts: "-Xms73g -Xmx73g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/clm-cluster/heap-dump.hprof -XX:+ExitOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"

hpa:
  minReplicas: 3
  maxReplicas: 5
```

---

### Kubernetes and the Helm Chart

The three Kubernetes architectures install IQ Server with Sonatype's `nexus-iq-server-ha` chart. Its
source and README are in [the chart repository](https://github.com/sonatype/nexus-iq-server-ha/tree/main/chart),
and it is published on [Artifact Hub](https://artifacthub.io/packages/helm/sonatype/nexus-iq-server-ha).

- **The chart version is pinned** by the default of `helm_chart_version` in `variables.tf`.
- **The IQ Server image comes from that chart**, since `helm-values.yaml` sets no tag, so the chart and the IQ Server it runs always match.
- **The initial admin password** comes from a Kubernetes secret that `helm-install.sh` creates from `iq_admin_initial_password`, named in `iq_server.initialAdminPasswordSecret`.
- **On AKS and GKE, OpenSearch runs on its own node pools**, one for data nodes and one for cluster managers, managed by the [OpenSearch Kubernetes Operator](https://github.com/opensearch-project/opensearch-k8s-operator). The pools are tainted so only OpenSearch runs there, and IQ Server reaches OpenSearch through a Service that selects only the data nodes.

### Logging

IQ Server writes its server, request, audit and policy violation logs to standard output, and each
platform's own log service collects them:

| Platform | Where the logs go |
|---|---|
| ECS Fargate (`infra-aws`, `infra-aws-ha`) | CloudWatch Logs, through a Fluent Bit sidecar, and log files on EFS |
| EKS (`infra-aws-ha-k8s-helm`) | CloudWatch Logs, through the Amazon CloudWatch Observability add-on |
| Container Apps (`infra-azure`, `infra-azure-ha`) | Azure Monitor Log Analytics, and log files on an Azure Files share |
| AKS (`infra-azure-ha-k8s-helm`) | Azure Monitor Container insights |
| Compute Engine (`infra-gcp`, `infra-gcp-ha`) | Cloud Logging, through the Google Cloud Ops Agent, and log files on the Filestore share |
| GKE (`infra-gcp-ha-k8s-helm`) | Cloud Logging |

Each architecture also writes the log files, `clm-server.log`, `request.log` and `audit.log`, to shared
storage, in a place that depends on how many nodes it runs:

| Architecture | Log files, as IQ Server sees the path |
|---|---|
| `infra-aws`, `infra-azure`, `infra-gcp` | `/var/log/nexus-iq-server/`, on EFS, the `nexus-iq-logs` Azure Files share, or the Filestore share's `logs` directory |
| `infra-aws-ha`, `infra-azure-ha` | `/var/log/nexus-iq-server/<node>/`, one directory per node, on EFS or the `iq-logs-ha` share |
| `infra-gcp-ha` | `/sonatype-work/clm-server-<node>/logs/` on Filestore |
| The three Kubernetes architectures | `/sonatype-work/clm-cluster/log/`, each file named after its pod |

**Audit events go to the database by default.** IQ Server writes them to its `audit_event` table rather
than to the audit log. To write them to the audit log and standard output as well, turn off the
`audit-log-destination-database` feature once, as an administrator:

```bash
curl -u admin -X DELETE https://<your IQ Server URL>/api/v2/config/features/audit-log-destination-database
```

`POST` to the same address turns it back on.

---

### JVM Configuration

**The Java heap is at most two thirds of the memory IQ Server gets**, rounded down to a whole GB, on
every platform and at every size, following IQ Server's guidance to leave at least a third of memory
free ([Estimating Heap Sizes](https://help.sonatype.com/en/estimating-heap-sizes.html)). Direct memory
and the JVM's own memory come out of that free third.

```
-Xms<HEAP>g -Xmx<HEAP>g
-XX:MaxDirectMemorySize=<DIRECT>g
-XX:+UseG1GC
-XX:+AlwaysPreTouch
-XX:+HeapDumpOnOutOfMemoryError
-XX:HeapDumpPath=/sonatype-work/heap-dump.hprof
-XX:+ExitOnOutOfMemoryError
```

The first out-of-memory error writes a heap dump to that file and the JVM exits; a later one skips the dump while the file exists, so delete it to allow another. The Kubernetes architectures name `/sonatype-work/clm-cluster/heap-dump.hprof`, because only that directory is on the shared storage in a pod. XS and S leave out the last three flags, so there IQ Server writes no heap dump and keeps running after an out-of-memory error.

Every figure below is in GB. Each cell is memory for IQ Server, then heap, then direct memory.

| Platform | XS | S | M | L | XL | Why the memory differs from the whole node |
|---|:---:|:---:|:---:|:---:|:---:|---|
| Compute Engine (`infra-gcp`, `infra-gcp-ha`) | 16 / 10 / 3 | 32 / 20 / 4 | 32 / 20 / 4 | 64 / 42 / 8 | 128 / 85 / 8 | It does not: IQ Server has the whole VM |
| Fargate (`infra-aws`, `infra-aws-ha`) | 16 / 10 / 3 | 30 / 20 / 4 | 32 / 20 / 4 | 64 / 42 / 8 | 120 / 80 / 8 | A task must be a CPU and memory pair Fargate allows: at most 30 GB at 4 vCPU, 60 at 8 and 120 at 16 ([task CPU and memory](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/fargate-tasks-services.html)) |
| Container Apps, `infra-azure` | 14 / 8 / 2 | 30 / 18 / 4 | 30 / 18 / 4 | - | - | Container Apps keeps part of every node for itself, so at every size the replica leaves 0.5 vCPU and 2 GB of its node |
| Container Apps, `infra-azure-ha` | - | - | 30 / 20 / 4 | 62 / 41 / 8 | 126 / 80 / 8 | As above |
| Kubernetes pods (EKS, AKS, GKE) | - | - | 26 / 17 / 4 | 56 / 37 / 8 | 112 / 74 / 8 on EKS, 110 / 73 / 8 on AKS and GKE | Kubernetes keeps part of every node for itself, and each cloud keeps a different share, so the pod memory limit is below the node |

**Some heaps are below the rule's value.** Two thirds of 32 GB is 21 GB, and the heap is 20 GB on the 32 GB
hosts (Compute Engine at S and M, Fargate at M), so heap plus 4 GB direct memory leaves 8 GB. On `infra-azure`,
two thirds of 14 GB is 9 GB and of 30 GB is 20 GB, and the heap stays at 8 GB at XS and 18 GB at S and M, so
the smaller replicas keep room for direct memory and the JVM's own memory. On `infra-azure-ha` at XL, two
thirds of 126 GB is 84 GB, and the heap is 80 GB, the same as on Fargate at XL.

**Direct memory is 4 GB at S and M on every platform**, 8 GB at L and XL, and 3 GB at XS (2 GB on Container Apps).

Two settings move with the heap: on `infra-aws-ha`, `ecs_memory_reservation` is the heap plus direct
memory (24 GB at M, 50 GB at L, 88 GB at XL), and on Kubernetes the pod's memory request is the heap
plus direct memory plus 4 GB for the JVM's own memory (25 GB at M, 49 GB at L, 86 GB on EKS and 85 GB on AKS
and GKE at XL).

---

### OpenSearch

This section applies with `search_engine = "opensearch"`, which is available at every size and is the
backend for estates above 10,000 applications. One cluster serves both of IQ Server's search features:
Advanced Search and the Nexus One index behind the Nexus One list pages, typeahead, and dashboard. With
`"builtin"`, no cluster is created and Nexus One keeps its index in IQ Server's PostgreSQL database: see
[Choosing the search backend](#choosing-the-search-backend).

IQ Server keeps seven indices in that one shared cluster: the Advanced Search index, behind the
`iq-index` alias, and six Nexus One indices, one each for applications, violations, waivers, components,
vulnerabilities and the shared entity data, named `iq-index-nexus-one-<generation>-<type>`.

**Terraform creates the cluster on every cloud**, at the shape in the [Per-size cluster specification](#per-size-cluster-specification):

- **AWS** (`infra-aws`, `infra-aws-ha`, `infra-aws-ha-k8s-helm`): an Amazon OpenSearch Service domain
  running OpenSearch 3.7. IQ Server authenticates with SigV4 through its task or pod role, so there is
  no password.
- **Azure and GCP VMs** (`infra-azure`, `infra-azure-ha`, `infra-gcp`, `infra-gcp-ha`): OpenSearch 3.7 on
  that cloud's virtual machines, with the security plugin on and TLS between IQ Server and the cluster.
  With three data nodes, Terraform also creates an internal load balancer in front of them, a Standard SKU
  internal load balancer on Azure and an internal passthrough Network Load Balancer on GCP, and points IQ
  Server at its address. With one data node, IQ Server connects to that node directly.
- **AKS and GKE** (`infra-azure-ha-k8s-helm`, `infra-gcp-ha-k8s-helm`): OpenSearch 3.7 on dedicated node
  pools, run by the OpenSearch Kubernetes Operator, with TLS, and reached through a Service that selects
  only the data nodes.

On Azure and GCP, Terraform generates the certificate authority, the certificates and the passwords, and
creates an `iq-server` user for IQ Server. You own upgrades, snapshots, and node replacement on these
clusters.

**To bring your own cluster instead**, set `opensearch_endpoint` on Azure and GCP, which leaves
`opensearch_create` false unless you set it, or `opensearch_domain_endpoint` on AWS, and give the
endpoint and credentials in the variables each
architecture's README names. Point the endpoint at an address that reaches every data node, and set
`opensearch_data_node_count` (Azure and GCP) or `opensearch_instance_count` (AWS) to your cluster's data
node count, since the deploy sets the shard counts from it.

#### Choosing the search backend

`search_engine` has no default. Set it in `terraform.tfvars`, or answer the guided script's question:

| Value | Nexus One index | Advanced Search | Sizes |
|---|---|---|---|
| `opensearch` | An OpenSearch cluster. Terraform creates it, unless you name one you already run | The same OpenSearch cluster | Every size, XS to XL |
| `builtin` | IQ Server's PostgreSQL database, the one every architecture already creates. No OpenSearch cluster is created | IQ Server's built-in index | Up to 10,000 applications: XS, S and M |

A plan stops if `search_engine` still reads `CHANGE_ME`, or holds anything else.

IQ Server offers PostgreSQL for the Nexus One index on estates of up to 10,000 applications and refuses it
above that. It offers OpenSearch for the Nexus One index only when `config.yml` carries a
`nexusOne.connection` block, which `builtin` leaves out, so with `builtin` there is nothing to choose
instead, and L and XL need `opensearch`. Choose `opensearch` for an estate you expect to grow past 10,000
applications, too, since IQ Server keeps the first backend chosen.

With `opensearch`, the deploy also tells IQ Server, once, to use OpenSearch for the Nexus One index, on
IQ Server versions that ask for that choice. IQ Server keeps that choice, and making it needs a license,
which IQ Server installs from `iq_license_file` on its first start. With `builtin`, the deploy makes no
choice for Nexus One: choose PostgreSQL on the Nexus One setup page, and IQ Server keeps that choice too.

#### What IQ Server's configuration carries

IQ Server's `config.yml` carries a `search:` block and a `nexusOne.connection` block, both naming the
same cluster. Terraform writes them in one of two forms, depending on the cloud.

**Amazon OpenSearch Service**, on the three AWS architectures:

```yaml
search:
  type: aws
  mode: OPENSEARCH
  domain: https://CHANGE_ME-search-domain.CHANGE_ME.es.amazonaws.com
  region: CHANGE_ME
  nexusOneIndexReplicas: 1   # 0 at XS and S, see "Replicas" below
nexusOne:
  connection:
    type: aws
    mode: OPENSEARCH
    domain: https://CHANGE_ME-search-domain.CHANGE_ME.es.amazonaws.com
    region: CHANGE_ME
    nexusOneIndexReplicas: 1   # 0 at XS and S, see "Replicas" below
```

**Self-managed OpenSearch**, on the three Azure and three GCP architectures, where the `uri` is the
load balancer, the data node Service, or the single data node:

```yaml
search:
  type: http
  mode: OPENSEARCH
  uri: https://CHANGE_ME-opensearch-host:9200
  username: 'CHANGE_ME'
  password: 'CHANGE_ME'
nexusOne:
  connection:
    type: http
    mode: OPENSEARCH
    uri: https://CHANGE_ME-opensearch-host:9200
    username: 'CHANGE_ME'
    password: 'CHANGE_ME'
    nexusOneIndexReplicas: 1   # 0 at XS and S, see "Replicas" below
```

#### Trusting a private certificate authority

A cluster Terraform creates on Azure or GCP has its certificate authority added to IQ Server's trust
store by the deploy. A cluster you bring whose certificate is signed by a private certificate authority
needs that authority added to a copy of IQ Server's JVM trust store:

| Architecture | How to trust a private certificate authority |
|---|---|
| `infra-azure` | Set `opensearch_ca_pem` to the authority's certificate, base64 encoded, see [TLS, and the JVM trust store](infra-azure/README.md#tls-and-the-jvm-trust-store) |
| `infra-azure-ha` | Set `opensearch_ca_pem` to the authority's certificate, base64 encoded, see [TLS, and the JVM trust store](infra-azure-ha/README.md#tls-and-the-jvm-trust-store) |
| `infra-azure-ha-k8s-helm` | Build a derived image with the authority in a copy of the trust store, see [TLS, and the JVM trust store](infra-azure-ha-k8s-helm/README.md#tls-and-the-jvm-trust-store) |
| `infra-gcp` | Set `opensearch_ca_certificate` to the authority's certificate as PEM text, see [Trusting a private certificate authority](infra-gcp/README.md#trusting-a-private-certificate-authority) |
| `infra-gcp-ha` | Set `opensearch_ca_certificate` to the authority's certificate as PEM text, see [Trusting a private certificate authority](infra-gcp-ha/README.md#trusting-a-private-certificate-authority) |
| `infra-gcp-ha-k8s-helm` | Set `opensearch_ca_certificate` to the authority's certificate as PEM text, see [Trusting a private certificate authority](infra-gcp-ha-k8s-helm/README.md#trusting-a-private-certificate-authority) |

#### Shards: set by the deploy from the data node count

The deploy sets the primary shard count for the component, violation and vulnerability indices once IQ
Server is healthy and before the first index build: 1 at XS and S, and the number of OpenSearch data
nodes, 3, at M, L and XL. Every other index has 1. A shard count applies only when an index is created.

#### Replicas: each architecture sets the count

A replica is a full second copy of every shard. It is what makes losing a data node survivable, and it
takes the disk and the indexing work of that second copy.

**Each architecture sets the Nexus One replica count from `opensearch_index_replicas`:**

| Size | OpenSearch data nodes | Replica count |
|------|:---------------------:|:-------------:|
| **XS** | 1 | `0` |
| **S** | 1 | `0` |
| **M** | 3 | `1` |
| **L** | 3 | `1` |
| **XL** | 3 | `1` |

**`0` on a single-node tier is deliberate.** One data node has nowhere to place a replica, so asking
for one leaves the index yellow for good. A yellow index still takes writes and returns correct reads.
**Losing that node means rebuilding the index.**

A replica can be added to a live index with `PUT <index>/_settings`, so a first choice is not binding.

#### The Advanced Search index takes the cluster's defaults

The Advanced Search index gets the cluster's default shard and replica counts, or those of an index
template whose pattern matches its name. On a single data node cluster Terraform creates on Azure or
GCP, the node's setup sets the cluster's default replica count to 0, so the index is created green.
Amazon OpenSearch Service does not accept that cluster setting; if an index on a single-node AWS domain
shows a replica it cannot place, apply an index template with `number_of_replicas: 0` matching its name.
Read the result off the live index with `GET <index>/_settings`.

#### Plan for twice the index during a rebuild

**Plan free disk for twice the Nexus One index, because a rebuild needs room for a second copy.** A
cluster that fits the index with 40% free is full during its own rebuild. A replica is a separate
doubling and applies at the same time. The storage per node in the specification below already allows
for it.

- **A rebuild is not a backup.** Rebuilding a lost index leaves search unavailable until it finishes. A managed AWS domain takes its own snapshots; a
  self-managed cluster takes whatever snapshots are scheduled for it.

#### Per-size cluster specification

Every cloud's data node has the same memory at each size, and the same vCPU everywhere except Azure at
XS, where `Standard_D2pls_v6`, the smallest Dplsv6 size, has 2 vCPU against 1. Each architecture's
`examples/<size>.tfvars` sets these values.

| Size | Data nodes | AWS | Azure | GCP | Storage per node ³ | Shards ¹ | Replicas |
|------|:----------:|:---:|:-----:|:---:|:----------------:|:--------:|:--------:|
| **XS** | 1 | `m8g.medium.search` | `Standard_D2pls_v6` | `c4a-standard-1` | 25 GB | 1 | `0` |
| **S** | 1 | `m8g.large.search` | `Standard_D2ps_v6` | `c4a-standard-2` | 50 GB | 1 | `0` |
| **M** | 3 ² | `m8g.large.search` | `Standard_D2ps_v6` | `c4a-standard-2` | 100 GB | 3 | `1` |
| **L** | 3 ² | `m8g.xlarge.search` | `Standard_D4ps_v6` | `c4a-standard-4` | 150 GB | 3 | `1` |
| **XL** | 3 ² | `r8g.2xlarge.search` | `Standard_E8ps_v6` | `c4a-highmem-8` | 250 GB | 3 | `1` |

¹ Primary shards for the component, violation and vulnerability indices, set by the deploy from the
data node count. Every other index has 1.

² One in each of three zones.

³ The volume to provision per node, covering a rebuild's second copy of the Nexus One indices. On Azure
the data disk is the smallest Premium SSD tier at or above it: 32, 64, 128, 256 and 256 GB.

The XL data node is 8 vCPU and 64 GB on every cloud.

**Moving between one and three data nodes on the Azure and GCP virtual machines builds a new cluster.**
Terraform replaces every data node and its disk, so the new cluster starts with no indices. Once the
apply and `iq-post-deploy.sh` finish, start a Nexus One index build in the Index Manager, as on a first
deploy.

Three dedicated cluster managers run at every size with more than one data node, one per zone, and
none at XS and S, where the one data node is its own cluster manager:

| Size | AWS | Azure | GCP |
|------|:---:|:-----:|:---:|
| **XS**, **S** | none | none | none |
| **M** | 3 x `m8g.medium.search` | 3 x `Standard_D2pls_v6`, 2 vCPU, 4 GB | 3 x `c4a-standard-1`, 1 vCPU, 4 GB |
| **L** | 3 x `m8g.medium.search` | 3 x `Standard_D2pls_v6`, 2 vCPU, 4 GB | 3 x `c4a-standard-1`, 1 vCPU, 4 GB |
| **XL** | 3 x `m8g.large.search` | 3 x `Standard_D2ps_v6`, 2 vCPU, 8 GB | 3 x `c4a-standard-2`, 2 vCPU, 8 GB |

On the Azure and GCP virtual machines, each node takes half its RAM as heap, up to 31 GB. On AKS and GKE
the node sizes are the same, and each OpenSearch pod gets what its node has left after the platform's
own reservations and daemon pods, so the heap is smaller where the node is small:

| Size | AKS data heap | AKS manager heap | GKE data heap | GKE manager heap |
|------|:-------------:|:----------------:|:-------------:|:----------------:|
| **M** | 4 GB | 0.9 GB | 3.6 GB | 1.1 GB |
| **L** | 8 GB | 0.9 GB | 8 GB | 1.1 GB |
| **XL** | 31 GB | 4 GB | 31 GB | 3.6 GB |

Each pod also leaves at least 640 MB outside the heap for OpenSearch's own memory. The pod sizes are in
[`infra-azure-ha-k8s-helm`](./infra-azure-ha-k8s-helm/README.md) and
[`infra-gcp-ha-k8s-helm`](./infra-gcp-ha-k8s-helm/README.md), and each deployment's
`opensearch_pod_sizing` output shows what it got.

#### Checking it worked

| Question | How to check |
|----------|--------------|
| Is search on OpenSearch? | `config.yml` carries both blocks, and `GET _cat/indices` lists the Advanced Search index and, after the first build, the Nexus One indices |
| Did the indices get the replica count you set? | `GET <index>/_settings` on the cluster, and read `number_of_replicas` |
| Did they get the shard count the deploy set? | The same read, for `number_of_shards`, or `GET /api/v2/config?property=nexusOneIndexComponentShards` on IQ Server |
| What did the Advanced Search index get? | The same read on it |
| Is the index healthy? | The Index Manager's Analyze view. Its `HEALTHY` and `WARNING` are about how far behind the index is, not how the cluster placed its shards |

**Read the shard count and the replica count off the live index, never off the configuration.** Both are
applied only when an index is created, and both can differ from what was asked for.

---

### Scaling Guidance

#### CPU Usage Guidelines

| CPU Usage (Aggregate) | Recommendation |
|----------------------|----------------|
| Below 40% | Room to spare; consider a smaller size |
| 40% - 70% (Target) | Optimal range with headroom for peaks |
| Above 70% | Scale required: add nodes or move to the next size |

---
## Customization Options

### Deployment Pattern Selection

| | Single Instance | High Availability | Kubernetes |
|---|:---:|:---:|:---:|
| **Auto-scaling** | No | Yes | Yes |
| **Zero-downtime updates** | No | Yes | Yes |
| **Multi-zone redundancy** | No | Yes | Yes |
| **K8s expertise required** | No | No | Yes |
| **HA license required** | No | Yes | Yes |
| **Best for sizes** | XS, S | M, L, XL | M, L, XL |

### Networking

All architectures create their own VPC/VNet with:
- Public subnets (load balancer; infra-azure has none)
- Private subnets (compute and OpenSearch)
- Database subnets (isolated)
- NAT Gateway / Cloud NAT for outbound access

### Security

- **Secrets**: AWS Secrets Manager / Azure Key Vault / GCP Secret Manager, holding the database, OpenSearch and initial admin passwords
- **Encryption**: All databases and storage encrypted at rest
- **Network**: Security groups restrict access; compute and OpenSearch run in private subnets
- **Identity**: IAM roles (AWS), Managed Identity (Azure), Workload Identity (GCP)
- **State**: `terraform.tfvars` and the Terraform state hold the passwords, so keep both private
- **Plain HTTP**: `infra-aws` and the `infra-azure-ha` Application Gateway serve IQ Server over plain HTTP until you put TLS in front, so `iq-post-deploy.sh` warns before it sends the admin password there. On `infra-azure-ha`, run it with `IQ_URL` set to the `container_app_url` output, which is `https://`

### Development vs Production

| Setting | Development | Production |
|---------|:-----------:|:----------:|
| `deletion_protection` | `false` | `true` |
| `skip_final_snapshot` | `true` | `false` |
| Multi-AZ database | Optional | Required |
| SSL/TLS | Optional | Required |
| Backup retention | 1 day | 7-35 days |

---

## Accessing IQ Server

### Web Interface

After deployment completes:
1. Wait 5-15 minutes for application initialization
2. Access the URL from `terraform output`
3. Log in as `admin`, with the password you set in `iq_admin_initial_password`

IQ Server takes `iq_admin_initial_password` on its first start only. Changing the variable later does not
change the admin password; change it in IQ Server instead.

### DNS Configuration (Custom Domain)

For custom domain access:

1. Create a DNS CNAME record pointing to the load balancer hostname
2. Configure an SSL certificate for your domain
3. Update the deployment's SSL/TLS variables and redeploy

### Health Check

The load balancer performs health checks on `/ping`. If the application shows unhealthy:
- Check container/instance logs for startup errors
- Verify database connectivity
- Ensure sufficient memory for the configured heap size

---

## Upgrading an Existing Deployment

An existing deployment needs these before its next plan:

- **Pin your size.** The defaults are now the Size M values, so a `terraform.tfvars` that leaves sizing
  unset shrinks compute and the database on the next apply. On `infra-aws-ha`, for example, the heap goes
  from 44 GB to 20 GB and Aurora from `db.r8g.2xlarge` to `db.r8g.xlarge`, and a database class change
  restarts the database. Copy your size's values from `examples/<size>.tfvars` into `terraform.tfvars`
  before the next plan.
- **Set `search_engine`.** It has no default. To keep what you have, set `search_engine = "builtin"`,
  which keeps the Nexus One index in PostgreSQL and supports up to 10,000 applications; to move to
  OpenSearch, set `"opensearch"`, and Terraform creates the cluster. A deployment that already
  sets `opensearch_endpoint` (`opensearch_domain_endpoint` on AWS) keeps the cluster it names.
- **Set `iq_admin_initial_password`.** The plan requires it. IQ Server reads it only on its first start,
  so an existing admin password stays as it is: `admin123` unless it was changed. The post-deploy step
  then stops on a 401, so run `./iq-post-deploy.sh` again with `IQ_ADMIN_PASSWORD` set to the existing
  password.
- **Set `iq_license_file`.** The plan requires it, and the file has to exist wherever Terraform runs,
  for the destroy as well. IQ Server installs it only when it has no license, so an installed license
  stays as it is. On Kubernetes, `helm-install.sh` replaces the `nexus-iq-license` secret with it.
- **GKE: the IQ Server node pool is sized in totals.** `node_group_min_size`, `node_group_max_size` and
  `node_group_desired_size` are totals across the pool's zones, with one node per zone at start. The pool
  uses as many zones as `node_group_min_size`, up to 3: 2 at Size M and L, 3 at Size XL. A pool sized per
  zone shrinks to them on the next apply.
- **AKS: the system node pool is a fixed 2 x `Standard_D2pls_v6`** for the AKS system pods only, set by
  `system_node_instance_type` and `system_node_count`. The IQ pods run on the user pool, which follows
  `node_group_min_size` and `node_group_max_size`. An existing cluster's system pool is rotated to the new
  size through a temporary pool, `systemtmp`.
- **GCP: the apply replaces a zonal Filestore instance.** The share is Regional tier, in the region rather
  than a zone, and replacing the instance deletes its files. Copy `sonatype-work` off the share before you
  apply, and back onto the Regional share after. Remove `filestore_zone` from `terraform.tfvars`; this
  configuration has no such variable.
- **EKS: the apply deletes the `/eks/<cluster>/nexus-iq-server` log group.** Logs go through the Amazon
  CloudWatch Observability add-on, and the apply deletes that log group and the logs in it. Export any you
  need first.
- **Kubernetes: the chart does not bundle Fluentd.** Its version is `helm_chart_version` in
  `variables.tf`, and the IQ Server image comes from the chart.

---

## Restoring a backup

**Restore the database and `sonatype-work` from the same backup.** The database names a scan file and a
report for every evaluation, and IQ Server reads them from the file share, so a database restored on its
own leaves continuous monitoring failing with `Failed policy monitoring` for every application whose
newest evaluation has no file.

Scans and reports live under IQ Server's cluster directory, or under `sonatype-work` when there is none:

| Architecture | Scans | Reports |
|---|---|---|
| `infra-aws`, `infra-azure`, `infra-gcp` | `/sonatype-work/scan/<application id>/` | `/sonatype-work/report/<application id>/` |
| HA and Kubernetes architectures | `/sonatype-work/clm-cluster/scan/<application id>/` | `/sonatype-work/clm-cluster/report/<application id>/` |

On the HA architectures, a backup taken from a single instance therefore restores into `clm-cluster/`, not
next to it. To check a restore, count the application directories under `scan` and `report` and compare
them with the number of applications IQ Server lists, then open one application's newest report in IQ
Server: it loads only when its files are there.

---

## Troubleshooting

| Issue | Possible Cause | Solution |
|-------|---------------|----------|
| Plan stops naming `CHANGE_ME` | A value in `terraform.tfvars` still reads `CHANGE_ME` | Replace every `CHANGE_ME`, including `search_engine` and `iq_admin_initial_password`, or use the guided deploy script |
| Plan rejects `iq_admin_initial_password` | Shorter than 12 characters | Choose a password of 12 characters or more |
| Plan rejects `iq_license_file` | It still reads `CHANGE_ME`, or names no file where Terraform runs | Set it to the path of your IQ Server license file. The file has to stay there, because every plan, the destroy's included, reads it |
| Fargate rejects the task definition | The CPU and memory pair is not one Fargate allows | Use the `ecs_cpu` and `ecs_memory` values from your size's block above |
| Container fails to start | Database not yet available | Wait 5-10 minutes for database provisioning to complete |
| Connection timeout to UI | Security group/firewall rules | Verify ports 80/443 allow inbound from your IP |
| Login refused | Wrong password, or a restored database | Log in as `admin` with `iq_admin_initial_password`, which applies only on the first start. A restored database brings its own users and passwords |
| Login refused with the right password | Several wrong passwords in a row start IQ Server's login cool-down: after 6 failures it refuses that user for 30 seconds, doubling with each further failure up to 30 minutes by default | Wait for the cool-down to end, then log in once with the right password |
| Apply warns that choosing the search backend needs a license | IQ Server has no license, so the license file was not installed on its first start | Check the IQ Server log for "could not be installed", fix `iq_license_file` and apply, or run `./iq-post-deploy.sh` with `IQ_LICENSE_FILE` set to the license file |
| GCP apply fails on `iam.serviceAccounts.create` or `servicenetworking.services.addPeering` | The deploying account lacks a role | Grant it Service Account Admin, Service Account User, Service Networking Admin, Cloud SQL Admin, Cloud Filestore Editor, Logging Admin, Monitoring Editor and Service Usage Admin |
| A VM or node pool cannot be created because the zone has no capacity for the machine type (`ZONE_RESOURCE_POOL_EXHAUSTED` on GCP, `ZonalAllocationFailed` on Azure) | The cloud has run out of that machine type in the zone | `deploy.sh` names the setting to change when this stops an apply. Set `opensearch_zones` to zones that have capacity and apply again; on GKE one zone is enough. On GCP, when every zone is out of a C4A type, set `opensearch_data_instance_type` to the x86 C4 type with the same vCPUs, such as `c4-standard-2`, and on the VM architectures the heap to half its memory. On AKS, set `node_pool_zones` for the IQ Server node pool, or use the same size from another series, such as `Standard_D8as_v6` for `Standard_D8ps_v6` |
| AKS apply retry fails because a node pool "already exists" | The first apply created the pool in Azure but failed before Terraform recorded it | Delete the pool with `az aks nodepool delete`, or import it with `terraform import`, then apply again |
| `iq-post-deploy.sh` fails with HTTP 502, 503 or 504 | A node behind the load balancer was still starting for longer than the script retries | Run `./iq-post-deploy.sh` again, or set `IQ_GATEWAY_RETRY_SECONDS` above 600 |
| GCP IQ Server VM stops answering and SSH hangs; the serial console shows a NULL pointer dereference in `ext4_mb_load_buddy_gfp` | Debian 12 kernel 6.1.192-1 (Debian bug 1154108) | The startup script boots the newest kernel before IQ Server starts. If the VM could not reach the Debian security mirror, IQ Server is not started; reset the VM to try again, and on `infra-gcp-ha` the health check replaces it |
| AWS apply fails creating a secret: a secret with this name is already scheduled for deletion | A secret from another deployment with the same `cluster_name` is still in its recovery window | Delete the secret with `aws secretsmanager delete-secret --force-delete-without-recovery`, or use another `cluster_name` |
| Amazon OpenSearch Service answers 401 "payload is not allowed" to `_cluster/settings` | The managed service does not allow `cluster.default_number_of_replicas` | Use `opensearch_index_replicas`, or an index template with `number_of_replicas` |
| Continuous monitoring logs `Failed policy monitoring` naming a scan file, or "The report for owner ID ... and scan ..." | A database restored without the `sonatype-work` files that belong with it | Restore the database and `sonatype-work` from the same backup, see [Restoring a backup](#restoring-a-backup) |
| `OutOfMemoryError` | Heap exceeds container memory | Use the heap for your platform in [JVM Configuration](#jvm-configuration) |
| Database connection refused | Credentials mismatch | Verify database password in secrets manager |
| Clustering not working | Missing HA license | Install an HA-capable license for multi-node deployments |
| Every IQ Server node but one stops with "Node clustering is not supported by the current license" and restarts | IQ Server has no license that allows clustering, so it runs one node | Check that `iq_license_file` names an HA-capable license and that the IQ Server log shows "Installing license". Once the license is installed, the nodes start on their next restart |
| AWS destroy stops naming `prevent_destroy` | The OpenSearch domain holds the Nexus One index, so Terraform refuses to delete it | Run `./tf-destroy.sh --delete-opensearch-domain`, which deletes the domain first and then the rest. `deploy.sh --destroy` passes it |
| No Nexus One index in OpenSearch | `search_engine = "builtin"`, or the first build not started | With `builtin`, Nexus One keeps its index in IQ Server's PostgreSQL database instead, once you choose PostgreSQL on the Nexus One setup page. To use OpenSearch instead, set `search_engine = "opensearch"` and apply before any backend is chosen, then start the build in the Index Manager. IQ Server keeps the first backend chosen, so once PostgreSQL is chosen, `iq-post-deploy.sh` stops on the choice |
| No audit events in the audit log | Audit events go to the database by default | Turn off `audit-log-destination-database`, see [Logging](#logging) |
| High disk usage | Report accumulation | Configure report purge policies; plan storage based on app count |
| Terraform destroy fails | Deletion protection enabled | Set `deletion_protection = false` before destroying |

### Architecture-Specific Guides

Each architecture directory contains its own detailed README with provider-specific troubleshooting:
- [AWS Single Instance](./infra-aws/)
- [AWS High Availability](./infra-aws-ha/)
- [AWS Kubernetes](./infra-aws-ha-k8s-helm/)
- [Azure Single Instance](./infra-azure/)
- [Azure High Availability](./infra-azure-ha/)
- [Azure Kubernetes](./infra-azure-ha-k8s-helm/)
- [GCP Single Instance](./infra-gcp/)
- [GCP High Availability](./infra-gcp-ha/)
- [GCP Kubernetes](./infra-gcp-ha-k8s-helm/)

---

## Cleanup

To stop all charges, destroy all resources when no longer needed. If you deployed with the guided
script, run `./deploy.sh --destroy` with the same answers. Otherwise, in the architecture's directory:

```bash
# For Kubernetes deployments: uninstall Helm release first
./helm-uninstall.sh

# Destroy all Terraform-managed infrastructure
./tf-destroy.sh
```

On GCP the destroy scripts are `./destroy.sh` in `infra-gcp` and `./gcp-ha-destroy.sh` in `infra-gcp-ha`.

> **WARNING:** This permanently deletes all infrastructure and data. Ensure you have backups of any important data (database exports, reports, configuration) before proceeding.

> **OpenSearch.** A domain the AWS architectures created carries `prevent_destroy`, so `./tf-destroy.sh` stops rather than deleting the index. `./tf-destroy.sh --delete-opensearch-domain` deletes the domain deliberately and then the rest, and `deploy.sh --destroy` passes it. The AWS destroy also deletes the log groups AWS creates outside Terraform, the database's PostgreSQL log and ECS Container Insights. On Azure and GCP, a cluster Terraform created is deleted with the rest of the deployment, indices included. A cluster you brought yourself is not touched.

> **Backups left on AWS.** On `infra-aws-ha` and `infra-aws-ha-k8s-helm`, a destroy with `db_skip_final_snapshot = false` (`skip_final_snapshot` on Kubernetes) leaves the database's final snapshot, and the automatic EFS backup AWS Backup keeps in `aws/efs/automatic-backup-vault` is not deleted and expires on its own. On `infra-aws` the same setting leaves the database's final snapshot.

If `terraform destroy` fails due to deletion protection:
1. Set `deletion_protection = false` in your variables
2. Run `terraform apply` to update the setting
3. Run the destroy script again

---

## Additional Resources

### Sonatype Documentation
- [IQ Server Documentation](https://help.sonatype.com/en/sonatype-lifecycle.html)
- [IQ Server Installation Guide](https://help.sonatype.com/en/install-self-hosted-iq-server.html)
- [IQ Server High Availability Installation](https://help.sonatype.com/en/iq-server-high-availability-installation.html)
- [IQ Server Helm chart source and README](https://github.com/sonatype/nexus-iq-server-ha/tree/main/chart)
- [IQ Server Helm chart on Artifact Hub](https://artifacthub.io/packages/helm/sonatype/nexus-iq-server-ha)
- [Docker Hub: nexus-iq-server](https://hub.docker.com/r/sonatype/nexus-iq-server)

### Cloud Provider Documentation
- [AWS Documentation](https://docs.aws.amazon.com)
- [Azure Documentation](https://learn.microsoft.com/azure)
- [Google Cloud Documentation](https://cloud.google.com/docs)

### Terraform Documentation
- [Terraform](https://developer.hashicorp.com/terraform/docs)
- [AWS Provider](https://registry.terraform.io/providers/hashicorp/aws)
- [Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm)
- [GCP Provider](https://registry.terraform.io/providers/hashicorp/google)

---

## License

Copyright (c) 2024-present Sonatype, Inc.

Licensed under the Apache License, Version 2.0. See [LICENSE](./LICENSE) for details.

---

## Support

These reference architectures are provided as examples and starting points for deploying Sonatype IQ Server in cloud environments.

- **IQ Server Issues**: Contact Sonatype Support at [support.sonatype.com](https://support.sonatype.com)
- **Architecture Questions**: Open a [GitHub Issue](https://github.com/sonatype/sca-reference-architectures/issues) in this repository
- **Cloud Infrastructure**: Refer to your cloud provider's support channels
