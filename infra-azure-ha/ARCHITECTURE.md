# Nexus IQ Server Azure Reference Architecture (High Availability)

## Deployment Profile

**Recommended for:**
- **Production environments**
- **Enterprise deployments** with high availability requirements
- **Large organizations** with 500+ onboarded applications
- **High scan frequency** (10+ evaluations per minute)
- **Mission-critical workloads** requiring 99.9%+ uptime

**System Specifications:**
- 2-10 Container App replicas with auto-scaling (2.0 vCPU / 4GB RAM each)
- Zone-redundant PostgreSQL Flexible Server with automatic failover
- Premium Azure File Share with Zone-Redundant Storage (ZRS)
- Multi-zone deployment across 3 availability zones
- Zone-redundant Application Gateway load balancer

## Overview

This reference architecture deploys Nexus IQ Server on Microsoft Azure using a High Availability (HA) configuration with zone redundancy, horizontal scaling, and enterprise-grade availability. The architecture is designed for production workloads requiring automatic failover, load distribution, and comprehensive disaster recovery capabilities.

### **⚠️ Important: Azure Container Apps Port Limitation**

**Azure Container Apps ingress has specific architectural constraints that affect HA deployments:**

- **Primary Port**: Container Apps exposes one primary port with full HTTP features (port 8070 via ingress port 80)
- **Additional Ports**: Azure supports up to 5 additional TCP ports, but with major restrictions:
  - Limited to basic TCP traffic (no HTTP health probe support)
  - Only available in VNET-integrated environments
  - Must be unique across the entire Container Apps environment
  - No built-in HTTP features (CORS, session affinity, health probes)
- **Health Probes**: Application Gateway HTTP health probes only work with the primary ingress port across all replicas

**HA Architecture Impact:**
- ✅ **Main application**: Full HTTP support via Application Gateway → Container App primary ingress → All replicas
- ❌ **Admin port health checks**: Additional ports don't support Application Gateway HTTP health probes across replicas
- ❌ **Admin port HTTP features**: Limited to basic TCP connectivity if exposed in HA environment

**Reference**: [Azure Container Apps Ingress Limitations](https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview) - Microsoft Documentation

## Scaling Options
- **Current Deployment**: High Availability (2-10 replicas with auto-scaling)
- **Horizontal Scaling**: KEDA-based auto-scaling with HTTP requests, CPU, and memory triggers
- **Database Scaling**: Zone-redundant PostgreSQL with automatic failover and read replicas capability
- **Storage Scaling**: Premium Azure File Share auto-scales based on usage with ZRS redundancy
- **Load Balancer Scaling**: Application Gateway auto-scales from 2-10 capacity units across availability zones

## 1. High-Level Architecture

