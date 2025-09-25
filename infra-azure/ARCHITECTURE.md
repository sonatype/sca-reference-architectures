# Nexus IQ Server Azure Reference Architecture (Single Instance)

## Deployment Profile

**Recommended for:**
- **Development and testing environments**
- **Proof of concept deployments**
- **Small to medium organizations** with up to 100 onboarded applications
- **Low to moderate scan frequency** (up to 2-3 evaluations per minute)

**System Specifications:**
- 2.0 vCPU / 4GB RAM (Cloud-native optimized)
- PostgreSQL Flexible Server external database
- Azure File Share persistent storage
- Single instance deployment with zone-redundant supporting services

## Overview
This reference architecture deploys Nexus IQ Server on Microsoft Azure using cloud-native services (Container Apps, PostgreSQL Flexible Server, Azure File Share) for operational excellence and security. This single-instance deployment provides a solid foundation for development, testing, and small to medium production workloads.

## Scaling Options
- **Current Deployment**: Single Instance (up to 100 applications)
- **Vertical Scaling**: Increase CPU/memory resources as needed
- **Database Scaling**: Enable high availability and zone redundancy
- **Storage Scaling**: Azure File Share auto-scales based on usage

## 1. High-Level Architecture

```
┌────────────────────────────────────────────────────────────────────────────────────────────┐
│                                       INTERNET                                             │
└───────────────────────────────────────────┬────────────────────────────────────────────────┘
                                            │
                                            │ HTTP/HTTPS Traffic
                                            │
┌───────────────────────────────────────────▼────────────────────────────────────────────────┐
│                                     AZURE VNET                                             │
│   ┌────────────────────────────────────────────────────────────────────────────────────┐   │
│   │                         PUBLIC SUBNET (Zone Redundant)                             │   │
│   │   ┌──────────────────────────────────────────────────────────────────────────────┐ │   │
│   │   │                      Application Gateway                                     │ │   │
│   │   │                        Port 80 → Backend Pool                                │ │   │
│   │   │                     Health Probes: 8070, 8071                                │ │   │
│   │   └───────────────────────────────────┬──────────────────────────────────────────┘ │   │
│   └───────────────────────────────────────┼────────────────────────────────────────────┘   │
│                                           │
│   ┌───────────────────────────────────────▼────────────────────────────────────────────┐   │
│   │                        PRIVATE SUBNET (Container Apps)                             │   │
│   │   ┌─────────────────────────────────────────────────────────────────────────────┐  │   │
│   │   │                    CONTAINER APP ENVIRONMENT                                │  │   │
│   │   │   ┌──────────────────────────────────────────────────────────────────────┐  │  │   │
│   │   │   │                 Nexus IQ Server Container                            │  │  │   │
│   │   │   │                   Port 8070: Application                             │  │  │   │
│   │   │   │                   Port 8071: Admin (Health Check Only)               │  │  │   │
│   │   │   │                   CPU: 2.0, Memory: 4Gi                              │  │  │   │
│   │   │   │                   Replicas: 1 (Single Instance)                      │  │  │   │
│   │   │   └───────────────────────────────┬──────────────────────────────────────┘  │  │   │
│   │   └───────────────────────────────────┼─────────────────────────────────────────┘  │   │
│   └───────────────────────────────────────┼────────────────────────────────────────────┘   │
│                                           │                                                │
│                                           │                                                │
│                         ┌─────────────────┴───────────────┐                                │
│                         │                                 │                                │
│   ┌─────────────────────▼───────────────────────┐   ┌─────▼────────────────────┐           │
│   │              STORAGE LAYER                  │   │     DATABASE SUBNET      │           │
│   │   ┌─────────────────────────────────────┐   │   │   ┌───────────────────┐  │           │
│   │   │       AZURE FILE SHARE              │   │   │   │   POSTGRESQL      │  │           │
│   │   │     /sonatype-work storage          │   │   │   │   FLEXIBLE SERVER │  │           │
│   │   │     Premium tier (Zone redundant)   │   │   │   │   Version 15      │  │           │
│   │   │     Encrypted at rest               │   │   │   │   B_Standard_B2s  │  │           │
│   │   │     SMB 3.0 protocol                │   │   │   │   Encrypted       │  │           │
│   │   └─────────────────────────────────────┘   │   │   │   Automated       │  │           │
│   └─────────────────────────────────────────────┘   │   │   Backups         │  │           │
│                                                     │   │   Key Vault       │  │           │
│                                                     │   │   Integration     │  │           │
│                                                     │   └───────────────────┘  │           │
│                                                     └──────────────────────────┘           │
└────────────────────────────────────────────────────────────────────────────────────────────┘

              ┌──────────────────────────────────────────────┐
              │             SUPPORTING SERVICES              │
              │                                              │
              │  • Log Analytics (Container Monitoring)      │
              │  • Key Vault (Database Credentials)          │
              │  • Application Insights (Optional APM)       │
              │  • Managed Identity (Service Authentication) │
              └──────────────────────────────────────────────┘
```

