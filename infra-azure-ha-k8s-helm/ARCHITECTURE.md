# Nexus IQ Server Azure AKS Reference Architecture (High Availability)

## Deployment Profile

**Recommended for:**
- **Production environments** requiring high availability
- **Enterprise organizations** with 100+ applications
- **High scan frequency** (10+ evaluations per minute)
- **Mission-critical deployments** with zero-downtime requirements

**System Specifications:**
- 2+ replicas with 4GB RAM each (Kubernetes HA optimized)
- Azure PostgreSQL Flexible Server (Zone-Redundant HA)
- Azure Files Premium with shared storage (Quartz clustering enabled by HA license)
- Multi-zone deployment across availability zones

## Overview
This reference architecture deploys Nexus IQ Server on Azure AKS using Kubernetes-native services for high availability, auto-scaling, and operational excellence. The HA deployment provides enterprise-grade reliability and performance.

**⚠️ Important**: This HA deployment requires a clustering-capable Nexus IQ license. The HA license enables Quartz scheduler clustering, allowing all pods to safely share the same work directory on Azure Files Premium storage.

## Scaling Options
- **Current Deployment**: High Availability (2+ replicas, unlimited applications)
- **Horizontal Scaling**: Auto-scaling 2-10 pods based on CPU/memory utilization
- **Vertical Scaling**: Increase pod CPU/memory resources as needed
- **Database Scaling**: PostgreSQL read replicas for enhanced database performance

## 1. High-Level Architecture

```
┌────────────────────────────────────────────────────────────────────────────────────────────┐
│                                       INTERNET                                             │
└───────────────────────────────────────┬────────────────────────────────────────────────────┘
                                        │
                                        │ HTTP/HTTPS Traffic
                                        │
┌───────────────────────────────────────▼────────────────────────────────────────────────────┐
│                                     AZURE VNET                                             │
│   ┌────────────────────────────────────────────────────────────────────────────────────┐   │
│   │                         PUBLIC SUBNETS (Multi-Zone)                                │   │
│   │   ┌──────────────────────────────────────────────────────────────────────────────┐ │   │
│   │   │                      Application Gateway                                     │ │   │
│   │   │                   Port 80 → Azure LoadBalancer (Port 8070)                   │ │   │
│   │   │                     Health Checks: /ping                                     │ │   │
│   │   │                     Zone-Redundant (Zones 1,2,3)                             │ │   │
│   │   └───────────────────────────────────┬──────────────────────────────────────────┘ │   │
│   └───────────────────────────────────────┼────────────────────────────────────────────┘   │
│                                           │
│   ┌───────────────────────────────────────▼────────────────────────────────────────────┐   │
│   │                        Azure LoadBalancer (Port 8070)                              │   │
│   └───────────────────────────────────────┬────────────────────────────────────────────┘   │
│                                           │
│   ┌───────────────────────────────────────▼────────────────────────────────────────────┐   │
│   │                        PRIVATE SUBNETS (Multi-Zone)                                │   │
│   │   ┌─────────────────────────────────────────────────────────────────────────────┐  │   │
│   │   │                           AKS CLUSTER                                       │  │   │
│   │   │   ┌──────────────────────────────────────────────────────────────────────┐  │  │   │
│   │   │   │              Nexus IQ Server HA Pods (2+ replicas)                   │  │  │   │
│   │   │   │                   Port 8070: Application                             │  │  │   │
│   │   │   │                   CPU: 2, Memory: 4Gi each                           │  │  │   │
│   │   │   │                   Unique work dirs per pod                           │  │  │   │
│   │   │   │                   Anti-Affinity: Different nodes                     │  │  │   │
│   │   │   └───────────────────────────────┬──────────────────────────────────────┘  │  │   │
│   │   └───────────────────────────────────┼─────────────────────────────────────────┘  │   │
│   └───────────────────────────────────────┼────────────────────────────────────────────┘   │
│                                           │                                                │
│                         ┌─────────────────┴───────────────┐                                │
│                         │                                 │                                │
│   ┌─────────────────────▼───────────────────────┐   ┌─────▼────────────────────┐           │
│   │              STORAGE LAYER                  │   │     DATABASE SUBNETS     │           │
│   │   ┌─────────────────────────────────────┐   │   │   ┌───────────────────┐  │           │
│   │   │    AZURE FILES PREMIUM (ZRS)        │   │   │   │ POSTGRESQL        │  │           │
│   │   │  Shared storage with HA clustering: │   │   │   │   Flexible Server │  │           │
│   │   │  /sonatype-work/clm-server          │   │   │   │   Zone-Redundant  │  │           │
│   │   │  /sonatype-work/clm-cluster         │   │   │   │   Primary + HA    │  │           │
│   │   │  Premium tier (Zone redundant)      │   │   │   │   Encrypted       │  │           │
│   │   │  ReadWriteMany (RWX) for all pods   │   │   │   │   Automated       │  │           │
│   │   │  Encrypted at rest + SMB 3.0        │   │   │   │   Backups         │  │           │
│   │   └─────────────────────────────────────┘   │   │   └───────────────────┘  │           │
│   └─────────────────────────────────────────────┘   └──────────────────────────┘           │
└────────────────────────────────────────────────────────────────────────────────────────────┘

              ┌─────────────────────────────────────────────┐
              │             SUPPORTING SERVICES             │
              │                                             │
              │  • Azure LoadBalancer (K8s Service)         │
              │  • Horizontal Pod Autoscaler                │
              │  • Azure Files CSI Driver                   │
              │  • Azure Monitor Container Insights         │
              │  • Kubernetes Secrets                       │
              └─────────────────────────────────────────────┘
```

