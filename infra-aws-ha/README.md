# Nexus IQ Server AWS Infrastructure (High Availability)

This directory contains Terraform configuration for deploying Nexus IQ Server on AWS using ECS Fargate in a **High Availability configuration** as part of a **Reference Architecture for Enterprise Cloud Deployments**.

## Architecture Overview

This infrastructure deploys a complete, production-ready Nexus IQ Server High Availability environment including:

- **ECS Fargate Cluster** - Multiple containerized Nexus IQ Server instances (2-6 tasks)
- **Application Load Balancer (ALB)** - HTTP load balancer with health checks and auto scaling
- **Aurora PostgreSQL Cluster** - Managed database cluster with Multi-AZ failover
- **EFS File System** - Shared persistent storage with clustering support and unique work directories
- **VPC & Networking** - Complete network infrastructure with public/private/database subnets
- **Security Groups** - Least-privilege network access controls
- **IAM Roles** - Service-specific permissions following AWS best practices
- **CloudWatch Logs** - Centralized logging for monitoring and troubleshooting
- **Secrets Manager** - Secure database credential storage
- **Application Auto Scaling** - Dynamic scaling based on CPU and memory utilization
- **Service Discovery** - Internal DNS for inter-service communication
- **AWS Backup** - Automated EFS backup with daily and weekly policies

```
Internet
    ↓
Application Load Balancer (Public Subnets)
    ↓
ECS Fargate Tasks (2-6 instances, Multi-AZ) ←→ EFS (Shared Clustering Storage)
    ↓
Aurora PostgreSQL Cluster (Database Subnets, Multi-AZ)
```

## Prerequisites

### Required Tools
- **Terraform** >= 1.0
- **AWS CLI** >= 2.0
- **aws-vault**

### AWS Account Requirements
- AWS account with administrative access
- MFA-enabled IAM user
- Cross-account role assumption capability

## AWS Configuration Setup

### 1. AWS CLI Profile Configuration

Create or update your `~/.aws/config` file with the following configuration:

```ini
[profile sonatype-ops]
credential_process = aws-vault export sonatype-ops --format=json
mfa_serial = arn:aws:iam::451349303221:mfa/your-username
region = us-east-1

[profile admin@iq-sandbox]
role_arn = arn:aws:iam::552183322382:role/admin
source_profile = sonatype-ops
```

**Key Configuration Details:**
- **`default`**: Basic AWS CLI defaults for region and output format
- **`sonatype-ops`**: Base profile using aws-vault's `credential_process` for secure MFA authentication
- **`admin@iq-sandbox`**: Cross-account role assumption profile that uses `sonatype-ops` as source

**Note**: This configuration uses aws-vault's `credential_process` to automatically handle MFA authentication, which is more secure than storing static credentials in `~/.aws/credentials`.

### 2. Verify Configuration

Test your AWS configuration:
```bash
aws sts get-caller-identity --profile admin@iq-sandbox
```

This should prompt for MFA and return your assumed role information.

## Quick Start

1. **Navigate to the HA infrastructure directory**:
   ```bash
   cd /path/to/sca-example-terraform/infra-aws-ha
   ```

2. **Review and customize variables**:
   ```bash
   # Edit terraform.tfvars with your specific values
   vim terraform.tfvars
   ```

3. **Initialize Terraform**:
   ```bash
   terraform init
   ```

4. **Plan the deployment**:
   ```bash
   ./tf-plan.sh
   ```

5. **Deploy the infrastructure**:
   ```bash
   ./tf-apply.sh
   ```

6. **Access your Nexus IQ Server**:
   - Get the application URL: `terraform output`
   - Wait 10-15 minutes for all services to be ready
   - Default credentials: `admin` / `admin123`

## Configuration

### 1. Review Variables in terraform.tfvars

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
ecs_cpu               = 2048        # 2 vCPU per task
ecs_memory           = 4096        # 4GB RAM per task
iq_desired_count     = 2           # Initial number of tasks (2-6)
iq_max_capacity      = 6           # Maximum auto scaling capacity
iq_docker_image      = "sonatype/nexus-iq-server:latest"

# Auto Scaling Configuration
cpu_target_percent    = 70         # CPU utilization target for scaling
memory_target_percent = 80         # Memory utilization target for scaling

