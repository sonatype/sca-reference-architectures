# Sonatype IQ Reference Architecture - AWS Cloud-Native (Single Instance)

This directory contains Terraform configuration for deploying a **single-instance** Sonatype IQ Server on AWS using ECS Fargate.

---

## Sizing Guide

This single-instance architecture supports sizes **XS**, **S**, and **M**. Choose your size based on application count and daily evaluation volume:

| Size | Applications | Evaluations/Day | Compute | Java Heap | Instance Type |
|------|:------------:|:---------------:|:-------:|:---------:|:-------------:|
| **XS** ¹ | < 500 | < 1,000 | 2 vCPU / 16 GB | 12 GB | Fargate (2048 CPU / 16384 MEM) |
| **S** ¹ | 500 – 2,000 | 1,000 – 5,000 | 4 vCPU / 32 GB | 24 GB | Fargate (4096 CPU / 32768 MEM) |
| **M** | 2,000 – 10,000 | 5,000 – 10,000 | 8 vCPU / 60 GB | 44 GB | Fargate (8192 CPU / 61440 MEM) |

> ¹ XS and S are projected sizing estimates. M has been validated through performance testing, which ran on a GCP ARM instance at 8 vCPU and 64 GB with a 48 GB heap rather than on a Fargate task. The 60 GB task and 44 GB heap above are the nearest shape Fargate allows, so treat the figures as indicative rather than measured at those values.

> **Why a 44 GB heap on a 60 GB task?** Fargate caps an 8 vCPU task at 60 GB, so a 48 GB heap plus `-XX:MaxDirectMemorySize=8g` would commit 56 GB of the 60, and `-XX:+AlwaysPreTouch` claims the whole heap at startup. 44 GB leaves 8 GB for the JVM's own non-heap memory and the rest of the container. Raising it back to 48 GB removes most of that margin.

> **Need more capacity?** For 10,000+ applications or multi-node deployments, use the [High Availability](../infra-aws-ha/) or [Kubernetes](../infra-aws-ha-k8s-helm/) architectures.

### Recommended `terraform.tfvars` by Size

<details>
<summary><strong>Size XS</strong> — Extra Small (< 500 applications)</summary>

```hcl
ecs_cpu              = 2048                # 2 vCPU
ecs_memory           = 16384               # 16 GB
iq_desired_count     = 1
iq_docker_image      = "sonatype/nexus-iq-server:latest"
java_opts            = "-Xms12g -Xmx12g -XX:MaxDirectMemorySize=4g -XX:+UseG1GC -XX:+AlwaysPreTouch -Dinsight.threads.monitor=3 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_instance_class    = "db.t4g.medium"     # 2 vCPU, 4 GB (burstable)
db_allocated_storage = 50
```
</details>

<details>
<summary><strong>Size S</strong> — Small (500 – 2,000 applications)</summary>

```hcl
ecs_cpu              = 4096                # 4 vCPU
ecs_memory           = 32768               # 32 GB
iq_desired_count     = 1
iq_docker_image      = "sonatype/nexus-iq-server:latest"
java_opts            = "-Xms24g -Xmx24g -XX:MaxDirectMemorySize=6g -XX:+UseG1GC -XX:+AlwaysPreTouch -Dinsight.threads.monitor=5 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_instance_class    = "db.r6g.large"      # 2 vCPU, 16 GB
db_allocated_storage = 100
```
</details>

<details>
<summary><strong>Size M</strong> — Medium (2,000 – 10,000 applications)</summary>

```hcl
ecs_cpu              = 8192                # 8 vCPU
ecs_memory           = 61440               # 60 GB, the maximum at 8 vCPU
iq_desired_count     = 1
iq_docker_image      = "sonatype/nexus-iq-server:latest"
java_opts            = "-Xms44g -Xmx44g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/Java_Heap_logs -XX:+CrashOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_instance_class    = "db.r6g.2xlarge"    # 8 vCPU, 64 GB
db_allocated_storage = 100                 # auto-scales to 500 GB
```
</details>

### Database Sizing

| Size | DB Instance Class | vCPU | Memory | Storage |
|------|:-----------------|:----:|:------:|:-------:|
| **XS** | db.t4g.medium (burstable) | 2 | 4 GB | 50 GB |
| **S** | db.r6g.large | 2 | 16 GB | 100 GB |
| **M** | db.r6g.2xlarge | 8 | 64 GB | 100 GB (auto-scales to 500 GB) |

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
- Ability to create: VPC, ECS, RDS, EFS, ALB, IAM roles

#### Required AWS Permissions
Your IAM user/role needs these AWS service permissions:
- **EC2**: VPC, subnets, security groups, network interfaces
- **ECS**: Clusters, task definitions, services
- **RDS**: Database instances, subnet groups, parameter groups
- **EFS**: File systems, mount targets, access points
- **ELB**: Application Load Balancers, target groups, listeners
- **IAM**: Roles, policies, instance profiles
- **Logs**: CloudWatch log groups
- **Secrets Manager**: Secrets creation and management
- **S3**: Terraform state storage (if using remote state)

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
   cd /path/to/sca-example-terraform/infra-aws
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
   - Initial startup can take 5-10 minutes
   - Database migrations, if needed, run on first boot

