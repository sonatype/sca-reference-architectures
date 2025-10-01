# Nexus IQ Server Azure Infrastructure (High Availability)

This directory contains Terraform configuration for deploying Nexus IQ Server on Azure using Container Apps in a **High Availability configuration** as part of a **Reference Architecture for Enterprise Cloud Deployments**.

## Architecture Overview

This infrastructure deploys a complete, production-ready Nexus IQ Server High Availability environment including:

- **Container Apps (2-10 replicas)** - Multi-instance containerized Nexus IQ Server with auto-scaling
- **Zone-Redundant Application Gateway** - HTTP load balancer with health checks across availability zones
- **Zone-Redundant PostgreSQL Flexible Server** - Managed database with automatic failover
- **Premium Azure Files (ZRS)** - Zone-redundant shared storage for clustering coordination
- **Virtual Network & Subnets** - Multi-zone network infrastructure with security groups
- **Zone-Redundant Storage** - Premium storage with zone-redundant replication
- **Key Vault** - Secure credential storage with network integration
- **Log Analytics & Monitoring** - Centralized logging and Application Insights
- **Auto Scaling** - KEDA-based scaling with CPU, memory, and HTTP request triggers
- **Backup & Recovery** - Automated backup policies for data protection

```
Internet
    ↓
Application Gateway (Zone-Redundant, Multiple AZs)
    ↓
Container Apps (2-10 replicas, Auto-scaling, Multi-AZ) ←→ Azure Files Premium (ZRS)
    ↓
PostgreSQL Flexible Server (Zone-Redundant with Standby)
```

## High Availability Features

### **Multi-Zone Redundancy**
- **Application Gateway**: Zone-redundant deployment across 3 availability zones
- **Container Apps**: Automatic distribution across zones with 2-10 replicas
- **PostgreSQL**: Zone-redundant with automatic standby in different zone
- **Storage**: Zone-Redundant Storage (ZRS) for 99.9999999999% durability

### **Auto-Scaling & Load Balancing**
- **KEDA-based Scaling**: CPU, memory, and HTTP request-based scaling (2-10 replicas)
- **Application Gateway**: Automatic load balancing with health probes
- **Rolling Updates**: Zero-downtime deployments with traffic shifting
- **Session Management**: Stateless design with shared storage for clustering

### **Data Protection**
- **Database**: Zone-redundant PostgreSQL with automatic failover (~30 seconds)
- **Storage**: Premium Azure Files with zone redundancy and backup policies
- **Secrets**: Key Vault with network isolation and access policies
- **Monitoring**: Comprehensive logging and Application Insights integration

### **Clustering Support**
- **Unique Work Directories**: Each replica gets isolated `/sonatype-work/clm-server-${HOSTNAME}`
- **Shared Cluster Directory**: Coordination through `/sonatype-work/clm-cluster`
- **Database Sharing**: All replicas connect to shared PostgreSQL cluster
- **File Upload Coordination**: Premium Azure Files ensures consistent file handling

## Prerequisites

### Required Tools
- **Terraform** >= 1.0
- **Azure CLI** >= 2.0
- **az login** authentication completed

### Azure Account Requirements
- Azure subscription with appropriate permissions
- Resource creation rights in target region
- Ability to create zone-redundant resources

## Quick Start

1. **Navigate to the HA infrastructure directory**:
   ```bash
   cd /path/to/sca-example-terraform/infra-azure-ha
   ```

2. **Copy and customize variables**:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
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

6. **Access your Nexus IQ Server HA cluster**:
   - Get URLs: `terraform output`
   - Wait 15-20 minutes for all HA services to be ready
   - Default credentials: `admin` / `admin123`

## Configuration

### 1. Essential HA Settings in terraform.tfvars

