# Nexus IQ Server AWS EKS Infrastructure (High Availability)

This directory contains Terraform configuration for deploying Nexus IQ Server on AWS using EKS (Elastic Kubernetes Service) with Helm in a **High Availability configuration** as part of a **Reference Architecture for Kubernetes Cloud Deployments**.

## Architecture Overview

This infrastructure deploys a complete, production-ready Nexus IQ Server High Availability environment including:

- **EKS Cluster** - Managed Kubernetes service with auto-scaling node groups
- **Aurora PostgreSQL Cluster** - High-availability database with multiple instances
- **EFS File System** - Shared persistent storage with access points for clustering
- **Application Load Balancer** - AWS ALB with health checks and ingress routing
- **VPC & Networking** - Complete network infrastructure with public/private subnets
- **Security Groups** - Least-privilege network access controls
- **IAM Roles** - Service-specific permissions following AWS best practices
- **AWS Load Balancer Controller** - Native Kubernetes ingress integration
- **Helm Chart Deployment** - Official Sonatype Nexus IQ Server HA chart

```
Internet
    ↓
Application Load Balancer (Public Subnets)
    ↓
EKS Cluster (Private Subnets)
├── Nexus IQ Server HA (2+ replicas) ←→ EFS (Shared Storage)
├── AWS Load Balancer Controller
└── Ingress Controller
    ↓
Aurora PostgreSQL Cluster (Database Subnets)
```

## Prerequisites

### Required Tools
- **Terraform** >= 1.0
- **AWS CLI** >= 2.0
- **kubectl** for Kubernetes cluster management
- **Helm** >= 3.9.3 for application deployment
- **aws-vault** (recommended for MFA)

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

## Quick Start

1. **Navigate to the infrastructure directory**:
   ```bash
   cd /path/to/sca-example-terraform/infra-aws-ha-k8s-helm
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

6. **Deploy Nexus IQ Server**:
   ```bash
   ./helm-install.sh
   ```

7. **Access your Nexus IQ Server**:
   - Get the application URL: `kubectl get ingress -n nexus-iq`
   - Wait 10-15 minutes for service to be ready
   - Default credentials: `admin` / `admin123`

## Configuration

### 1. Review Variables in terraform.tfvars

Edit `terraform.tfvars` to customize your deployment:

```hcl
# General Configuration
aws_region = "us-east-1"
environment = "prod"
cluster_name = "nexus-iq-ha"

# EKS Configuration
kubernetes_version = "1.27"
node_instance_type = "m5.2xlarge"
node_group_min_size = 2
node_group_max_size = 6
node_group_desired_size = 3

# Aurora Configuration
aurora_instance_class = "db.r6g.2xlarge"
aurora_instance_count = 2  # 1 writer + 1 reader
database_password = "YourSecurePassword123!"  # Change this!

# Nexus IQ HA Configuration
nexus_iq_replica_count = 2
nexus_iq_license = "base64-encoded-license"
nexus_iq_admin_password = "admin123"
```

### 2. Important Settings

- **`nexus_iq_replica_count = 2`** - Minimum for HA (requires HA license)
- **`database_password`** - Use a strong, unique password
- **`nexus_iq_license`** - Base64 encoded HA-capable license
- **Resource Names** - All AWS resources are prefixed with cluster name

## High Availability Features

- **Multi-AZ Deployment**: Infrastructure spans multiple Availability Zones
- **Auto-Scaling**: EKS node groups and Horizontal Pod Autoscaler (HPA)
- **Database HA**: Aurora PostgreSQL with automatic failover
- **Shared Storage**: EFS provides consistent storage across all replicas
- **Load Balancing**: Application Load Balancer with health checks
- **Pod Anti-Affinity**: Ensures replicas run on different nodes
- **Pod Disruption Budgets**: Maintains availability during updates

## Security Features

- **VPC Isolation**: Application runs in private subnets
- **Database Security**: Aurora in isolated database subnets
- **Secrets Management**: Database credentials stored in Kubernetes secrets
- **Encryption**:
  - EFS encrypted at rest and in transit
  - Aurora encrypted at rest
  - EBS encryption for EKS node storage
- **Security Groups**: Least-privilege network access
- **RBAC**: Kubernetes role-based access control

## Monitoring and Operations

### Check Deployment Status

```bash
# Check pod status
kubectl get pods -n nexus-iq

# Check service status
kubectl get svc -n nexus-iq

# Check ingress status
kubectl get ingress -n nexus-iq

# View logs
kubectl logs -f -l app.kubernetes.io/name=nexus-iq-server-ha -n nexus-iq
```

### Scaling Operations

```bash
# Scale manually
kubectl scale deployment nexus-iq-server-ha --replicas=3 -n nexus-iq

