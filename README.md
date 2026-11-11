# Sonatype IQ Server Infrastructure as Code — AWS, Azure, and GCP Reference Architectures

Production-ready Terraform configurations for deploying Sonatype IQ Server across AWS, Azure, and GCP with Single Instance, High Availability, and Kubernetes deployment patterns.

---

## Cost and Responsibility Disclaimer

**WARNING: These reference architectures deploy real cloud resources that incur costs.**

You are solely responsible for all cloud infrastructure costs resulting from deploying these configurations. Resources provisioned include compute instances, managed databases, load balancers, storage volumes, and networking components — all of which accrue charges while active.

- **Review pricing** for all services in your cloud provider's pricing calculator before deployment
- **Set billing alerts** to avoid unexpected charges
- **Destroy resources** promptly when no longer needed using the provided cleanup scripts
- **Monitor usage** through your cloud provider's cost management tools

Sonatype provides these configurations as reference examples. You are responsible for reviewing and customizing them to meet your organization's security, compliance, and operational requirements.

---

## What This Provides

### 9 Reference Architectures

| | AWS | Azure | GCP |
|---|---|---|---|
| **Single Instance** | ECS Fargate + RDS | Container Apps + PostgreSQL | GCE Docker + Cloud SQL |
| **High Availability** | ECS Fargate + Aurora + EFS | Container Apps + Zone-Redundant DB | MIG + Regional Cloud SQL + Filestore |
| **Kubernetes** | EKS + Helm | AKS + Helm | GKE + Helm |

### Key Features