```
┌────────────────────────────────────────────────────────────────────────────────────────────┐
│                                       INTERNET                                             │
└───────────────────────────────────────────┬────────────────────────────────────────────────┘
                                            │
                                            │ HTTP/HTTPS Traffic
                                            │
┌───────────────────────────────────────────▼────────────────────────────────────────────────┐
│                                 AZURE VNET (HA Multi-Zone)                                 │
│   ┌────────────────────────────────────────────────────────────────────────────────────┐   │
│   │              PUBLIC SUBNETS (Zone Redundant: Zones 1,2,3)                          │   │
│   │   ┌──────────────────────────────────────────────────────────────────────────────┐ │   │
│   │   │                   Application Gateway (HA)                                   │ │   │
│   │   │              Port 80 → Backend Pool (2-10 Replicas)                          │ │   │
│   │   │              Auto-scaling: 2-10 Capacity Units                               │ │   │
│   │   │              Health Probes: Port 80 Only (All Replicas)                      │ │   │
│   │   │              Zone Distribution: AZ 1,2,3                                     │ │   │
│   │   └───────────────────────────────────┬──────────────────────────────────────────┘ │   │
│   └───────────────────────────────────────┼────────────────────────────────────────────┘   │
│                                           │
│   ┌───────────────────────────────────────▼────────────────────────────────────────────┐   │
│   │              PRIVATE SUBNETS (Multi-Zone: Zones 1,2,3)                             │   │
│   │   ┌─────────────────────────────────────────────────────────────────────────────┐  │   │
│   │   │                    CONTAINER APP ENVIRONMENT (HA)                           │  │   │
│   │   │   ┌──────────────────────────────────────────────────────────────────────┐  │  │   │
│   │   │   │              Nexus IQ Server Replicas (2-10)                         │  │  │   │
│   │   │   │                                                                      │  │  │   │
│   │   │   │  ┌────────────────┐ ┌────────────────┐ ┌────────────────┐            │  │  │   │
│   │   │   │  │   Replica 1    │ │   Replica 2    │ │   Replica N    │            │  │  │   │
│   │   │   │  │ Port 8070: App │ │ Port 8070: App │ │ Port 8070: App │            │  │  │   │
│   │   │   │  │ Port 8071: Adm │ │ Port 8071: Adm │ │ Port 8071: Adm │            │  │  │   │
│   │   │   │  │ CPU: 2.0       │ │ CPU: 2.0       │ │ CPU: 2.0       │            │  │  │   │
│   │   │   │  │ Memory: 4Gi    │ │ Memory: 4Gi    │ │ Memory: 4Gi    │            │  │  │   │
│   │   │   │  │ Zone: AZ 1     │ │ Zone: AZ 2     │ │ Zone: AZ 3     │            │  │  │   │
│   │   │   │  └────────────────┘ └────────────────┘ └────────────────┘            │  │  │   │
│   │   │   └───────────────────────────────┬──────────────────────────────────────┘  │  │   │
│   │   └───────────────────────────────────┼─────────────────────────────────────────┘  │   │
│   └───────────────────────────────────────┼────────────────────────────────────────────┘   │
│                                           │                                                │
│                                           │                                                │
│                         ┌─────────────────┴───────────────┐                                │
│                         │                                 │                                │
│   ┌─────────────────────▼───────────────────────┐   ┌─────▼────────────────────┐           │
│   │           STORAGE LAYER (HA)                │   │     DATABASE SUBNET      │           │
│   │   ┌─────────────────────────────────────┐   │   │   ┌───────────────────┐  │           │
│   │   │       AZURE FILE SHARE (ZRS)        │   │   │   │   POSTGRESQL      │  │           │
│   │   │     /sonatype-work clustering       │   │   │   │   FLEXIBLE SERVER │  │           │
│   │   │     Premium tier (Zone redundant)   │   │   │   │   (Zone Redundant)│  │           │
│   │   │     Shared across all replicas      │   │   │   │   Version 15      │  │           │
│   │   │     200GB quota, auto-scaling       │   │   │   │   GP_Standard_D4s │  │           │
│   │   │     Encrypted at rest               │   │   │   │   Primary: Zone 1 │  │           │
│   │   │     SMB 3.0 protocol                │   │   │   │   Standby: Zone 2 │  │           │
│   │   └─────────────────────────────────────┘   │   │   │   Auto-failover   │  │           │
│   └─────────────────────────────────────────────┘   │   │   Encrypted       │  │           │
│                                                     │   │   Geo-redundant   │  │           │
│                                                     │   │   Backups         │  │           │
│                                                     │   │   Key Vault       │  │           │
│                                                     │   │   Integration     │  │           │
│                                                     │   └───────────────────┘  │           │
│                                                     └──────────────────────────┘           │
└────────────────────────────────────────────────────────────────────────────────────────────┘

              ┌──────────────────────────────────────────────┐
              │           SUPPORTING SERVICES (HA)           │
              │                                              │
              │  • Log Analytics (Multi-Replica Monitoring)  │
              │  • Key Vault (Secrets Distribution)          │
              │  • Application Insights (APM Aggregation)    │
              │  • Managed Identity (HA Service Auth)        │
              │  • KEDA Auto-scaling (HTTP/CPU/Memory)       │
              │  • Zone-Redundant Public IP                  │
              └──────────────────────────────────────────────┘
```