# Database Configuration (Aurora Cluster)
db_name                     = "nexusiq"
db_username                 = "nexusiq"
db_password                 = "YourSecurePassword123!"  # Change this!
db_instance_class          = "db.r6g.large"
postgres_version           = "15.4"
aurora_backup_retention    = 7     # Days
```

### 2. Important HA Settings

- **`iq_desired_count = 2`** - Minimum number of instances for HA (2-6 supported)
- **`iq_max_capacity = 6`** - Maximum auto scaling capacity
- **`cpu_target_percent = 70`** - CPU threshold for auto scaling
- **`memory_target_percent = 80`** - Memory threshold for auto scaling
- **`db_password`** - Use a strong, unique password
- **Resource Names** - All AWS resources are prefixed with "ref-arch-iq-ha" (e.g., "ref-arch-iq-ha-cluster")
- **`aurora_backup_retention = 7`** - Database backup retention period

## Security Features

- **VPC Isolation**: Application runs in private subnets across multiple AZs
- **Database Security**: Aurora cluster in isolated database subnets with Multi-AZ deployment
- **Secrets Management**: Database credentials stored in AWS Secrets Manager
- **Encryption**:
  - EFS encrypted at rest and in transit
  - Aurora encrypted at rest and in transit
  - S3 ALB logs encrypted
- **Security Groups**: Least-privilege network access
- **Work Directory Isolation**: Unique work directories per task prevent clustering conflicts

## High Availability Features

- **Multi-AZ Deployment**: Tasks distributed across multiple availability zones
- **Auto Scaling**: ECS service scales from 2-6 tasks based on CPU/memory utilization
- **Aurora Cluster**: Multi-AZ database deployment with automatic failover (~30 seconds)
- **Load Balancing**: ALB distributes traffic across healthy containers (session stickiness disabled)
- **Rolling Deployments**: Zero-downtime updates with 50% minimum healthy capacity
- **EFS Clustering**: Shared storage with unique work directories and cluster coordination
- **Service Discovery**: Internal DNS for efficient inter-service communication

## Custom Clustering Solution

This deployment solves critical IQ Server clustering challenges:

- **Work Directory Conflicts**: Each task gets unique `/sonatype-work/clm-server-${HOSTNAME}` directory
- **Database Sharing**: Custom config.yml generation ensures all instances connect to shared Aurora cluster
- **Cluster Coordination**: Shared `/sonatype-work/clm-cluster` directory for coordination
- **Dynamic Configuration**: config.yml generated per task with proper database configuration

## Monitoring and Logging

- **CloudWatch Logs**: Application logs centralized in CloudWatch
- **Container Insights**: ECS cluster monitoring enabled
- **Aurora Monitoring**: Performance Insights and Enhanced Monitoring enabled
- **Auto Scaling Metrics**: CPU and memory utilization tracking
- **ALB Access Logs**: Load balancer access logs stored in S3
- **Service Discovery**: Health check monitoring for service registration

## Persistent Storage

- **EFS File System**: Shared storage for clustering with unique work directories
- **Aurora Database**: PostgreSQL cluster for application data with continuous backups
- **Auto-scaling Storage**: Aurora storage scales automatically
- **AWS Backup**: Automated EFS backup with daily/weekly retention policies

## Cost Optimization

- **Fargate**: Pay-per-use container compute with auto scaling
- **Aurora**: Right-sized cluster instances with storage auto-scaling
- **S3 Lifecycle**: ALB logs automatically expire after 90 days
- **Resource Tagging**: All resources tagged for cost allocation
- **Auto Scaling**: Dynamically adjusts capacity based on demand

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

## Automated Deployment Scripts

This infrastructure includes convenient scripts that handle MFA authentication automatically:

### Available Scripts

- **`./tf-plan.sh`** - Preview infrastructure changes with MFA authentication
- **`./tf-apply.sh`** - Deploy infrastructure with MFA authentication
- **`./tf-destroy.sh`** - Destroy infrastructure with automatic backup recovery point cleanup

### How the Scripts Work

1. **Use aws-vault** for secure MFA authentication
2. **Handle credentials automatically** - no manual token management
3. **Include safety features** - automatic cleanup in destroy script
4. **Non-interactive** - run with `-auto-approve` flags for automation

### Manual Terraform Commands (Alternative)

If you prefer to run Terraform commands manually:

```bash
# Initialize Terraform
terraform init

# Plan deployment with MFA
aws-vault exec admin@iq-sandbox -- terraform plan

# Apply configuration with MFA
aws-vault exec admin@iq-sandbox -- terraform apply

# Show outputs
terraform output

