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
| [Terraform](https://terraform.io/downloads) | >= 1.0 | All deployments |
| [AWS CLI](https://aws.amazon.com/cli/) | Latest | AWS deployments |
| [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) | Latest | Azure deployments |
| [Google Cloud CLI](https://cloud.google.com/sdk/docs/install) | Latest | GCP deployments |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | Latest | Kubernetes deployments only |
| [Helm](https://helm.sh/docs/intro/install/) | >= 3.9.3 | Kubernetes deployments only |

### IQ Server Requirements

- **Docker Image**: `sonatype/nexus-iq-server` ([Docker Hub](https://hub.docker.com/r/sonatype/nexus-iq-server))
- **License**: Standard license for single instance; HA-capable license for multi-node deployments
- **PostgreSQL**: Minimum PostgreSQL 16. Recommended, and the default for new deployments, PostgreSQL 18. Provisioned automatically by Terraform

### SSL Certificate (Optional)

For HTTPS access, prepare:
- **AWS**: ACM certificate ARN
- **Azure**: Application Gateway certificate or Key Vault reference
- **GCP**: Google-managed or self-managed SSL certificate

---

## Quick Start (5 Minutes to Deploy)

### Sizing Guide

Choose your deployment size based on your application count and daily evaluation volume:

| Size | Applications | Evaluations/Day | Nodes | Compute (per node) | Java Heap | HA Required |
|------|:------------:|:---------------:|:-----:|:-------------------:|:---------:|:-----------:|
| **XS** ¹ | < 500 | < 1,000 | 1 | 2 vCPU / 16 GB | 12 GB | No |
| **S** ¹ | 500 – 2,000 | 1,000 – 5,000 | 1 | 4 vCPU / 32 GB | 24 GB | No |
| **M** | 2,000 – 10,000 | 5,000 – 10,000 | 2 | 8 vCPU / 64 GB | 48 GB | Recommended |
| **L** | 10,000 – 20,000 | 10,000 – 20,000 | 3 | 8 vCPU / 64 GB | 48 GB | Required |
| **XL** | 20,000 – 80,000 | 20,000+ | 4 | 16 vCPU / 128 GB | 96 GB | Required |

> ¹ XS and S are projected sizing estimates. M, L, and XL have been validated through performance testing, which ran on the GCP ARM instances below: `n4a-highmem-8` at 8 vCPU and 64 GB with a 48 GB heap for M and L, and `n4a-highmem-16` at 16 vCPU and 128 GB with a 96 GB heap for XL.

> **Note:** M and L use the same per-node specification (8 vCPU / 64 GB). The difference is the number of load-balanced nodes (2 vs 3), not the machine size. XL requires larger instances (16 vCPU / 128 GB) to handle concurrent continuous monitoring, policy evaluations, and larger heap requirements.

> **AWS Fargate is the one exception to the memory column.** A Fargate task size has to be one of the CPU and memory pairs Fargate allows, and those stop at 30 GB for 4 vCPU, 60 GB for 8 vCPU and 120 GB for 16 vCPU ([task CPU and memory](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/fargate-tasks-services.html)). So `infra-aws` runs a 30 GB task with a 22 GB heap at S, `infra-aws` and `infra-aws-ha` run a 60 GB task with a 44 GB heap at M and L, and `infra-aws-ha` a 120 GB task with a 96 GB heap at XL. Azure, GCP, and the EKS node groups use the 64 GB and 128 GB sizes above.

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

### Step 2: Configure Your Deployment

```bash
git clone https://github.com/sonatype/sca-reference-architectures.git
cd sca-reference-architectures/<your-chosen-architecture>

# Copy and edit the example variables file
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values (region, instance sizes, passwords, etc.)
```

### Step 3: Deploy

```bash
terraform init
./tf-plan.sh    # Review the execution plan
./tf-apply.sh   # Deploy infrastructure
```

For **Kubernetes deployments**, also run:

```bash
./helm-install.sh   # Deploy IQ Server via Helm chart
```

### Step 4: Get Your Access Information

```bash
terraform output
```

This displays the load balancer URL, database endpoint, and other access details.

### Step 5: Access IQ Server

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
| **Expected throughput** | ~310 evals/hour/node (~7,440/day/node) | ~310 evals/hour/node (~14,880–22,320/day total) | ~405 evals/hour/node (~29,160–38,880/day total) |
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
| **Expected throughput** | ~310 evals/hour/node (~7,440/day/node) | ~310 evals/hour/node (~14,880–22,320/day total) | ~405 evals/hour/node (~29,160–38,880/day total) |
| **Compute** | | | |
| Instance type | Standard_E8ps_v6 (ARM) or Standard_E8_v5 (x86) | Standard_E8ps_v6 (ARM) or Standard_E8_v5 (x86) | Standard_E16ps_v6 (ARM) or Standard_E16_v5 (x86) |
| vCPUs | 8 | 8 | 16 |
| Memory | 64 GB | 64 GB | 128 GB |
| Java Heap | `-Xms48g -Xmx48g` | `-Xms48g -Xmx48g` | `-Xms96g -Xmx96g` |
| Deployment option | Azure Container Apps or AKS | Azure Container Apps or AKS | AKS recommended at this scale |
| **Database** | | | |
| Service | Azure Database for PostgreSQL — Flexible Server | Azure Database for PostgreSQL — Flexible Server | Azure Database for PostgreSQL — Flexible Server |
| PostgreSQL version | Minimum 16, recommended and default 18 | Minimum 16, recommended and default 18 | Minimum 16, recommended and default 18 |
| SKU | GP_Standard_D8s_v3 (8 vCores, 32 GB) | GP_Standard_D8s_v3 (8 vCores, 32 GB) | MO_Standard_E16s_v3 (16 vCores, 128 GB) |
| Storage | 128 GB, auto-grow | 256 GB, auto-grow to 1 TB | 512 GB, auto-grow to 2 TB |
| Zone redundancy | Recommended | Required | Required with automatic failover |
| **Storage** | | | |
| Service | Azure Files, Standard HDD on Container Apps, Premium SSD with NFS on AKS | Azure Files, Standard HDD on Container Apps, Premium SSD with NFS on AKS | Azure Files, Premium SSD (SMB on Container Apps, NFS on AKS) |
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
| **Expected throughput** | ~310 evals/hour/node (~7,440/day/node) | ~310 evals/hour/node (~14,880–22,320/day total) | ~405 evals/hour/node (~29,160–38,880/day total) |
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

> **Note on GCP storage tiers:** BASIC_HDD is the default recommendation. At 10+ TiB, HDD unlocks 5,000 write IOPS at roughly the same cost as 2.5 TiB SSD. Use BASIC_SSD when storage needs are small (< 2.5 TiB) but IOPS demand is high, or when sub-millisecond disk latency is required. Enterprise edition Cloud SQL (not Enterprise Plus) is sufficient.

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
| **Azure** | Standard_E8_v5 | x86_64 |

#### Size XL (16 vCPU / 128 GB)

| Cloud Provider | Instance Type | Architecture |
|----------------|---------------|--------------|
| **GCP** | n4a-highmem-16 | ARM (Google Axion) |
| **AWS** | r8g.4xlarge or newer, r9g.4xlarge on EKS | ARM (Graviton4 or newer) |
| **AWS** | r8i.4xlarge | x86_64 |
| **Azure** | Standard_E16ps_v6 | ARM (Azure Cobalt 100) |
| **Azure** | Standard_E16_v5 | x86_64 |

#### Database Instance Comparison

| Size | GCP | AWS | Azure |
|------|-----|-----|-------|
| **M** (2 nodes) | db-custom-8-30720 Enterprise (8 vCPU, 30 GB) | db.r8g.2xlarge (8 vCPU, 64 GB) | GP_Standard_D8s_v3 (8 vCores, 32 GB) |
| **L** (3 nodes) | db-custom-8-30720 Enterprise (8 vCPU, 30 GB) | db.r8g.2xlarge (8 vCPU, 64 GB) | GP_Standard_D8s_v3 (8 vCores, 32 GB) |
| **XL** (4 nodes) | db-custom-16-65536 Enterprise (16 vCPU, 64 GB) | db.r8g.4xlarge (16 vCPU, 128 GB) | MO_Standard_E16s_v3 (16 vCores, 128 GB) |

> **DB sizing scales with node count, not application count.** The database was not a bottleneck during testing. XL needs 16 vCPU primarily for connection pool aggregation from 4 nodes (~560 peak connections), not query complexity.

> **ARM instances recommended.** At 8 vCPU and 64 GB, the ARM instances cost less on demand than their x86 equivalents, at list prices in November 2026: 15% less on GCP (`n4a-highmem-8` against `n4-highmem-8`, us-central1), 8% less on AWS (`r9g.2xlarge` against `r8i.2xlarge`, us-east-1) and 30% less on Azure (`Standard_E8ps_v6` against `Standard_E8s_v6`, eastus). These are price differences, not measured price-performance. If using x86_64 instances, verify performance characteristics are similar.

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
iq_docker_image      = "sonatype/nexus-iq-server:latest"
java_opts            = "-Xms12g -Xmx12g -XX:MaxDirectMemorySize=4g -XX:+UseG1GC -XX:+AlwaysPreTouch -Dinsight.threads.monitor=3 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_sku_name          = "GP_Standard_D2ds_v6" # 2 vCores, 8 GB
db_storage_mb        = 51200               # 50 GB
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
iq_docker_image      = "sonatype/nexus-iq-server:latest"
java_opts            = "-Xms24g -Xmx24g -XX:MaxDirectMemorySize=6g -XX:+UseG1GC -XX:+AlwaysPreTouch -Dinsight.threads.monitor=5 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_sku_name          = "GP_Standard_D2s_v3" # 2 vCores, 8 GB
db_storage_mb        = 102400              # 100 GB
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
db_sku_name          = "GP_Standard_D8s_v3" # 8 vCores, 32 GB
db_storage_mb        = 102400              # 100 GB, infra-azure only; infra-azure-ha fixes its storage at 64 GB
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
nexus_iq_memory_request = "48Gi"
nexus_iq_memory_limit   = "56Gi"
nexus_iq_cpu_request    = "6"
nexus_iq_cpu_limit      = "8"
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
db_sku_name          = "GP_Standard_D8s_v3" # 8 vCores, 32 GB
db_high_availability_mode = "ZoneRedundant" # Required for L
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
nexus_iq_memory_request = "96Gi"
nexus_iq_memory_limit   = "112Gi"
nexus_iq_cpu_request    = "12"
nexus_iq_cpu_limit      = "16"
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
db_sku_name          = "MO_Standard_E16s_v3" # 16 vCores, 128 GB
db_high_availability_mode = "ZoneRedundant" # Required
storage_account_tier = "Premium"           # Required for NFS with AKS
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
