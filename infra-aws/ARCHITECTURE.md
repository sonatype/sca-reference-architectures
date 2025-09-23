# Nexus IQ Server AWS Reference Architecture (Single Instance)

## Deployment Profile

**Recommended for:**
- **Development and testing environments**
- **Proof of concept deployments**
- **Small to medium organizations** with up to 100 onboarded applications
- **Low to moderate scan frequency** (up to 2-3 evaluations per minute)

**System Specifications:**
- 2 vCPU / 4GB RAM (Cloud-native optimized)
- PostgreSQL external database
- EFS persistent storage
- Single availability zone primary deployment with multi-AZ database

## Overview
This reference architecture deploys Nexus IQ Server on AWS using cloud-native services (ECS Fargate, RDS, EFS) for operational excellence and security. This single-instance deployment provides a solid foundation for development, testing, and small to medium production workloads.

## Scaling Options
- **Current Deployment**: Single Instance (up to 100 applications)
- **Vertical Scaling**: Increase CPU/memory resources as needed
- **Database Scaling**: Enable Multi-AZ RDS deployment for enhanced availability

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
│   │   │                        Port 80 → Target Groups                               │ │   │
│   │   │                     Health Checks: 8070, 8071                                │ │   │
│   │   └───────────────────────────────────┬──────────────────────────────────────────┘ │   │
│   └───────────────────────────────────────┼────────────────────────────────────────────┘   │
│                                           │
│   ┌───────────────────────────────────────▼────────────────────────────────────────────┐   │
│   │                        PRIVATE SUBNETS (Multi-AZ)                                  │   │
│   │   ┌─────────────────────────────────────────────────────────────────────────────┐  │   │
│   │   │                        ECS FARGATE CLUSTER                                  │  │   │
│   │   │   ┌──────────────────────────────────────────────────────────────────────┐  │  │   │
│   │   │   │                 Nexus IQ Server Container                            │  │  │   │
│   │   │   │                   Port 8070: Application                             │  │  │   │
│   │   │   │                   Port 8071: Admin (Health Check Only)               │  │  │   │
│   │   │   │                   CPU: 2048, Memory: 4096                            │  │  │   │
│   │   │   └───────────────────────────────┬──────────────────────────────────────┘  │  │   │
│   │   └───────────────────────────────────┼─────────────────────────────────────────┘  │   │
│   └───────────────────────────────────────┼────────────────────────────────────────────┘   │
│                                           │                                                │
│                                           │                                                │
│                         ┌─────────────────┴───────────────┐                                │
│                         │                                 │                                │
│   ┌─────────────────────▼───────────────────────┐   ┌─────▼────────────────────┐           │
│   │              STORAGE LAYER                  │   │     DATABASE SUBNETS     │           │
│   │   ┌─────────────────────────────────────┐   │   │   ┌───────────────────┐  │           │
│   │   │         EFS FILE SYSTEM             │   │   │   │   RDS POSTGRESQL  │  │           │
│   │   │     /sonatype-work storage          │   │   │   │   Multi-AZ        │  │           │
│   │   │     Encrypted at rest               │   │   │   │   Deployment      │  │           │
│   │   │     Access Point: 997:997           │   │   │   │   Encrypted       │  │           │
│   │   └─────────────────────────────────────┘   │   │   │   Automated       │  │           │
│   └─────────────────────────────────────────────┘   │   │   Backups         │  │           │
│                                                     │   │   Secrets Mgr     │  │           │
│                                                     │   │   Integration     │  │           │
│                                                     │   └───────────────────┘  │           │
│                                                     └──────────────────────────┘           │
└────────────────────────────────────────────────────────────────────────────────────────────┘

              ┌─────────────────────────────────────────────┐
              │             SUPPORTING SERVICES             │
              │                                             │
              │  • CloudWatch Logs (Container Monitoring)   │
              │  • Secrets Manager (Database Credentials)   │
              │  • S3 Bucket (ALB Access Logs)              │
              │  • IAM Roles (ECS Task & Execution)         │
              └─────────────────────────────────────────────┘
