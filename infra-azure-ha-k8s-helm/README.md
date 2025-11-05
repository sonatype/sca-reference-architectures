# Nexus IQ Server Azure Kubernetes Service Infrastructure (High Availability)

This directory contains Terraform configuration for deploying Nexus IQ Server on Azure using AKS (Azure Kubernetes Service) with Helm in a **High Availability configuration** as part of a **Reference Architecture for Enterprise Cloud Deployments**.

## Architecture Overview

This infrastructure deploys a complete, production-ready Nexus IQ Server High Availability environment including:

- **AKS Cluster (2-10 pods)** - Multi-pod Kubernetes deployment with Horizontal Pod Autoscaler
- **Zone-Redundant Application Gateway** - HTTP load balancer with health checks across availability zones
- **Zone-Redundant PostgreSQL Flexible Server** - Managed database with automatic failover
- **Azure Files Premium (ZRS)** - Zone-redundant shared storage with CSI driver
- **Azure LoadBalancer** - Kubernetes LoadBalancer service with health probe integration
- **Virtual Network & Subnets** - Multi-zone network infrastructure with security groups
- **Helm Chart Deployment** - Official Sonatype Nexus IQ Server HA chart
- **Auto Scaling** - Horizontal Pod Autoscaler with CPU and memory triggers
- **Pod Anti-Affinity** - Ensures pods run on different nodes for resilience

```
Internet
    ↓
Application Gateway (Zone-Redundant, Multiple AZs)
    ↓
Azure LoadBalancer (Port 8070, Health Probes)
    ↓
AKS Pods (2-10 pods, Auto-scaling, Multi-Zone) ←→ Azure Files Premium (ZRS)
    ↓
PostgreSQL Flexible Server (Zone-Redundant with Standby)
```

## High Availability Features

### **Multi-Zone Redundancy**
- **Application Gateway**: Zone-redundant deployment across 3 availability zones
- **AKS Node Pools**: Automatic distribution across zones
- **PostgreSQL**: Zone-redundant with automatic standby in different zone
- **Storage**: Zone-Redundant Storage (ZRS) for 99.9999999999% durability

### **Auto-Scaling & Load Balancing**
- **Horizontal Pod Autoscaler**: CPU (70%) and memory (80%) based scaling (2-10 pods)
- **Cluster Autoscaler**: Node-level scaling (1-4 nodes)
- **Azure LoadBalancer**: Automatic load balancing with HTTP health probes
- **Rolling Updates**: Zero-downtime deployments with Pod Disruption Budgets

### **Data Protection**
- **Database**: Zone-redundant PostgreSQL with automatic failover (~30 seconds)
- **Storage**: Azure Files Premium with zone redundancy and CSI driver
- **Secrets**: Kubernetes secrets with optional Azure Key Vault CSI driver
- **Monitoring**: Azure Monitor Container Insights and Log Analytics

### **Clustering Support**
- **Shared Storage**: Azure Files Premium provides consistent storage across all replicas
- **Work Directory**: All pods share `/sonatype-work/clm-server` with HA license-enabled clustering
- **Cluster Directory**: Coordination through `/sonatype-work/clm-cluster`
- **Database Sharing**: All pods connect to shared PostgreSQL cluster
- **HA License Required**: Clustering-capable license enables Quartz scheduler clustering
- **Pod Anti-Affinity**: Ensures pods run on different nodes
- **Pod Disruption Budget**: Maintains minAvailable: 1 during updates

## Prerequisites

### Required Tools
- **Terraform** >= 1.0
- **Azure CLI** >= 2.0
- **kubectl** for Kubernetes cluster management
- **Helm** >= 3.9.3 for application deployment
- **az login** authentication completed

### Azure Account Requirements
- Azure subscription with administrative access
- Sufficient vCPU quota (48+ vCPUs required for Standard_D8s_v3 nodes in production HA setup)
- Resource creation rights in target region (East US 2)

## Quick Start