## 2. Network Flow & Security

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           TRAFFIC FLOW                                      │
└─────────────────────────────────────────────────────────────────────────────┘

Internet → Application Gateway (Port 80)
    ↓
Azure LoadBalancer (K8s LoadBalancer Service, Port 8070)
    ↓
Nexus IQ HA Pods (Port 8070, Multiple replicas)
    ↓
    ├── PostgreSQL Flexible Server (Port 5432, Primary/HA endpoints)
    │
    └── Azure Files Premium (Port 445, SMB 3.0)

Security Groups & Network Policies:
┌─────────────────┬──────────────────┬─────────────────┬──────────────────┐
│   Component     │    Inbound       │    Outbound     │    Protocol      │
├─────────────────┼──────────────────┼─────────────────┼──────────────────┤
│ App Gateway     │ Internet:80,443  │ AKS:NodePort    │ HTTP/HTTPS       │
│ AKS Pods        │ AppGW via Svc    │ PostgreSQL:5432 │ TCP              │
│                 │                  │ Azure Files:445 │ SMB 3.0          │
│ PostgreSQL      │ AKS Pods:5432    │ None            │ PostgreSQL       │
│ Azure Files     │ AKS Pods:445     │ None            │ SMB 3.0          │
└─────────────────┴──────────────────┴─────────────────┴──────────────────┘
```

## 3. Component Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           AKS KUBERNETES DEPLOYMENT                         │
└─────────────────────────────────────────────────────────────────────────────┘

AKS Cluster: nexus-iq-ha
    ├── Kubernetes Version: 1.29+
    ├── Control Plane: Azure Managed
    ├── Node Pools:
    │   ├── System Pool: Auto-scaling (2-6 nodes)
    │   └── User Pool: Auto-scaling (2-6 nodes)
    └── Availability Zones: Multi-zone distribution (1,2,3)
    ↓
Namespace: nexus-iq
    ├── Deployment: nexus-iq-server-ha
    │   ├── Replicas: 2-10 (HPA managed)
    │   ├── Strategy: RollingUpdate
    │   └── Pod Anti-Affinity: Ensure distribution across nodes
    ├── Service: nexus-iq-server-ha (ClusterIP)
    ├── Ingress: nexus-iq-server-ha (AGIC integration)
    ├── HPA: Horizontal Pod Autoscaler (CPU/Memory targets)
    └── Secrets: Database credentials, license
    ↓
Pod Specifications:
    ├── Container: sonatype/nexus-iq-server:latest
    ├── Resources: CPU 2, Memory 4Gi
    ├── Ports: 8070 (application)
    ├── Health Checks: readiness/liveness probes
    └── Volume Mounts:
        ├── /sonatype-work ← Azure Files PVC (ReadWriteMany)
        │   └── All pods share: /sonatype-work/clm-server (HA clustering)
        │   └── Shared coordination: /sonatype-work/clm-cluster
        └── /var/log/nexus-iq-server ← Azure Files (logs)

┌─────────────────────────────────────────────────────────────────────────────┐
│                            DATA PERSISTENCE                                 │
└─────────────────────────────────────────────────────────────────────────────┘

Database Layer:
┌─────────────────────────────────────────────────────────────────────────────┐
│ Azure PostgreSQL Flexible Server (nexus-iq-ha-db)                           │
│  ├── SKU: GP_Standard_D4s_v3 (4 vCores, 16GB RAM)                          │
│  ├── HA Mode: ZoneRedundant                                                │
│  ├── Version: PostgreSQL 15                                                │
│  ├── Multi-Zone: Yes (Primary + Standby)                                   │
│  ├── Storage: 64GB (auto-scaling capable)                                  │
│  ├── Storage Tier: P6 (Premium SSD)                                        │
│  ├── Encryption: At rest + in transit (SSL required)                       │
│  ├── Backup: Automated, 7-day retention                                    │
│  └── Geo-Redundant: Enabled                                                │
└─────────────────────────────────────────────────────────────────────────────┘

Storage Layer:
┌─────────────────────────────────────────────────────────────────────────────┐
│ Azure Files Premium (nexus-iq-ha-files)                                     │
│  ├── Performance Tier: Premium                                              │
│  ├── Replication: Zone-Redundant Storage (ZRS)                             │
│  ├── CSI Driver: Azure Files CSI Driver                                    │
│  ├── StorageClass: azure-files-premium                                     │
│  ├── PVC: nexus-iq-pvc (shared across pods)                                │
│  ├── Quota: 512GB                                                           │
│  ├── Protocol: SMB 3.0                                                      │
│  └── Encryption: Transit + At Rest                                          │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 4. Operational Excellence

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              MONITORING                                     │
└─────────────────────────────────────────────────────────────────────────────┘

Kubernetes Monitoring:
├── Container Insights: Enabled on AKS cluster
├── Log Analytics Workspace: Centralized logging
├── Application Insights: Application performance monitoring
├── Pod Metrics: CPU, memory, network, storage
├── Application Logs: kubectl logs, Azure Monitor integration
└── Cluster Metrics: Node utilization, pod scheduling

Auto-Scaling:
├── Horizontal Pod Autoscaler: 2-10 pods based on CPU/memory
├── Cluster Autoscaler: Node pools scale based on pod demands
└── Metrics: Azure Monitor metrics integration

┌─────────────────────────────────────────────────────────────────────────────┐
│                              AUTOMATION                                     │
└─────────────────────────────────────────────────────────────────────────────┘

Deployment Automation:
├── Terraform: Infrastructure as Code
├── Helm: Kubernetes application deployment
├── Scripts: tf-*.sh and helm-*.sh for automated operations
└── GitOps Ready: Declarative configuration management

High Availability:
├── Pod Anti-Affinity: Pods distributed across nodes/zones
├── Rolling Updates: Zero-downtime deployments
├── Pod Disruption Budgets: Maintain minimum replicas during updates
└── Health Checks: Automatic pod restart on failure

Azure-Specific Features:
├── Managed Identities: Workload identity for secure access
├── Azure Policy: Governance and compliance
├── Azure Key Vault: Secrets management integration
└── Azure RBAC: Fine-grained access control
```