```

## 2. Network Flow & Security

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           TRAFFIC FLOW                                      │
└─────────────────────────────────────────────────────────────────────────────┘

Internet → ALB (Port 80)
    ↓
ALB Security Group (HTTP: 80, HTTPS: 443)
    ↓
Target Group Health Checks:
    • Port 8070: /         (accepts 200,302,303,404)
    • Port 8071: /healthcheck (accepts 200,404) - Internal Only
    ↓
ECS Security Group (Port 8070 from ALB only)
    ↓
Nexus IQ Container (Private Subnet)
    ↓
    ├── RDS Security Group (Port 5432 from ECS only)
    │   ↓
    │   PostgreSQL Database (DB Subnet)
    │
    └── EFS Security Group (Port 2049 from ECS only)
        ↓
        EFS File System (Multi-AZ)

┌─────────────────────────────────────────────────────────────────────────────┐
│                          SECURITY BOUNDARIES                                │
└─────────────────────────────────────────────────────────────────────────────┘

Public Zone:     │ Internet Gateway ← → ALB only
Private Zone:    │ NAT Gateway → ECS Tasks (no inbound from internet)
Database Zone:   │ ECS Tasks → RDS only (completely isolated)
Storage Zone:    │ ECS Tasks → EFS only (encrypted in transit)

Security Groups (Least Privilege):
┌─────────────────┬──────────────────┬─────────────────┬──────────────────┐
│   Component     │    Inbound       │    Outbound     │    Protocol      │
├─────────────────┼──────────────────┼─────────────────┼──────────────────┤
│ ALB             │ Internet:80,443  │ ECS:8070        │ HTTP             │
│ ECS Tasks       │ ALB:8070         │ RDS:5432        │ TCP              │
│                 │ ALB:8071 (health)│ EFS:2049        │ TCP/NFS          │
│ RDS             │ ECS:5432         │ None            │ PostgreSQL       │
│ EFS             │ ECS:2049         │ None            │ NFS              │
└─────────────────┴──────────────────┴─────────────────┴──────────────────┘
```

## 3. Component Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           ECS FARGATE DEPLOYMENT                            │
└─────────────────────────────────────────────────────────────────────────────┘

ECS Cluster: ref-arch-iq-cluster
    ↓
ECS Service: ref-arch-nexus-iq-service
    ├── Desired Count: 1 (Single Instance)
    ├── Launch Type: FARGATE
    ├── Platform Version: LATEST
    ├── Deployment: Rolling (100% max, 0% min healthy)
    └── Load Balancer Integration:
        ├── Target Group 1: ref-arch-iq-tg (Port 8070)
        └── Target Group 2: ref-arch-iq-admin-tg (Port 8071, Health Check Only)
    ↓
Task Definition: ref-arch-nexus-iq-server
    ├── CPU: 2048 (2 vCPU)
    ├── Memory: 4096 MB (4 GB)
    ├── Network Mode: awsvpc
    ├── Container: nexus-iq-server
    │   ├── Image: sonatypecommunity/nexus-iq-server:latest
    │   ├── Environment Variables:
    │   │   ├── DB_TYPE: postgresql
    │   │   ├── DB_HOST: <RDS_ENDPOINT>
    │   │   ├── DB_PORT: 5432
    │   │   └── DB_NAME: nexusiq
    │   ├── Secrets (from Secrets Manager):
    │   │   ├── DB_USER
    │   │   └── DB_PASSWORD
    │   ├── Health Check: curl -f http://localhost:8070/
    │   └── Volume Mounts:
    │       └── /sonatype-work ← EFS (Persistent Data)
    └── CloudWatch Logs: /ecs/ref-arch-nexus-iq-server

┌─────────────────────────────────────────────────────────────────────────────┐
│                            DATA PERSISTENCE                                 │
└─────────────────────────────────────────────────────────────────────────────┘