1. **Navigate to the HA infrastructure directory**:
   ```bash
   cd /path/to/sca-example-terraform/infra-azure-ha-k8s-helm
   ```

2. **Copy and customize variables**:
   ```bash
   # Edit terraform.tfvars with your specific values
   vim terraform.tfvars
   ```

3. **Initialize Terraform**:
   ```bash
   terraform init
   ```

4. **Plan the HA deployment**:
   ```bash
   ./tf-plan.sh
   ```

5. **Deploy the HA infrastructure**:
   ```bash
   ./tf-apply.sh
   ```

6. **Deploy Nexus IQ Server HA using Helm**:
   ```bash
   ./helm-install.sh
   ```

7. **Access your Nexus IQ Server HA cluster**:
   - Get the URL: `terraform output application_gateway_fqdn`
   - URL format: `http://nexus-iq-ha-<random>.eastus2.cloudapp.azure.com`
   - Wait 5-10 minutes for all HA services to be ready
   - **Note**: Current configuration uses reduced resources (2 CPU/12Gi per pod) due to vCPU quota limits. Request quota increase to 48+ vCPUs for production deployment with full resources (4 CPU/16Gi per pod)
   - Default credentials: `admin` / (password from terraform.tfvars)

## Configuration

### Helm Chart and Kubernetes Integration

**Helm Chart**: This deployment uses the official `sonatype/nexus-iq-server-ha` Helm chart with Azure-specific configurations.

**Storage Integration**: Azure Files Premium with CSI driver provides ReadWriteMany (RWX) access for all pods via PersistentVolumeClaim.

**Service Type**: Kubernetes LoadBalancer service with Azure-specific health probe annotations for integration with Application Gateway.

### 1. Essential HA Settings in terraform.tfvars

```hcl
# High Availability Configuration
azure_region = "eastus2"  # East US 2
kubernetes_version = "1.33.3"
node_instance_type = "Standard_D8s_v3"  # 8 vCPU, 32GB RAM
node_group_min_size = 2
node_group_max_size = 5
node_group_desired_size = 3

# Zone-Redundant Database (matching AWS Aurora specs)
postgres_version = "15"
db_sku_name = "MO_Standard_E16s_v3"  # Memory Optimized: 16 vCores, 128GB RAM
db_high_availability_mode = "ZoneRedundant"
db_geo_redundant_backup_enabled = false  # Not supported in all regions
database_password = "SecurePassword123!"  # Change this!

# Zone-Redundant Storage
storage_account_tier = "Premium"
storage_account_replication_type = "ZRS"
storage_share_quota_gb = 512

# Zone-Redundant Application Gateway
app_gateway_sku_name = "Standard_v2"
app_gateway_sku_tier = "Standard_v2"
app_gateway_min_capacity = 2
app_gateway_max_capacity = 10

# Helm Configuration
helm_chart_version = "195.0.0"
nexus_iq_replica_count = 3
nexus_iq_cpu_request = "4"
nexus_iq_cpu_limit = "6"
nexus_iq_memory_request = "16Gi"
nexus_iq_memory_limit = "24Gi"
nexus_iq_admin_password = "admin123"
```

### 2. Network Configuration (Multi-Zone)

```hcl
# Network Configuration for HA
vnet_cidr = "10.1.0.0/16"
public_subnet_cidr = "10.1.1.0/24"    # Application Gateway
aks_subnet_cidr = "10.1.10.0/23"      # AKS nodes and pods
db_subnet_cidr = "10.1.20.0/24"       # PostgreSQL
```

### 3. Helm Values Configuration

