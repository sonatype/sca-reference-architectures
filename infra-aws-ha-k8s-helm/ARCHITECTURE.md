# Nexus IQ Server AWS EKS Reference Architecture (High Availability)

## Deployment Profile

**Recommended for:**
- **Production environments** requiring high availability
- **Enterprise organizations** with 100+ applications
- **High scan frequency** (10+ evaluations per minute)
- **Mission-critical deployments** with zero-downtime requirements

**System Specifications:**
- 2+ replicas with 4GB RAM each (Kubernetes HA optimized)
- Aurora PostgreSQL cluster (Multi-AZ)
- EFS shared persistent storage
- Multi-AZ deployment across availability zones

## Overview
This reference architecture deploys Nexus IQ Server on AWS EKS using Kubernetes-native services for high availability, auto-scaling, and operational excellence. The HA deployment provides enterprise-grade reliability and performance.

**⚠️ Important**: This HA deployment requires a clustering-capable Nexus IQ license and uses shared EFS storage for cluster coordination between pods.

## Scaling Options
- **Current Deployment**: High Availability (2+ replicas, unlimited applications)
- **Horizontal Scaling**: Auto-scaling 2-10 pods based on CPU/memory utilization
- **Vertical Scaling**: Increase pod CPU/memory resources as needed
- **Database Scaling**: Aurora read replicas for enhanced database performance

## 1. High-Level Architecture

```
┌────────────────────────────────────────────────────────────────────────────────────────────┐
│                                       INTERNET                                             │
└───────────────────────────────────────────┬────────────────────────────────────────────────┘
                                            │
                                            │ HTTP/HTTPS Traffic
                                            │
┌───────────────────────────────────────────▼────────────────────────────────────────────────┐
│                                        AWS VPC                                             │
│   ┌────────────────────────────────────────────────────────────────────────────────────┐   │
│   │                         PUBLIC SUBNETS (Multi-AZ)                                  │   │
│   │   ┌──────────────────────────────────────────────────────────────────────────────┐ │   │
│   │   │                      Application Load Balancer                               │ │   │
│   │   │                        Port 80 → Ingress Controller                          │ │   │
│   │   │                     Health Checks: /healthcheck                              │ │   │
│   │   └───────────────────────────────────┬──────────────────────────────────────────┘ │   │
│   └───────────────────────────────────────┼────────────────────────────────────────────┘   │
│                                           │
│   ┌───────────────────────────────────────▼────────────────────────────────────────────┐   │
│   │                        PRIVATE SUBNETS (Multi-AZ)                                  │   │
│   │   ┌─────────────────────────────────────────────────────────────────────────────┐  │   │
│   │   │                           EKS CLUSTER                                       │  │   │
│   │   │   ┌──────────────────────────────────────────────────────────────────────┐  │  │   │
│   │   │   │              Nexus IQ Server HA Pods (2+ replicas)                   │  │  │   │
│   │   │   │                   Port 8070: Application                             │  │  │   │
│   │   │   │                   CPU: 2, Memory: 4Gi each                           │  │  │   │
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
│   │   │         EFS FILE SYSTEM             │   │   │   │ AURORA POSTGRESQL │  │           │
│   │   │     /sonatype-work shared           │   │   │   │   Cluster         │  │           │
│   │   │     Encrypted at rest/transit       │   │   │   │   Multi-AZ        │  │           │
│   │   │     CSI Driver integration          │   │   │   │   Writer + Reader │  │           │
│   │   └─────────────────────────────────────┘   │   │   │   Encrypted       │  │           │
│   └─────────────────────────────────────────────┘   │   │   Automated       │  │           │
│                                                     │   │   Backups         │  │           │
│                                                     │   └───────────────────┘  │           │
│                                                     └──────────────────────────┘           │
└────────────────────────────────────────────────────────────────────────────────────────────┘

              ┌─────────────────────────────────────────────┐
              │             SUPPORTING SERVICES             │
              │                                             │
              │  • AWS Load Balancer Controller             │
              │  • Horizontal Pod Autoscaler                │
              │  • EFS CSI Driver                           │
              │  • CloudWatch Container Insights            │
              │  • Kubernetes Secrets                       │
              └─────────────────────────────────────────────┘
```

## 2. Network Flow & Security

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           TRAFFIC FLOW                                      │
└─────────────────────────────────────────────────────────────────────────────┘

Internet → ALB (Port 80)
    ↓
AWS Load Balancer Controller (Ingress)
    ↓
Kubernetes Service (ClusterIP)
    ↓
Nexus IQ HA Pods (Port 8070, Multiple replicas)
    ↓
    ├── Aurora Cluster (Port 5432, Writer/Reader endpoints)
    │
    └── EFS Shared Storage (Port 2049, NFS)