## 2. Network Flow & Security

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           TRAFFIC FLOW                                      │
└─────────────────────────────────────────────────────────────────────────────┘

Internet → Application Gateway (Port 80)
    ↓
Application Gateway NSG (HTTP: 80, HTTPS: 443)
    ↓
Backend Pool Health Probes:
    • Port 8070: /         (accepts 200,302,303,404)
    • Port 8071: /healthcheck (accepts 200,404) - Internal Only
    ↓
Container Apps NSG (Port 8070, 8071 from App Gateway only)
    ↓
Nexus IQ Container (Private Subnet)
    ↓
    ├── Database NSG (Port 5432 from Container Apps only)
    │   ↓
    │   PostgreSQL Flexible Server (DB Subnet)
    │
    └── Storage Account (SMB 445 from Container Apps only)
        ↓
        Azure File Share (Zone Redundant)

┌─────────────────────────────────────────────────────────────────────────────┐
│                          SECURITY BOUNDARIES                                │
└─────────────────────────────────────────────────────────────────────────────┘

Public Zone:     │ Internet Gateway ← → Application Gateway only
Private Zone:    │ Container Apps Environment (no inbound from internet)
Database Zone:   │ Container Apps → PostgreSQL only (completely isolated)
Storage Zone:    │ Container Apps → File Share only (service endpoints)

