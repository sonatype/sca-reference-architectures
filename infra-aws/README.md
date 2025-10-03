# Nexus IQ Server AWS Infrastructure

This directory contains Terraform configuration for deploying Nexus IQ Server on AWS using ECS Fargate as part of a **Reference Architecture for Native Cloud Deployments**.

## Architecture Overview

This infrastructure deploys a complete, production-ready Nexus IQ Server environment including:

- **ECS Fargate Cluster** - Containerized Nexus IQ Server deployment
- **Application Load Balancer (ALB)** - HTTP load balancer with health checks
- **RDS PostgreSQL** - Managed database with encryption and automated backups
- **EFS File System** - Shared persistent storage for Nexus IQ data with proper permissions
- **VPC & Networking** - Complete network infrastructure with public/private subnets
- **Security Groups** - Least-privilege network access controls
- **IAM Roles** - Service-specific permissions following AWS best practices
- **CloudWatch Logs** - Centralized logging for monitoring and troubleshooting
- **Secrets Manager** - Secure database credential storage

```
Internet
    ↓
Application Load Balancer (Public Subnets)
    ↓
ECS Fargate Tasks (Private Subnets) ←→ EFS (Persistent Storage)
    ↓
RDS PostgreSQL (Database Subnets)
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

1. **Navigate to the infrastructure directory**:
   ```bash
   cd /path/to/sca-example-terraform/infra-aws
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
   - Wait 5-10 minutes for service to be ready
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
ecs_cpu           = 2048        # 2 vCPU
ecs_memory        = 4096        # 4GB RAM
iq_desired_count  = 1           # Single instance (recommended)
iq_docker_image   = "sonatype/nexus-iq-server:latest"

# Database Configuration
db_name                     = "nexusiq"
db_username                 = "nexusiq"
db_password                 = "YourSecurePassword123!"  # Change this!
db_instance_class           = "db.t3.medium"
postgres_version            = "15"
```

### 2. Important Settings

- **`iq_desired_count = 1`** - Keep this at 1. Only use a single Nexus IQ Server
- **`db_password`** - Use a strong, unique password
- **Resource Names** - All AWS resources are prefixed with "ref-arch" (e.g., "ref-arch-iq-cluster")
- **`db_deletion_protection = false`** - Set to true for production use

## Security Features

- **VPC Isolation**: Application runs in private subnets
- **Database Security**: RDS in isolated database subnets
- **Secrets Management**: Database credentials stored in AWS Secrets Manager
- **Encryption**:
  - EFS encrypted at rest
  - RDS encrypted at rest
  - S3 ALB logs encrypted
- **Security Groups**: Least-privilege network access

## High Availability

- **Multi-AZ Deployment**: Resources distributed across multiple availability zones
- **Auto Scaling**: ECS service can scale based on demand
- **Database Backup**: Automated backups with configurable retention
- **Load Balancing**: ALB distributes traffic across healthy containers

## Monitoring and Logging

- **CloudWatch Logs**: Application logs centralized in CloudWatch
- **Container Insights**: ECS cluster monitoring enabled
- **RDS Enhanced Monitoring**: Database performance metrics
- **ALB Access Logs**: Load balancer access logs stored in S3

## Persistent Storage

- **EFS File System**: Shared storage for `/sonatype-work` directory
- **Database**: PostgreSQL RDS for application data
- **Auto-scaling Storage**: RDS storage scales automatically up to configured limit

## Cost Optimization

- **Fargate**: Pay-per-use container compute
- **RDS**: Right-sized instance with storage auto-scaling
- **S3 Lifecycle**: ALB logs automatically expire after 90 days
- **Resource Tagging**: All resources tagged for cost allocation

## Networking

### Subnets
- **Public Subnets**: Load balancer and NAT gateway
- **Private Subnets**: ECS Fargate tasks
- **Database Subnets**: RDS instance (no internet access)

### Security Groups
- **ALB**: Allows HTTP (80) and HTTPS (443) from internet
- **ECS**: Allows traffic from ALB on port 8070
- **RDS**: Allows PostgreSQL (5432) from ECS tasks
- **EFS**: Allows NFS (2049) from ECS tasks

## Automated Deployment Scripts

This infrastructure includes convenient scripts that handle MFA authentication automatically:

### Available Scripts

- **`./tf-plan.sh`** - Preview infrastructure changes with MFA authentication
- **`./tf-apply.sh`** - Deploy infrastructure with MFA authentication
- **`./tf-destroy.sh`** - Destroy infrastructure with automatic secret cleanup

### How the Scripts Work

1. **Use aws-vault** for secure MFA authentication
2. **Handle credentials automatically** - no manual token management
3. **Include safety features** - automatic secret cleanup in destroy script
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
application_url = "http://ref-arch-iq-alb-1234567890.us-east-1.elb.amazonaws.com"
ecs_cluster_name = "ref-arch-iq-cluster"
ecs_service_name = "ref-arch-nexus-iq-service"
database_endpoint = "ref-arch-iq-database.xxxxx.us-east-1.rds.amazonaws.com"
```

### 2. Access the Application

1. **Wait for service to be ready** (5-10 minutes after deployment)
2. **Open the application URL** from terraform output
3. **Default credentials**: `admin` / `admin123`
4. **Complete setup wizard** on first access

### 3. Monitor Deployment Status