Security Groups & Network Policies:
┌─────────────────┬──────────────────┬─────────────────┬──────────────────┐
│   Component     │    Inbound       │    Outbound     │    Protocol      │
├─────────────────┼──────────────────┼─────────────────┼──────────────────┤
│ ALB             │ Internet:80,443  │ EKS:NodePort    │ HTTP/HTTPS       │
│ EKS Pods        │ ALB via Service  │ Aurora:5432     │ TCP              │
│                 │                  │ EFS:2049        │ NFS              │
│ Aurora          │ EKS Pods:5432    │ None            │ PostgreSQL       │
│ EFS             │ EKS Pods:2049    │ None            │ NFS              │
└─────────────────┴──────────────────┴─────────────────┴──────────────────┘
```

## 3. Component Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           EKS KUBERNETES DEPLOYMENT                         │
└─────────────────────────────────────────────────────────────────────────────┘

EKS Cluster: nexus-iq-ha
    ├── Kubernetes Version: 1.27+
    ├── Control Plane: AWS Managed
    ├── Node Groups: Auto-scaling (2-6 nodes)
    └── Availability Zones: Multi-AZ distribution
    ↓
Namespace: nexus-iq
    ├── Deployment: nexus-iq-server-ha
    │   ├── Replicas: 2-10 (HPA managed)
    │   ├── Strategy: RollingUpdate
    │   └── Pod Anti-Affinity: Ensure distribution across nodes
    ├── Service: nexus-iq-server-ha (ClusterIP)
    ├── Ingress: nexus-iq-server-ha (ALB integration)
    ├── HPA: Horizontal Pod Autoscaler (CPU/Memory targets)
    └── Secrets: Database credentials, license
    ↓
Pod Specifications:
    ├── Container: sonatype/nexus-iq-server:latest
    ├── Resources: CPU 2, Memory 4Gi
    ├── Ports: 8070 (application)
    ├── Health Checks: readiness/liveness probes
    └── Volume Mounts:
        ├── /sonatype-work ← EFS PVC (shared)
        └── /var/log/nexus-iq-server ← EFS (logs)

┌─────────────────────────────────────────────────────────────────────────────┐
│                            DATA PERSISTENCE                                 │
└─────────────────────────────────────────────────────────────────────────────┘

Database Layer:
┌─────────────────────────────────────────────────────────────────────────────┐
│ Aurora PostgreSQL Cluster (nexus-iq-ha-aurora-cluster)                      │
│  ├── Writer Instance: db.r6g.large                                          │
│  ├── Reader Instance: db.r6g.large (optional)                               │
│  ├── Version: PostgreSQL 15.4                                               │
│  ├── Multi-AZ: Yes                                                          │
│  ├── Storage: Auto-scaling                                                  │
│  ├── Encryption: At rest + in transit                                       │
│  └── Backup: Automated, 7-day retention                                     │
└─────────────────────────────────────────────────────────────────────────────┘

Storage Layer:
┌─────────────────────────────────────────────────────────────────────────────┐
│ EFS File System (nexus-iq-ha-efs)                                           │
│  ├── Performance Mode: General Purpose                                      │
│  ├── CSI Driver: AWS EFS CSI Driver                                         │
│  ├── StorageClass: efs-storageclass                                         │
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
├── Container Insights: Enabled on EKS cluster
├── Pod Metrics: CPU, memory, network, storage
├── Application Logs: kubectl logs, CloudWatch integration
└── Cluster Metrics: Node utilization, pod scheduling

Auto-Scaling:
├── Horizontal Pod Autoscaler: 2-10 pods based on CPU/memory
├── Cluster Autoscaler: Node groups scale based on pod demands
└── Metrics: CloudWatch metrics integration

┌─────────────────────────────────────────────────────────────────────────────┐
│                              AUTOMATION                                     │
└─────────────────────────────────────────────────────────────────────────────┘

Deployment Automation:
├── Terraform: Infrastructure as Code
├── Helm: Kubernetes application deployment
├── Scripts: tf-*.sh and helm-*.sh for automated operations
└── GitOps Ready: Declarative configuration management

High Availability:
├── Pod Anti-Affinity: Pods distributed across nodes/AZs
├── Rolling Updates: Zero-downtime deployments
├── Pod Disruption Budgets: Maintain minimum replicas during updates
└── Health Checks: Automatic pod restart on failure
```

## 5. Resource Naming Convention

All resources use consistent naming patterns for easy identification:

| Component | Resource Name | Purpose |
|-----------|---------------|---------|
| **Infrastructure** |
| EKS Cluster | `{cluster-name}` | Managed Kubernetes cluster |
| VPC | `{cluster-name}-vpc` | Isolated network environment |
| Subnets | `{cluster-name}-*-subnet-*` | Network segmentation |
| Security Groups | `{cluster-name}-*-sg` | Network access control |
| **Kubernetes** |
| Namespace | `nexus-iq` | Application isolation |
| Deployment | `nexus-iq-server-ha` | Pod management |
| Service | `nexus-iq-server-ha` | Internal networking |
| Ingress | `nexus-iq-server-ha` | External access |
| PVC | `nexus-iq-pvc` | Persistent storage claim |
| **Storage** |
| Aurora Cluster | `{cluster-name}-aurora-cluster` | HA database cluster |
| EFS File System | `{cluster-name}-efs` | Shared persistent storage |
| **Security** |
| Secrets | `nexus-iq-*` | Credential storage |
| IAM Roles | `{cluster-name}-*-role` | Service permissions |