# Destroy infrastructure with MFA
aws-vault exec admin@iq-sandbox -- terraform destroy
```

## Accessing the Application

### 1. Get Deployment Information

```bash
terraform output
```

Example output:
```
application_url = "http://ref-arch-iq-ha-cluster-alb-1234567890.us-east-1.elb.amazonaws.com"
ecs_cluster_name = "ref-arch-iq-ha-cluster"
ecs_service_name = "ref-arch-iq-ha-cluster-nexus-iq-service"
aurora_cluster_endpoint = "ref-arch-iq-ha-cluster-aurora-cluster.cluster-xxxxx.us-east-1.rds.amazonaws.com"
```

### 2. Access the Application

1. **Wait for services to be ready** (10-15 minutes after deployment)
2. **Open the application URL** from terraform output
3. **Default credentials**: `admin` / `admin123`
4. **Complete setup wizard** on first access

### 3. Monitor Deployment Status

Check ECS service status:
```bash
aws-vault exec admin@iq-sandbox -- aws ecs describe-services \
  --cluster ref-arch-iq-ha-cluster \
  --services ref-arch-iq-ha-cluster-nexus-iq-service \
  --region us-east-1
```

View application logs from all instances:
```bash
aws-vault exec admin@iq-sandbox -- aws logs tail \
  /ecs/ref-arch-iq-ha-cluster/nexus-iq-server \
  --follow \
  --region us-east-1
```

Check auto scaling status:
```bash
aws-vault exec admin@iq-sandbox -- aws application-autoscaling describe-scalable-targets \
  --service-namespace ecs \
  --region us-east-1
```

## AWS Console Access

Monitor your HA infrastructure in the AWS Console:

- **ECS Service**: ECS → Clusters → `ref-arch-iq-ha-cluster`
- **Auto Scaling**: ECS → Clusters → Services → Auto Scaling tab
- **Database**: RDS → Databases → `ref-arch-iq-ha-cluster-aurora-cluster`
- **Load Balancer**: EC2 → Load Balancers → `ref-arch-iq-ha-cluster-alb`
- **Target Groups**: EC2 → Target Groups → `ref-arch-iq-ha-cluster-iq-tg`
- **Logs**: CloudWatch → Log Groups → `/ecs/ref-arch-iq-ha-cluster/nexus-iq-server`
- **VPC**: VPC → Your VPCs → `ref-arch-iq-ha-vpc`
- **Storage**: EFS → File Systems → `ref-arch-iq-ha-cluster-efs`
- **Service Discovery**: Cloud Map → Namespaces → `ref-arch-iq-ha-cluster.local`

## File Structure

```
infra-aws-ha/
├── main.tf              # VPC, networking, and core infrastructure
├── ecs.tf               # ECS cluster, service, auto scaling, and task definitions
├── rds-aurora.tf        # Aurora PostgreSQL cluster and secrets
├── load_balancer.tf     # Application Load Balancer and S3 logging
├── security_groups.tf   # Network security rules
├── iam.tf               # IAM roles and policies
├── service_discovery.tf # Cloud Map service discovery
├── autoscaling.tf       # Application Auto Scaling policies
├── backup.tf            # AWS Backup configuration for EFS
├── variables.tf         # Input variable definitions
├── outputs.tf           # Output value definitions
├── terraform.tfvars     # Infrastructure configuration
├── tf-apply.sh          # Deployment script with MFA support
├── tf-plan.sh           # Planning script with MFA support
├── tf-destroy.sh        # Enhanced cleanup script with backup recovery point removal
└── README.md            # This file
```

## Troubleshooting

### Common Issues

1. **MFA Authentication Fails**
   ```bash
   # Verify your AWS configuration
   aws sts get-caller-identity --profile admin@iq-sandbox
   ```

2. **ECS Tasks Keep Restarting**
   ```bash
   # Check container logs from all tasks
   aws-vault exec admin@iq-sandbox -- aws logs tail \
     /ecs/ref-arch-iq-ha-cluster/nexus-iq-server --follow --region us-east-1
   ```
   - **Work directory conflicts**: Verify unique work directory creation
   - **Database connection errors**: Check Aurora cluster status and credentials
   - **EFS permission errors**: Check EFS access point configuration

3. **Application Not Accessible**
   - Wait 10-15 minutes for all ECS services to fully start
   - Check ALB target group health in AWS Console
   - Verify security group rules allow HTTP traffic on port 80
   - Ensure at least 2 healthy targets are registered

4. **Database Connection Issues**
   - Verify Aurora cluster status in AWS Console
   - Check database credentials in Secrets Manager
   - Ensure ECS tasks can reach Aurora cluster endpoints
   - Verify custom config.yml generation includes database configuration

5. **Auto Scaling Not Working**
   - Ensure IQ Server cluster directory is set, and shared among nodes
   - Ensure IQ Server workspace directory is set for each node individually, and not shared among nodes
   - Ensure IQ Server clustering license compliance, i.e. the IQ license must be valid for clusterning

   ```bash
   # Check auto scaling policies
   aws-vault exec admin@iq-sandbox -- aws application-autoscaling describe-scaling-policies \
     --service-namespace ecs --region us-east-1

   # Check CloudWatch metrics
   aws-vault exec admin@iq-sandbox -- aws cloudwatch get-metric-statistics \
     --namespace AWS/ECS --metric-name CPUUtilization \
     --start-time 2023-01-01T00:00:00Z --end-time 2023-01-01T01:00:00Z \
     --period 300 --statistics Average --region us-east-1
   ```

6. **Clustering Issues**
   ```bash
   # Verify unique work directories are created
   aws-vault exec admin@iq-sandbox -- aws logs filter-log-events \
     --log-group-name /ecs/ref-arch-iq-ha-cluster/nexus-iq-server \
     --filter-pattern "Creating unique sonatypeWork directory"

   # Check for work directory conflicts (should be empty)
   aws-vault exec admin@iq-sandbox -- aws logs filter-log-events \
     --log-group-name /ecs/ref-arch-iq-ha-cluster/nexus-iq-server \
     --filter-pattern "Work directory.*already in use"

   # Verify PostgreSQL connections (should see postgresql, not H2)
   aws-vault exec admin@iq-sandbox -- aws logs filter-log-events \
     --log-group-name /ecs/ref-arch-iq-ha-cluster/nexus-iq-server \
     --filter-pattern "postgresql"
   ```

7. **Backup Vault Deletion Issues**
   ```bash
   # If destroy fails due to recovery points
   aws-vault exec admin@iq-sandbox -- aws backup list-recovery-points-by-backup-vault \
     --backup-vault-name ref-arch-iq-ha-cluster-efs-backup-vault
   ```
   The enhanced `tf-destroy.sh` script automatically handles recovery point cleanup.

### Resource Limits

- **ECS Service**: Scales from 2-6 tasks based on demand
- **Aurora Cluster**: Uses db.r6g.large instances for performance
- **Storage**: EFS provides unlimited scalable storage with clustering support

## Cleanup

### Complete Infrastructure Removal

Remove all AWS resources:
```bash
./tf-destroy.sh
```

This will:
- Prompt for MFA authentication
- Automatically clean up AWS Backup recovery points
- Automatically clean up Secrets Manager secrets
- Destroy all Terraform-managed resources

### Partial Cleanup

Stop only the ECS service (keeps data):
```bash
aws-vault exec admin@iq-sandbox -- terraform destroy \
  -target=aws_ecs_service.iq_service
