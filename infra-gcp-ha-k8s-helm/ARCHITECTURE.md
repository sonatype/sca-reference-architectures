# Nexus IQ Server GCP GKE Reference Architecture (High Availability)

## Deployment Profile

**Recommended for:**
- **Production environments** requiring high availability
- **Enterprise organizations** with 100+ applications
- **High scan frequency** (10+ evaluations per minute)
- **Mission-critical deployments** with zero-downtime requirements

**System Specifications:**
- 2-10 replicas with 4GB RAM each (Kubernetes HA optimized)
- Cloud SQL PostgreSQL Regional (Multi-Zone with automatic failover)
- Filestore shared persistent storage (2.5TB BASIC_SSD)
- Multi-zone deployment across zones within a region

## Overview
This reference architecture deploys Nexus IQ Server on GCP GKE using Kubernetes-native services for high availability, auto-scaling, and operational excellence. The HA deployment provides enterprise-grade reliability and performance.

**⚠️ Important**: This HA deployment requires a clustering-capable Nexus IQ license and uses shared Filestore (NFS) for cluster coordination between pods.

## Scaling Options
- **Current Deployment**: High Availability (2-10 replicas, unlimited applications)
- **Horizontal Scaling**: Auto-scaling 2-10 pods based on CPU/memory utilization
- **Vertical Scaling**: Increase pod CPU/memory resources as needed
- **Database Scaling**: Cloud SQL read replicas for enhanced database performance

## 1. High-Level Architecture

```
┌────────────────────────────────────────────────────────────────────────────────────────────┐
│                                       INTERNET                                             │
└───────────────────────────────────────────┬────────────────────────────────────────────────┘
                                            │
                                            │ HTTP/HTTPS Traffic
                                            │
┌───────────────────────────────────────────▼────────────────────────────────────────────────┐
│                                        GCP VPC                                             │
│   ┌────────────────────────────────────────────────────────────────────────────────────┐   │
│   │                         PUBLIC SUBNET (Single Region)                              │   │
│   │   ┌──────────────────────────────────────────────────────────────────────────────┐ │   │
│   │   │                      Cloud Load Balancer (L7)                                │ │   │
│   │   │                        Port 80 → GKE Ingress                                 │ │   │
│   │   │                     Health Checks: /ping (port 8070)                         │ │   │
│   │   │                     Cloud Armor DDoS Protection                              │ │   │
│   │   └───────────────────────────────────┬──────────────────────────────────────────┘ │   │
│   └───────────────────────────────────────┼────────────────────────────────────────────┘   │
│                                           │
│   ┌───────────────────────────────────────▼────────────────────────────────────────────┐   │
│   │                    PRIVATE SUBNETS (Multi-Zone)                                    │   │
│   │   ┌─────────────────────────────────────────────────────────────────────────────┐  │   │
│   │   │                           GKE CLUSTER (Private)                             │  │   │
│   │   │   ┌──────────────────────────────────────────────────────────────────────┐  │  │   │
│   │   │   │              Nexus IQ Server HA Pods (2-10 replicas)                │  │  │   │
│   │   │   │                   Port 8070: Application                             │  │  │   │
│   │   │   │                   CPU: 2, Memory: 4Gi each                           │  │  │   │
│   │   │   │                   Anti-Affinity: Different nodes                     │  │  │   │
│   │   │   │                   Fluentd Sidecars for logging                       │  │  │   │
│   │   │   └───────────────────────────────┬──────────────────────────────────────┘  │  │   │
│   │   │   ┌──────────────────────────────────────────────────────────────────────┐  │  │   │
│   │   │   │          Fluentd Aggregator (StatefulSet)                            │  │  │   │
│   │   │   │          Collects logs → Cloud Logging                               │  │  │   │
│   │   │   └──────────────────────────────────────────────────────────────────────┘  │  │   │
│   │   └───────────────────────────────────┼─────────────────────────────────────────┘  │   │
│   └───────────────────────────────────────┼────────────────────────────────────────────┘   │
│                                           │                                                │
│                         ┌─────────────────┴───────────────┐                                │
│                         │                                 │                                │
│   ┌─────────────────────▼───────────────────────┐   ┌─────▼────────────────────┐           │
│   │              STORAGE LAYER                  │   │   DATABASE SUBNETS       │           │
│   │   ┌─────────────────────────────────────┐   │   │   ┌───────────────────┐  │           │
│   │   │      FILESTORE (NFS)                │   │   │   │  CLOUD SQL        │  │           │
│   │   │     /sonatype-work shared           │   │   │   │  POSTGRESQL       │  │           │
│   │   │     2.5TB BASIC_SSD                 │   │   │   │  Regional         │  │           │
│   │   │     Multi-zone access               │   │   │   │  Multi-Zone       │  │           │
│   │   │     Encrypted at rest/transit       │   │   │   │  Failover         │  │           │
│   │   │     NFS v3                          │   │   │   │  Encrypted        │  │           │
│   │   └─────────────────────────────────────┘   │   │   │  Automated        │  │           │
│   └─────────────────────────────────────────────┘   │   │  Backups          │  │           │
│                                                     │   └───────────────────┘  │           │
│                                                     └──────────────────────────┘           │
└────────────────────────────────────────────────────────────────────────────────────────────┘

              ┌─────────────────────────────────────────────┐
              │             SUPPORTING SERVICES             │
              │                                             │
              │  • GCE Ingress Controller (built-in)       │
              │  • Horizontal Pod Autoscaler                │
              │  • Workload Identity (GCP's IRSA)           │
              │  • Cloud Logging (Fluentd)                  │
              │  • Cloud Monitoring                         │
              │  • Secret Manager                           │
              └─────────────────────────────────────────────┘
```