## 2. Network Flow & Security

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           TRAFFIC FLOW (HA)                                 │
└─────────────────────────────────────────────────────────────────────────────┘

Internet → Application Gateway (Port 80) - Zone Redundant
    ↓
Application Gateway NSG (HTTP: 80, HTTPS: 443, Management: 65200-65535)
    ↓
Backend Pool Health Probes (HA Load Balancing):
    • Port 80: /           (accepts 200,301,302,303) - All replicas
    • Port 8071: NOT ACCESSIBLE - Container Apps ingress limitation
    • Load balancing across 2-10 replicas in multiple zones
    ↓
Container Apps NSG (HTTP/HTTPS and Load Balancer probes + Inter-replica)
    ↓
Nexus IQ Container Replicas (Private Subnets Multi-Zone)
    ↓
    ├── Database NSG (Port 5432 from Container Apps only)
    │   ↓
    │   PostgreSQL Flexible Server (DB Subnet Zone Redundant)
    │   ├── Primary Database (Zone 1)
    │   └── Standby Database (Zone 2) - Automatic failover
    │
    └── Storage Account (SMB 445 from Container Apps only)
        ↓
        Azure File Share (Zone Redundant Premium)
        ├── Shared cluster coordination: /sonatype-work/clm-cluster
        └── Unique replica directories: /sonatype-work/clm-server-$HOSTNAME

┌─────────────────────────────────────────────────────────────────────────────┐
│                          SECURITY BOUNDARIES (HA)                           │
└─────────────────────────────────────────────────────────────────────────────┘

Public Zone:     │ Internet Gateway ← → Application Gateway only (Multi-AZ)
Private Zone:    │ Container App Replicas (no inbound from internet, Multi-AZ)
Database Zone:   │ Container Apps → PostgreSQL only (Zone redundant, isolated)
Storage Zone:    │ Container Apps → File Share only (ZRS, service endpoints)

