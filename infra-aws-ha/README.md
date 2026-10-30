# Sonatype IQ Reference Architecture - AWS Cloud-Native (High Availability)

This directory contains Terraform configuration for deploying Sonatype IQ Server on AWS using ECS Fargate in a **High Availability configuration** with auto-scaling and multi-AZ deployment.

---

## Sizing Guide

This HA architecture supports sizes **M**, **L**, and **XL**. Choose your size based on application count and daily evaluation volume:

| Size | Applications | Evaluations/Day | Nodes | Compute (per node) | Java Heap | Instance Type |
|------|:------------:|:---------------:|:-----:|:-------------------:|:---------:|:-------------:|
| **M** | 2,000 – 10,000 | 5,000 – 10,000 | 2 | 8 vCPU / 60 GB | 44 GB | Fargate (8192 CPU / 61440 MEM) |
| **L** | 10,000 – 20,000 | 10,000 – 20,000 | 3 | 8 vCPU / 60 GB | 44 GB | Fargate (8192 CPU / 61440 MEM) |
| **XL** | 20,000 – 80,000 | 20,000+ | 4 | 16 vCPU / 120 GB | 96 GB | Fargate (16384 CPU / 122880 MEM) |

> Expected throughput: ~310 evals/hour/node (M/L) or ~405 evals/hour/node (XL), from performance testing of these sizes. That testing ran on GCP ARM instances, `n4a-highmem-8` at 8 vCPU and 64 GB with a 48 GB heap for M and L, and `n4a-highmem-16` at 16 vCPU and 128 GB with a 96 GB heap for XL, not on Fargate tasks. The 60 GB task and 44 GB heap above are the nearest shape Fargate allows, so treat the figures as indicative rather than measured at those values.

> **Why a 44 GB heap at M and L?** Fargate caps an 8 vCPU task at 60 GB, so a 48 GB heap plus `-XX:MaxDirectMemorySize=8g` would commit 56 GB of the 60, and `-XX:+AlwaysPreTouch` claims the whole heap at startup. 44 GB leaves 8 GB for the JVM's own non-heap memory and the rest of the container. XL keeps 96 GB, which leaves 16 GB of its 120 GB task.

> **Smaller deployments?** For < 2,000 applications with a single instance, use the [Single Instance](../infra-aws/) architecture.

### Recommended `terraform.tfvars` by Size

<details>
<summary><strong>Size M</strong> — Medium (2,000 – 10,000 applications, 2 nodes)</summary>

```hcl
ecs_cpu              = 8192                # 8 vCPU
ecs_memory           = 61440               # 60 GB, the maximum at 8 vCPU
iq_desired_count     = 2                   # 2 nodes for HA
iq_min_count         = 2
iq_max_count         = 3
iq_docker_image      = "sonatype/nexus-iq-server:latest"
java_opts            = "-Xms44g -Xmx44g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/Java_Heap_logs -XX:+CrashOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
aurora_instance_class = "db.r6g.2xlarge"   # 8 vCPU, 64 GB
aurora_instances      = 2                  # Multi-AZ
```
</details>

<details>
<summary><strong>Size L</strong> — Large (10,000 – 20,000 applications, 3 nodes)</summary>

```hcl
ecs_cpu              = 8192                # 8 vCPU
ecs_memory           = 61440               # 60 GB, the maximum at 8 vCPU
iq_desired_count     = 3                   # 3 nodes recommended
iq_min_count         = 2
iq_max_count         = 4
iq_docker_image      = "sonatype/nexus-iq-server:latest"
java_opts            = "-Xms44g -Xmx44g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/Java_Heap_logs -XX:+CrashOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
aurora_instance_class = "db.r6g.2xlarge"   # 8 vCPU, 64 GB
aurora_instances      = 2                  # Multi-AZ with failover
```
</details>

<details>
<summary><strong>Size XL</strong> — Extra Large (20,000 – 80,000 applications, 4 nodes)</summary>

```hcl
ecs_cpu              = 16384               # 16 vCPU
ecs_memory           = 122880              # 120 GB, the maximum at 16 vCPU
iq_desired_count     = 4                   # 4 nodes for XL
iq_min_count         = 3
iq_max_count         = 5
iq_docker_image      = "sonatype/nexus-iq-server:latest"
java_opts            = "-Xms96g -Xmx96g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/Java_Heap_logs -XX:+CrashOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
aurora_instance_class = "db.r6g.4xlarge"   # 16 vCPU, 128 GB
aurora_instances      = 2                  # Multi-AZ with automatic failover
```
</details>

