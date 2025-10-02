# Nexus IQ Server High Availability on AWS EKS

This directory contains Terraform configuration and Helm deployment scripts for deploying Nexus IQ Server in **High Availability (HA)** mode on Amazon EKS using the official Sonatype Helm chart.

## Architecture Overview

This infrastructure deploys a complete, production-ready Nexus IQ Server HA environment including:

- **EKS Cluster** - Managed Kubernetes service with auto-scaling node groups
- **Aurora PostgreSQL Cluster** - High-availability database with multiple instances
- **EFS File System** - Shared persistent storage with access points for data and logs
- **Application Load Balancer** - AWS ALB with health checks and ingress routing
- **VPC & Networking** - Complete network infrastructure with public/private subnets
- **Security Groups** - Least-privilege network access controls
- **IAM Roles** - Service-specific permissions following AWS best practices
- **AWS Load Balancer Controller** - Native Kubernetes ingress integration
- **Fluentd Log Aggregation** - Optional CloudWatch logs integration

```
Internet
    ↓
Application Load Balancer (Public Subnets)
    ↓
EKS Cluster (Private Subnets)
├── Nexus IQ Server HA (2+ replicas) ←→ EFS (Shared Storage)
├── AWS Load Balancer Controller
└── Fluentd (Optional)
    ↓
Aurora PostgreSQL Cluster (Database Subnets)
```

## High Availability Features

- **Multi-AZ Deployment**: Infrastructure spans multiple Availability Zones
- **Auto-Scaling**: EKS node groups and Horizontal Pod Autoscaler (HPA)
- **Database HA**: Aurora PostgreSQL with automatic failover
- **Shared Storage**: EFS provides consistent storage across all replicas
- **Load Balancing**: Application Load Balancer with health checks
- **Pod Anti-Affinity**: Ensures replicas run on different nodes
- **Pod Disruption Budgets**: Maintains availability during updates

## Prerequisites

### Required Tools

- **AWS CLI** configured with appropriate credentials
- **Terraform** >= 1.0
- **kubectl** for Kubernetes cluster management
- **Helm** >= 3.9.3 for application deployment
- **jq** for JSON processing (used by scripts)

### AWS Permissions

Your AWS credentials must have permissions for:
- EKS cluster and node group management
- VPC and networking resources
- Aurora RDS cluster creation
- EFS file system management
- IAM role and policy management
- Application Load Balancer resources
- Systems Manager (Parameter Store)
- Secrets Manager

### Nexus IQ Server Requirements

- Valid Nexus IQ Server license (base64 encoded)
- Kubernetes 1.23+
- PostgreSQL 10.7 or newer (provided by Aurora)

## Quick Start

### 1. Configure Variables

```bash
# Copy the example configuration
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your specific values
vi terraform.tfvars
```

**Required updates in terraform.tfvars:**
- `database_password` - Set a strong password for PostgreSQL
- `nexus_iq_license` - Your base64 encoded Nexus IQ license
- `nexus_iq_admin_password` - Initial admin password
- `ingress_hostname` - (Optional) Custom hostname for ingress
- `acm_certificate_arn` - (Optional) For HTTPS/TLS

### 2. Deploy Infrastructure

```bash
# Plan the infrastructure
./tf-plan.sh

# Apply the infrastructure (15-25 minutes)
./tf-apply.sh
```

### 3. Deploy Nexus IQ Server

```bash
# Install Nexus IQ Server HA using Helm
./helm-install.sh
```

> **Note**: The installation script will automatically create all required Kubernetes resources including namespace, StorageClass, and PersistentVolumeClaim.

### 4. Access Your Application

After deployment, access Nexus IQ Server via:
- **Application Load Balancer URL** (recommended for production)
- **Port forwarding** (for development/testing)

```bash
# Get ALB URL
kubectl get ingress -n nexus-iq

# Or port forward for local access
kubectl port-forward svc/nexus-iq-server-ha 8070:8070 -n nexus-iq
```

## File Structure

### Key Files

**Terraform Infrastructure:**
- `main.tf`, `variables.tf`, `outputs.tf` - Core Terraform configuration
- `eks.tf`, `rds.tf`, `efs.tf`, `alb.tf` - AWS resource definitions
- `terraform.tfvars` - Your environment-specific configuration

