# Sonatype IQ Reference Architecture - AWS Cloud-Native (High Availability)

This directory contains Terraform configuration for deploying Sonatype IQ Server on AWS using ECS Fargate in a **High Availability configuration** with auto-scaling and multi-AZ deployment.

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

### Configuration Variables

Edit `terraform.tfvars` to customize your deployment:

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

# ECS Configuration - L Customer Profile
# L Profile: 8 vCPU ARM (Graviton), 64 GB RAM
ecs_cpu                 = 8192   # 8 vCPU
ecs_memory              = 65536  # 64 GB
ecs_memory_reservation  = 49152  # 48 GB soft limit

# IQ Server Configuration
iq_desired_count        = 2  # Minimum 2 for HA
iq_min_count           = 2
iq_max_count           = 5
iq_cpu_target_value    = 70  # CPU target for auto scaling (%)
iq_memory_target_value = 80  # Memory target for auto scaling (%)
iq_docker_image        = "sonatype/nexus-iq-server:latest"

# Java options for L profile: 48GB heap (75% of 64GB RAM)
# AlwaysPreTouch: Pre-faults heap pages for consistent GC performance
# CrashOnOutOfMemoryError: Ensures clean crash for easier troubleshooting
# insight.threads.monitor=10: Enables monitoring thread pool with 10 threads
java_opts = "-Xms48g -Xmx48g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+CrashOnOutOfMemoryError -Djava.util.prefs.userRoot=/sonatype-work/javaprefs -Dinsight.threads.monitor=10"

# Database Configuration (Aurora PostgreSQL)
db_name                     = "nexusiq"
db_username                 = "nexusiq"
db_password                 = "YourSecurePassword123!"  # Change this!
aurora_engine_version       = "15.10"
aurora_instance_class       = "db.r6g.2xlarge"  # 8 vCPU, 64 GB RAM, ARM Graviton
aurora_instances            = 2
db_backup_retention_period  = 7
db_backup_window           = "03:00-04:00"
db_maintenance_window      = "sun:04:00-sun:05:00"
db_skip_final_snapshot     = true
db_deletion_protection     = false

# Load Balancer Configuration
# ssl_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
alb_deletion_protection = false
alb_idle_timeout        = 180  # 3 minutes

# EFS Configuration
efs_throughput_mode                  = "provisioned"
efs_provisioned_throughput_in_mibps = 100

# Monitoring Configuration
enable_container_insights = true
enable_prometheus        = true
log_retention_days       = 30
```

**Important Settings:**
- **`iq_desired_count = 3`** - Initial number of instances for HA (minimum 2 recommended)
- **`iq_min_count = 2`** - Minimum auto scaling capacity (must be at least 2 for HA)
- **`iq_max_count = 5`** - Maximum auto scaling capacity
- **`aurora_instances = 2`** - Number of Aurora instances (minimum 2 for HA)
- **`db_password`** - Use a strong, unique password (required change)
- **`db_deletion_protection = false`** - Set to `true` for production to prevent accidental database deletion
- **`db_skip_final_snapshot = true`** - Set to `false` for production to create a final backup snapshot before database deletion
- **`alb_deletion_protection = false`** - Set to `true` for production use
- **Resource Names** - Controlled by `cluster_name` variable

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
- **Auto Scaling**: ECS service scales from 2-5 tasks based on CPU/memory utilization
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