2. **Access the web UI:**

   Use the application URL displayed at the end of the deployment.

   Example: `http://ref-arch-iq-alb-123456789.us-east-1.elb.amazonaws.com`

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
> | `postgres_version` | 15.10 | 15.19 |

### Configuration Variables

Edit `terraform.tfvars` to customize your deployment:

```hcl
# General Configuration
aws_region  = "us-east-1"

# Network Configuration
vpc_cidr               = "10.0.0.0/16"
public_subnet_cidrs    = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs   = ["10.0.10.0/24", "10.0.20.0/24"]
db_subnet_cidrs        = ["10.0.30.0/24", "10.0.40.0/24"]

# ECS Configuration
ecs_cpu           = 8192  # 8 vCPU
ecs_memory        = 32768 # 32 GB
iq_desired_count  = 1 # Single instance
iq_docker_image   = "sonatype/nexus-iq-server:latest"
java_opts         = "-Xms24g -Xmx24g -XX:+UseG1GC -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"

# Database Configuration
db_name                     = "nexusiq"
db_username                 = "nexusiq"
db_password                 = "CHANGE_ME_STRONG_PASSWORD"  # Change this!
db_instance_class           = "db.r6g.4xlarge"
db_allocated_storage        = 500
db_max_allocated_storage    = 1000
postgres_version            = "15.19"
db_backup_retention_period  = 7
db_backup_window           = "03:00-04:00"
db_maintenance_window      = "sun:04:00-sun:05:00"
db_skip_final_snapshot     = true
db_deletion_protection     = false

# Load Balancer Configuration
# ssl_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
alb_deletion_protection = false

# Logging Configuration
log_retention_days = 30
```

**Important Settings:**
- **`iq_desired_count = 1`** - Keep this at 1. Only use a single Sonatype IQ Server instance
- **`db_password`** - Use a strong, unique password (required change)
- **`db_deletion_protection = false`** - Set to `true` for production to prevent accidental database deletion
- **`db_skip_final_snapshot = true`** - Set to `false` for production to create a final backup snapshot before database deletion
- **`alb_deletion_protection = false`** - Set to `true` for production use
- **Resource Names** - All AWS resources are prefixed with "ref-arch" (e.g., "ref-arch-iq-cluster")

## Security Features

- **VPC Isolation**: Application runs in private subnets
- **Database Security**: RDS in isolated database subnets
- **Secrets Management**: Database credentials stored in AWS Secrets Manager
- **Encryption**:
  - EFS encrypted at rest and in transit
  - RDS encrypted at rest
  - S3 ALB logs encrypted
- **Security Groups**: Least-privilege network access

## Reliability and Backup

This is a **single instance** deployment.
- **Single Instance**: One ECS Fargate task running Sonatype IQ Server (runs in one AZ at a time)
- **Single AZ Database**: RDS instance runs in one availability zone (no multi-AZ failover)
- **Multi-AZ Infrastructure**: Supporting resources (ALB, subnets, NAT gateways) span 2 availability zones for infrastructure resilience
- **Automatic Restart**: ECS automatically restarts the container if it fails (may restart in different AZ, causing brief downtime)
- **Database Backups**: Automated RDS backups with 7-day retention (configurable)
- **EFS Persistence**: Application data stored on EFS survives container restarts

## Monitoring and Logging

This deployment includes **production-grade logging** with a unified CloudWatch approach:

### Structured Logging with Fluent Bit
- **Fluent Bit Sidecar**: Lightweight log processor running alongside IQ Server
- **5 Log Types Collected**: Application, request, audit, policy-violation, stderr
- **Aggregated to One CloudWatch Log Group**: All logs sent to `/ecs/ref-arch-nexus-iq-server`
- **Separated by Stream Prefix**: Each log type has its own stream prefix for easy filtering
- **Dual Output**: Logs written to both CloudWatch AND EFS for persistence

### CloudWatch Unified Log Group
- **Log Group**: `/ecs/ref-arch-nexus-iq-server`
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
- **RDS Enhanced Monitoring**: Database performance metrics
- **ALB Access Logs**: Load balancer access logs stored in S3

## Persistent Storage

- **EFS File System**: Shared storage for `/sonatype-work` directory
- **Database**: PostgreSQL RDS for application data
- **Auto-scaling Storage**: RDS storage scales automatically up to configured limit

## Networking

### Subnets
- **Public Subnets**: Load balancer and NAT gateway
- **Private Subnets**: ECS Fargate tasks
- **Database Subnets**: RDS instance (no internet access)

### Security Groups
- **ALB**: Allows HTTP (80) and HTTPS (443) from internet
- **ECS**: Allows traffic from ALB on port 8070
- **RDS**: Allows PostgreSQL (5432) from ECS tasks only
- **EFS**: Allows NFS (2049) from ECS tasks only