Network Security Groups (Least Privilege HA):
┌─────────────────┬──────────────────┬─────────────────┬──────────────────┐
│   Component     │    Inbound       │    Outbound     │    Protocol      │
├─────────────────┼──────────────────┼─────────────────┼──────────────────┤
│ App Gateway HA  │ Internet:80,443  │ Container:80    │ HTTP             │
│                 │ AzureMgmt:65200+ │ Multi-replica   │ HTTPS            │
│ Container Apps  │ AppGW:80,443     │ PostgreSQL:5432 │ TCP              │
│ (Multi-replica) │ LB Probes        │ FileShare:445   │ TCP/SMB          │
│                 │ Inter-replica    │ Inter-replica   │ HTTP             │
│ PostgreSQL HA   │ Container:5432   │ Standby sync    │ PostgreSQL       │
│ (Zone Redundant)│ Primary/Standby  │ None            │ Replication      │
│ File Share ZRS  │ Container:445    │ Zone sync       │ SMB/ZRS          │
└─────────────────┴──────────────────┴─────────────────┴──────────────────┘
```

### Application Layer (High Availability)
- **Container App Environment**: `cae-ref-arch-iq-ha`
  - Log Analytics Workspace integration
  - VNET-integrated with private subnet infrastructure
- **Container Apps**: `ca-ref-arch-iq-ha`
  - **Replica Configuration**: Min 2, Max 10 replicas (validation enforces HA minimum)
  - **Auto-scaling**: HTTP request-based scaling (100 concurrent requests threshold)
  - **Resource Allocation**: 2.0 CPU, 4Gi memory per replica
  - **Clustering**: Shared Azure File Share for inter-replica coordination
  - **Health Probes**: Startup (30s), Liveness (30s), Readiness (15s) probes on port 8070

### Load Balancing & Traffic Management
- **Application Gateway**: `agw-ref-arch-iq-ha`
  - **Zone Redundancy**: Deployed across zones 1, 2, 3
  - **Auto-scaling**: Min 2, Max 10 capacity units
  - **SKU**: Standard_v2 (required for zone redundancy)
  - **Health Probes**: HTTP probes on Container App ingress (port 80)
  - **Rewrite Rules**: Container App hostname rewriting for proper redirects
  - **Public IP**: Zone-redundant static IP with DNS label
- **Traffic Distribution**: Cookie-based affinity disabled for proper HA load balancing

### Data Layer (Zone Redundant)
- **PostgreSQL Flexible Server**: `psqlfs-ref-arch-iq-ha`
  - **High Availability**: Zone-redundant mode (Primary: Zone 1, Standby: Zone 2)
  - **SKU**: GP_Standard_D4s_v3 (4 vCores, 16GB RAM)
  - **Storage**: 64GB Premium (P6 tier) with auto-grow
  - **Backup**: 7-day retention, geo-redundant backup enabled
  - **Network**: Private endpoint, VNET integration, private DNS zone
  - **Database**: `nexusiq` database with UTF-8 charset
- **Configuration**: Optimized PostgreSQL settings for IQ Server workload
  - `shared_preload_libraries = pg_stat_statements`
  - `log_statement = all`
  - `log_min_duration_statement = 1000ms`
  - Connection/checkpoint/disconnection logging enabled

### Storage & Shared File System
- **Storage Account**: Premium FileStorage with Zone-Redundant Storage (ZRS)
  - **Replication**: ZRS for zone redundancy
  - **Network Security**: VNET integration with private subnet access
  - **Performance**: Premium tier for better I/O performance
- **Azure File Share**: `iq-data-ha` (200GB quota)
  - **Purpose**: Nexus IQ Server clustering and shared work directory
  - **Access Mode**: ReadWrite for all Container App replicas
  - **Integration**: Container App environment storage mount

### Security & Secrets Management
- **Key Vault**: `kvrefarchiqha{suffix}`
  - **SKU**: Standard with soft delete (7-day retention)
  - **Network Access**: VNET integration with private subnets
  - **Stored Secrets**: Database credentials and connection details
  - **Access Policies**: Current user (Terraform) and Container App managed identity
- **Managed Identity**: System-assigned identity for Container Apps with Key Vault access

## 3. Component Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    AZURE CONTAINER APPS DEPLOYMENT (HA)                     │
└─────────────────────────────────────────────────────────────────────────────┘

Container App Environment: cae-ref-arch-iq-ha
    ├── Location: Private Subnets (Multi-Zone Infrastructure)
    ├── Log Analytics: log-ref-arch-iq-ha
    ├── Application Insights: appi-ref-arch-iq-ha (optional)
    ├── Storage Mount: Azure File Share (ZRS Premium)
    └── Zone Distribution: Replicas across AZ 1, 2, 3
    ↓
Container App: ca-ref-arch-iq-ha (HA Configuration)
    ├── Replicas: 2-10 (min: 2, max: 10, auto-scaling)
    ├── Revision Mode: Single (consistent deployment)
    ├── Identity: System Assigned Managed Identity
    ├── Auto-scaling Triggers:
    │   ├── HTTP Requests: >100 concurrent (KEDA)
    │   ├── CPU Utilization: >70%
    │   └── Memory Utilization: >80%
    ├── Container Configuration (Per Replica):
    │   ├── Image: sonatype/nexus-iq-server:latest
    │   ├── CPU: 2.0 vCPU
    │   ├── Memory: 4Gi (4 GB)
    │   ├── Custom entrypoint with HA config.yml generation (EmptyDir volume)
    │   ├── Environment Variables:
    │   │   ├── DB_HOST: <PostgreSQL_FQDN>
    │   │   ├── DB_PORT: 5432
    │   │   ├── DB_NAME: nexusiq
    │   │   ├── HOSTNAME: <unique-replica-identifier>
    │   │   └── JAVA_OPTS: -Xmx3g -Djava.util.prefs.userRoot=/sonatype-work/javaprefs
    │   ├── Secrets (from Key Vault):
    │   │   ├── DB_USERNAME
    │   │   └── DB_PASSWORD
    │   └── Volume Mounts (HA Clustering):
    │       ├── /sonatype-work/clm-server-$HOSTNAME ← Unique per replica
    │       └── /sonatype-work/clm-cluster ← Shared cluster coordination
    └── Application Ingress (HA Load Balancing):
        ├── External Ingress: Disabled (accessed via Application Gateway)
        ├── Target Port: 8070
        ├── Transport: HTTP
        └── Session Affinity: Disabled (stateless HA design)

┌─────────────────────────────────────────────────────────────────────────────┐
│                         DATA PERSISTENCE (HA)                              │
└─────────────────────────────────────────────────────────────────────────────┘

Database Layer (Zone Redundant):
┌─────────────────────────────────────────────────────────────────────────────┐
│ PostgreSQL Flexible Server (psqlfs-ref-arch-iq-ha)                          │
│  ├── SKU: GP_Standard_D4s_v3 (4 vCores, 16GB RAM)                           │
│  ├── Version: PostgreSQL 15                                                 │
│  ├── High Availability: ZoneRedundant (Primary: AZ1, Standby: AZ2)          │
│  ├── Storage: 64GB Premium (P6), Auto-scaling enabled                       │
│  ├── Encryption: At rest enabled, TLS in transit                            │
│  ├── Backup: Automated, 7-day retention, geo-redundant                      │
│  ├── Network: Private DNS zone integration, VNET integration                │
│  ├── Credentials: Stored in Azure Key Vault                                 │
│  ├── Failover: Automatic (~30 seconds)                                      │
│  └── Connection Pooling: Optimized for multi-replica access                 │
└─────────────────────────────────────────────────────────────────────────────┘

File Storage (Zone Redundant):
┌─────────────────────────────────────────────────────────────────────────────┐
│ Azure Storage Account (st<random>ha)                                        │
│  ├── Type: Premium FileStorage                                              │
│  ├── Performance: Premium (consistent IOPS)                                 │
│  ├── Replication: ZRS (Zone-Redundant Storage)                              │
│  ├── Encryption: Microsoft-managed keys                                     │
│  └── File Share: iq-data-ha, 200GB quota                                    │
│      ├── Protocol: SMB 3.0 with Azure AD authentication                     │
│      ├── Mounted at: /sonatype-work (shared across all replicas)            │
│      ├── Access: Service endpoint from private subnets                      │
│      └── Clustering Support:                                                │
│          ├── /sonatype-work/clm-cluster (shared coordination)               │
│          └── /sonatype-work/clm-server-$HOSTNAME (unique per replica)       │
└─────────────────────────────────────────────────────────────────────────────┘

Load Balancer (Zone Redundant):
┌─────────────────────────────────────────────────────────────────────────────┐
│ Application Gateway (agw-ref-arch-iq-ha)                                    │
│  ├── SKU: Standard_v2 (required for zone redundancy)                        │
│  ├── Zones: 1, 2, 3 (zone-redundant deployment)                            │
│  ├── Capacity: Auto-scaling 2-10 capacity units                             │
│  ├── Public IP: Zone-redundant static IP (pip-agw-ha)                       │
│  ├── Backend Pool: Container App replicas (dynamic, 2-10)                   │
│  ├── Health Probes: HTTP / on port 80 (15s interval, 3 retries)             │
│  ├── Load Balancing: Round-robin across healthy replicas                    │
│  ├── Session Management: No sticky sessions (stateless design)              │
│  └── SSL Termination: Optional (production recommendation)                  │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 4. Operational Excellence

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              MONITORING (HA)                               │
└─────────────────────────────────────────────────────────────────────────────┘

Log Analytics Integration (Multi-Replica):
├── Container App Logs: System and application logs from all replicas
├── Environment Logs: Container App Environment metrics (2-10 replicas)
├── Log Retention: 30 days (configurable)
├── Application Gateway Metrics (Zone Redundant):
│   ├── ResponseTime (across all backend replicas)
│   ├── ThroughputPerSecond (aggregate from all replicas)
│   ├── FailedRequests (per replica tracking)
│   ├── BackendResponseTime (individual replica performance)
│   ├── HealthProbeStatus (replica health across zones)
│   └── BackendConnectionTime (replica connectivity)
├── PostgreSQL HA Metrics:
│   ├── Primary/Standby Status
│   ├── Failover Events
│   ├── Replication Lag
│   └── Connection Pool Status
└── Optional Application Insights: Performance monitoring and APM aggregation

HA-Specific Monitoring Commands:
```bash
# Monitor all Container App replicas
az containerapp replica list \\
  --resource-group rg-ref-arch-iq-ha \\
  --name ca-ref-arch-iq-ha \\
  --query '[].{Name:name,Status:properties.runningState,Zone:properties.zone}'

