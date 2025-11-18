# Sonatype IQ Reference Architecture - AWS EKS with Helm (High Availability)

This directory contains Terraform configuration for deploying Sonatype IQ Server on AWS using EKS (Elastic Kubernetes Service) with Helm in a **High Availability configuration** with auto-scaling and multi-AZ deployment.

## Deployment Guide

### Step 1: Prerequisites

#### Required Tools
Install these tools on your local machine:

| Tool | Version | Installation | Purpose |
|------|---------|--------------|---------|
| **Terraform** | >= 1.0 | [Install Guide](https://developer.hashicorp.com/terraform/install) | Infrastructure as Code |
| **AWS CLI** | >= 2.0 | [Install Guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) | AWS API access |
| **aws-vault** | Latest | [Install Guide](https://github.com/99designs/aws-vault#installing) | Secure credential management |
| **kubectl** | Latest | [Install Guide](https://kubernetes.io/docs/tasks/tools/) | Kubernetes cluster management |
| **Helm** | >= 3.9.3 | [Install Guide](https://helm.sh/docs/intro/install/) | Application deployment |

#### AWS Account Requirements
- AWS account with administrative access (or sufficient permissions listed below)
- IAM user with MFA enabled
- Ability to create: VPC, EKS, RDS Aurora, EFS, ALB, IAM roles

#### Required AWS Permissions
Your IAM user/role needs these AWS service permissions:
- **EC2**: VPC, subnets, security groups, network interfaces, EIPs, NAT gateways
- **EKS**: Clusters, node groups, add-ons (CoreDNS, kube-proxy, VPC CNI, EBS CSI, EFS CSI), OIDC providers
- **RDS**: Aurora clusters, instances, subnet groups, parameter groups
- **EFS**: File systems, mount targets, access points, backup policies
- **ELB**: Application Load Balancers, target groups, listeners
- **IAM**: Roles, policies, OIDC providers
- **Auto Scaling**: Launch configurations, auto scaling groups (for EKS node groups)
- **KMS**: Keys and aliases for encryption (RDS, EFS)
- **Logs**: CloudWatch log groups and streams
- **Secrets Manager**: Secrets creation and management
- **SSM Parameter Store**: Parameters for storing database credentials and EFS IDs
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
   cd /path/to/sca-example-terraform/infra-aws-ha-k8s-helm
   cp terraform.tfvars.example terraform.tfvars
   ```

2. **Edit `terraform.tfvars` with your values (or leave to get started quickly):**
   ```bash
   vi terraform.tfvars
   ```

### Step 4: Deploy Infrastructure and Application

1. **Initialize Terraform:**
   ```bash
   terraform init
   ```

   This downloads required providers (AWS, Kubernetes, Helm, etc.)

2. **Review the deployment plan:**
   ```bash
   ./tf-plan.sh
   ```

   This shows what resources will be created without actually deploying them.

3. **Deploy the infrastructure:**
   ```bash
   ./tf-apply.sh
   ```

   This creates the EKS cluster, Aurora database, EFS, and networking.

4. **Install IQ Server using Helm:**
   ```bash
   ./helm-install.sh
   ```

   This script:
   - Configures kubectl to access the EKS cluster
   - Retrieves database credentials from AWS Secrets Manager
   - Installs the official Sonatype Helm chart
   - Configures ingress and load balancer

### Step 5: Access Sonatype IQ Server

1. **Wait for service to be ready:**
   - Initial startup can take 10-15 minutes
   - All pods must complete database migrations and clustering setup

2. **Access the web UI:**

   Use the application URL displayed at the end of the Helm deployment.

   Example: `http://k8s-nexusiq-12345-67890.us-east-1.elb.amazonaws.com`

3. **Login credentials:**
   - **Username:** `admin`
   - **Password:** `admin123` (change immediately!)

---

## Teardown / Cleanup

**WARNING: This will delete ALL infrastructure and data!**

1. **Uninstall the Helm deployment:**
   ```bash
   ./helm-uninstall.sh
   ```

2. **Destroy all infrastructure:**
   ```bash
   ./tf-destroy.sh
   ```

   > **Keep the terminal open** - If you close it mid-destroy, the process will potentially stop and leave resources partially deleted.

---

## Configuration

### Configuration Variables

Edit `terraform.tfvars` to customize your deployment:

```hcl
# AWS Configuration
aws_region  = "us-east-1"
environment = "prod"

# Cluster Configuration
cluster_name = "nexus-iq-ha"
vpc_cidr     = "10.0.0.0/16"

# EKS Configuration
kubernetes_version       = "1.30"
node_instance_type      = "m5d.2xlarge"
node_group_min_size     = 2
node_group_max_size     = 5
node_group_desired_size = 3
node_disk_size          = 50

# RDS Aurora Configuration
aurora_engine_version   = "15.10"
aurora_instance_class   = "db.r6g.4xlarge"
aurora_instance_count   = 2
database_name           = "nexusiq"
database_username       = "nexusiq"
database_password       = "SecurePassword123!"  # Change this!
backup_retention_period = 7
skip_final_snapshot     = true
deletion_protection     = false

# EFS Configuration
efs_provisioned_throughput = 100

# Nexus IQ Server Configuration
nexus_iq_version       = "1.195.0"
nexus_iq_license       = ""
nexus_iq_admin_password = "admin123"
nexus_iq_replica_count = 3

# Resource Limits
nexus_iq_memory_request = "16Gi"
nexus_iq_memory_limit   = "24Gi"
nexus_iq_cpu_request    = "4"
nexus_iq_cpu_limit      = "6"

# Helm Configuration
helm_chart_version = "195.0.0"
helm_namespace     = "nexus-iq"

# Logging Configuration
enable_fluentd        = true
enable_cloudwatch_logs = true

# Ingress Configuration
enable_ingress_nginx = true
ingress_hostname     = "nexus-iq.yourdomain.com"
ingress_tls_enabled  = false
acm_certificate_arn  = ""

# Monitoring Configuration
enable_hpa                      = true
hpa_min_replicas               = 2
hpa_max_replicas               = 5
hpa_target_cpu_utilization     = 70
hpa_target_memory_utilization  = 80
```

**Important Settings:**
- **`nexus_iq_replica_count = 3`** - Initial number of replicas for HA (minimum 2 recommended)
- **`hpa_min_replicas = 2`** - Minimum auto scaling capacity (must be at least 2 for HA)
- **`hpa_max_replicas = 5`** - Maximum auto scaling capacity
- **`aurora_instance_count = 2`** - Number of Aurora instances (minimum 2 for HA)
- **`database_password`** - Use a strong, unique password (required change)
- **`nexus_iq_license`** - Base64 encoded HA-capable license
- **`deletion_protection = false`** - Set to `true` for production to prevent accidental database deletion
- **`skip_final_snapshot = true`** - Set to `false` for production to create a final backup snapshot before database deletion
- **Resource Names** - All AWS resources are prefixed with cluster name

### Clustering Solution

This deployment leverages Kubernetes and Helm for IQ Server clustering:

- **Pod Distribution**: Kubernetes pod anti-affinity ensures replicas run on different nodes across AZs
- **Shared Storage**: EFS provides consistent storage across all replicas with proper locking
- **Database Sharing**: All replicas connect to the shared Aurora cluster via Kubernetes secrets
- **Service Discovery**: Kubernetes service provides stable DNS and load balancing

**Important**: Ensure your Sonatype IQ Server license supports clustering for HA deployments.

## Security Features

- **VPC Isolation**: Application runs in private subnets across multiple AZs
- **Database Security**: Aurora cluster in isolated database subnets with Multi-AZ deployment
- **Secrets Management**: Database credentials stored in Kubernetes secrets (sourced from AWS Secrets Manager)
- **Encryption**:
  - EFS encrypted at rest and in transit
  - Aurora encrypted at rest
  - EBS encryption for EKS node storage
- **Security Groups**: Least-privilege network access
- **RBAC**: Kubernetes role-based access control
- **IRSA**: IAM Roles for Service Accounts for pod-level AWS permissions

## Reliability and Backup

This is a **High Availability** deployment with comprehensive reliability features:

- **Multi-AZ Deployment**: EKS nodes, pods, and Aurora instances distributed across multiple availability zones
- **Horizontal Pod Autoscaler (HPA)**: Pods scale from 2-5 based on CPU/memory utilization
- **Node Auto Scaling**: EKS node groups scale from 2-5 nodes based on pod resource requests
- **Aurora Cluster**: Multi-AZ database deployment with automatic failover (~30 seconds)
- **Automatic Restart**: Kubernetes automatically restarts failed pods
- **Pod Disruption Budgets**: Maintains availability during updates and node maintenance
- **Rolling Updates**: Zero-downtime updates with controlled rollout
- **Database Backups**: Automated Aurora backups with 7-day retention (configurable)
- **EFS Persistence**: Application data stored on EFS survives pod restarts

## Monitoring and Logging

This deployment includes **production-grade logging** with a unified CloudWatch approach:

### Structured Logging with Fluentd
- **Fluentd Sidecars**: Lightweight log forwarders in each IQ Server pod
- **Fluentd Aggregator**: Central aggregator pod (DaemonSet) receives logs from sidecars
- **5 Log Types Collected**: Application, request, audit, policy-violation, stderr
- **Aggregated to One CloudWatch Log Group**: All logs sent to `/eks/${cluster_name}/nexus-iq-server`
- **Separated by Stream Prefix**: Each log type has its own stream prefix for easy filtering
- **IRSA Authentication**: Fluentd uses IAM Roles for Service Accounts to write to CloudWatch

### CloudWatch Unified Log Group
- **Log Group**: `/eks/${cluster_name}/nexus-iq-server`
- **Log Streams** (organized by prefix):
  - `application/` - Main IQ Server logs
  - `request/` - HTTP request logs
  - `audit/` - Audit events (JSON format)
  - `policy-violation/` - Policy violations (JSON format)
  - `stderr/` - System.err output for debugging
  - `fluentd/` - Fluentd internal logs

### Additional Monitoring
- **Kubernetes Metrics**: Pod CPU/memory usage via `kubectl top`
- **HPA Metrics**: Horizontal Pod Autoscaler metrics
- **Aurora Monitoring**: Performance Insights and Enhanced Monitoring enabled
- **EKS Control Plane Logs**: Audit, authenticator, controller logs

## Persistent Storage

- **EFS File System**: Shared storage for clustering with Kubernetes CSI driver
- **Aurora Database**: PostgreSQL cluster for application data with continuous backups
- **Auto-scaling Storage**: Aurora storage scales automatically
- **EBS Volumes**: Node storage encrypted at rest

## Networking

### Subnets
- **Public Subnets**: Load balancer and NAT gateways across multiple AZs
- **Private Subnets**: EKS worker nodes across multiple AZs
- **Database Subnets**: Aurora cluster instances (no internet access)

### Security Groups
- **ALB**: Allows HTTP (80) and HTTPS (443) from internet
- **EKS Nodes**: Allows traffic from ALB, inter-node communication
- **Aurora**: Allows PostgreSQL (5432) from EKS nodes only
- **EFS**: Allows NFS (2049) from EKS nodes only