```hcl
# High Availability Configuration
iq_min_replicas                  = 2           # Minimum replicas (must be >= 2 for HA)
iq_max_replicas                  = 10          # Maximum auto scaling capacity
container_cpu                    = 2.0         # CPU per replica
container_memory                 = "4Gi"       # Memory per replica

# Zone-Redundant Database
db_high_availability_mode        = "ZoneRedundant"  # Zone-redundant PostgreSQL
db_sku_name                      = "GP_Standard_D4s_v3"  # 4 vCores, 16GB
postgres_version                 = "15"
db_geo_redundant_backup_enabled  = true

# Zone-Redundant Storage
storage_account_tier             = "Premium"   # Premium performance
storage_account_replication_type = "ZRS"       # Zone-Redundant Storage

# Zone-Redundant Application Gateway
app_gateway_zones               = ["1", "2", "3"]  # Multi-zone deployment
app_gateway_sku_tier            = "Standard_v2"    # v2 required for zones

# Auto Scaling Thresholds
cpu_utilization_threshold       = 70          # CPU % for scaling
memory_utilization_threshold    = 80          # Memory % for scaling
scale_rule_concurrent_requests  = 100         # Requests threshold
```

### 2. Network Configuration (Multi-Zone)

```hcl
# Network Configuration for HA
vnet_cidr               = "10.0.0.0/16"
public_subnet_cidrs     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]    # Multi-zone
private_subnet_cidrs    = ["10.0.10.0/24", "10.0.20.0/24", "10.0.30.0/24"] # Multi-zone
db_subnet_cidr          = "10.0.40.0/24"
```

### 3. Security Configuration

```hcl
# Database Security
db_password                      = "YourSecurePassword123!"  # Change this!
db_backup_retention_days         = 7
db_geo_redundant_backup_enabled  = true

# Key Vault Security
key_vault_sku_name              = "standard"
key_vault_soft_delete_retention_days = 7
```

## High Availability Architecture

### **Container App Clustering**
```bash
# Each replica gets unique work directory
/sonatype-work/clm-server-${HOSTNAME}/    # Unique per replica
/sonatype-work/clm-cluster/               # Shared coordination
```

### **Database High Availability**
- **Primary Zone**: Zone 1 (writer instance)
- **Standby Zone**: Zone 2 (automatic failover target)
- **Failover Time**: ~30 seconds automatic promotion
- **Backup**: Continuous with 7-day retention + geo-redundant

### **Storage High Availability**
- **Zone-Redundant**: Data replicated across 3 zones in region
- **Performance**: Premium tier for consistent IOPS
- **Durability**: 99.9999999999% annual durability
- **Access**: Simultaneous access from all Container App replicas

### **Load Balancer High Availability**
- **Zone Distribution**: Application Gateway instances across zones 1, 2, 3
- **Health Checks**: Automatic failover for unhealthy replicas
- **Auto Scaling**: 2-10 instances based on demand
- **Session Handling**: Stateless design (no sticky sessions)

## Monitoring and Operations

### **Health Monitoring**
```bash
# Check Container App replica status
az containerapp show \
  --resource-group $(terraform output -raw resource_group_name) \
  --name ca-ref-arch-iq-ha \
  --query '{replicas:properties.template.scale,status:properties.provisioningState}'

# Check Application Gateway health
az network application-gateway show-backend-health \
  --resource-group $(terraform output -raw resource_group_name) \
  --name agw-ref-arch-iq-ha

# Check database HA status
az postgres flexible-server show \
  --resource-group $(terraform output -raw resource_group_name) \
  --name psqlfs-ref-arch-iq-ha \
  --query '{status:state,haMode:highAvailability.mode,primaryZone:availabilityZone,standbyZone:highAvailability.standbyAvailabilityZone}'
```

### **Log Monitoring**
```bash
# View Container App logs from all replicas
az containerapp logs show \
  --resource-group $(terraform output -raw resource_group_name) \
  --name ca-ref-arch-iq-ha \
  --follow

# View Application Gateway access logs
az monitor log-analytics query \
  --workspace $(terraform output -raw log_analytics_workspace_id) \
  --analytics-query "AzureDiagnostics | where ResourceType == 'APPLICATIONGATEWAYS' | limit 50"
```