## 2. Network Flow & Security

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           TRAFFIC FLOW                                      │
└─────────────────────────────────────────────────────────────────────────────┘

Internet → Cloud Load Balancer (Port 80) with Cloud Armor
    ↓
GCE Ingress Controller (Kubernetes Ingress)
    ↓
Kubernetes Service (NodePort - required by GCE Ingress)
    ↓
Nexus IQ HA Pods (Port 8070, Multiple replicas, Multi-Zone)
    ↓
    ├── Cloud SQL (Port 5432, Regional with automatic failover)
    │
    └── Filestore (Port 2049, NFS v3)

Security Groups & Firewall Rules:
┌─────────────────┬──────────────────┬─────────────────┬──────────────────┐
│   Component     │    Inbound       │    Outbound     │    Protocol      │
├─────────────────┼──────────────────┼─────────────────┼──────────────────┤
│ Cloud LB        │ Internet:80,443  │ GKE:NodePort    │ HTTP/HTTPS       │
│ GKE Pods        │ LB via Service   │ Cloud SQL:5432  │ TCP              │
│                 │                  │ Filestore:2049  │ NFS              │
│                 │                  │ Cloud Logging   │ HTTPS            │
│ Cloud SQL       │ GKE Pods:5432    │ None            │ PostgreSQL       │
│ Filestore       │ GKE Pods:2049    │ None            │ NFS v3           │
└─────────────────┴──────────────────┴─────────────────┴──────────────────┘
```

## 3. Component Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           GKE KUBERNETES DEPLOYMENT                         │
└─────────────────────────────────────────────────────────────────────────────┘

GKE Cluster: nexus-iq-ha
    ├── Kubernetes Version: 1.27+
    ├── Control Plane: GCP Managed
    ├── Node Pools: Auto-scaling (2-6 nodes)
    ├── Private Cluster: Nodes without external IPs
    └── Multi-Zone: Distribution across zones
    ↓
Namespace: nexus-iq
    ├── Deployment: nexus-iq-server-ha
    │   ├── Replicas: 2-10 (HPA managed)
    │   ├── Strategy: RollingUpdate
    │   └── Pod Anti-Affinity: Ensure distribution across zones
    ├── Service: nexus-iq-server-ha (NodePort - GCE Ingress requirement)
    ├── Ingress: nexus-iq-server-ha (GCE integration with BackendConfig)
    ├── BackendConfig: Health check configuration (/ping endpoint)
    ├── HPA: Horizontal Pod Autoscaler (CPU/Memory targets)
    └── Secrets: Database credentials, license
    ↓
Pod Specifications:
    ├── Container: sonatype/nexus-iq-server:latest
    ├── Resources: CPU 2, Memory 4Gi
    ├── Ports: 8070 (application), 8071 (admin)
    ├── Health Checks: readiness/liveness probes
    └── Volume Mounts:
        ├── /sonatype-work ← Filestore PV (shared NFS)
        └── Fluentd sidecar ← Log forwarding

┌─────────────────────────────────────────────────────────────────────────────┐
│                            DATA PERSISTENCE                                 │
└─────────────────────────────────────────────────────────────────────────────┘

Database Layer:
┌─────────────────────────────────────────────────────────────────────────────┐
│ Cloud SQL PostgreSQL Regional (nexus-iq-ha-db-*)                            │
│  ├── Instance Tier: db-custom-8-30720 (8 vCPU, 30GB RAM)                   │
│  ├── Version: PostgreSQL 15                                                 │
│  ├── Availability: REGIONAL (Multi-Zone with automatic failover)            │
│  ├── Read Replica: Optional for read scaling                                │
│  ├── Storage: Auto-scaling SSD                                              │
│  ├── Encryption: At rest + in transit                                       │
│  └── Backup: Automated, 7-day retention                                     │
└─────────────────────────────────────────────────────────────────────────────┘

Storage Layer:
┌─────────────────────────────────────────────────────────────────────────────┐
│ Filestore (nexus-iq-ha-filestore-*)                                         │
│  ├── Tier: BASIC_SSD                                                        │
│  ├── Capacity: 2.5TB (2560GB minimum)                                       │
│  ├── Protocol: NFS v3                                                       │
│  ├── Share Name: /nexus_iq_ha_data                                          │
│  ├── PV: nexus-iq-filestore-pv                                              │
│  ├── PVC: nexus-iq-pvc (shared across pods)                                 │
│  └── Encryption: Transit + At Rest                                          │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 4. Operational Excellence

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              MONITORING                                     │
└─────────────────────────────────────────────────────────────────────────────┘

Kubernetes Monitoring:
├── Cloud Monitoring: Enabled on GKE cluster
├── Pod Metrics: CPU, memory, network, storage
├── Application Logs: Cloud Logging with Fluentd aggregator
└── Cluster Metrics: Node utilization, pod scheduling

Cloud Logging Architecture:
├── Fluentd Sidecars: Log forwarders in each IQ Server pod
├── Fluentd Aggregator: Central StatefulSet for log collection
├── Workload Identity: Secure authentication to Cloud Logging
├── Log Filters: resource.type="k8s_container", namespace="nexus-iq"
└── Retention: Configurable with log bucket policies

Auto-Scaling:
├── Horizontal Pod Autoscaler: 2-10 pods based on CPU/memory
├── Cluster Autoscaler: Node pools scale based on pod demands
└── Metrics: Cloud Monitoring metrics integration

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
```