**Kubernetes Resources:**
- `helm-values.yaml` - Main Helm chart values file
- `efs-storageclass.yaml` - EFS StorageClass definition
- `nexus-iq-namespace.yaml` - Namespace definition
- `nexus-iq-pvc.yaml` - PersistentVolumeClaim definition

**Deployment Scripts:**
- `tf-*.sh` - Terraform deployment scripts
- `helm-*.sh` - Helm deployment and management scripts

## Configuration

### Infrastructure Configuration

Key variables in `terraform.tfvars`:

```hcl
# AWS Configuration
aws_region = "us-east-1"
environment = "prod"
cluster_name = "nexus-iq-ha"

# EKS Configuration
kubernetes_version = "1.27"
node_instance_type = "m5.large"
node_group_min_size = 2
node_group_max_size = 6
node_group_desired_size = 3

# Aurora Configuration
aurora_instance_class = "db.r6g.large"
aurora_instance_count = 2  # 1 writer + 1 reader

# Nexus IQ HA Configuration
nexus_iq_replica_count = 2
nexus_iq_memory_request = "4Gi"
nexus_iq_memory_limit = "6Gi"
```

### Helm Configuration

Customize the Nexus IQ deployment by editing `helm-values.yaml`:

```yaml
# High Availability Configuration
iq:
  replicaCount: 2

  # Resource Configuration
  resources:
    requests:
      memory: "4Gi"
      cpu: "2"
    limits:
      memory: "6Gi"
      cpu: "4"

# Auto-scaling Configuration
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 70
```

## Deployment Scripts

### Terraform Scripts

- **`tf-plan.sh`** - Plan infrastructure changes
- **`tf-apply.sh`** - Deploy infrastructure
- **`tf-destroy.sh`** - Destroy all resources

### Helm Scripts

- **`helm-install.sh`** - Install Nexus IQ Server HA
- **`helm-upgrade.sh`** - Upgrade existing deployment
- **`helm-uninstall.sh`** - Uninstall deployment (complete cleanup by default)
  - Default: Complete cleanup (removes cluster-wide resources)
  - `--graceful`: Graceful uninstall (preserves cluster resources)

### Script Features

All scripts include:
- ✅ Prerequisite validation
- ✅ AWS credential verification
- ✅ Comprehensive error handling
- ✅ Progress indicators and status updates
- ✅ Cleanup and rollback instructions

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

# View HPA events
kubectl describe hpa nexus-iq-server-ha -n nexus-iq
```

### Database Operations

```bash
# Get database connection info
terraform output rds_cluster_endpoint
terraform output rds_cluster_reader_endpoint

# Connect to database (requires database credentials)
kubectl get secret nexus-iq-db-credentials -n nexus-iq -o yaml
```

## Backup and Recovery

### Database Backups

Aurora PostgreSQL provides:
- **Automated backups** with 7-day retention (configurable)
- **Point-in-time recovery** within backup retention period
- **Manual snapshots** for longer-term retention

### EFS Backups

EFS automatic backups are enabled by default:
- **Daily backups** with lifecycle management
- **Cross-region replication** (optional)

### Configuration Backups

```bash
# Backup Helm configuration
helm get values nexus-iq-server-ha -n nexus-iq > backup-helm-values.yaml

# Backup Kubernetes resources
kubectl get all -n nexus-iq -o yaml > backup-k8s-resources.yaml
```

## Troubleshooting

### Common Issues

1. **Pods stuck in Pending state**
   ```bash
   kubectl describe pod <pod-name> -n nexus-iq
   # Check events for resource constraints or scheduling issues
   ```

2. **Database connection issues**
   ```bash
   # Verify database credentials
   kubectl get secret nexus-iq-db-credentials -n nexus-iq -o yaml

   # Check security group rules
   aws ec2 describe-security-groups --group-ids $(terraform output -raw rds_security_group_id)
   ```

3. **EFS mount issues**
   ```bash
   # Check EFS mount targets
   aws efs describe-mount-targets --file-system-id $(terraform output -raw efs_id)

   # Verify EFS security group
   kubectl describe pv | grep efs
   ```

5. **Stuck resources during cleanup**
   ```bash
   # Force complete cleanup (default behavior)
   ./helm-uninstall.sh

   # If namespace is stuck in Terminating state
   kubectl patch namespace nexus-iq -p '{"metadata":{"finalizers":[]}}' --type=merge

   # Remove stuck PersistentVolumes
   kubectl get pv | grep nexus
   kubectl patch pv <pv-name> -p '{"metadata":{"finalizers":[]}}' --type=merge
   ```

4. **Load Balancer not accessible**
   ```bash
   # Check ALB status
   kubectl get ingress -n nexus-iq
   kubectl describe ingress nexus-iq-server-ha -n nexus-iq

   # Check AWS Load Balancer Controller logs
   kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
   ```

### Debug Commands

```bash
# Get cluster info
kubectl cluster-info