- Production-grade Terraform with security best practices
- Multi-AZ/Zone deployments for high availability
- Auto-scaling (CPU, memory, and load-based)
- Managed PostgreSQL databases with automated backups and failover
- Encrypted storage and secrets management
- Load balancing with health checks
- Official Sonatype Helm chart integration (Kubernetes deployments)
- ARM instance support, at a lower on-demand price than the x86 equivalents (see [Cross-Provider Instance Comparison](#cross-provider-instance-comparison))
- OpenSearch configuration for Advanced Search and the Nexus One index, at every size

### Official Documentation

- [IQ Server Documentation](https://help.sonatype.com/iqserver)
- [IQ Server Installation Guide](https://help.sonatype.com/iqserver/install)
- [Sonatype Helm Charts](https://github.com/sonatype/helm3-charts)

---

## Prerequisites

### Cloud Account Setup

You need an active cloud account with permissions to create:
- VPC/VNet and networking resources
- Compute containers or instances (ECS, Container Apps, GCE, EKS/AKS/GKE)
- Managed database instances (RDS, Azure Database, Cloud SQL)
- Load balancers and storage volumes
- IAM roles and security groups

### Tools Installation

| Tool | Version | Required For |
|------|---------|--------------|
| [Terraform](https://terraform.io/downloads) | >= 1.2 | All deployments |
| [AWS CLI](https://aws.amazon.com/cli/) | Latest | AWS deployments |
| [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) | Latest | Azure deployments |
| [Google Cloud CLI](https://cloud.google.com/sdk/docs/install) | Latest | GCP deployments |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | Latest | Kubernetes deployments only |
| [Helm](https://helm.sh/docs/intro/install/) | >= 3.9.3 | Kubernetes deployments only |

### IQ Server Requirements

- **Docker Image**: `sonatype/nexus-iq-server` ([Docker Hub](https://hub.docker.com/r/sonatype/nexus-iq-server))
- **License**: Standard license for single instance; HA-capable license for multi-node deployments
- **PostgreSQL**: Minimum PostgreSQL 16. Recommended, and the default for new deployments, PostgreSQL 18. Provisioned automatically by Terraform
- **OpenSearch**: A reachable OpenSearch cluster, required at every size. The three AWS architectures can create the domain for you; on Azure and GCP you build the cluster yourself. See [OpenSearch](#opensearch).

### SSL Certificate (Optional)

For HTTPS access, prepare:
- **AWS**: ACM certificate ARN
- **Azure**: a custom domain certificate on the Container App
- **GCP**: Google-managed or self-managed SSL certificate

---

## Quick Start (5 Minutes to Deploy)

### Sizing Guide

<!-- TO BE ADDED (CLM-55936): the "expected to change" notice goes here, in Product's own wording,
     once Product has approved it. Nothing below should be read as that notice. -->

Choose your deployment size based on your application count and daily evaluation volume:

| Size | Applications | Evaluations/Day | Nodes | Compute (per node) | Java Heap | HA Required | OpenSearch |
|------|:------------:|:---------------:|:-----:|:-------------------:|:---------:|:-----------:|:----------:|
| **XS** ¹ | < 500 | < 1,000 | 1 | 2 vCPU / 16 GB | 12 GB | No | Required ² |
| **S** ¹ | 500 - 2,000 | 1,000 - 5,000 | 1 | 4 vCPU / 32 GB | 24 GB | No | Required ² |
| **M** | 2,000 - 10,000 | 5,000 - 10,000 | 2 | 8 vCPU / 64 GB | 48 GB | Recommended | Required ² |
| **L** | 10,000 - 20,000 | 10,000 - 20,000 | 3 | 8 vCPU / 64 GB | 48 GB | Required | Required ² |
| **XL** | 20,000 - 80,000 | 20,000+ | 4 | 16 vCPU / 128 GB | 96 GB | Required | Required ² |

> ¹ XS and S are projected sizing estimates. M, L, and XL have been validated through performance testing, which ran on the GCP ARM instances below: `n4a-highmem-8` at 8 vCPU and 64 GB with a 48 GB heap for M and L, and `n4a-highmem-16` at 16 vCPU and 128 GB with a 96 GB heap for XL.

> ² OpenSearch is part of every size. The per-size cluster specification, meaning data node count, node size, storage, shards and replicas, is in [Per-size cluster specification](#per-size-cluster-specification).

> **Note:** M and L use the same per-node specification (8 vCPU / 64 GB). The difference is the number of load-balanced nodes (2 vs 3), not the machine size. XL requires larger instances (16 vCPU / 128 GB) to handle concurrent continuous monitoring, policy evaluations, and larger heap requirements.

> **AWS Fargate is the one exception to the memory column.** A Fargate task size has to be one of the CPU and memory pairs Fargate allows, and those stop at 60 GB for 8 vCPU and 120 GB for 16 vCPU ([task CPU and memory](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/fargate-tasks-services.html)). So `infra-aws` and `infra-aws-ha` run a 60 GB task with a 44 GB heap at M and L, and a 120 GB task with a 96 GB heap at XL. Azure, GCP, and the EKS node groups use the 64 GB and 128 GB sizes above.
<!-- TO BE ADDED (no ticket yet): a link from this sizing table to the generic architecture's help pages,
     and an XXS row, once both are published. The help pages do not exist yet, so there is no URL to
     link. The generic architecture and its H2 option are tracked separately. -->

### Step 1: Choose Your Reference Architecture

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

### Step 2: Provision an OpenSearch Cluster

OpenSearch is required at every size. The three AWS architectures can create an Amazon OpenSearch
Service domain for you; the six Azure and GCP ones cannot, so on those clouds build a reachable
self-managed cluster first and keep its endpoint, user name, and password to hand. The per-size
cluster specification is in [Per-size cluster specification](#per-size-cluster-specification).

Skipping this step leaves IQ Server on its built-in search index, with no Nexus One index.

### Step 3: Configure Your Deployment

```bash
git clone https://github.com/sonatype/sca-reference-architectures.git
cd sca-reference-architectures/<your-chosen-architecture>

# Copy and edit the example variables file
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values (region, instance sizes, passwords, etc.)
# Set search_engine = "opensearch", because every example file ships with
# "lucene". Then point the deployment at your OpenSearch cluster. Every
# architecture takes variables for it, named in its own README: "OpenSearch for
# the Nexus One Index" on AWS, "Advanced Search with OpenSearch" on Azure,
# "Search Backend" on GCP.
```

### Step 4: Deploy

```bash
terraform init
./tf-plan.sh    # Review the execution plan
./tf-apply.sh   # Deploy infrastructure
```

For **Kubernetes deployments**, also run:

```bash
./helm-install.sh   # Deploy IQ Server via Helm chart
```

### Step 5: Get Your Access Information

```bash
terraform output
```

This displays the load balancer URL, database endpoint, and other access details.

### Step 6: Access IQ Server

1. Navigate to the load balancer URL from the Terraform outputs
2. Wait 5-15 minutes for the application to initialize
3. Log in with default credentials:
   - **Username**: `admin`
   - **Password**: `admin123`
4. **Change the default password immediately**

---

## Reference Architectures — Detailed Specifications

### AWS Reference Architectures

Use the table below to compare infrastructure characteristics and resource requirements for each IQ deployment size on AWS.

|  | **Size M** | **Size L** | **Size XL** |
|--|-----------|-----------|------------|
| **Applications** | 2,000 – 10,000 | 10,000 – 20,000 | 20,000 – 80,000 |
| **Number of IQ Server nodes** | 2 | 3 | 4 |
| **Deployment type** | Single Instance or HA | HA required | HA required |
| **Expected throughput, with continuous monitoring running** | ~310 evals/hour/node (~7,440/day/node) | ~310 evals/hour/node (~14,880 to 22,320/day total) | ~405 evals/hour/node (~29,160 to 38,880/day total) |
| **Compute** | | | |
| Instance type | Fargate: 8 vCPU, 60 GB task. EKS: r9g.2xlarge (ARM, r8g or newer) or r8i.2xlarge (x86) | Fargate: 8 vCPU, 60 GB task. EKS: r9g.2xlarge (ARM, r8g or newer) or r8i.2xlarge (x86) | Fargate: 16 vCPU, 120 GB task. EKS: r9g.4xlarge (ARM, r8g or newer) or r8i.4xlarge (x86) |
| vCPUs | 8 | 8 | 16 |
| Memory | 60 GB Fargate task, or 64 GB per EKS node | 60 GB Fargate task, or 64 GB per EKS node | 120 GB Fargate task, or 128 GB per EKS node |
| Java Heap | `-Xms44g -Xmx44g` on Fargate, `-Xms48g -Xmx48g` on EKS | `-Xms44g -Xmx44g` on Fargate, `-Xms48g -Xmx48g` on EKS | `-Xms96g -Xmx96g` |
| **Database** | | | |
| Service | RDS PostgreSQL or Aurora PostgreSQL | Aurora PostgreSQL (recommended) | Aurora PostgreSQL (strongly recommended) |
| PostgreSQL version | Minimum 16, recommended and default 18 | Minimum 16, recommended and default 18 | Minimum 16, recommended and default 18 |
| Instance class | db.r8g.2xlarge (8 vCPU, 64 GB) | db.r8g.2xlarge (8 vCPU, 64 GB) | db.r8g.4xlarge (16 vCPU, 128 GB) |
| Storage | 128 GB gp3 on RDS, auto-scaling to 500 GB; Aurora grows on its own | Aurora, grows on its own up to 1 TB | Aurora, grows on its own up to 2 TB |
| Multi-AZ | Recommended | Required | Required with automatic failover |
| **Storage** | | | |
| Service | Amazon EFS | Amazon EFS | Amazon EFS |
| Throughput mode | Elastic (recommended) | Elastic (recommended) | Elastic (recommended) |
| Estimated capacity | 200 GB – 500 GB | 500 GB – 1.5 TB | 1.5 TB – 4 TB |
| Cost optimization | Enable lifecycle policies — move files older than 30 days to EFS Infrequent Access (IA) for ~92% storage savings | Enable lifecycle policies — move files older than 30 days to EFS IA | Enable lifecycle policies — move files older than 30 days to EFS IA |
| **Terraform Templates** | [Single Instance](./infra-aws) &#124; [High Availability](./infra-aws-ha) &#124; [HA Kubernetes](./infra-aws-ha-k8s-helm) | [High Availability](./infra-aws-ha) &#124; [HA Kubernetes](./infra-aws-ha-k8s-helm) | [High Availability](./infra-aws-ha) &#124; [HA Kubernetes](./infra-aws-ha-k8s-helm) |

> **Note on AWS EFS:** EFS uses SSD-backed infrastructure — there is no HDD vs SSD tier choice. Cost optimization is achieved through lifecycle policies (moving infrequently accessed data to the IA storage class) and Elastic throughput mode (pay only for throughput consumed).

---

### Azure Reference Architectures

Use the table below to compare infrastructure characteristics and resource requirements for each IQ deployment size on Azure.

|  | **Size M** | **Size L** | **Size XL** |
|--|-----------|-----------|------------|
| **Applications** | 2,000 – 10,000 | 10,000 – 20,000 | 20,000 – 80,000 |
| **Number of IQ Server nodes** | 2 | 3 | 4 |
| **Deployment type** | Single Instance or HA | HA required | HA required |
| **Expected throughput, with continuous monitoring running** | ~310 evals/hour/node (~7,440/day/node) | ~310 evals/hour/node (~14,880 to 22,320/day total) | ~405 evals/hour/node (~29,160 to 38,880/day total) |
| **Compute** | | | |
| Instance type | Standard_E8ps_v6 (ARM) or Standard_E8s_v7 (x86) | Standard_E8ps_v6 (ARM) or Standard_E8s_v7 (x86) | Standard_E16ps_v6 (ARM) or Standard_E16s_v7 (x86) |
| vCPUs | 8 | 8 | 16 |
| Memory | 64 GB | 64 GB | 128 GB |
| Java Heap | `-Xms48g -Xmx48g` | `-Xms48g -Xmx48g` | `-Xms96g -Xmx96g` |
| Deployment option | Azure Container Apps or AKS | Azure Container Apps or AKS | AKS recommended at this scale |
| **Database** | | | |
| Service | Azure Database for PostgreSQL — Flexible Server | Azure Database for PostgreSQL — Flexible Server | Azure Database for PostgreSQL — Flexible Server |
| PostgreSQL version | Minimum 16, recommended and default 18 | Minimum 16, recommended and default 18 | Minimum 16, recommended and default 18 |
| SKU | MO_Standard_E8ds_v6 (8 vCores, 64 GB) | MO_Standard_E8ds_v6 (8 vCores, 64 GB) | MO_Standard_E16ds_v6 (16 vCores, 128 GB) |
| Storage | 128 GB, auto-grow | 256 GB, auto-grow to 1 TB | 512 GB, auto-grow to 2 TB |
| Zone redundancy | Recommended | Required | Required with automatic failover |
| **Storage** | | | |
| Service | Azure Files — Standard HDD (pay-as-you-go) | Azure Files — Standard HDD (pay-as-you-go) | Azure Files — Standard HDD (SMB) or Premium SSD (NFS/AKS) |
| Protocol | SMB 3.0 | SMB 3.0 | SMB 3.0 (Standard) or NFS (requires Premium) |
| Redundancy | ZRS for HA deployments | ZRS | ZRS |
| File share quota | 500 GB | 1,536 GB | 4,096 GB, on Premium the quota is the billed size |
| **Terraform Templates** | [Single Instance](./infra-azure) &#124; [High Availability](./infra-azure-ha) &#124; [HA Kubernetes](./infra-azure-ha-k8s-helm) | [High Availability](./infra-azure-ha) &#124; [HA Kubernetes](./infra-azure-ha-k8s-helm) | [High Availability](./infra-azure-ha) &#124; [HA Kubernetes](./infra-azure-ha-k8s-helm) |

> **Note on Azure storage tiers:** Standard HDD is the default recommendation based on performance testing (peak ~1,212 write ops/sec, well within Standard HDD limits). Use Premium SSD when: NFS protocol is required (AKS/Kubernetes deployments), or high sustained write volume makes per-transaction costs exceed SSD flat-rate pricing. At XL scale with AKS, Premium SSD is mandatory since NFS requires it.

---

### GCP Reference Architectures

Use the table below to compare infrastructure characteristics and resource requirements for each IQ deployment size on GCP. GCP was the primary test platform — all performance data was validated on GCP ARM-based instances.

|  | **Size M** | **Size L** | **Size XL** |
|--|-----------|-----------|------------|
| **Applications** | 2,000 – 10,000 | 10,000 – 20,000 | 20,000 – 80,000 |
| **Number of IQ Server nodes** | 2 | 3 | 4 |
| **Deployment type** | Single Instance or HA | HA required | HA required |
| **Expected throughput, with continuous monitoring running** | ~310 evals/hour/node (~7,440/day/node) | ~310 evals/hour/node (~14,880 to 22,320/day total) | ~405 evals/hour/node (~29,160 to 38,880/day total) |
| **Compute** | | | |
| Machine type | n4a-highmem-8 (ARM Google Axion) | n4a-highmem-8 (ARM Google Axion) | n4a-highmem-16 (ARM Google Axion) |
| vCPUs | 8 | 8 | 16 |
| Memory | 64 GB | 64 GB | 128 GB |
| Java Heap | `-Xms48g -Xmx48g` | `-Xms48g -Xmx48g` | `-Xms96g -Xmx96g` |
| Deployment | GCE with Docker or GKE | GCE with Docker or GKE | GCE with Docker or GKE |
| **Database** | | | |
| Service | Cloud SQL PostgreSQL | Cloud SQL PostgreSQL | Cloud SQL PostgreSQL |
| PostgreSQL version | Minimum 16, recommended and default 18 | Minimum 16, recommended and default 18 | Minimum 16, recommended and default 18 |
| Instance tier | db-custom-8-30720 (8 vCPU, 30 GB) | db-custom-8-30720 (8 vCPU, 30 GB) | db-custom-16-65536 (16 vCPU, 64 GB) |
| Edition | Enterprise | Enterprise | Enterprise |
| Storage | 128 GB PD-SSD, auto-resize to 500 GB | 256 GB PD-SSD, auto-resize to 1 TB | 512 GB PD-SSD, auto-resize to 2 TB |
| Availability | Zonal (Regional for production) | Regional (automatic failover) | Regional with automatic failover |
| **Storage** | | | |
| Service | Cloud Filestore | Cloud Filestore | Cloud Filestore |
| Tier | BASIC_HDD (1 TiB) | BASIC_HDD (2.5 TiB) | BASIC_HDD (10 TiB) |
| Protocol | NFS v3 | NFS v3 | NFS v3 |
| IOPS | 600 read / 1,000 write | 600 read / 1,000 write | 1,000 read / 5,000 write |
| **Terraform Templates** | [Single Instance](./infra-gcp) &#124; [High Availability](./infra-gcp-ha) &#124; [HA Kubernetes](./infra-gcp-ha-k8s-helm) | [High Availability](./infra-gcp-ha) &#124; [HA Kubernetes](./infra-gcp-ha-k8s-helm) | [High Availability](./infra-gcp-ha) &#124; [HA Kubernetes](./infra-gcp-ha-k8s-helm) |

> **Note on GCP storage tiers:** BASIC_HDD is the default recommendation. At 10+ TiB, HDD unlocks 5,000 write IOPS (4x our observed peak of ~1,212 ops/sec) at roughly the same cost as 2.5 TiB SSD. Use BASIC_SSD when storage needs are small (< 2.5 TiB) but IOPS demand is high, or when sub-millisecond disk latency is required. Enterprise edition Cloud SQL (not Enterprise Plus) is sufficient — the database was not a bottleneck during performance testing.

---

### Cross-Provider Instance Comparison

The following tables provide equivalent instance types across cloud providers for quick cross-reference.

#### Size M and L (8 vCPU / 64 GB)

| Cloud Provider | Instance Type | Architecture |
|----------------|---------------|--------------|
| **GCP** | n4a-highmem-8 | ARM (Google Axion) |
| **AWS** | r8g.2xlarge or newer, r9g.2xlarge on EKS | ARM (Graviton4 or newer) |
| **AWS** | r8i.2xlarge | x86_64 |
| **Azure** | Standard_E8ps_v6 | ARM (Azure Cobalt 100) |
| **Azure** | Standard_E8s_v7 | x86_64 |

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
| **M** (2 nodes) | db-custom-8-30720 Enterprise (8 vCPU, 30 GB) | db.r8g.2xlarge (8 vCPU, 64 GB) | MO_Standard_E8ds_v6 (8 vCores, 64 GB) |
| **L** (3 nodes) | db-custom-8-30720 Enterprise (8 vCPU, 30 GB) | db.r8g.2xlarge (8 vCPU, 64 GB) | MO_Standard_E8ds_v6 (8 vCores, 64 GB) |
| **XL** (4 nodes) | db-custom-16-65536 Enterprise (16 vCPU, 64 GB) | db.r8g.4xlarge (16 vCPU, 128 GB) | MO_Standard_E16ds_v6 (16 vCores, 128 GB) |

> **DB sizing scales with node count, not application count.** The database was not a bottleneck during testing. XL needs 16 vCPU primarily for connection pool aggregation from 4 nodes (~560 peak connections), not query complexity.

> **ARM instances recommended.** At 8 vCPU and 64 GB, the ARM instances cost less on demand than their x86 equivalents, at list prices in November 2026: 15% less on GCP (`n4a-highmem-8` against `n4-highmem-8`, us-central1), 8% less on AWS (`r9g.2xlarge` against `r8i.2xlarge`, us-east-1) and 47% less on Azure (`Standard_E8ps_v6` against `Standard_E8s_v7`, eastus). These are price differences, not measured price-performance. If using x86_64 instances, verify performance characteristics are similar.

---

### Detailed Specifications

Each size below shows the key Terraform variables you need to configure. Copy the block for your chosen size into your `terraform.tfvars` file and adjust for your environment.

#### Size XS — Extra Small (< 500 applications) ¹

Single instance for development, testing, or very small production environments.

**AWS (ECS Fargate):**
```hcl
# infra-aws/terraform.tfvars — Size XS
ecs_cpu              = 2048                # 2 vCPU
ecs_memory           = 16384               # 16 GB
iq_desired_count     = 1                   # Single instance
iq_docker_image      = "sonatype/nexus-iq-server:latest"
java_opts            = "-Xms12g -Xmx12g -XX:MaxDirectMemorySize=4g -XX:+UseG1GC -XX:+AlwaysPreTouch -Dinsight.threads.monitor=3 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_instance_class    = "db.m8g.large"      # 2 vCPU, 8 GB
db_allocated_storage = 64                  # GB
```

**Azure (Container Apps):**
```hcl
# infra-azure/terraform.tfvars — Size XS
container_cpu        = 2.0                 # 2 vCPU
container_memory     = "16Gi"              # 16 GB
workload_profile_type = "D4"               # 4 cores, 16 GB per node
iq_docker_image      = "sonatype/nexus-iq-server:latest"
java_opts            = "-Xms12g -Xmx12g -XX:MaxDirectMemorySize=4g -XX:+UseG1GC -XX:+AlwaysPreTouch -Dinsight.threads.monitor=3 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_sku_name          = "GP_Standard_D2ds_v6" # 2 vCores, 8 GB
db_storage_mb        = 65536               # 64 GB
```

**GCP (GCE Docker):**
```hcl
# infra-gcp/terraform.tfvars — Size XS
gce_machine_type     = "n4a-highmem-2"     # 2 vCPU, 16 GB (ARM)
iq_docker_image      = "sonatype/nexus-iq-server:latest"
java_opts            = "-Xms12g -Xmx12g -XX:MaxDirectMemorySize=4g -XX:+UseG1GC -XX:+AlwaysPreTouch -Dinsight.threads.monitor=3 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_instance_tier     = "db-custom-2-7680"  # 2 vCPU, 7.5 GB
db_disk_size         = 64                  # GB
```

> ¹ Projected sizing estimate — not yet validated through performance testing.

---

#### Size S — Small (500 – 2,000 applications) ¹

Single instance for small production environments with moderate evaluation volume.

**AWS (ECS Fargate):**
```hcl
# infra-aws/terraform.tfvars — Size S
ecs_cpu              = 4096                # 4 vCPU
ecs_memory           = 30720              # 30 GB, the maximum at 4 vCPU
iq_desired_count     = 1                   # Single instance
iq_docker_image      = "sonatype/nexus-iq-server:latest"
java_opts            = "-Xms22g -Xmx22g -XX:MaxDirectMemorySize=6g -XX:+UseG1GC -XX:+AlwaysPreTouch -Dinsight.threads.monitor=5 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_instance_class    = "db.r8g.large"      # 2 vCPU, 16 GB
db_allocated_storage = 128                 # GB
```

**Azure (Container Apps):**
```hcl
# infra-azure/terraform.tfvars — Size S
container_cpu        = 4.0                 # 4 vCPU
container_memory     = "32Gi"              # 32 GB
workload_profile_type = "E4"               # 4 cores, 32 GB per node
iq_docker_image      = "sonatype/nexus-iq-server:latest"
java_opts            = "-Xms24g -Xmx24g -XX:MaxDirectMemorySize=6g -XX:+UseG1GC -XX:+AlwaysPreTouch -Dinsight.threads.monitor=5 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_sku_name          = "MO_Standard_E2ds_v6" # 2 vCores, 16 GB
db_storage_mb        = 131072              # 128 GB
```

**GCP (GCE Docker):**
```hcl
# infra-gcp/terraform.tfvars — Size S
gce_machine_type     = "n4a-highmem-4"     # 4 vCPU, 32 GB (ARM)
iq_docker_image      = "sonatype/nexus-iq-server:latest"
java_opts            = "-Xms24g -Xmx24g -XX:MaxDirectMemorySize=6g -XX:+UseG1GC -XX:+AlwaysPreTouch -Dinsight.threads.monitor=5 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_instance_tier     = "db-custom-2-13312" # 2 vCPU, 13 GB
db_disk_size         = 128                 # GB
```

> ¹ Projected sizing estimate — not yet validated through performance testing.

---

#### Size M — Medium (2,000 – 10,000 applications)

Production deployment supporting 5,000-10,000 evaluations/day. Single instance or HA (2 nodes).

**AWS (ECS Fargate — Single Instance):**
```hcl
# infra-aws/terraform.tfvars — Size M
ecs_cpu              = 8192                # 8 vCPU
ecs_memory           = 61440              # 60 GB, the maximum at 8 vCPU
iq_desired_count     = 1                   # Single instance (or 2 for HA)
iq_docker_image      = "sonatype/nexus-iq-server:latest"
java_opts            = "-Xms44g -Xmx44g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/Java_Heap_logs -XX:+CrashOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_instance_class    = "db.r8g.2xlarge"    # 8 vCPU, 64 GB
db_allocated_storage = 128                 # GB, auto-scales to 500 GB
```

**AWS (ECS Fargate — High Availability):**
```hcl
# infra-aws-ha/terraform.tfvars — Size M
ecs_cpu              = 8192                # 8 vCPU
ecs_memory           = 61440              # 60 GB, the maximum at 8 vCPU
iq_desired_count     = 2                   # 2 nodes for HA
iq_min_count         = 2                   # Minimum instances
iq_max_count         = 3                   # Maximum instances
iq_docker_image      = "sonatype/nexus-iq-server:latest"
java_opts            = "-Xms44g -Xmx44g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/Java_Heap_logs -XX:+CrashOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
aurora_instance_class = "db.r8g.2xlarge"   # 8 vCPU, 64 GB
aurora_instances      = 2                  # Multi-AZ
```

**Azure (Container Apps):**
```hcl
# infra-azure/terraform.tfvars — Size M (Single Instance)
# infra-azure-ha/terraform.tfvars, Size M (HA)
container_cpu        = 8.0                 # 8 vCPU
container_memory     = "64Gi"              # 64 GB
iq_min_replicas      = 2                   # infra-azure-ha only; infra-azure is fixed at 1 replica
iq_max_replicas      = 3                   # infra-azure-ha only, Size M ceiling
iq_docker_image      = "sonatype/nexus-iq-server:latest"
java_opts            = "-Xms48g -Xmx48g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/Java_Heap_logs -XX:+CrashOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_sku_name          = "MO_Standard_E8ds_v6" # 8 vCores, 64 GB
db_storage_mb        = 131072              # 128 GB, grows automatically
file_share_quota_gb  = 500                 # infra-azure-ha; infra-azure names it file_share_quota
```

**GCP (GCE Docker):**
```hcl
# infra-gcp/terraform.tfvars — Size M (Single Instance)
# infra-gcp-ha/terraform.tfvars, Size M (HA: set iq_target_instances = 2, iq_min_instances = 2, iq_max_instances = 3)
# infra-gcp names the machine type gce_machine_type; infra-gcp-ha names it instance_machine_type
gce_machine_type     = "n4a-highmem-8"     # 8 vCPU, 64 GB (ARM)
iq_docker_image      = "sonatype/nexus-iq-server:latest"
java_opts            = "-Xms48g -Xmx48g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/Java_Heap_logs -XX:+CrashOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_instance_tier     = "db-custom-8-30720" # 8 vCPU, 30 GB (Enterprise)
db_disk_size         = 128                 # GB, auto-resize to 500 GB
db_max_disk_size     = 500
filestore_tier       = "BASIC_HDD"         # 1 TiB (600 read / 1,000 write IOPS)
filestore_capacity_gb = 1024               # 1 TiB minimum
```

---

#### Size L — Large (10,000 – 20,000 applications)

High-availability production deployment supporting 10,000-20,000 evaluations/day. Requires 3 nodes.

**AWS (ECS Fargate HA):**
```hcl
# infra-aws-ha/terraform.tfvars — Size L
ecs_cpu              = 8192                # 8 vCPU
ecs_memory           = 61440              # 60 GB, the maximum at 8 vCPU
iq_desired_count     = 3                   # 3 nodes recommended
iq_min_count         = 2                   # Minimum instances
iq_max_count         = 4                   # Maximum instances
iq_docker_image      = "sonatype/nexus-iq-server:latest"
java_opts            = "-Xms44g -Xmx44g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/Java_Heap_logs -XX:+CrashOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
aurora_instance_class = "db.r8g.2xlarge"   # 8 vCPU, 64 GB
aurora_instances      = 2                  # Multi-AZ with failover
```

**AWS (EKS + Helm):**
```hcl
# infra-aws-ha-k8s-helm/terraform.tfvars — Size L
node_instance_type      = "r9g.2xlarge"    # 8 vCPU, 64 GB (ARM)
node_group_desired_size = 3                # 3 nodes
node_group_min_size     = 2
node_group_max_size     = 5
nexus_iq_replica_count  = 3                # 3 IQ pods
# Pod CPU, memory and heap are Helm chart values in helm-values.yaml:
# see the Size L block in infra-aws-ha-k8s-helm/README.md.
aurora_instance_class   = "db.r8g.2xlarge" # 8 vCPU, 64 GB
aurora_instance_count   = 2
```

**Azure (Container Apps HA):**
```hcl
# infra-azure-ha/terraform.tfvars — Size L
container_cpu        = 8.0                 # 8 vCPU
container_memory     = "64Gi"              # 64 GB
iq_min_replicas      = 2                   # Minimum 2 for HA
iq_max_replicas      = 4                   # Scale up to 4
iq_docker_image      = "sonatype/nexus-iq-server:latest"
java_opts            = "-Xms48g -Xmx48g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/Java_Heap_logs -XX:+CrashOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_sku_name          = "MO_Standard_E8ds_v6" # 8 vCores, 64 GB
db_storage_mb        = 262144              # 256 GB, grows automatically
db_storage_tier      = "P15"
db_high_availability_mode = "ZoneRedundant" # Required for L
file_share_quota_gb  = 1536
```

**GCP (MIG HA):**
```hcl
# infra-gcp-ha/terraform.tfvars — Size L
instance_machine_type = "n4a-highmem-8"    # 8 vCPU, 64 GB (ARM)
iq_target_instances  = 3                   # 3 instances across zones
iq_min_instances     = 2
iq_max_instances     = 4
iq_docker_image      = "sonatype/nexus-iq-server:latest"
java_opts            = "-Xms48g -Xmx48g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/Java_Heap_logs -XX:+CrashOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_instance_tier     = "db-custom-8-30720" # 8 vCPU, 30 GB (Enterprise)
db_availability_type = "REGIONAL"          # Required for L
db_disk_size         = 256                 # GB, auto-resize to 1 TB
db_max_disk_size     = 1000
filestore_tier       = "BASIC_HDD"         # 2.5 TiB
filestore_capacity_gb = 2560               # 2.5 TiB
```

---

#### Size XL — Extra Large (20,000 – 80,000 applications)

Enterprise-scale HA deployment supporting 20,000+ evaluations/day. Requires 4 nodes with larger instances.

**AWS (ECS Fargate HA):**
```hcl
# infra-aws-ha/terraform.tfvars — Size XL
ecs_cpu              = 16384               # 16 vCPU
ecs_memory           = 122880             # 120 GB, the maximum at 16 vCPU
iq_desired_count     = 4                   # 4 nodes for XL
iq_min_count         = 3                   # Minimum instances
iq_max_count         = 5                   # Maximum instances
iq_docker_image      = "sonatype/nexus-iq-server:latest"
java_opts            = "-Xms96g -Xmx96g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/Java_Heap_logs -XX:+CrashOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
aurora_instance_class = "db.r8g.4xlarge"   # 16 vCPU, 128 GB
aurora_instances      = 2                  # Multi-AZ with automatic failover
```

**AWS (EKS + Helm):**
```hcl
# infra-aws-ha-k8s-helm/terraform.tfvars — Size XL
node_instance_type      = "r9g.4xlarge"    # 16 vCPU, 128 GB (ARM)
node_group_desired_size = 4                # 4 nodes
node_group_min_size     = 3
node_group_max_size     = 5
nexus_iq_replica_count  = 4                # 4 IQ pods
# Pod CPU, memory and heap are Helm chart values in helm-values.yaml:
# see the Size XL block in infra-aws-ha-k8s-helm/README.md.
aurora_instance_class   = "db.r8g.4xlarge" # 16 vCPU, 128 GB
aurora_instance_count   = 2
```

**Azure (AKS — recommended for XL):**
```hcl
# infra-azure-ha-k8s-helm/terraform.tfvars — Size XL
node_instance_type   = "Standard_E16ps_v6" # 16 vCPU, 128 GB (ARM)
node_group_min_size  = 3
node_group_max_size  = 5
node_group_desired_size = 4                # 4 nodes
nexus_iq_replica_count = 4                 # 4 IQ pods
# The container image and the Java heap are Helm chart values, set in
# helm-values.yaml as iq_server.tag and iq_server.javaOpts.
db_sku_name          = "MO_Standard_E16ds_v6" # 16 vCores, 128 GB
db_storage_mb        = 524288              # 512 GB, grows automatically
db_storage_tier      = "P20"
db_high_availability_mode = "ZoneRedundant" # Required
storage_account_tier = "Premium"           # Required for NFS with AKS
storage_share_quota_gb = 4096              # billed as provisioned on Premium
```

**GCP (MIG HA):**
```hcl
# infra-gcp-ha/terraform.tfvars — Size XL
instance_machine_type = "n4a-highmem-16"   # 16 vCPU, 128 GB (ARM)
iq_target_instances  = 4                   # 4 instances across zones
iq_min_instances     = 3
iq_max_instances     = 5
iq_docker_image      = "sonatype/nexus-iq-server:latest"
java_opts            = "-Xms96g -Xmx96g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/Java_Heap_logs -XX:+CrashOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_instance_tier     = "db-custom-16-65536" # 16 vCPU, 64 GB (Enterprise)
db_availability_type = "REGIONAL"          # Required with automatic failover
db_disk_size         = 512                 # GB, auto-resize to 2 TB
db_max_disk_size     = 2000
filestore_tier       = "BASIC_HDD"         # 10 TiB (1,000 read / 5,000 write IOPS)
filestore_capacity_gb = 10240              # 10 TiB
```

**GCP (GKE + Helm):**
```hcl
# infra-gcp-ha-k8s-helm/terraform.tfvars — Size XL
node_instance_type      = "n4a-highmem-16" # 16 vCPU, 128 GB (ARM)
node_group_min_size     = 3
node_group_max_size     = 5
node_group_desired_size = 4                # 4 nodes
nexus_iq_replica_count  = 4                # 4 IQ pods
# The container image and the Java heap are Helm chart values, set in
# helm-values.yaml as iq_server.tag and iq_server.javaOpts.
db_instance_tier        = "db-custom-16-65536" # 16 vCPU, 64 GB (Enterprise)
db_availability_type    = "REGIONAL"
db_disk_size            = 512              # GB, auto-resize to 2 TB
db_max_disk_size        = 2000
filestore_tier          = "BASIC_HDD"
filestore_capacity_gb   = 10240            # 10 TiB
```

---

### JVM Configuration

Set Java heap to approximately **75% of available RAM**. The following `JAVA_OPTS` are recommended for all deployment sizes:

```
-Xms<HEAP>g -Xmx<HEAP>g
-XX:MaxDirectMemorySize=8g
-XX:+UseG1GC
-XX:+AlwaysPreTouch
-XX:+HeapDumpOnOutOfMemoryError
-XX:HeapDumpPath=/sonatype-work/Java_Heap_logs
-XX:+CrashOnOutOfMemoryError
-Dinsight.threads.monitor=10
```

| Size | Instance Memory | Recommended Heap (-Xms/-Xmx) | MaxDirectMemory | CM Threads |
|------|:--------------:|:----------------------------:|:---------------:|:----------:|
| **XS** | 16 GB | 12 GB | 4 GB | 3 |
| **S** | 32 GB | 24 GB | 6 GB | 5 |
| **M** | 64 GB | 48 GB | 8 GB | 10 |
| **L** | 64 GB | 48 GB | 8 GB | 10 |
| **XL** | 128 GB | 96 GB | 8 GB | 10 |

> **On AWS Fargate, M and L run a 44 GB heap, not 48 GB.** Fargate caps an 8 vCPU task at 60 GB, so a 48 GB heap plus `-XX:MaxDirectMemorySize=8g` would commit 56 GB of the 60, and `-XX:+AlwaysPreTouch` claims the whole heap at startup. 44 GB leaves 8 GB for the JVM's own non-heap memory and the rest of the container. XL keeps its 96 GB heap, which leaves 16 GB of a 120 GB task. S runs a 22 GB heap for the same reason: Fargate caps a 4 vCPU task at 30 GB, and 22 GB plus `-XX:MaxDirectMemorySize=6g` commits 28 GB of the 30.

> **On the three Kubernetes architectures, M and L pods set `-XX:MaxDirectMemorySize=4g`, not 8g.** The pod's memory limit is 56 Gi, so a 48 GB heap plus 8 GB of direct memory would fill it and leave nothing for metaspace and thread stacks. XL pods keep 8g under a 112 Gi limit.

---

### OpenSearch

OpenSearch is part of every reference architecture, and it is required at every size in the sizing
table, though each architecture leaves it off by default with `search_engine = "lucene"`. One cluster serves both of IQ Server's search features: Advanced Search and
the Nexus One index behind the Nexus One list pages, typeahead, and dashboard. IQ Server's `config.yml`
carries a `search:` block and a `nexusOne.connection` block, both naming the same endpoint and
credentials.

Only AWS offers a first-party managed OpenSearch service, so the three AWS architectures point IQ at an
Amazon OpenSearch Service domain and authenticate with SigV4. The Azure and GCP architectures point IQ
at a self-managed cluster on that cloud's own virtual machines and authenticate with a username and
password, which means the customer also chooses the OpenSearch server version and owns upgrades,
snapshots, and node replacement.

#### Which configurations build the cluster, and which take an endpoint

**The three AWS architectures create the domain; the six Azure and GCP ones do not.** With
`search_engine = "opensearch"` and `opensearch_domain_endpoint` left empty, each AWS root creates the
domain itself, and naming an existing domain in that variable creates nothing. Azure and GCP have no
first-party managed OpenSearch service, so those six only take an endpoint and point IQ Server at it.

- **Nothing turns it on for you.** `search_engine` defaults to `lucene` in all nine roots, so a
  deployment that wants either search feature sets `search_engine = "opensearch"`.
- **A cluster you supply has to exist before the deployment is useful.** IQ Server configured against
  an endpoint that answers nothing will not serve search.
- **An index on a cluster you supply survives `terraform destroy`.** Its lifecycle stays independent of
  the IQ deployment, which is also why an upgrade or a redeployment costs no rebuild. A domain the AWS
  roots created carries `prevent_destroy` instead, so a destroy stops rather than deleting the index.

What the architecture needs from you is the endpoint, or on AWS the shape to build the domain at. What
the specification below gives you is what to size it against.

#### Seven indices in one shared cluster

A deployment running both features holds **seven indices on one cluster**: six for the Nexus One index
and one for Advanced Search.

| Index | What it holds |
|-------|---------------|
| `application` | Applications |
| `violation` | Policy violations |
| `waiver` | Policy waivers |
| `component` | Components |
| `vulnerability` | Vulnerabilities |
| `entity` | Organizations, application categories, component labels, policies, users, and license threat groups, which share one index |
| Advanced Search | The Advanced Search index, named from your own index configuration |

The two halves of search behave differently on the same cluster, and it is worth knowing which is
which: IQ Server sends an explicit shard count and replica count for the six Nexus One indices, and it
sends **neither** for the Advanced Search index. So that one index is created on whatever your cluster
would give any index with no settings of its own.

#### Shards: 3 for three indices at M and above

Every Nexus One index is created with **one primary shard** unless configured otherwise. Three of the
six can be raised per tenant, through the configuration API rather than `config.yml`:

| Setting | Index it applies to |
|---------|---------------------|
| `nexusOneIndexComponentShards` | `component` |
| `nexusOneIndexViolationShards` | `violation` |
| `nexusOneIndexVulnerabilityShards` | `vulnerability` |

`application`, `entity`, and `waiver` have no such setting and always get one shard. The three that can
be raised are capped by `nexusOneIndexMaxShards`, which defaults to **12**.

**At M, L and XL every architecture creates these three indices with 3 shards**, and every other index
with 1. At XS and S every index keeps 1. Set the three before the Nexus One index is first built, with
one request to the configuration API as an administrator:

```bash
curl -u admin -X PUT -H 'Content-Type: application/json' \
  -d '{"nexusOneIndexComponentShards": 3, "nexusOneIndexViolationShards": 3, "nexusOneIndexVulnerabilityShards": 3}' \
  https://<your IQ Server URL>/api/v2/config
```

Going past 3 helps only when a read of that index misses its latency target *and*
the cluster has idle CPU for the extra threads; a document count on its own is not evidence, and shard
count sets the minimum heap the cluster needs, so extra shards on a small index spend heap for nothing.

**A shard count applies only when an index is created.** OpenSearch fixes the primary shard count at
creation and an index cannot be resharded, so raising one does nothing to the index a tenant already
has. The order is: set the count, then rebuild the index.

#### Replicas: each architecture sets the count

A replica is a full second copy of every shard. It is what makes losing a data node survivable, and it
costs the disk and the indexing work of that second copy.

**Each architecture writes the replica count itself**, so a reader can see it was chosen. When IQ
Server is not given one, it uses 1:

| Size | OpenSearch data nodes | Replica count |
|------|:---------------------:|:-------------:|
| **XS** | 1 | `0` |
| **S** | 1 | `0` |
| **M** | 3, or 2 on `infra-aws-ha-k8s-helm` | `1` |
| **L** | 3, or 2 on `infra-aws-ha-k8s-helm` | `1` |
| **XL** | 3, or 2 on `infra-aws-ha-k8s-helm` | `1` |

**`0` on a single-node tier is a decision, not an omission.** One data node has nowhere to place a
replica, so asking for one leaves the index permanently yellow for no benefit, which makes a real
problem indistinguishable from this one. It is also not a limitation: a yellow index is created, opens,
takes writes, and returns correct reads, because yellow means every primary shard is assigned and at
least one replica is not. Primaries serve every read and take every write. IQ Server reports no
OpenSearch color as a failure, and the Index Manager's own `HEALTHY` / `WARNING` bands describe how far
behind the index is rather than how the cluster placed its shards.

What a single-node tier does cost you is plain: **losing that node means rebuilding the index.** There
is nothing to fail over to.

A replica can be added to a live index with `PUT <index>/_settings`, so a first choice is not binding.

#### Your cluster's own shard and replica defaults are your choice, and they matter

Because IQ Server sends no shard count and no replica count for the Advanced Search index, that index
gets your cluster's default, or an index template whose pattern matches its name. On a managed AWS
domain the default is AWS's. **On a self-managed cluster it is yours**, which makes it a setting to
choose on purpose rather than one to inherit.

Leave it alone and you can end up with a replica on the Advanced Search index while the Nexus One
indices have none, on the same cluster, with nobody having chosen that. Nothing in IQ Server will tell
you either way, because IQ Server never asks what the index got. Read it off the live index with
`GET <index>/_settings`, never off `config.yml`.

The route to setting it is an index template applied to the cluster, matching the Advanced Search index
name. `cluster.default_number_of_replicas` in `opensearch.yml` is the wrong lever: it takes effect only
on a brand-new cluster and is ignored once the cluster state has persisted a value.

#### Plan for twice the index during a rebuild

A Nexus One index rebuild does not write into the index that is serving. It builds a whole new set of
indices and moves the aliases onto it once every pass has succeeded, then keeps the old set for
**30 minutes** after the cutover so a search already running against it is not destroyed underneath it.
That window is a fixed value in IQ Server with no setting.

So during a rebuild, and for half an hour after it, the cluster holds:

- **Twice the Nexus One shards.** At XS and S, one shard per index, that is 12 primaries rather than
  6. At M, L and XL, with three indices at 3 shards, it is 24 rather than 12. Both are before replicas
  and before the Advanced Search index's own shards.
- **Twice the Nexus One disk**, and twice the document count.

**Judge free disk against the doubled figure, not the steady state.** A cluster that fits the index
with 40% free is full during its own rebuild. Note also that a replica is a *separate* doubling and
applies at the same time.

Two related things worth stating plainly:

- **Reading the index size during a rebuild, or in the half hour after it, gives you the doubled
  number.** Filter to the generation named in the newest cutover log line to see what is really
  serving.
- **A rebuild is not a backup.** A full rebuild of a large estate has been measured at about an hour
  and a half, with search stale or absent throughout. A managed AWS domain takes its own snapshots; a
  self-managed cluster takes whatever you schedule.

#### Per-size cluster specification

**Measured:** every AWS size, Azure M and L, and GCP M. The other sizes are not measured on that
cloud. The GCP M measurement ran 1 shard per index, so the 3 shards at M are not measured on GCP. Storage per node is the published size on every cloud, chosen at or above the measured use.
Every cloud's data node has the same memory at each size, and the same vCPU everywhere except Azure at XS, where `Standard_D2pls_v6`, the smallest Dplsv6 size, has 2 vCPU against 1. The measurements are on
[the OpenSearch sizing pages](https://sonatype.atlassian.net/wiki/spaces/INSIGHT/pages/2866971307).
Each architecture's README carries its own table with the variables that set them.

| Size | Data nodes | AWS | Azure | GCP | Storage per node | Shards ¹ | Replicas |
|------|:----------:|:---:|:-----:|:---:|:----------------:|:--------:|:--------:|
| **XS** | 1 | `m8g.medium.search` | `Standard_D2pls_v6` | `c4a-standard-1` | 25 GB | 1 | `0` |
| **S** | 1 | `m8g.large.search` | `Standard_D2ps_v6` | `c4a-standard-2` | 50 GB | 1 | `0` |
| **M** | 3 ² | `m8g.large.search` | `Standard_D2ps_v6` | `c4a-standard-2` | 100 GB | 3 | `1` |
| **L** | 3 ² | `m8g.xlarge.search` | `Standard_D4ps_v6` | `c4a-standard-4` | 150 GB | 3 | `1` |
| **XL** | 3 ² | `r8g.2xlarge.search` | `Standard_E8ps_v6` | `c4a-highmem-8` | 250 GB | 3 | `1` |

¹ Primary shards for the component, violation and vulnerability indices. Every other index has 1.

² Two on `infra-aws-ha-k8s-helm`, one in each of the two zones it builds. The measurement ran three, so
that count is not measured.

The XL data node is 8 vCPU and 64 GB on every cloud. Azure Premium SSD is billed and performs by fixed
tiers, so the Azure READMEs name the smallest tier at or above each storage figure.

Three dedicated cluster managers run at every size with more than one data node, one per zone where
the architecture builds three zones, and none at XS and S, where the one data node is its own cluster
manager:

| Size | AWS | Azure | GCP |
|------|:---:|:-----:|:---:|
| **XS**, **S** | none | none | none |
| **M** | 3 x `m8g.medium.search` | 3 x `Standard_D2pls_v6`, 2 vCPU, 4 GB | 3 x `c4a-standard-1`, 1 vCPU, 4 GB, 2 GB heap |
| **L** | 3 x `m8g.medium.search` | 3 x `Standard_D2pls_v6`, 2 vCPU, 4 GB | 3 x `c4a-standard-1`, 1 vCPU, 4 GB, 2 GB heap |
| **XL** | 3 x `m8g.large.search` | 3 x `Standard_D2ps_v6`, 2 vCPU, 8 GB | 3 x `c4a-standard-2`, 2 vCPU, 8 GB |

On `infra-aws-ha-k8s-helm`, which builds two zones, one zone holds two of the three managers, so
losing that zone loses their quorum.

The AWS masters are measured at every size and the Azure managers at M and L. The GCP M measurement
ran its managers on `c4a-standard-2`; the published `c4a-standard-1` matches the AWS `m8g.medium.search`.
The rest are chosen at or above the AWS equivalent. Each manager takes half its RAM as heap. The Azure
managers have a 30 GiB P4 Premium SSD OS disk, and the GCP managers a 20 GB Hyperdisk Balanced boot
disk.

**On Azure and GCP, put an internal load balancer in front of the data nodes at M and above**, and set
`opensearch_endpoint` to its address, which is how those measurements ran:

- **GCP**: an internal passthrough Network Load Balancer, with a regional TCP health check on 9200, a
  regional backend service over the data nodes, a forwarding rule on a private IP, and a firewall rule
  allowing TCP 9200 from Google's health check ranges `35.191.0.0/16` and `130.211.0.0/22`. See
  [Internal passthrough Network Load Balancer overview](https://cloud.google.com/load-balancing/docs/internal).
- **Azure**: a Standard SKU internal load balancer, with a TCP health probe on 9200 and an NSG rule
  allowing the `AzureLoadBalancer` service tag on 9200 ahead of the subnet's deny-all rule. The
  OpenSearch VMs also need outbound access to install and update packages, which the measurements
  gave them through a NAT gateway on the OpenSearch subnet. See
  [What is Azure NAT Gateway?](https://learn.microsoft.com/en-us/azure/nat-gateway/nat-overview).
- **Both**, with `opensearch_use_tls = true`: each data node's certificate names the load balancer's
  address in its subject alternative names. The load balancer passes TLS through, so IQ Server checks
  the node's certificate against `opensearch_endpoint`.

The architectures do not create these, because the cluster is yours to build. On AWS the domain's own
endpoint is the one address IQ Server uses. Each architecture's README lists what to create.

#### Checking it worked

| Question | How to check |
|----------|--------------|
| Is search on OpenSearch? | The server log carries `Search backend: OPENSEARCH` at startup |
| Did the indices get the replica count you set? | `GET <index>/_settings` on the cluster, and read `number_of_replicas` |
| Did they get the shard count you set? | The same read, for `number_of_shards`. An out-of-range value is ignored with a warning and the index is created with one shard, so check the log too |
| What did the Advanced Search index get? | The same read on it. IQ Server sends it nothing, so this is the only way to know |
| Is the index healthy? | The Index Manager's Analyze view. Its `HEALTHY` and `WARNING` are about how far behind the index is, not how the cluster placed its shards |

**Read the shard count and the replica count off the live index, never off the configuration.** Both are
applied only when an index is created, and both can differ from what you asked for.

---

### Scaling Guidance

#### CPU Usage Guidelines

| CPU Usage (Aggregate) | Recommendation |
|----------------------|----------------|
| Below 40% | Consider scaling down or increasing CM threads |
| 40% – 70% (Target) | Optimal range with headroom for peaks |
| Above 70% | Scale required — add nodes or migrate to larger instances |

#### Continuous Monitoring Performance

Continuous Monitoring is one of the most resource-intensive operations. The bottleneck is HDS (Hosted Data Services) latency. Set `-Dinsight.threads.monitor=10` to maximize CM throughput.

<!-- TO BE UPDATED (CLM-55927): the ~310 and ~405 evals/hour figures below, and the three per-provider
     "Expected throughput" rows that repeat them, are awaiting a re-measurement. Leave the numbers
     alone until it lands, and keep the qualifier on those three rows that they are measured with
     continuous monitoring running, so a reader of a provider table does not take them as general
     evaluation throughput. -->

| Instance | CM Threads | 1,000 Apps CM Duration | Concurrent Eval Throughput |
|----------|:----------:|:----------------------:|:--------------------------:|
| 8 vCPU / 64 GB (M/L) | 10 | ~11.5 hours | ~310 evals/hour |
| 16 vCPU / 128 GB (XL) | 10 | ~7.5 hours | ~405 evals/hour |

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
| **Lower initial cost** | Yes | No | No |
| **Best for sizes** | XS, S | M, L, XL | M, L, XL |

### Networking

All architectures create their own VPC/VNet with:
- Public subnets (load balancer)
- Private subnets (compute)
- Database subnets (isolated)
- NAT Gateway / Cloud NAT for outbound access

### Security

- **Secrets**: AWS Secrets Manager / Azure Key Vault / GCP Secret Manager
- **Encryption**: All databases and storage encrypted at rest
- **Network**: Security groups restrict access; compute runs in private subnets
- **Identity**: IAM roles (AWS), Managed Identity (Azure), Workload Identity (GCP)

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
3. Default credentials: `admin` / `admin123`
4. **Change the default password immediately**

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

## Troubleshooting

| Issue | Possible Cause | Solution |
|-------|---------------|----------|
| Container fails to start | Database not yet available | Wait 5-10 minutes for database provisioning to complete |
| Connection timeout to UI | Security group/firewall rules | Verify ports 80/443 allow inbound from your IP |
| `OutOfMemoryError` | Heap exceeds container memory | Ensure heap is ≤75% of allocated memory |
| Database connection refused | Credentials mismatch | Verify database password in secrets manager |
| Clustering not working | Missing HA license | Install an HA-capable license for multi-node deployments |
| Slow evaluations | CM threads set to default (1) | Set `-Dinsight.threads.monitor=10` in JAVA_OPTS |
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

To avoid ongoing cloud charges, destroy all resources when no longer needed:

```bash
# For Kubernetes deployments: uninstall Helm release first
./helm-uninstall.sh

# Destroy all Terraform-managed infrastructure
./tf-destroy.sh
```

> **WARNING:** This permanently deletes all infrastructure and data. Ensure you have backups of any important data (database exports, reports, configuration) before proceeding.

> **Your OpenSearch cluster is not deleted by this.** On Azure and GCP nothing here created the cluster, so `terraform destroy` does not delete it or its indices; remove it separately when you no longer need it. A domain the AWS architectures created carries `prevent_destroy`, so the destroy stops rather than deleting the index, and each AWS README's OpenSearch section has the steps that remove it deliberately.

If `terraform destroy` fails due to deletion protection:
1. Set `deletion_protection = false` in your variables
2. Run `terraform apply` to update the setting
3. Run `./tf-destroy.sh` again

---

## Additional Resources

### Sonatype Documentation
- [IQ Server Documentation](https://help.sonatype.com/iqserver)
- [IQ Server Installation Guide](https://help.sonatype.com/iqserver/install)
- [Sonatype Helm Charts](https://github.com/sonatype/helm3-charts)
- [Docker Hub — nexus-iq-server](https://hub.docker.com/r/sonatype/nexus-iq-server)

### Cloud Provider Documentation
- [AWS Documentation](https://docs.aws.amazon.com)
- [Azure Documentation](https://docs.microsoft.com/azure)
- [Google Cloud Documentation](https://cloud.google.com/docs)

### Terraform Documentation
- [Terraform](https://terraform.io/docs)
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