Key settings in `helm-values.yaml`:
```yaml
# HA Replica count
replicaCount: 3

# Resources per pod
resources:
  requests:
    cpu: "4"
    memory: "16Gi"
  limits:
    cpu: "6"
    memory: "24Gi"

# Java options for HA deployment
javaOpts: "-Xms24g -Xmx24g -XX:+UseG1GC -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"

# Service Type with Azure LoadBalancer
serviceType: "LoadBalancer"
serviceAnnotations:
  service.beta.kubernetes.io/azure-load-balancer-health-probe-request-path: "/ping"
  service.beta.kubernetes.io/azure-load-balancer-health-probe-protocol: "http"

# Storage with Azure Files Premium (SMB/CIFS)
persistence:
  storageClassName: "azurefile-nfs"  # Custom storage class using SMB protocol
  accessModes:
    - ReadWriteMany
  size: "100Gi"

# Horizontal Pod Autoscaler
autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 5
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 80
```

## High Availability Architecture

### **Kubernetes Pod Clustering**
```bash
# Shared storage with HA license-enabled Quartz clustering
/sonatype-work/clm-server/                # Shared by all pods
/sonatype-work/clm-cluster/               # Shared coordination
```

**Note**: This matches the AWS EKS pattern. The HA license enables Quartz scheduler clustering, allowing multiple pods to safely share the same work directory. This is different from Container Apps (infra-azure-ha) which uses per-replica unique directories.

### **Database High Availability**
- **Primary Zone**: Zone 1 (writer instance)
- **Standby Zone**: Zone 2 (automatic failover target)
- **Failover Time**: ~30 seconds automatic promotion
- **Backup**: Continuous with 7-day retention + geo-redundant

### **Storage High Availability**
- **Zone-Redundant**: Data replicated across 3 zones in region
- **Performance**: Premium tier for consistent IOPS
- **Protocol**: SMB/CIFS (version 3.1.1) for reliable Azure Files integration
- **Durability**: 99.9999999999% annual durability
- **Access**: ReadWriteMany (RWX) for all pods via Azure Files CSI driver

### **Load Balancer High Availability**
- **Zone Distribution**: Application Gateway instances across zones 1, 2, 3
- **Health Checks**: Azure LoadBalancer HTTP probes on /ping endpoint
- **Auto Scaling**: HPA scales 2-10 pods, Cluster Autoscaler scales nodes
- **Session Handling**: Stateless design with shared storage

## Monitoring and Operations

### **Health Monitoring**
```bash
# Check pod status
kubectl get pods -n nexus-iq

# Check HPA status
kubectl get hpa -n nexus-iq

# Check node status
kubectl get nodes

# Check Application Gateway health
az network application-gateway show-backend-health \
  --resource-group rg-nexus-iq-ha \
  --name agw-nexus-iq-ha

# Check database HA status
az postgres flexible-server show \
  --resource-group rg-nexus-iq-ha \
  --name postgres-nexus-iq-ha \
  --query '{status:state,haMode:highAvailability.mode,primaryZone:availabilityZone,standbyZone:highAvailability.standbyAvailabilityZone}'
```

### **Log Monitoring**
```bash
# View pod logs from all replicas
kubectl logs -f -l name=nexus-iq-server-ha-iq-server -n nexus-iq

# View logs from specific pod
kubectl logs <pod-name> -n nexus-iq

# View events
kubectl get events -n nexus-iq --sort-by='.lastTimestamp'
```

### **Scaling Operations**
```bash
# Manually scale pods
kubectl scale deployment nexus-iq-server-ha-iq-server-deployment --replicas=3 -n nexus-iq

# View HPA metrics
kubectl get hpa -n nexus-iq -w

# View pod resource usage
kubectl top pods -n nexus-iq
```

## Disaster Recovery & Backup

### **Recovery Scenarios**

1. **Single Pod Failure**
   - **Detection**: Liveness/readiness probes detect failure within 30 seconds
   - **Response**: Azure LoadBalancer removes from rotation
   - **Recovery**: Kubernetes recreates pod within 1-2 minutes

2. **Node Failure**
   - **Detection**: Kubernetes detects node NotReady status
   - **Response**: Pods rescheduled to healthy nodes
   - **Recovery**: Pod anti-affinity ensures pods spread across nodes