### Database Sizing

| Size | Aurora Instance Class | vCPU | Memory | Storage |
|------|:--------------------|:----:|:------:|:-------:|
| **M** | db.r6g.2xlarge | 8 | 64 GB | 100 GB (auto-scales to 500 GB) |
| **L** | db.r6g.2xlarge | 8 | 64 GB | 200 GB – 1 TB auto-scaling |
| **XL** | db.r6g.4xlarge | 16 | 128 GB | 500 GB – 2 TB auto-scaling |

### Shared Storage (EFS)

| Size | Throughput Mode | Estimated Capacity | Cost Optimization |
|------|:---------------|:------------------:|:-----------------|
| **M** | Elastic | 200 GB – 500 GB | Lifecycle policies: 30-day move to IA |
| **L** | Elastic | 500 GB – 1.5 TB | Lifecycle policies: 30-day move to IA |
| **XL** | Elastic | 1.5 TB – 4 TB | Lifecycle policies: 30-day move to IA |

---

## OpenSearch for the Nexus One Index

Sonatype IQ Server can keep its Nexus One index in an AWS-managed OpenSearch
domain instead of the index built into the server. Set `search_engine` to
`opensearch` and give it the domain to use:

```hcl
search_engine              = "opensearch"
opensearch_domain_endpoint = "search-my-domain-abc123.us-east-1.es.amazonaws.com"
opensearch_domain_name     = "my-domain"
opensearch_index_replicas  = 1
```

`search_engine = "lucene"` is the default and needs none of the other three.

**On this architecture OpenSearch is the index that every task shares.** The
built-in index lives on each task's own storage, so a cluster of tasks keeps a
copy each and each copy is rebuilt separately. An OpenSearch domain is one
index all the tasks read and write, which is why it matters more here than on
the single-instance architecture.

### This configuration does not create the domain

You create the domain, and you give its host name to Terraform. That is
deliberate. The domain holds the index, so leaving it outside this
configuration means switching engines, replacing the ECS service or running
`terraform destroy` here never deletes indexed data, and you can resize,
upgrade and back the domain up on its own schedule.

Two things the domain needs:

- **It must be reachable from the ECS tasks.** Put it in the same VPC, across
  the private subnets, and allow inbound 443 from the task security group.
  Turn zone awareness on so the domain survives losing an Availability Zone,
  which is the point of this architecture.
- **Leave fine-grained access control off.** IQ Server signs its requests with
  SigV4 using the ECS task role, and Terraform grants that role `es:ESHttp*`
  on the domain you named. Add the task role ARN to the domain's access
  policy, which the `ecs_task_role_arn` output gives you.

**Fine-grained access control has to stay off for as long as the domain holds this
index.** Turning it on gives the domain an internal user database and changes how
every request is authenticated, so SigV4 alone no longer reaches it and IQ Server's
`type: aws` configuration stops working. There is no credential to supply instead:
this architecture authenticates with the ECS task role and nothing else.

### Domain shape per size