## 5. Resource Naming Convention

All resources use consistent naming patterns for easy identification:

| Component | Resource Name | Purpose |
|-----------|---------------|---------|
| **Infrastructure** |
| GKE Cluster | `{cluster-name}` | Managed Kubernetes cluster |
| VPC | `{cluster-name}-vpc` | Isolated network environment |
| Subnets | `{cluster-name}-*-subnet-*` | Network segmentation |
| Firewall Rules | `{cluster-name}-*` | Network access control |
| **Kubernetes** |
| Namespace | `nexus-iq` | Application isolation |
| Deployment | `nexus-iq-server-ha` | Pod management |
| Service | `nexus-iq-server-ha` | Internal networking |
| Ingress | `nexus-iq-server-ha` | External access |
| BackendConfig | `nexus-iq-backendconfig` | Health check config |
| PV | `nexus-iq-filestore-pv` | Persistent volume |
| PVC | `nexus-iq-pvc` | Persistent storage claim |
| **Storage** |
| Cloud SQL | `{cluster-name}-db-*` | Regional database |
| Filestore | `{cluster-name}-filestore-*` | Shared NFS storage |
| **Security** |
| Secrets | `nexus-iq-*` | Credential storage |
| Service Accounts | `{cluster-name}-*-sa` | Workload Identity |