3. **Availability Zone Failure**
   - **Database**: Automatic failover to standby zone (~30 seconds)
   - **Storage**: Automatic failover to healthy zones (transparent)
   - **Application Gateway**: Redistributes traffic to healthy zones
   - **AKS**: Pods restart on nodes in available zones

4. **Complete Region Failure**
   - **Database**: Geo-redundant backups available for restore
   - **Storage**: Azure Files backup/snapshot for recovery
   - **Recovery**: Deploy infrastructure in secondary region from backups

### **Backup Strategy**
```bash
# Database backup status
az postgres flexible-server backup list \
  --resource-group rg-nexus-iq-ha \
  --name postgres-nexus-iq-ha

# Azure Files snapshots
az storage share snapshot list \
  --account-name stnexusiqhaiqa \
  --name iq-data-ha
```

## Performance Tuning

### **Pod Performance**
- **CPU/Memory**: Right-size per pod (default: 1.5 CPU, 4GB)
- **HPA Thresholds**: Tune based on usage patterns (70% CPU, 80% memory)
- **Pod Count**: Adjust min/max based on load requirements (2-10 pods)

### **Database Performance**
- **Instance Size**: Scale up SKU based on concurrent connections
- **Connection Pooling**: Configure in helm-values.yaml
- **Query Performance**: Use PostgreSQL performance insights

### **Storage Performance**
- **Premium Tier**: Provides consistent IOPS for file operations
- **File Share Size**: Increase quota for better performance
- **Access Patterns**: Optimized for concurrent ReadWriteMany access

## Troubleshooting

### **Common HA Issues**

1. **Pods Not Starting**
   ```bash
   # Check pod status and events
   kubectl describe pod <pod-name> -n nexus-iq

   # Common causes:
   # - Database connectivity issues
   # - Storage mount failures (Azure Files CSI)
   # - Resource constraints (CPU/memory)
   # - Image pull failures
   ```

2. **Database Connection Issues**
   ```bash
   # Check database status
   az postgres flexible-server show \
     --name postgres-nexus-iq-ha \
     --resource-group rg-nexus-iq-ha

   # Check network connectivity from AKS
   kubectl run -it --rm debug --image=postgres:15 --restart=Never -- \
     psql -h postgres-nexus-iq-ha.postgres.database.azure.com -U nexusiq -d nexusiq
   ```

3. **Storage Mount Issues**
   ```bash
   # Check PVC status
   kubectl get pvc -n nexus-iq

   # Check storage class
   kubectl get sc azurefile-csi

   # Check Azure Files
   az storage share show \
     --name iq-data-ha \
     --account-name stnexusiqhaiqa
   ```

4. **Load Balancer Issues**
   ```bash
   # Check LoadBalancer service
   kubectl get svc -n nexus-iq

   # Check Application Gateway backend health
   az network application-gateway show-backend-health \
     --name agw-nexus-iq-ha \
     --resource-group rg-nexus-iq-ha

   # Verify LoadBalancer IP in backend pool
   az network application-gateway address-pool show \
     --resource-group rg-nexus-iq-ha \
     --gateway-name agw-nexus-iq-ha \
     --name aks-backend-pool
   ```

5. **HA Replica Issues**
   - First pod needs to start before second pod
   - Upload HA license after first pod is running
   - Check logs: `kubectl logs <pod-name> -n nexus-iq`
   - Verify database migration completed

### **Performance Troubleshooting**

1. **Slow Response Times**
   - Check database connection pool settings in helm-values.yaml
   - Verify Azure Files performance metrics
   - Review HPA thresholds and scaling metrics
   - Analyze Application Gateway metrics

2. **Memory/CPU Issues**
   - Increase pod resource requests/limits in helm-values.yaml
   - Adjust Java heap settings (javaOpts in helm-values.yaml)
   - Review HPA scaling policies
   - Scale up node instance type if needed

## File Structure