# Check Application Gateway backend health (all replicas)
az network application-gateway show-backend-health \\
  --resource-group rg-ref-arch-iq-ha \\
  --name agw-ref-arch-iq-ha

# Monitor PostgreSQL HA status
az postgres flexible-server show \\
  --resource-group rg-ref-arch-iq-ha \\
  --name psqlfs-ref-arch-iq-ha \\
  --query '{Status:state,HAMode:highAvailability.mode,PrimaryZone:availabilityZone,StandbyZone:highAvailability.standbyAvailabilityZone}'
```

┌─────────────────────────────────────────────────────────────────────────────┐
│                              AUTOMATION (HA)                               │
└─────────────────────────────────────────────────────────────────────────────┘

Deployment Scripts (HA-Enhanced):
├── tf-plan.sh   : HA validation, zone redundancy checks, replica validation
├── tf-apply.sh  : HA deployment with replica monitoring
└── tf-destroy.sh: HA cleanup with backup vault and soft-delete management

Identity & Access Management (HA):
├── System Assigned Managed Identity: Container Apps service identity (shared)
├── Key Vault Access Policies: Restricted to all Container App replicas
├── Service Endpoints: Storage and Key Vault access from all private subnets
├── Role-Based Access Control: Least privilege access across HA components
└── Zone-Redundant Access: Identity access across all availability zones

Auto-scaling Configuration:
```bash
# Monitor auto-scaling events
az monitor activity-log list \\
  --resource-group rg-ref-arch-iq-ha \\
  --caller 'KEDA' \\
  --max-events 50

