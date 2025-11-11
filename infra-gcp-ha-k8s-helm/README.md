# Nexus IQ Server GCP GKE Infrastructure (High Availability)

This directory contains Terraform configuration for deploying Nexus IQ Server on GCP using GKE (Google Kubernetes Engine) with Helm in a **High Availability configuration** as part of a **Reference Architecture for Kubernetes Cloud Deployments**.

## Architecture Overview

This infrastructure deploys a complete, production-ready Nexus IQ Server High Availability environment including:

- **GKE Cluster** - Multi-zone managed Kubernetes service with autoscaling node pools
- **Cloud SQL PostgreSQL Regional** - High-availability database with automatic failover across zones
- **Filestore** - Shared NFS persistent storage (2.5TB BASIC_SSD) for clustering
- **Cloud Load Balancer** - L7 HTTP(S) load balancer via GKE Ingress with Cloud Armor
- **VPC & Networking** - Complete network infrastructure with private cluster configuration
- **Workload Identity** - Secure service account access (GCP's IRSA equivalent)
- **Cloud Logging** - Fluentd aggregator pattern for centralized logging
- **Helm Chart Deployment** - Official Sonatype Nexus IQ Server HA chart

```
Internet
    ↓
Cloud Load Balancer (L7 with Cloud Armor)
    ↓
GKE Cluster (Private, Multi-Zone)
├── Nexus IQ Server HA (2-10 replicas) ←→ Filestore (Shared NFS)
├── Fluentd Aggregator (Cloud Logging)
└── Horizontal Pod Autoscaler
    ↓
Cloud SQL PostgreSQL Regional (Multi-Zone with Automatic Failover)
```

## Prerequisites

### Required Tools
- **Terraform** >= 1.0
- **Google Cloud SDK** >= 400.0
- **kubectl** for Kubernetes cluster management
- **Helm** >= 3.9.3 for application deployment
- **gcloud** authentication completed

### GCP Account Requirements
- GCP project with billing enabled
- Authenticated gcloud CLI
- Sufficient IAM permissions to create resources
- APIs enabled (script will enable automatically)

## GCP Configuration Setup

### 1. GCloud CLI Configuration

Authenticate with Google Cloud:

```bash
gcloud auth login

gcloud config set project your-project-id

gcloud auth application-default login
```

### 2. Verify Configuration

Test your GCP configuration:
```bash
gcloud config list
gcloud projects list
```

## Quick Start

1. **Navigate to the infrastructure directory**:
   ```bash
   cd /path/to/sca-example-terraform/infra-gcp-ha-k8s-helm
   ```

2. **Review and customize variables**:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   vim terraform.tfvars
   ```

3. **Plan the deployment**:
   ```bash
   ./tf-plan.sh
   ```

4. **Deploy the infrastructure**:
   ```bash
   ./tf-apply.sh
   ```

5. **Deploy Nexus IQ Server**:
   ```bash
   ./helm-install.sh
   ```

6. **Access your Nexus IQ Server**:
   - Get the ingress IP: `kubectl get ingress -n nexus-iq`
   - Wait 10-15 minutes for service to be ready
   - Default credentials: `admin` / `admin123`

## Configuration

### 1. Review Variables in terraform.tfvars

Edit `terraform.tfvars` to customize your deployment:

```hcl
gcp_project_id = "your-gcp-project-id"
gcp_region     = "us-central1"
environment    = "prod"
cluster_name   = "nexus-iq-ha"

public_subnet_cidr   = "10.100.1.0/24"
private_subnet_cidrs = ["10.100.10.0/24", "10.100.11.0/24", "10.100.12.0/24"]

kubernetes_version      = "1.27"
node_instance_type      = "n2-standard-8"
node_group_min_size     = 2
node_group_max_size     = 6
node_group_desired_size = 3

postgres_version         = "POSTGRES_15"
db_instance_tier         = "db-custom-8-30720"
db_availability_type     = "REGIONAL"
db_password              = "YourSecurePassword123!"

filestore_tier        = "BASIC_SSD"
filestore_capacity_gb = 2560

nexus_iq_replica_count = 3
```

### 2. Important HA Settings

- **`node_group_min_size = 2`** - Minimum nodes for HA
- **`node_group_max_size = 6`** - Maximum auto scaling capacity
- **`db_availability_type = "REGIONAL"`** - Multi-zone database with automatic failover
- **`enable_read_replica = true`** - Database read replica for load distribution
- **`filestore_tier = "BASIC_SSD"`** - High-performance NFS storage
- **`nexus_iq_replica_count = 3`** - Minimum 2 for HA (requires HA license)

## High Availability Features

### Multi-Zone Deployment
- **GKE Node Pools**: Automatically distributed across zones
- **Cloud SQL Regional**: Multi-zone with automatic failover
- **Filestore**: Zone-redundant shared storage

### Auto-Scaling & Load Balancing
- **Horizontal Pod Autoscaler**: CPU (70%) and memory (80%) based scaling (2-10 pods)
- **Cluster Autoscaler**: Node-level scaling (2-6 nodes)
- **Cloud Load Balancer**: L7 load balancing with health checks
- **Rolling Updates**: Zero-downtime deployments with Pod Disruption Budgets

### Data Protection
- **Database**: Regional Cloud SQL with automatic failover
- **Storage**: Filestore with shared NFS for clustering
- **Secrets**: Secret Manager with Workload Identity
- **Monitoring**: Cloud Logging and Cloud Monitoring

### Clustering Support
- **Shared Storage**: Filestore provides consistent storage across all replicas
- **Work Directory**: All pods share `/sonatype-work/clm-server` (requires HA license)
- **Cluster Directory**: Coordination through `/sonatype-work/clm-cluster`
- **Database Sharing**: All pods connect to shared Cloud SQL cluster
- **Pod Anti-Affinity**: Ensures pods run on different nodes
- **Pod Disruption Budget**: Maintains minAvailable: 1 during updates

## Security Features

- **Private GKE Cluster**: Nodes in private subnets with no public IPs
- **Workload Identity**: Secure service account access without keys
- **Encrypted Storage**: Cloud SQL and Filestore encrypted at rest and in transit
- **Secret Manager**: Database credentials stored securely
- **Cloud Armor**: DDoS protection and rate limiting
- **Network Security**: Firewall rules and private networking
- **SSL/TLS**: Optional HTTPS with managed certificates

## Monitoring and Operations

### Cloud Logging

This deployment uses **production-grade logging** with a unified Cloud Logging approach via Fluentd:

#### Fluentd Aggregator Pattern
- **Fluentd Sidecars**: Lightweight log forwarders in each IQ Server pod
- **Fluentd Aggregator**: Central aggregator pod receives logs from sidecars
- **Unified Log Stream**: All logs sent to Cloud Logging
- **Workload Identity**: Fluentd uses Workload Identity for secure authentication

#### Viewing Cloud Logs

```bash
gcloud logging read 'resource.type="k8s_container" AND resource.labels.namespace_name="nexus-iq"' --limit=50

gcloud logging read 'resource.type="k8s_container" AND resource.labels.namespace_name="nexus-iq" AND severity>=ERROR' --limit=20
```

### Check Deployment Status

```bash
kubectl get pods -n nexus-iq

kubectl get svc -n nexus-iq

kubectl get ingress -n nexus-iq

kubectl logs -f -l app.kubernetes.io/name=nexus-iq-server-ha -n nexus-iq
```

### Scaling Operations

```bash
kubectl scale deployment nexus-iq-server-ha --replicas=5 -n nexus-iq

kubectl get hpa -n nexus-iq

kubectl top pods -n nexus-iq
```

## Automated Deployment Scripts

This infrastructure includes convenient scripts for deployment:

### Available Scripts

- **`./tf-plan.sh`** - Preview infrastructure changes
- **`./tf-apply.sh`** - Deploy infrastructure
- **`./tf-destroy.sh`** - Destroy infrastructure with cleanup
- **`./helm-install.sh`** - Install Nexus IQ Server HA using Helm
- **`./helm-upgrade.sh`** - Upgrade existing Helm deployment
- **`./helm-uninstall.sh`** - Uninstall Helm deployment

## GCP Console Access

Monitor your infrastructure in the GCP Console:

- **GKE Cluster**: Kubernetes Engine → Clusters → `nexus-iq-ha`
- **Database**: SQL → Instances → `nexus-iq-ha-db-*`
- **Load Balancer**: Network Services → Load balancing
- **Logs**: Logging → Logs Explorer (filter by namespace: nexus-iq)
- **VPC**: VPC Network → VPC networks → `nexus-iq-ha-vpc`
- **Filestore**: Filestore → Instances → `nexus-iq-ha-filestore-*`

## File Structure

```
infra-gcp-ha-k8s-helm/
├── main.tf                      # VPC, networking, provider config
├── gke.tf                       # GKE cluster, node pools, Workload Identity
├── database.tf                  # Cloud SQL PostgreSQL Regional
├── storage.tf                   # Filestore NFS
├── logging.tf                   # Cloud Logging, metrics, alerts
├── security.tf                  # Firewall rules, Cloud Armor
├── variables.tf                 # Input variable definitions
├── outputs.tf                   # Output value definitions
├── terraform.tfvars.example     # Example configuration
├── helm-values.yaml             # Helm chart values
├── nexus-iq-namespace.yaml      # Kubernetes namespace
├── filestore-pv.yaml            # Filestore PersistentVolume
├── filestore-pvc.yaml           # PersistentVolumeClaim
├── tf-plan.sh                   # Planning script
├── tf-apply.sh                  # Deployment script
├── tf-destroy.sh                # Cleanup script
├── helm-install.sh              # Helm install script
├── helm-upgrade.sh              # Helm upgrade script
├── helm-uninstall.sh            # Helm uninstall script
└── README.md                    # This file
```

## Troubleshooting

### Common Issues

1. **Pods stuck in Pending state**
   ```bash
   kubectl describe pod <pod-name> -n nexus-iq
   ```

2. **Database connection issues**
   ```bash
   gcloud sql instances describe nexus-iq-ha-db-* --project your-project-id
   ```

3. **Filestore mount issues**
   ```bash
   gcloud filestore instances list --project your-project-id
   kubectl describe pv nexus-iq-filestore-pv
   ```

4. **Load Balancer not accessible**
   ```bash
   kubectl get ingress -n nexus-iq
   kubectl describe ingress nexus-iq-server-ha -n nexus-iq
   ```

5. **View logs from all pods**
   ```bash
   kubectl logs -f -l app.kubernetes.io/name=nexus-iq-server-ha -n nexus-iq --all-containers=true
   ```

## Cleanup

### Remove Application Only

```bash
./helm-uninstall.sh
```

### Remove All Infrastructure

```bash
./tf-destroy.sh
```

**Warning**: Complete cleanup will permanently delete all data including the Cloud SQL database and Filestore. Ensure you have backups if needed.

## Production Considerations

For production HA deployments, consider:

1. **SSL/TLS Certificate**: Configure managed certificates for HTTPS
2. **Custom Domain**: Set up Cloud DNS for custom domain
3. **Backup Strategy**: Review Cloud SQL and Filestore backup settings
4. **Monitoring**: Add Cloud Monitoring alert notification channels
5. **Resource Sizing**: Adjust instance types and auto scaling based on usage
6. **Network Security**: Restrict ingress access with Cloud Armor rules
7. **License Management**: Ensure HA license compliance (minimum 2 replicas)
8. **Disaster Recovery**: Consider multi-region deployment strategy
9. **Cost Optimization**: Use committed use discounts for predictable workloads
10. **Security Hardening**: Enable Binary Authorization, Pod Security Policies

## Cost Optimization

- **GKE**: Pay for nodes with Cluster Autoscaler (scales down to save costs)
- **Cloud SQL**: Right-sized instance with storage auto-scaling
- **Filestore**: BASIC_SSD tier balances performance and cost
- **Committed Use Discounts**: Optional for predictable workloads
- **Auto Scaling**: Dynamically adjusts capacity based on demand

**Estimated Monthly Costs** (us-central1, 24/7 operation):
- GKE Nodes (3x n2-standard-8): ~$750-900
- Cloud SQL Regional (db-custom-8-30720): ~$1,200
- Cloud SQL Read Replica: ~$600
- Filestore (2.5TB BASIC_SSD): ~$640
- Load Balancer: ~$18-25
- **Total**: ~$3,210-3,365/month

*Note: Costs vary by region and usage. Use [GCP Pricing Calculator](https://cloud.google.com/products/calculator) for accurate estimates.*

## Reference Architecture

This HA infrastructure serves as a **Reference Architecture for Kubernetes Cloud Deployments** demonstrating:

- **Cloud-native patterns**: Managed Kubernetes, containerized deployments
- **High availability**: Multi-zone deployment, auto-scaling, shared storage
- **Security best practices**: Workload Identity, encryption, private networking
- **Operational excellence**: Centralized logging, monitoring, automation
- **Cost optimization**: Right-sized resources, auto-scaling
- **Reliability**: Multi-zone deployment, automated backups, health checks

## Support

For issues with this HA infrastructure:
1. Check the troubleshooting section above
2. Review Cloud Logging and GKE logs
3. Verify GCP permissions and quotas
4. Consult the [Nexus IQ Server documentation](https://help.sonatype.com/iqserver)
5. Review [GKE documentation](https://cloud.google.com/kubernetes-engine/docs)
6. Check [Cloud SQL documentation](https://cloud.google.com/sql/docs)

For Terraform-specific issues:
- Review the [Terraform Google Provider documentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- Check [GCP service documentation](https://cloud.google.com/docs)