## 5. Resource Naming Convention

All resources use consistent naming patterns for easy identification:

| Component | Resource Name | Purpose |
|-----------|---------------|---------|
| **Infrastructure** |
| Resource Group | `rg-{cluster-name}` | Logical resource container |
| AKS Cluster | `aks-{cluster-name}` | Managed Kubernetes cluster |
| VNet | `vnet-{cluster-name}` | Isolated network environment |
| Subnets | `snet-*` | Network segmentation |
| Network Security Groups | `nsg-*` | Network access control |
| **Application Gateway** |
| App Gateway | `agw-{cluster-name}` | Ingress controller |
| Public IP | `pip-agw-{cluster-name}` | External access endpoint |
| **Kubernetes** |
| Namespace | `nexus-iq` | Application isolation |
| Deployment | `nexus-iq-server-ha` | Pod management |
| Service | `nexus-iq-server-ha` | Internal networking |
| Ingress | `nexus-iq-server-ha` | External access |
| PVC | `nexus-iq-pvc` | Persistent storage claim |
| **Storage** |
| PostgreSQL Server | `psql-{cluster-name}` | HA database server |
| Database | `nexusiq` | Application database |
| Storage Account | `st{cluster-name}iqha` | Files storage account |
| File Shares | `iq-data-ha`, `iq-cluster-ha` | Shared persistent storage |
| **Monitoring** |
| Log Analytics | `log-{cluster-name}` | Centralized logging |
| App Insights | `appi-{cluster-name}` | Application monitoring |
| **Security** |
| Secrets | `nexus-iq-*` | Credential storage |
| Managed Identities | `id-agic-{cluster-name}` | Workload identities |