```
infra-azure-ha-k8s-helm/
├── main.tf                    # VNet, subnets, NSGs (multi-zone)
├── aks.tf                     # AKS cluster with node pools
├── database.tf                # Zone-redundant PostgreSQL Flexible Server
├── storage.tf                 # Azure Files Premium with ZRS
├── application_gateway.tf     # Zone-redundant Application Gateway
├── variables.tf               # Input variable definitions (HA-focused)
├── outputs.tf                 # Output value definitions (HA status)
├── terraform.tfvars.example   # Example HA configuration
├── helm-values.yaml           # Helm chart values for HA
├── tf-plan.sh                 # HA-aware planning script
├── tf-apply.sh                # HA deployment script
├── tf-destroy.sh              # Enhanced HA cleanup script
├── helm-install.sh            # Helm HA deployment script
├── helm-upgrade.sh            # Helm HA upgrade script
├── helm-uninstall.sh          # Helm HA uninstall script
├── README.md                  # This file
├── ARCHITECTURE.md            # Detailed HA architecture documentation
└── REFERENCE_ARCHITECTURE.md  # Enterprise reference documentation
```

## Production Considerations

For production HA deployments, consider:

1. **SSL/TLS**: Configure Application Gateway with SSL certificate and HTTPS listener
2. **Custom Domain**: Set up Azure DNS with health checks
3. **Monitoring**: Implement comprehensive alerting for HA components (Container Insights, Azure Monitor)
4. **Backup Testing**: Regular backup and restore testing for database and storage
5. **Disaster Recovery**: Cross-region replication strategy with geo-redundant backups
6. **Security**: Network security groups, private endpoints, and Azure Key Vault CSI driver
7. **Compliance**: Data residency and compliance requirements
8. **Performance**: Load testing for auto-scaling validation (HPA and Cluster Autoscaler)
9. **Capacity Planning**: Right-sizing for peak load scenarios
10. **Cost Optimization**: Azure Reservations for AKS nodes and scheduled scaling

## Cost Optimization

### **HA Resource Costs**
- **AKS**: Pay for nodes (Standard_D2s_v3) with Cluster Autoscaler
- **PostgreSQL**: Zone-redundant adds ~50% cost vs single-zone
- **Azure Files Premium**: Higher cost but better performance and ZRS durability
- **Application Gateway**: Zone-redundant Standard_v2 SKU with auto-scaling
- **Azure LoadBalancer**: Basic SKU included with AKS

### **Optimization Strategies**
- Use Cluster Autoscaler and HPA to minimize idle resources
- Schedule scaling for predictable load patterns
- Right-size database, nodes, and pod resources
- Use Azure Reservations for long-term AKS node commitments
- Consider Azure Spot VMs for non-critical workloads

## Support

For issues with this HA infrastructure:
1. Check the troubleshooting section above
2. Review Azure Monitor Container Insights and logs
3. Verify HA configuration settings in terraform.tfvars and helm-values.yaml
4. Test failover scenarios (pod, node, zone failures)
5. Consult the [Nexus IQ Server documentation](https://help.sonatype.com/iqserver)

For Azure-specific issues:
- Review [AKS documentation](https://docs.microsoft.com/en-us/azure/aks/)
- Check [PostgreSQL Flexible Server documentation](https://docs.microsoft.com/en-us/azure/postgresql/flexible-server/)
- Consult [Application Gateway documentation](https://docs.microsoft.com/en-us/azure/application-gateway/)
- Review [Azure Files CSI driver documentation](https://docs.microsoft.com/en-us/azure/aks/azure-files-csi)

## Reference Architecture

This HA infrastructure serves as a **Reference Architecture for Enterprise Cloud Deployments** demonstrating:

- **High availability patterns**: Multi-zone deployment, auto-scaling, automatic failover
- **Kubernetes-native clustering**: AKS with shared storage and pod anti-affinity
- **Security best practices**: Network isolation, RBAC, encrypted storage
- **Operational excellence**: Comprehensive monitoring, automated scaling, backup policies
- **Cost optimization**: Auto-scaling (HPA + Cluster Autoscaler), right-sized resources
- **Reliability**: Multi-zone deployment, automated recovery, health monitoring