# Check node status
kubectl get nodes -o wide

# Check system pods
kubectl get pods -n kube-system

# View events
kubectl get events --sort-by='.lastTimestamp' -n nexus-iq

# Check resource usage
kubectl top nodes
kubectl top pods -n nexus-iq
```

## Security Considerations

### Network Security

- **VPC isolation** with private subnets for EKS and database
- **Security groups** with minimal required access
- **Network ACLs** for additional layer of security

### Access Control

- **IAM roles** with least-privilege permissions
- **Kubernetes RBAC** for service account permissions
- **Pod security contexts** for non-root execution

### Data Encryption

- **EFS encryption** at rest and in transit
- **Aurora encryption** at rest with KMS
- **EBS encryption** for EKS node storage

### Secrets Management

- **Kubernetes secrets** for database credentials and licenses
- **AWS Secrets Manager** integration (optional)
- **Parameter Store** for non-sensitive configuration

## Cost Optimization

### Right-sizing Recommendations

- **EKS nodes**: Start with m5.large, scale based on usage
- **Aurora instances**: db.r6g.large for production workloads
- **EFS**: Use provisioned throughput only if needed

### Cost Monitoring

```bash
# Check resource usage
kubectl top nodes
kubectl top pods -n nexus-iq

# Monitor Aurora usage
aws rds describe-db-clusters --db-cluster-identifier $(terraform output -raw cluster_id)-aurora-cluster
```

## Upgrading

### Infrastructure Updates

```bash
# Update Terraform configuration
vi terraform.tfvars

# Plan and apply changes
./tf-plan.sh
./tf-apply.sh
```

### Application Updates

```bash
# Update Helm chart version in terraform.tfvars
vi terraform.tfvars

# Update helm-values.yaml if needed
vi helm-values.yaml

# Perform rolling upgrade
./helm-upgrade.sh
```

### Kubernetes Version Updates

EKS cluster version updates should be performed carefully:

1. Update `kubernetes_version` in `terraform.tfvars`
2. Run `./tf-plan.sh` to review changes
3. Apply during maintenance window
4. Update node groups following AWS recommendations

## Cleanup

### Remove Application Only

```bash
# Complete cleanup (default) - removes everything including cluster resources
./helm-uninstall.sh

# Graceful uninstall - preserves cluster-wide resources like EFS StorageClass
./helm-uninstall.sh --graceful
```

> **Note**: The default behavior performs a complete cleanup including removal of cluster-wide resources (StorageClass, PersistentVolumes) and handles stuck finalizers. This ensures a clean state for fresh installations.

### Remove All Infrastructure

```bash
# WARNING: This will delete ALL data
./tf-destroy.sh
```

## Support and Documentation

- **Architecture Details**: See [ARCHITECTURE.md](ARCHITECTURE.md)
- **Nexus IQ Server Documentation**: [https://help.sonatype.com/iqserver](https://help.sonatype.com/iqserver)
- **Helm Chart Repository**: [https://github.com/sonatype/nexus-iq-server-ha](https://github.com/sonatype/nexus-iq-server-ha)
- **AWS EKS Documentation**: [https://docs.aws.amazon.com/eks/](https://docs.aws.amazon.com/eks/)

## Contributing

When making changes to this infrastructure:

1. Test changes in a development environment first
2. Update documentation as needed
3. Follow Terraform and Kubernetes best practices
4. Ensure all scripts remain executable and functional

---

**⚠️ Important Notes:**

- This configuration creates production-grade infrastructure with associated AWS costs
- Database deletion protection is enabled by default
- EFS and Aurora have backup enabled by default
- Review all security groups and IAM policies before production deployment