**Not published yet.** The node count, node type and storage each size needs
are being measured under
[CLM-55930](https://sonatype.atlassian.net/browse/CLM-55930), and this section
is filled in once that reports. Size the domain yourself until then.

The replica count is measured on the same ticket:

| Size | `opensearch_index_replicas` |
|------|:---------------------------:|
| **M** | **pending CLM-55930** |
| **L** | **pending CLM-55930** |
| **XL** | **pending CLM-55930** |

Every size here runs more than one IQ Server task and should run more than one
data node, so a replica can be placed. Until the measured value is published,
set it from your own availability requirement: at 0 replicas a lost data node
means the index is rebuilt rather than recovered, and a rebuild of a large
index takes over an hour.

### What Terraform writes into `config.yml`

```yaml
search:
  type: aws
  mode: OPENSEARCH
  domain: https://<opensearch_domain_endpoint>
  region: <aws_region>
  nexusOneIndexReplicas: <opensearch_index_replicas>
```

- **`type: aws`** signs every request with SigV4 through the task role.
  `type: http` always sends a user name and password, which a domain with
  fine-grained access control off has no way to check.
- **`mode: OPENSEARCH`** is written out rather than left to default. The
  default is `HYBRID`, which also writes every batch to the built-in index.
- **`nexusOneIndexReplicas`** is always written, because IQ Server's own
  default is 0 and this configuration states the value rather than inheriting
  it.

Shard counts are held in IQ Server's database, not in `config.yml`, and a
shard count only takes effect when an index is created.

---

## Deployment Guide

### Step 1: Prerequisites

#### Required Tools
Install these tools on your local machine:

| Tool | Version | Installation | Purpose |
|------|---------|--------------|---------|
| **Terraform** | >= 1.0 | [Install Guide](https://developer.hashicorp.com/terraform/install) | Infrastructure as Code |
| **AWS CLI** | >= 2.0 | [Install Guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) | AWS API access |
| **aws-vault** | Latest | [Install Guide](https://github.com/99designs/aws-vault#installing) | Secure credential management |

#### AWS Account Requirements
- AWS account with administrative access (or sufficient permissions listed below)
- IAM user with MFA enabled
- Ability to create: VPC, ECS, RDS Aurora, EFS, ALB, IAM roles

#### Required AWS Permissions
Your IAM user/role needs these AWS service permissions:
- **EC2**: VPC, subnets, security groups, network interfaces, EIPs, NAT gateways, route tables
- **ECS**: Clusters, task definitions, services, container insights
- **RDS**: Aurora clusters, instances, subnet groups, parameter groups
- **EFS**: File systems, mount targets, access points, backup policies
- **ELB**: Application Load Balancers, target groups, listeners
- **IAM**: Roles, policies, instance profiles
- **Application Auto Scaling**: Scaling policies and targets for ECS services
- **Cloud Map**: Service discovery private DNS namespaces and services
- **Backup**: Backup vaults, plans, selections for EFS
- **KMS**: Keys and aliases for encryption (Aurora, EFS, Backup)
- **Logs**: CloudWatch log groups and streams
- **Secrets Manager**: Secrets creation and management
- **SSM Parameter Store**: Parameters for storing Fluent Bit configuration
- **S3**: ALB logs storage, log archival (optional), Terraform state storage (if using remote state)

### Step 2: Configure AWS Credentials

**The provided scripts use aws-vault for secure credential management.**

1. **Choose a profile name** (e.g., `nexus-iq-deployment`)

2. **Configure your AWS profile in `~/.aws/config`:**
   ```ini
   [profile nexus-iq-deployment]
   region = us-east-1
   output = json
   mfa_serial = arn:aws:iam::<YOUR_ACCOUNT_ID>:mfa/<YOUR-USERNAME>
   ```

3. **Add credentials to aws-vault and test:**
   ```bash
   aws-vault add nexus-iq-deployment
   ```
   Enter your AWS Access Key ID and Secret Access Key when prompted

   ```bash
   aws-vault exec nexus-iq-deployment -- aws sts get-caller-identity
   ```
   You should see your AWS account details.

4. **Set the AWS_PROFILE environment variable:**

   The scripts require the `AWS_PROFILE` environment variable to be set:

   Option 1: Export for your entire session
   ```bash
   export AWS_PROFILE=nexus-iq-deployment
   export AWS_REGION=us-east-1  # Optional: override default region
   ```

   Option 2: Set inline for a single command
   ```bash
   AWS_PROFILE=nexus-iq-deployment <script>
   ```

### Step 3: Configure Terraform Variables

1. **Copy the example configuration:**
   ```bash
   cd /path/to/sca-example-terraform/infra-aws-ha
   cp terraform.tfvars.example terraform.tfvars
   ```

2. **Edit `terraform.tfvars` with your values (or leave to get started quickly):**
   ```bash
   vi terraform.tfvars
   ```

### Step 4: Deploy Infrastructure

1. **Initialize Terraform:**
   ```bash
   terraform init
   ```

   This downloads required providers (AWS, etc.)

2. **Review the deployment plan:**
   ```bash
   ./tf-plan.sh
   ```

   This shows what resources will be created without actually deploying them.

3. **Deploy the infrastructure:**
   ```bash
   ./tf-apply.sh
   ```

   The script will display the application URL when complete.

### Step 5: Access Sonatype IQ Server

1. **Wait for service to be ready:**
   - Initial startup can take 10-15 minutes
   - All instances must complete database migrations and clustering setup

2. **Access the web UI:**

   Use the application URL displayed at the end of the deployment.

   Example: `http://ref-arch-iq-ha-cluster-alb-123456789.us-east-1.elb.amazonaws.com`

3. **Login credentials:**
   - **Username:** `admin`
   - **Password:** `admin123` (change immediately!)

---

## Teardown / Cleanup

**WARNING: This will delete ALL infrastructure and data!**

1. **Destroy all resources:**
   ```bash
   ./tf-destroy.sh
   ```

   > **Keep the terminal open** - If you close it mid-destroy, the process will potentially stop and leave resources partially deleted.

---

## Configuration

> **Upgrading an existing deployment.** These variable defaults changed with the
> published sizing. A deployment whose `terraform.tfvars` does not set a variable
> picks up the new default on its next apply. Set the values your deployment is
> running at in `terraform.tfvars` before applying.
>
> | Variable | Previous default | New default |
> |---|:---:|:---:|
> | `iq_max_count` | 5 | 4 |
> | `aurora_engine_version` | 15.10 | 15.19 |

### Configuration Variables

Edit `terraform.tfvars` to customize your deployment. The task counts below are the Size L values from
the [Sizing Guide](#sizing-guide); use the per-size block for your own size instead of copying these.

```hcl
# General Configuration
aws_region   = "us-east-1"
cluster_name = "ref-arch-iq-ha-cluster"

# Network Configuration
vpc_cidr               = "10.0.0.0/16"
public_subnet_cidrs    = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
private_subnet_cidrs   = ["10.0.10.0/24", "10.0.20.0/24", "10.0.30.0/24"]
db_subnet_cidrs        = ["10.0.40.0/24", "10.0.50.0/24", "10.0.60.0/24"]
enable_nat_gateway     = true

# ECS Configuration
ecs_cpu                 = 8192   # 8 vCPU
ecs_memory              = 32768  # 32 GB
ecs_memory_reservation  = 24576  # 24 GB soft limit

# IQ Server Configuration
iq_desired_count        = 3
iq_min_count           = 2
iq_max_count           = 4
iq_cpu_target_value    = 70  # CPU target for auto scaling (%)
iq_memory_target_value = 80  # Memory target for auto scaling (%)
iq_docker_image        = "sonatype/nexus-iq-server:latest"
java_opts              = "-Xms24g -Xmx24g -XX:+UseG1GC -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"

# Database Configuration (Aurora PostgreSQL)
db_name                     = "nexusiq"
db_username                 = "nexusiq"
db_password                 = "CHANGE_ME_STRONG_PASSWORD"  # Change this!
aurora_engine_version       = "15.19"
aurora_instance_class       = "db.r6g.4xlarge"
aurora_instances            = 2
db_backup_retention_period  = 7
db_backup_window           = "03:00-04:00"
db_maintenance_window      = "sun:04:00-sun:05:00"
db_skip_final_snapshot     = true
db_deletion_protection     = false

# Load Balancer Configuration
# ssl_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
alb_deletion_protection = false

# EFS Configuration
efs_throughput_mode                  = "provisioned"
efs_provisioned_throughput_in_mibps = 100

# Monitoring Configuration
enable_container_insights = true
enable_prometheus        = true
log_retention_days       = 30

# Search Backend (optional)
# "lucene" (default) uses the index built into IQ Server. "opensearch" points
# IQ Server at an OpenSearch domain that already exists, which this
# configuration does not create. See the OpenSearch section above.
search_engine = "lucene"
# opensearch_domain_endpoint = "search-my-domain-abc123.us-east-1.es.amazonaws.com"
# opensearch_domain_name     = "my-domain"
# opensearch_index_replicas  = 1
```

**Important Settings:**
- **`iq_desired_count = 3`** - Initial number of tasks, the Size L value. Size M uses 2 and Size XL uses 4
- **`iq_min_count = 2`** - Minimum auto scaling capacity, the Size M and L value. Size XL uses 3, and every size must be at least 2 for HA
- **`iq_max_count = 4`** - Maximum auto scaling capacity, the Size L value. Size M uses 3 and Size XL uses 5
- **`aurora_instances = 2`** - Number of Aurora instances (minimum 2 for HA)
- **`db_password`** - Use a strong, unique password (required change)
- **`db_deletion_protection = false`** - Set to `true` for production to prevent accidental database deletion
- **`db_skip_final_snapshot = true`** - Set to `false` for production to create a final backup snapshot before database deletion
- **`alb_deletion_protection = false`** - Set to `true` for production use
- **Resource Names** - Controlled by `cluster_name` variable, which defaults to `ref-arch-iq-ha-cluster`. **Give each deployment its own value to run more than one in a single AWS account**, since the load balancer, target groups, IAM roles, log group, SSM parameters, Secrets Manager secret and Aurora cluster identifier all have to be unique. One value per size, for example `ref-arch-m-cluster` through `ref-arch-xl-cluster`, is the intended use.

### Custom Clustering Solution

This deployment solves critical IQ Server clustering challenges:

- **Work Directory Conflicts**: Each task gets unique `/sonatype-work/clm-server-${HOSTNAME}` directory
- **Database Sharing**: Custom config.yml generation ensures all instances connect to shared Aurora cluster
- **Cluster Coordination**: Shared `/sonatype-work/clm-cluster` directory for coordination
- **Dynamic Configuration**: config.yml generated per task with proper database configuration

**Important**: Ensure your Sonatype IQ Server license supports clustering for HA deployments.

## Security Features

- **VPC Isolation**: Application runs in private subnets across multiple AZs
- **Database Security**: Aurora cluster in isolated database subnets with Multi-AZ deployment
- **Secrets Management**: Database credentials stored in AWS Secrets Manager
- **Encryption**:
  - EFS encrypted at rest and in transit
  - Aurora encrypted at rest
  - S3 ALB logs encrypted
- **Security Groups**: Least-privilege network access
- **Work Directory Isolation**: Unique work directories per task prevent clustering conflicts

## Reliability and Backup

This is a **High Availability** deployment with comprehensive reliability features:

- **Multi-AZ Deployment**: ECS tasks and Aurora instances distributed across multiple availability zones
- **Auto Scaling**: ECS service scales between the minimum and maximum task counts for your size based on CPU/memory utilization. Size M is 2 to 3, Size L is 2 to 4, Size XL is 3 to 5
- **Aurora Cluster**: Multi-AZ database deployment with automatic failover (~30 seconds)
- **Automatic Restart**: ECS automatically restarts failed containers
- **Load Balancing**: ALB distributes traffic across healthy containers
- **Rolling Deployments**: Zero-downtime updates with 50% minimum healthy capacity
- **Database Backups**: Automated Aurora backups with 7-day retention (configurable)
- **EFS Backups**: Automated EFS backup with daily and weekly policies via AWS Backup
- **EFS Persistence**: Application data stored on EFS survives container restarts
- **Service Discovery**: Internal DNS for efficient inter-service communication

## Monitoring and Logging

This deployment includes **production-grade logging** with a unified CloudWatch approach:

### Structured Logging with Fluent Bit
- **Fluent Bit Sidecar**: Lightweight log processor running alongside each IQ Server task
- **5 Log Types Collected**: Application, request, audit, policy-violation, stderr
- **Aggregated to One CloudWatch Log Group**: All logs sent to `/ecs/${cluster_name}/nexus-iq-server`
- **Separated by Stream Prefix**: Each log type has its own stream prefix for easy filtering
- **Dual Output**: Logs written to both CloudWatch AND EFS for persistence

### CloudWatch Unified Log Group
- **Log Group**: `/ecs/${cluster_name}/nexus-iq-server`
- **Log Streams** (organized by prefix):
  - `application/` - Main IQ Server logs with multiline parsing
  - `request/` - HTTP request logs with field extraction
  - `audit/` - Audit events (JSON format)
  - `policy-violation/` - Policy violations (JSON format)
  - `stderr/` - System.err output for debugging
  - `fluent-bit/` - Fluent Bit internal logs

### EFS Aggregated Logs
- **Location**: `/var/log/nexus-iq-server/aggregated/`
- **Format**: JSON with ECS metadata enrichment

### Additional Monitoring
- **Container Insights**: ECS cluster monitoring enabled
- **Aurora Monitoring**: Performance Insights and Enhanced Monitoring enabled
- **Auto Scaling Metrics**: CPU and memory utilization tracking
- **ALB Access Logs**: Load balancer access logs stored in S3

## Persistent Storage

- **EFS File System**: Shared storage for clustering with unique work directories
- **Aurora Database**: PostgreSQL cluster for application data with continuous backups
- **Auto-scaling Storage**: Aurora storage scales automatically
- **AWS Backup**: Automated EFS backup with daily/weekly retention policies

## Networking

### Subnets
- **Public Subnets**: Load balancer and NAT gateways across multiple AZs
- **Private Subnets**: ECS Fargate tasks across multiple AZs
- **Database Subnets**: Aurora cluster instances (no internet access)

### Security Groups
- **ALB**: Allows HTTP (80) and HTTPS (443) from internet
- **ECS**: Allows traffic from ALB on port 8070, inter-task communication
- **Aurora**: Allows PostgreSQL (5432) from ECS tasks only
- **EFS**: Allows NFS (2049) from ECS tasks only