# Check current scaling metrics
az monitor metrics list \\
  --resource-group rg-ref-arch-iq-ha \\
  --resource-type 'Microsoft.App/containerApps' \\
  --metric 'Requests,CpuUsage,MemoryUsage'
```

┌─────────────────────────────────────────────────────────────────────────────┐
│                         DISASTER RECOVERY (HA)                             │
└─────────────────────────────────────────────────────────────────────────────┘

Backup Strategy (Zone Redundant):
├── PostgreSQL HA: Zone-redundant with automatic failover + geo-redundant backups
├── File Share ZRS: Zone-redundant storage with automatic zone failover
├── Application State: Persisted across PostgreSQL + File Share (all replicas)
├── Key Vault: Soft delete enabled (90-day recovery) + zone redundancy
└── Infrastructure: Terraform state for rapid multi-zone rebuild

HA Recovery Scenarios:
1. **Single Replica Failure**:
   - Application Gateway removes failed replica within 30 seconds
   - Auto-scaler provisions replacement replica within 2-3 minutes
   - No service interruption (other replicas continue serving)

2. **Availability Zone Failure**:
   - PostgreSQL: Automatic failover to standby zone (~30 seconds)
   - Storage: ZRS automatic failover to healthy zones
   - Container Apps: Replicas restart in available zones
   - Application Gateway: Redistributes traffic to healthy zones

3. **Region Failure**:
   - Restore PostgreSQL from geo-redundant backup
   - Deploy infrastructure with Terraform in secondary region
   - File Share data restored from geo-redundant backups (if configured)
   - Key Vault secrets restored from soft delete

Recovery Process (HA):
```bash
# 1. Restore PostgreSQL HA from backup point-in-time
az postgres flexible-server restore \\
  --source-server psqlfs-ref-arch-iq-ha \\
  --target-server psqlfs-ref-arch-iq-ha-restore \\
  --restore-time "2023-12-01T10:00:00Z" \\
  --resource-group rg-ref-arch-iq-ha-dr

