# Sonatype IQ Server Reference Architectures

This repository contains Terraform configurations for deploying Sonatype IQ Server across multiple cloud providers (AWS, Azure, GCP) with various deployment patterns including single-instance and high-availability configurations.

## Repository Structure

This repository contains **9 reference architectures** organized by cloud provider and deployment pattern:

### AWS Deployments
- **[infra-aws](infra-aws/)** - Single instance deployment with ECS Fargate and RDS PostgreSQL
- **[infra-aws-ha](infra-aws-ha/)** - High availability deployment with ECS Fargate, Aurora PostgreSQL cluster, and EFS clustering
- **[infra-aws-ha-k8s-helm](infra-aws-ha-k8s-helm/)** - High availability deployment on EKS with Helm chart

### Azure Deployments
- **[infra-azure](infra-azure/)** - Single instance deployment with Container Apps and Azure Database for PostgreSQL
- **[infra-azure-ha](infra-azure-ha/)** - High availability deployment with Container Apps and zone-redundant PostgreSQL
- **[infra-azure-ha-k8s-helm](infra-azure-ha-k8s-helm/)** - High availability deployment on AKS with Helm chart

### GCP Deployments
- **[infra-gcp](infra-gcp/)** - Single instance deployment with GCE Docker containers and Cloud SQL PostgreSQL
- **[infra-gcp-ha](infra-gcp-ha/)** - High availability deployment with Managed Instance Groups and regional Cloud SQL
- **[infra-gcp-ha-k8s-helm](infra-gcp-ha-k8s-helm/)** - High availability deployment on GKE with Helm chart

## Deployment Patterns

### Single Instance Deployments
Suitable for development, testing, or small-scale production environments:
- Lower cost and simpler infrastructure
- Single availability zone deployment
- Automatic container/instance restarts on failure
- Standard database with automated backups

**Available for**: AWS, Azure, GCP

### High Availability Deployments
Designed for production environments requiring high availability and scalability:
- Multi-zone deployment across availability zones
- Auto-scaling based on CPU, memory, or load metrics
- Regional/zone-redundant database with automatic failover
- Shared storage (EFS, Azure Files, Cloud Filestore) for clustering
- Load balancing across multiple instances/pods
- Rolling updates with zero downtime

**Available for**: AWS, Azure, GCP

### Kubernetes Deployments (EKS/AKS/GKE)
Enterprise-grade Kubernetes deployments using official Sonatype Helm charts:
- Horizontal Pod Autoscaler (HPA) for dynamic scaling
- Cluster Autoscaler for node-level scaling
- Kubernetes-native service discovery and load balancing
- Pod anti-affinity for distribution across nodes and zones
- Pod Disruption Budgets for update reliability
- RBAC and Workload Identity/IRSA for security

**Available for**: AWS (EKS), Azure (AKS), GCP (GKE)

## Quick Start

Each deployment directory contains its own comprehensive README with step-by-step instructions. General workflow:

1. **Choose a deployment** based on your cloud provider and requirements
2. **Install prerequisites**: Terraform, cloud CLI (aws/az/gcloud), kubectl (for K8s), Helm (for K8s)
3. **Configure credentials**: Authenticate with your cloud provider
4. **Customize variables**: Copy and edit `terraform.tfvars.example`
5. **Deploy infrastructure**: Run `terraform init`, then use the provided deployment scripts (`./tf-plan.sh` and `./tf-apply.sh`)
6. **Deploy application** (K8s only): Run the provided Helm install script (`./helm-install.sh`)
7. **Access IQ Server**: Use the load balancer URL provided in outputs

## Security Considerations

All deployments implement security best practices:
- **Private subnets** for application and database resources
- **Encryption at rest** for databases and storage
- **Encryption in transit** with TLS/SSL support
- **Least-privilege IAM** roles and service accounts
- **Secrets management** using cloud-native solutions
- **Network isolation** with VPC/VNet and security groups
- **No public database access** - databases in private subnets only

## Cost Considerations

Deployment costs vary significantly by:
- **Cloud provider** and region
- **Deployment pattern** (single instance vs HA)
- **Instance/node sizes** and auto-scaling configuration
- **Database tier** and storage configuration
- **Data transfer** and load balancer usage

**Cost Optimization Tips:**
- Start with single instance deployments for non-production
- Use auto-scaling to reduce costs during low-usage periods
- Review and right-size compute resources based on usage
- Use committed use discounts for predictable workloads
- Enable storage auto-scaling with appropriate limits

## Support and Documentation

### Sonatype Resources
- **IQ Server Documentation**: [help.sonatype.com/iqserver](https://help.sonatype.com/iqserver)
- **Sonatype Support**: [support.sonatype.com](https://support.sonatype.com)

### Cloud Provider Documentation
- **AWS**: [docs.aws.amazon.com](https://docs.aws.amazon.com)
- **Azure**: [docs.microsoft.com/azure](https://docs.microsoft.com/azure)
- **GCP**: [cloud.google.com/docs](https://cloud.google.com/docs)

### Terraform Documentation
- **Terraform**: [terraform.io/docs](https://terraform.io/docs)
- **AWS Provider**: [registry.terraform.io/providers/hashicorp/aws](https://registry.terraform.io/providers/hashicorp/aws)
- **Azure Provider**: [registry.terraform.io/providers/hashicorp/azurerm](https://registry.terraform.io/providers/hashicorp/azurerm)
- **GCP Provider**: [registry.terraform.io/providers/hashicorp/google](https://registry.terraform.io/providers/hashicorp/google)

## Contributing

When contributing to this repository:
1. Maintain consistency with existing deployment patterns
2. Follow the established README structure for each deployment
3. Verify all Terraform configurations with `terraform validate` and `terraform plan`
4. Test deployments in a non-production environment
5. Update documentation to reflect any configuration changes

## Disclaimer

These reference architectures are provided as examples and starting points for deploying Sonatype IQ Server in cloud environments. Organizations should review and customize these configurations to meet their specific security, compliance, and operational requirements before deploying to production environments.