### **Scaling Operations**
```bash
# Manually scale replicas (if needed)
az containerapp update \
  --resource-group $(terraform output -raw resource_group_name) \
  --name ca-ref-arch-iq-ha \
  --min-replicas 3 \
  --max-replicas 12

# View current scaling metrics
az monitor metrics list \
  --resource $(terraform output -raw container_app_environment_id) \
  --metric "Requests,CPUUsage,MemoryUsage"
```

## Disaster Recovery & Backup

### **Recovery Scenarios**

1. **Single Replica Failure**
   - **Detection**: Health probes detect failure within 30 seconds
   - **Response**: Application Gateway removes from rotation
   - **Recovery**: Auto-scaler replaces failed replica within 2-3 minutes

2. **Availability Zone Failure**
   - **Database**: Automatic failover to standby zone (~30 seconds)
   - **Storage**: Automatic failover to healthy zones (transparent)
   - **Application Gateway**: Redistributes traffic to healthy zones
   - **Container Apps**: Replicas restart in available zones

3. **Complete Region Failure**
   - **Database**: Geo-redundant backups available for restore
   - **Storage**: Geo-redundant backup policies (if configured)
   - **Recovery**: Deploy infrastructure in secondary region from backups

### **Backup Strategy**
```bash
# Database backup status
az postgres flexible-server backup list \
  --resource-group $(terraform output -raw resource_group_name) \
  --name psqlfs-ref-arch-iq-ha

# Storage backup policies
az backup policy list \
  --resource-group $(terraform output -raw resource_group_name) \
  --vault-name bv-ref-arch-iq-ha
```

## Performance Tuning

### **Container App Performance**
- **CPU/Memory**: Right-size per replica (default: 2 CPU, 4GB)
- **Auto-scaling**: Tune thresholds based on usage patterns
- **Replica Count**: Adjust min/max based on load requirements

### **Database Performance**
- **Instance Size**: Scale up SKU based on concurrent connections
- **Connection Pooling**: Configure application connection pooling
- **Query Performance**: Use PostgreSQL performance insights

### **Storage Performance**
- **Premium Tier**: Provides consistent IOPS for file operations
- **File Share Size**: Increase quota for better performance
- **Access Patterns**: Optimize for shared clustering workload

## Troubleshooting

### **Common HA Issues**

1. **Replicas Not Starting**
   ```bash
   # Check Container App events
   az containerapp logs show --name ca-ref-arch-iq-ha --resource-group $(terraform output -raw resource_group_name)

   # Common causes:
   # - Database connectivity issues
   # - Storage mount failures
   # - Resource constraints
   # - Image pull failures
   ```

2. **Database Connection Issues**
   ```bash
   # Check database status
   az postgres flexible-server show --name psqlfs-ref-arch-iq-ha --resource-group $(terraform output -raw resource_group_name)

   # Check network connectivity
   az network nsg rule list --nsg-name nsg-database-ha --resource-group $(terraform output -raw resource_group_name)
   ```

3. **Clustering Issues**
   ```bash
   # Check shared storage access
   az storage share show --name iq-data-ha --account-name $(terraform output -raw storage_account_name)

   # Verify unique work directories
   # Each replica should have /sonatype-work/clm-server-${HOSTNAME}
   # Shared cluster directory: /sonatype-work/clm-cluster
   ```

4. **Load Balancer Issues**
   ```bash
   # Check Application Gateway backend health
   az network application-gateway show-backend-health \
     --name agw-ref-arch-iq-ha \
     --resource-group $(terraform output -raw resource_group_name)

   # Check health probe configuration
   az network application-gateway probe show \
     --gateway-name agw-ref-arch-iq-ha \
     --name iq-health-probe-ha \
     --resource-group $(terraform output -raw resource_group_name)
   ```