# 2. Deploy infrastructure with Terraform (HA configuration)
terraform apply -var-file="terraform-ha-dr.tfvars"

# 3. File Share data automatically available (ZRS)
# 4. Key Vault secrets restored from soft delete
# 5. Container Apps start with existing data (all replicas)
```

## 5. Resource Naming Convention

| Resource Type | Naming Pattern | Example | Purpose |
|---------------|----------------|---------|---------|
| Resource Group | `rg-ref-arch-iq-ha` | `rg-ref-arch-iq-ha` | Container for all HA resources |
| Virtual Network | `vnet-ref-arch-iq-ha` | `vnet-ref-arch-iq-ha` | Multi-zone network infrastructure |
| Subnets | `snet-{tier}-{zone}` | `snet-public-1`, `snet-private-2` | Zone-specific network segments |
| NSGs | `nsg-{tier}-ha` | `nsg-public-ha`, `nsg-private-ha` | Network security rules |
| Container App Env | `cae-ref-arch-iq-ha` | `cae-ref-arch-iq-ha` | HA container environment |
| Container App | `ca-ref-arch-iq-ha` | `ca-ref-arch-iq-ha` | Nexus IQ HA application |
| Application Gateway | `agw-ref-arch-iq-ha` | `agw-ref-arch-iq-ha` | Zone-redundant load balancer |
| PostgreSQL Server | `psqlfs-ref-arch-iq-ha` | `psqlfs-ref-arch-iq-ha` | Zone-redundant database |
| Storage Account | `st{random}ha` | `st7xk9mha` | Premium ZRS storage |
| Key Vault | `kv-ref-arch-iq-ha{suffix}` | `kvrefarchiqha7x9k` | Secrets management |
| Public IP | `pip-agw-ha` | `pip-agw-ha` | Static IP for Application Gateway |
| Log Analytics | `log-ref-arch-iq-ha` | `log-ref-arch-iq-ha` | Centralized logging |

**High Availability Naming Conventions:**
- All resources include `-ha` suffix to distinguish from single-instance deployment
- Zone-specific resources numbered 1-3 for availability zone distribution
- Random suffixes used where Azure requires globally unique names

### Logging & Metrics
- **Log Analytics Workspace**: `log-ref-arch-iq-ha` (30-day retention)
- **Application Insights**: `appi-ref-arch-iq-ha` (when enabled)
- **Container Apps Insights**: Built-in Container Apps monitoring
- **Application Gateway Diagnostics**: Access, Performance, and Firewall logs

### Health Monitoring
- **Container App Health Probes**:
  - Startup probe: 30s interval, 10 failure threshold (extended for HA startup)
  - Liveness probe: 30s interval, 3 failure threshold
  - Readiness probe: 15s interval, 3 failure threshold
- **Application Gateway Health Probes**: HTTP checks on Container App ingress
- **Database Monitoring**: Built-in PostgreSQL Flexible Server metrics and alerts

## 6. Azure Container Apps Port Architecture

### **Current Port Configuration**

| **Component** | **Port** | **Accessibility** | **Purpose** |
|---------------|----------|-------------------|-------------|
| **Container App Ingress** | 80 | ✅ External | Main application access (HA load balanced) |
| **Nexus IQ Application** | 8070 | ✅ Internal | Application server (mapped from port 80, all replicas) |
| **Nexus IQ Admin** | 8071 | ❌ Internal only | Admin interface (not externally accessible across replicas) |

**High Availability Port Setup:**
- **Primary Ingress Port**: 8070 (Nexus IQ Server web interface)
  - Exposed externally via Container Apps ingress (port 80)
  - Application Gateway health probes target this port
  - Load balancing across 2-10 replicas
- **Admin Port**: 8071 (Internal admin interface)
  - Available within container for admin operations
  - Not exposed externally due to Azure Container Apps limitations

### **Azure Container Apps Ingress Architecture**

**Current Working Pattern (HA):**
```
Internet → Application Gateway (Port 80) → Container App Ingress → Nexus IQ Replicas (2-10) ✅
```

**Attempted Admin Pattern (HA):**
```
Internet → Application Gateway (Port 8071) → ❌ BLOCKED - Container Apps doesn't expose port 8071 across replicas
```

### **Admin Port Access Limitations**

**❌ What Cannot Be Done in HA:**
- External health checks on port 8071 across multiple replicas
- Direct admin port access from Application Gateway to specific replicas
- Multi-port load balancing configurations for admin access
- Admin-specific health probe endpoints across replica fleet

**✅ What Works in HA:**
- Main application access and health monitoring across all replicas
- Internal admin functionality within each individual container
- Database connectivity and file storage from all replicas
- Application monitoring and logging aggregated from all replicas
- Load balancing and auto-scaling of main application traffic

### **HA-Specific Considerations**

**Multi-Replica Port Sharing:**
- All replicas share the same ingress configuration
- Container Apps automatically load balances across healthy replicas
- Each replica runs independently on port 8070 internally
- Application Gateway distributes traffic to available replicas

**Admin Port Access Limitations in HA:**
- Port 8071 not accessible externally across replicas
- Azure Container Apps ingress supports only one primary external port
- Admin operations require container exec to specific replica

### **Workarounds for Admin Access in HA Environment**

**Container Exec (Recommended):**
```bash
# List available replicas
az containerapp replica list \\
  --resource-group rg-ref-arch-iq-ha \\
  --name ca-ref-arch-iq-ha

# Exec into specific replica for admin access
az containerapp exec \\
  --resource-group rg-ref-arch-iq-ha \\
  --name ca-ref-arch-iq-ha \\
  --replica-name <replica-name>
```

**Internal Admin Access:**
```bash
# Once inside container, access admin port
curl http://localhost:8071/admin/system-information
```

**Log Analysis for Admin Operations:**
```bash
# Monitor admin activities through Container Apps logs
az containerapp logs show \\
  --resource-group rg-ref-arch-iq-ha \\
  --name ca-ref-arch-iq-ha \\
  --follow
```

### **Production Recommendations for HA**

1. **Primary Access**: Use Application Gateway URL for all production access
2. **Admin Operations**: Plan admin tasks using container exec access
3. **Monitoring**: Implement comprehensive logging for admin activity tracking
4. **Health Checks**: Rely on port 8070 health probes across all replicas
5. **Load Balancing**: Configure Application Gateway for optimal replica distribution

This HA port architecture ensures consistent access patterns while working within Azure Container Apps constraints across multiple replicas.

---

**This High Availability architecture provides enterprise-grade deployment for Nexus IQ Server with automatic failover, horizontal scaling, zone redundancy, and comprehensive monitoring suitable for production environments requiring 99.9%+ uptime.**