Network Security Groups (Least Privilege):
┌─────────────────┬──────────────────┬─────────────────┬──────────────────┐
│   Component     │    Inbound       │    Outbound     │    Protocol      │
├─────────────────┼──────────────────┼─────────────────┼──────────────────┤
│ App Gateway     │ Internet:80,443  │ Container:8070  │ HTTP             │
│ Container Apps  │ AppGW:8070,8071  │ PostgreSQL:5432 │ TCP              │
│                 │                  │ FileShare:445   │ TCP/SMB          │
│ PostgreSQL      │ Container:5432   │ None            │ PostgreSQL       │
│ File Share      │ Container:445    │ None            │ SMB              │
└─────────────────┴──────────────────┴─────────────────┴──────────────────┘
```

## 3. Component Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        AZURE CONTAINER APPS DEPLOYMENT                      │
└─────────────────────────────────────────────────────────────────────────────┘

Container App Environment: cae-ref-arch-iq
    ├── Location: Private Subnet (Infrastructure Subnet)
    ├── Log Analytics: log-ref-arch-iq
    ├── Application Insights: appi-ref-arch-iq (optional)
    └── Storage Mount: Azure File Share
    ↓
Container App: ca-ref-arch-iq
    ├── Replicas: 1 (min: 1, max: 1)
    ├── Revision Mode: Single
    ├── Identity: System Assigned Managed Identity
    ├── Container Configuration:
    │   ├── Image: sonatypecommunity/nexus-iq-server:latest
    │   ├── CPU: 2.0 vCPU
    │   ├── Memory: 4Gi (4 GB)
    │   ├── Custom entrypoint with config.yml generation
    │   ├── Environment Variables:
    │   │   ├── DB_HOST: <PostgreSQL_FQDN>
    │   │   ├── DB_PORT: 5432
    │   │   ├── DB_NAME: nexusiq
    │   │   └── JAVA_OPTS: -Xmx2g -Djava.util.prefs.userRoot=/sonatype-work/javaprefs
    │   ├── Secrets (from Key Vault):
    │   │   ├── DB_USERNAME
    │   │   └── DB_PASSWORD
    │   └── Volume Mounts:
    │       └── /sonatype-work ← Azure File Share (Persistent Data)
    └── Application Ingress:
        ├── External Ingress: Disabled (accessed via Application Gateway)
        ├── Target Port: 8070
        └── Transport: HTTP

┌─────────────────────────────────────────────────────────────────────────────┐
│                            DATA PERSISTENCE                                 │
└─────────────────────────────────────────────────────────────────────────────┘

Database Layer:
┌─────────────────────────────────────────────────────────────────────────────┐
│ PostgreSQL Flexible Server (psql-ref-arch-iq)                               │
│  ├── SKU: B_Standard_B2s (2 vCores, 4GB RAM)                                │
│  ├── Version: PostgreSQL 15                                                 │
│  ├── High Availability: No (Single Instance Reference)                      │
│  ├── Storage: 32GB, Auto-scaling enabled                                    │
│  ├── Encryption: At rest enabled                                            │
│  ├── Backup: Automated, 7-day retention                                     │
│  ├── Network: Private DNS zone integration                                  │
│  └── Credentials: Stored in Azure Key Vault                                 │
└─────────────────────────────────────────────────────────────────────────────┘

File Storage:
┌─────────────────────────────────────────────────────────────────────────────┐
│ Azure Storage Account (strefarchiq<random>)                                 │
│  ├── Type: StorageV2 (General Purpose v2)                                   │
│  ├── Performance: Standard                                                  │
│  ├── Replication: LRS (Locally Redundant)                                   │
│  ├── Encryption: Microsoft-managed keys                                     │
│  └── File Share: Premium tier, 100GB quota                                  │
│      ├── Protocol: SMB 3.0                                                  │
│      ├── Mounted at: /sonatype-work                                         │
│      └── Access: Service endpoint from private subnet                       │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 4. Operational Excellence

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              MONITORING                                     │
└─────────────────────────────────────────────────────────────────────────────┘

Log Analytics Integration:
├── Container App Logs: System and application logs
├── Environment Logs: Container App Environment metrics
├── Log Retention: 30 days (configurable)
├── Application Gateway Metrics:
│   ├── ResponseTime
│   ├── ThroughputPerSecond
│   ├── FailedRequests
│   └── BackendResponseTime
└── Optional Application Insights: Performance monitoring and APM

┌─────────────────────────────────────────────────────────────────────────────┐
│                              AUTOMATION                                     │
└─────────────────────────────────────────────────────────────────────────────┘

Deployment Scripts:
├── tf-plan.sh   : Plan with Azure CLI authentication
├── tf-apply.sh  : Deploy with Azure CLI authentication
└── tf-destroy.sh: Cleanup with automatic Key Vault purge

Identity & Access Management:
├── System Assigned Managed Identity: Container Apps service identity
├── Key Vault Access Policies: Restricted to Container Apps identity
├── Service Endpoints: Storage and Key Vault access from private subnet
└── Role-Based Access Control: Least privilege access

┌─────────────────────────────────────────────────────────────────────────────┐
│                         DISASTER RECOVERY                                   │
└─────────────────────────────────────────────────────────────────────────────┘

Backup Strategy:
├── PostgreSQL: Automated daily backups (7-day retention)
├── File Share: Point-in-time restore capabilities
├── Application State: Persisted in PostgreSQL + File Share
├── Key Vault: Soft delete enabled (90-day recovery period)
└── Infrastructure: Terraform state for rapid rebuild

Recovery Process:
1. Restore PostgreSQL from backup point-in-time
2. Deploy infrastructure with Terraform
3. File Share data automatically available
4. Key Vault secrets restored from soft delete
5. Container App starts with existing data
```

## 5. Resource Naming Convention

All resources use the prefix `ref-arch-iq` for easy identification:

| Component | Resource Name | Purpose |
|-----------|---------------|---------|
| **Networking** |
| Resource Group | `rg-ref-arch-iq` | Container for all resources |
| Virtual Network | `vnet-ref-arch-iq` | Isolated network environment |
| Public Subnet | `snet-public` | Application Gateway placement |
| Private Subnet | `snet-private` | Container Apps environment |
| Database Subnet | `snet-database` | PostgreSQL isolation |
| **Compute** |
| Container App Environment | `cae-ref-arch-iq` | Serverless container platform |
| Container App | `ca-ref-arch-iq` | Application hosting |
| **Load Balancing** |
| Application Gateway | `appgw-ref-arch-iq` | Public-facing load balancer |
| Public IP | `pip-appgw-ref-arch-iq` | Static public IP address |
| **Storage** |
| PostgreSQL Server | `psql-ref-arch-iq` | PostgreSQL database |
| Storage Account | `strefarchiq<random>` | Blob and file storage |
| File Share | `iq-data` | Persistent file storage |
| **Security** |
| Key Vault | `kv-ref-arch-iq-<random>` | Secrets management |
| Network Security Groups | `nsg-*` | Network access control |
| **Monitoring** |
| Log Analytics | `log-ref-arch-iq` | Centralized logging |
| Application Insights | `appi-ref-arch-iq` | Application performance monitoring |