# Check HPA status
kubectl get hpa -n nexus-iq
```

## Automated Deployment Scripts

This infrastructure includes convenient scripts that handle MFA authentication automatically:

### Available Scripts

- **`./tf-plan.sh`** - Preview infrastructure changes with MFA authentication
- **`./tf-apply.sh`** - Deploy infrastructure with MFA authentication
- **`./tf-destroy.sh`** - Destroy infrastructure with automatic cleanup
- **`./helm-install.sh`** - Install Nexus IQ Server HA using Helm
- **`./helm-upgrade.sh`** - Upgrade existing Helm deployment
- **`./helm-uninstall.sh`** - Uninstall Helm deployment with cleanup

## AWS Console Access

Monitor your infrastructure in the AWS Console:

- **EKS Cluster**: EKS → Clusters → `nexus-iq-ha`
- **Database**: RDS → Databases → `nexus-iq-ha-aurora-cluster`
- **Load Balancer**: EC2 → Load Balancers → ALB created by ingress
- **VPC**: VPC → Your VPCs → `nexus-iq-ha-vpc`
- **Storage**: EFS → File Systems → `nexus-iq-ha-efs`

## File Structure

```
infra-aws-ha-k8s-helm/
├── main.tf                    # VPC, networking, and core infrastructure
├── eks.tf                     # EKS cluster and node groups
├── rds.tf                     # Aurora PostgreSQL cluster
├── efs.tf                     # EFS file system
├── alb.tf                     # Application Load Balancer controller
├── variables.tf               # Input variable definitions
├── outputs.tf                 # Output value definitions
├── terraform.tfvars           # Infrastructure configuration
├── helm-values.yaml           # Helm chart values
├── efs-storageclass.yaml      # EFS StorageClass
├── nexus-iq-namespace.yaml    # Kubernetes namespace
├── nexus-iq-pvc.yaml          # PersistentVolumeClaim
├── tf-*.sh                    # Terraform deployment scripts
├── helm-*.sh                  # Helm deployment scripts
└── README.md                  # This file
```

## Troubleshooting

### Common Issues

1. **MFA Authentication Fails**
   ```bash
   # Verify your AWS configuration
   aws sts get-caller-identity --profile admin@iq-sandbox
   ```

2. **Pods stuck in Pending state**
   ```bash
   kubectl describe pod <pod-name> -n nexus-iq
   # Check events for resource constraints or scheduling issues
   ```

3. **Database connection issues**
   ```bash
   # Verify database credentials
   kubectl get secret nexus-iq-db-credentials -n nexus-iq -o yaml
   ```

4. **EFS mount issues**
   ```bash
   # Check EFS mount targets
   aws efs describe-mount-targets --file-system-id $(terraform output -raw efs_id)
   ```

5. **Load Balancer not accessible**
   ```bash
   # Check ALB status
   kubectl get ingress -n nexus-iq
   kubectl describe ingress nexus-iq-server-ha -n nexus-iq
   ```

## Cleanup

### Remove Application Only

```bash
# Complete cleanup (default)
./helm-uninstall.sh

# Graceful uninstall (preserves cluster resources)
./helm-uninstall.sh --graceful
```

### Remove All Infrastructure

```bash
# WARNING: This will delete ALL data
./tf-destroy.sh
```

## Production Considerations

For production deployments, consider:

1. **SSL/TLS Certificate**: Add ACM certificate and HTTPS ingress
2. **Domain Name**: Configure Route53 for custom domain
3. **Backup Strategy**: Review Aurora and EFS backup settings
4. **Monitoring**: Add CloudWatch alarms and dashboards
5. **Resource Sizing**: Adjust CPU/memory based on usage patterns
6. **Network Security**: Restrict ingress access to specific IP ranges
7. **License Management**: Ensure HA license compliance

## Reference Architecture

This infrastructure serves as a **Reference Architecture for Kubernetes Cloud Deployments** demonstrating:

- **Cloud-native patterns**: Managed Kubernetes, containerized deployments
- **High availability**: Multi-AZ deployment, auto-scaling, shared storage
- **Security best practices**: Network isolation, encryption, RBAC
- **Operational excellence**: Centralized logging, monitoring, automation
- **Cost optimization**: Right-sized resources, auto-scaling
- **Reliability**: Multi-AZ deployment, automated backups

## Support

For issues with this infrastructure:
1. Check the troubleshooting section above
2. Review AWS CloudWatch and Kubernetes logs
3. Verify AWS permissions and MFA setup
4. Consult the [Nexus IQ Server documentation](https://help.sonatype.com/iqserver)