### **Performance Troubleshooting**

1. **Slow Response Times**
   - Check database connection pool settings
   - Verify storage performance metrics
   - Review auto-scaling thresholds
   - Analyze Application Gateway metrics

2. **Memory/CPU Issues**
   - Increase container resource allocations
   - Adjust Java heap settings in java_opts
   - Review auto-scaling policies

## File Structure

```
infra-azure-ha/
├── main.tf                    # VNet, subnets, NSGs (multi-zone)
├── container_app.tf           # Container Apps with HA clustering
├── database.tf                # Zone-redundant PostgreSQL Flexible Server
├── storage.tf                 # Premium Azure Files with ZRS
├── key_vault.tf               # Key Vault for secrets management
├── application_gateway.tf     # Zone-redundant Application Gateway
├── autoscaling.tf             # Auto-scaling configuration
├── variables.tf               # Input variable definitions (HA-focused)
├── outputs.tf                 # Output value definitions (HA status)
├── terraform.tfvars.example   # Example HA configuration
├── tf-plan.sh                 # HA-aware planning script
├── tf-apply.sh                # HA deployment script
├── tf-destroy.sh              # Enhanced HA cleanup script
├── README.md                  # This file
└── ARCHITECTURE.md            # Detailed HA architecture documentation
```

## Production Considerations

For production HA deployments, consider:

1. **SSL/TLS**: Configure Application Gateway with SSL certificate
2. **Custom Domain**: Set up DNS with health checks
3. **Monitoring**: Implement comprehensive alerting for HA components
4. **Backup Testing**: Regular backup and restore testing
5. **Disaster Recovery**: Cross-region replication strategy
6. **Security**: Network security groups and private endpoints
7. **Compliance**: Data residency and compliance requirements
8. **Performance**: Load testing for auto-scaling validation
9. **Capacity Planning**: Right-sizing for peak load scenarios
10. **Cost Optimization**: Reserved instances and scheduled scaling

## Cost Optimization

### **HA Resource Costs**
- **Container Apps**: Pay per replica-hour with auto-scaling
- **PostgreSQL**: Zone-redundant adds ~50% cost vs single-zone
- **Premium Storage**: Higher cost but better performance and durability
- **Application Gateway**: Zone-redundant v2 SKU
- **Backup**: Additional cost for geo-redundant backups

### **Optimization Strategies**
- Use auto-scaling to minimize idle replicas
- Schedule scaling for predictable load patterns
- Right-size database and container resources
- Use Azure Reservations for long-term commitments

## Support

For issues with this HA infrastructure:
1. Check the troubleshooting section above
2. Review Azure Monitor logs and metrics
3. Verify HA configuration settings
4. Test failover scenarios
5. Consult the [Nexus IQ Server documentation](https://help.sonatype.com/iqserver)

For Azure-specific issues:
- Review [Container Apps documentation](https://docs.microsoft.com/en-us/azure/container-apps/)
- Check [PostgreSQL Flexible Server documentation](https://docs.microsoft.com/en-us/azure/postgresql/flexible-server/)
- Consult [Application Gateway documentation](https://docs.microsoft.com/en-us/azure/application-gateway/)

## Reference Architecture

This HA infrastructure serves as a **Reference Architecture for Enterprise Cloud Deployments** demonstrating:

- **High availability patterns**: Multi-zone deployment, auto-scaling, automatic failover
- **Cloud-native clustering**: Container Apps with shared storage clustering
- **Security best practices**: Network isolation, secret management, encrypted storage
- **Operational excellence**: Comprehensive monitoring, automated scaling, backup policies
- **Cost optimization**: Auto-scaling, right-sized resources, zone-redundant architecture
- **Reliability**: Multi-zone deployment, automated recovery, health monitoring