## 6. GCP vs AWS Implementation Differences

### Key Architectural Differences

| Aspect | AWS (EKS) | GCP (GKE) | Reason for Difference |
|--------|-----------|-----------|----------------------|
| **Ingress Controller** | AWS Load Balancer Controller (ALB) | GCE Ingress Controller (built-in) | GCP provides native L7 load balancing |
| **Service Type** | ClusterIP (ALB handles routing) | NodePort (required by GCE Ingress) | GCE Ingress requires NodePort services |
| **Health Check Config** | ALB Ingress annotations | BackendConfig CRD | GCP uses BackendConfig for fine-grained control |
| **Shared Storage** | EFS (NFS) with CSI driver | Filestore (NFS v3) native | Both use NFS, GCP Filestore is managed service |
| **Storage Provisioning** | EFS StorageClass + CSI | Direct PV/PVC with NFS server | GCP doesn't require CSI for basic NFS |
| **Database** | Aurora PostgreSQL (Multi-AZ) | Cloud SQL Regional (Multi-Zone) | Terminology: AZ vs Zone, similar failover |
| **IAM Integration** | IRSA (IAM Roles for Service Accounts) | Workload Identity | GCP's equivalent to IRSA |
| **Logging** | CloudWatch Logs | Cloud Logging | Platform-specific logging services |
| **Node Instance Type** | m5.2xlarge (8 vCPU, 32GB) | n2-standard-8 (8 vCPU, 32GB) | Equivalent compute, different naming |
| **Database Instance** | db.r6g.4xlarge (16 vCPU, 128GB) | db-custom-8-30720 (8 vCPU, 30GB) | GCP allows custom configurations |
| **Cluster Privacy** | Private subnets with NAT Gateway | Private cluster with Cloud NAT | Both provide private node networking |
| **DDoS Protection** | AWS Shield + WAF | Cloud Armor | Platform-specific security services |

### Why NodePort Instead of ClusterIP?

**AWS EKS with ALB Controller:**
- Uses ClusterIP services
- ALB Controller creates ALB that routes directly to pod IPs
- More efficient, bypasses NodePort overhead

**GCP GKE with GCE Ingress:**
- Requires NodePort services (GCP limitation)
- GCE Ingress creates Cloud Load Balancer that routes to NodePorts
- NodePort acts as stable entry point for load balancer

### Why BackendConfig?

**AWS:**
- Health check configuration via Ingress annotations
- Simple annotation-based approach

**GCP:**
- BackendConfig CRD provides fine-grained control
- Separates health check config from ingress definition
- Allows more detailed configuration (intervals, timeouts, paths)
- Standard GCP/GKE pattern for production deployments

### Storage Architecture Differences

**AWS EFS:**
- Requires EFS CSI Driver installation
- Uses StorageClass for dynamic provisioning
- Access Points for POSIX permissions

**GCP Filestore:**
- Native NFS v3 service
- Direct PV/PVC without CSI driver for basic use
- Manual PV creation with NFS server reference
- Simpler setup, managed by GCP

### Database Sizing Philosophy

**AWS Aurora:**
- Larger instances (db.r6g.4xlarge: 16 vCPU, 128GB RAM)
- Designed for higher scale, more aggressive sizing

**GCP Cloud SQL:**
- Custom-sized instance (db-custom-8-30720: 8 vCPU, 30GB RAM)
- Right-sized for workload, cost-optimized
- GCP allows flexible custom configurations
- Can scale up as needed

Both approaches are valid; GCP example shows more conservative starting point that can scale.