Check ECS service status:
```bash
aws-vault exec admin@iq-sandbox -- aws ecs describe-services \
  --cluster ref-arch-iq-cluster \
  --services ref-arch-nexus-iq-service \
  --region us-east-1
```

View application logs:
```bash
aws-vault exec admin@iq-sandbox -- aws logs tail \
  /ecs/ref-arch-nexus-iq-server \
  --follow \
  --region us-east-1
```

## AWS Console Access

Monitor your infrastructure in the AWS Console:

- **ECS Service**: ECS → Clusters → `ref-arch-iq-cluster`
- **Database**: RDS → Databases → `ref-arch-iq-database`
- **Load Balancer**: EC2 → Load Balancers → `ref-arch-iq-alb`
- **Logs**: CloudWatch → Log Groups → `/ecs/ref-arch-nexus-iq-server`
- **VPC**: VPC → Your VPCs → `ref-arch-iq-vpc`
- **Storage**: EFS → File Systems → `ref-arch-iq-efs`

## File Structure

```
infra-aws/
├── main.tf              # VPC, networking, and core infrastructure
├── ecs.tf               # ECS cluster, service, and task definitions
├── rds.tf               # PostgreSQL database and secrets
├── load_balancer.tf     # Application Load Balancer and S3 logging
├── security_groups.tf   # Network security rules
├── iam.tf               # IAM roles and policies
├── variables.tf         # Input variable definitions
├── outputs.tf           # Output value definitions
├── terraform.tfvars     # Infrastructure configuration
├── tf-apply.sh          # Deployment script with MFA support
├── tf-plan.sh           # Planning script with MFA support
├── tf-destroy.sh        # Cleanup script with MFA support
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
   # Check container logs
   aws-vault exec admin@iq-sandbox -- aws logs tail \
     /ecs/ref-arch-nexus-iq-server --follow --region us-east-1
   ```
   - **Lock file errors**: Ensure `iq_desired_count = 1` (single instance)
   - **EFS permission errors**: Check EFS access point configuration

3. **Application Not Accessible**
   - Wait 5-10 minutes for ECS service to fully start
   - Check ALB target group health in AWS Console
   - Verify security group rules allow HTTP traffic on port 80

4. **Database Connection Issues**
   - Verify database credentials in Secrets Manager
   - Check RDS instance status in AWS Console
   - Ensure ECS tasks can reach database subnets

5. **Secrets Manager Conflicts**
   ```bash
   # If you get "secret already scheduled for deletion" error:
   aws-vault exec admin@iq-sandbox -- aws secretsmanager restore-secret \
     --secret-id ref-arch-iq-db-credentials --region us-east-1
   aws-vault exec admin@iq-sandbox -- aws secretsmanager delete-secret \
     --secret-id ref-arch-iq-db-credentials --force-delete-without-recovery --region us-east-1
   ```

### Resource Limits

- **ECS Service**: Limited to 1 task (Nexus IQ requirement)
- **Database**: Uses db.t3.medium for performance
- **Storage**: EFS provides unlimited scalable storage

## Cleanup

### Complete Infrastructure Removal

Remove all AWS resources:
```bash
./tf-destroy.sh
```

This will:
- Prompt for MFA authentication
- Automatically clean up Secrets Manager secrets
- Destroy all Terraform-managed resources

### Partial Cleanup

Stop only the ECS service (keeps data):
```bash
aws-vault exec admin@iq-sandbox -- terraform destroy \
  -target=aws_ecs_service.iq_service
```

**Warning**: Complete cleanup will permanently delete all data including the database. Ensure you have backups if needed.

## Security Features

- **Network Isolation**: Private subnets for ECS and RDS
- **Encryption**: RDS storage encryption enabled
- **Secrets Management**: Database credentials stored in AWS Secrets Manager
- **IAM**: Least-privilege roles with specific resource access
- **Security Groups**: Minimal required network access
- **VPC**: Isolated network environment
- **EFS Access Points**: Proper file system permissions for container access

## Production Considerations

For production deployments, consider:

1. **SSL/TLS Certificate**: Add ACM certificate and HTTPS listener
2. **Domain Name**: Configure Route53 for custom domain
3. **Backup Strategy**: Review RDS backup settings
4. **Monitoring**: Add CloudWatch alarms and dashboards
5. **High Availability**: Consider multi-AZ RDS deployment
6. **Resource Sizing**: Adjust CPU/memory based on usage patterns
7. **Network Security**: Restrict ALB access to specific IP ranges
8. **Database Protection**: Set `db_deletion_protection = true`
9. **Final Snapshots**: Set `db_skip_final_snapshot = false`

## Reference Architecture

This infrastructure serves as a **Reference Architecture for Native Cloud Deployments** demonstrating:

- **Cloud-native patterns**: Serverless containers, managed services
- **Security best practices**: Network isolation, encryption, secrets management
- **Operational excellence**: Centralized logging, monitoring, automation
- **Cost optimization**: Right-sized resources, lifecycle policies
- **Reliability**: Multi-AZ deployment, automated backups

## Support

For issues with this infrastructure:
1. Check the troubleshooting section above
2. Review AWS CloudWatch logs
3. Verify AWS permissions and MFA setup
4. Consult the [Nexus IQ Server documentation](https://help.sonatype.com/iqserver)

For Terraform-specific issues:
- Review the [Terraform AWS Provider documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- Check [AWS service documentation](https://docs.aws.amazon.com/) for specific services