```

**Warning**: Complete cleanup will permanently delete all data including the Aurora cluster. Ensure you have backups if needed.

## Security Features

- **Network Isolation**: Private subnets for ECS and Aurora across multiple AZs
- **Encryption**: Aurora cluster encryption at rest and in transit
- **Secrets Management**: Database credentials stored in AWS Secrets Manager
- **IAM**: Least-privilege roles with specific resource access
- **Security Groups**: Minimal required network access with clustering support
- **VPC**: Isolated network environment with Multi-AZ deployment
- **EFS Access Points**: Proper file system permissions for container clustering access

## Production Considerations

For production HA deployments, consider:

1. **SSL/TLS Certificate**: Add ACM certificate and HTTPS listener
2. **Domain Name**: Configure Route53 for custom domain
3. **Backup Strategy**: Review Aurora and EFS backup settings
4. **Monitoring**: Add CloudWatch alarms and dashboards for all instances
5. **Cross-Region Replication**: Consider Aurora Global Database for DR
6. **Resource Sizing**: Adjust CPU/memory and auto scaling thresholds based on usage patterns
7. **Network Security**: Restrict ALB access to specific IP ranges
8. **Database Protection**: Set `aurora_deletion_protection = true`
9. **Final Snapshots**: Set `aurora_skip_final_snapshot = false`
10. **License Management**: Ensure IQ Server clustering license compliance

## Reference Architecture

This HA infrastructure serves as a **Reference Architecture for Enterprise Cloud Deployments** demonstrating:

- **High availability patterns**: Multi-AZ deployment, auto scaling, failover
- **Cloud-native clustering**: Custom IQ Server clustering solution
- **Security best practices**: Network isolation, encryption, secrets management
- **Operational excellence**: Centralized logging, monitoring, automation
- **Cost optimization**: Auto scaling, right-sized resources, lifecycle policies
- **Reliability**: Multi-AZ deployment, automated backups, health checks

## Support

For issues with this HA infrastructure:
1. Check the troubleshooting section above
2. Review AWS CloudWatch logs for all instances
3. Verify AWS permissions and MFA setup
4. Check ECS service auto scaling configuration
5. Consult the [Nexus IQ Server documentation](https://help.sonatype.com/iqserver)

For Terraform-specific issues:
- Review the [Terraform AWS Provider documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- Check [AWS service documentation](https://docs.aws.amazon.com/) for specific services
- Verify [ECS Auto Scaling](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-auto-scaling.html) configuration