Database Layer:
┌─────────────────────────────────────────────────────────────────────────────┐
│ RDS PostgreSQL (ref-arch-iq-database)                                       │
│  ├── Instance: db.t3.medium                                                 │
│  ├── Version: PostgreSQL 15                                                 │
│  ├── Multi-AZ: No (Single Instance Reference)                               │
│  ├── Storage: GP2, Auto-scaling enabled                                     │
│  ├── Encryption: At rest enabled                                            │
│  ├── Backup: Automated, 7-day retention                                     │
│  └── Credentials: Stored in AWS Secrets Manager                             │
└─────────────────────────────────────────────────────────────────────────────┘

File Storage:
┌─────────────────────────────────────────────────────────────────────────────┐
│ EFS File System (ref-arch-iq-efs)                                           │
│  ├── Performance Mode: General Purpose                                      │
│  ├── Throughput: Provisioned (100 MiB/s)                                    │
│  ├── Encryption: Transit + At Rest                                          │
│  ├── Access Point: /nexus-iq-data (UID/GID: 997)                            │
│  └── Mount Targets: Private subnets in all AZs                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 4. Operational Excellence

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              MONITORING                                     │
└─────────────────────────────────────────────────────────────────────────────┘

CloudWatch Integration:
├── Container Insights: Enabled on ECS Cluster
├── Application Logs: /ecs/ref-arch-nexus-iq-server
├── Log Retention: 30 days
├── Target Group Metrics:
│   ├── HealthyHostCount
│   ├── UnHealthyHostCount
│   └── RequestCount
└── ALB Access Logs: S3 bucket (90-day lifecycle)

┌─────────────────────────────────────────────────────────────────────────────┐
│                              AUTOMATION                                     │
└─────────────────────────────────────────────────────────────────────────────┘

Deployment Scripts:
├── tf-plan.sh   : Plan with MFA authentication
├── tf-apply.sh  : Deploy with MFA authentication
└── tf-destroy.sh: Cleanup with automatic secret removal

IAM Roles:
├── ECS Execution Role: Pull images, write logs, access secrets
├── ECS Task Role: Application-specific permissions
└── Service-Linked Role: ECS service management

┌─────────────────────────────────────────────────────────────────────────────┐
│                         DISASTER RECOVERY                                   │
└─────────────────────────────────────────────────────────────────────────────┘

Backup Strategy:
├── RDS: Automated daily backups (7-day retention)
├── EFS: Cross-region replication (optional)
├── Application State: Persisted in RDS + EFS
└── Infrastructure: Terraform state for rapid rebuild

Recovery Process:
1. Restore RDS from backup
2. Deploy infrastructure with Terraform
3. EFS data automatically available
4. Application starts with existing data
```

## 5. Resource Naming Convention

All resources use the prefix `ref-arch-iq-` for easy identification:

| Component | Resource Name | Purpose |
|-----------|---------------|---------|
| **Networking** |
| VPC | `ref-arch-iq-vpc` | Isolated network environment |
| Public Subnets | `ref-arch-iq-public-subnet-*` | ALB placement |
| Private Subnets | `ref-arch-iq-private-subnet-*` | ECS tasks |
| Database Subnets | `ref-arch-iq-db-subnet-*` | RDS isolation |
| **Compute** |
| ECS Cluster | `ref-arch-iq-cluster` | Container orchestration |
| ECS Service | `ref-arch-nexus-iq-service` | Service management |
| Task Definition | `ref-arch-nexus-iq-server` | Container specification |
| **Load Balancing** |
| ALB | `ref-arch-iq-alb` | Public-facing load balancer |
| Target Group | `ref-arch-iq-tg` | Main application routing |
| Admin Target Group | `ref-arch-iq-admin-tg` | Health check only |
| **Storage** |
| RDS Instance | `ref-arch-iq-database` | PostgreSQL database |
| EFS File System | `ref-arch-iq-efs` | Persistent file storage |
| **Security** |
| Secret | `ref-arch-iq-db-credentials` | Database authentication |
| Security Groups | `ref-arch-iq-*-sg` | Network access control |
