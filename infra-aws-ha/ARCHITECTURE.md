# Nexus IQ Server AWS Reference Architecture (High Availability)

## Deployment Profile

**Recommended for:**
- **Production environments** requiring high availability and fault tolerance
- **Enterprise organizations** with 100+ onboarded applications
- **High scan frequency** (5+ evaluations per minute)
- **Business-critical deployments** requiring minimal downtime
- **Organizations with strict SLA requirements** (99.9%+ uptime)

**System Specifications:**
- 2-6 ECS Fargate tasks (2 vCPU / 4GB RAM each)
- Aurora PostgreSQL cluster (Multi-AZ with automatic failover)
- EFS shared storage with clustering support
- Multi-AZ deployment across 2-3 availability zones
- Application Auto Scaling based on CPU/memory utilization

## Overview
This reference architecture deploys Nexus IQ Server in a High Availability configuration on AWS using cloud-native services (ECS Fargate, Aurora, EFS) for enterprise-grade resilience and scalability. This HA deployment provides automatic failover, multi-instance clustering, and horizontal scaling to meet demanding production workloads.

The architecture resolves critical IQ Server clustering challenges including work directory locking conflicts, database sharing requirements, and file upload compatibility through custom configuration management and infrastructure design.

## Scaling Path

- **Previous**: [Single Instance](../infra-aws/ARCHITECTURE.md) (up to 100 applications)
- **Current**: High Availability (100-1000+ applications, auto-scaling 2-6 tasks)
- **Enterprise**: Multi-region with cross-region replication and disaster recovery

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
│   │   │                    Session Stickiness: Disabled                              │ │   │
│   │   │                     Auto Scaling: 2-6 Targets                                │ │   │
│   │   └───────────────────────────────────┬──────────────────────────────────────────┘ │   │
│   └───────────────────────────────────────┼────────────────────────────────────────────┘   │
│                                           │
│   ┌───────────────────────────────────────▼────────────────────────────────────────────┐   │
│   │                        PRIVATE SUBNETS (Multi-AZ)                                  │   │
│   │   ┌─────────────────────────────────────────────────────────────────────────────┐  │   │
│   │   │                        ECS FARGATE CLUSTER                                  │  │   │
│   │   │   ┌──────────────────┐              ┌──────────────────┐                    │  │   │
│   │   │   │ IQ Server Task 1 │              │ IQ Server Task 2 │                    │  │   │
│   │   │   │ Port 8070: App   │◄────────────►│ Port 8070: App   │                    │  │   │
│   │   │   │ Port 8071: Admin │              │ Port 8071: Admin │                    │  │   │
│   │   │   │ CPU: 2048        │              │ CPU: 2048        │                    │  │   │
│   │   │   │ Memory: 4096     │              │ Memory: 4096     │                    │  │   │
│   │   │   │ AZ-1a            │              │ AZ-1b            │                    │  │   │
│   │   │   └──────────────────┘              └──────────────────┘                    │  │   │
│   │   │   │                                                                         │  │   │
│   │   │   │ Service Discovery: nexus-iq.ref-arch-iq-ha-cluster.local                │  │   │
│   │   │   │ Auto Scaling: CPU/Memory Target Tracking (2-6 tasks)                    │  │   │
│   │   │   └─────────────────────────────────┬───────────────────────────────────────┘  │   │
│   │   └─────────────────────────────────────┼──────────────────────────────────────────┘   │
│   └─────────────────────────────────────────┼──────────────────────────────────────────────┘
│                                             │                                              │
│                                             │                                              │
│                           ┌─────────────────┴─────────────────┐                            │
│                           │                                   │                            │
│   ┌───────────────────────▼─────────────────────────┐   ┌─────▼────────────────────────┐   │
│   │                STORAGE LAYER                    │   │      DATABASE SUBNETS        │   │
│   │   ┌─────────────────────────────────────────┐   │   │   ┌───────────────────────┐  │   │
│   │   │           EFS FILE SYSTEM               │   │   │   │  AURORA POSTGRESQL    │  │   │
│   │   │                                         │   │   │   │       CLUSTER         │  │   │
│   │   │  /sonatype-work/                        │   │   │   │                       │  │   │
│   │   │  ├── clm-server-${HOSTNAME}/            │   │   │   │  Writer (AZ-1a)       │  │   │
│   │   │  │   ├── data/ ← Unique per task        │   │   │   │  Reader (AZ-1b)       │  │   │
│   │   │  │   └── lock ← Work dir isolation      │   │   │   │  Version: 15.4        │  │   │
│   │   │  └── clm-cluster/ ← Shared coordination │   │   │   │  Multi-AZ: Yes        │  │   │
│   │   │                                         │   │   │   │  Encrypted at rest    │  │   │
│   │   │  Performance: General Purpose           │   │   │   │  Automated backups    │  │   │
│   │   │  Throughput: Provisioned (100 MiB/s)    │   │   │   │  Secrets Manager      │  │   │
│   │   │  Encryption: Transit + At Rest          │   │   │   │  Auto failover: ~30s  │  │   │
│   │   │  Access Point: UID/GID 997              │   │   │   └───────────────────────┘  │   │
│   │   │  AWS Backup: Daily/Weekly policies      │   │   └──────────────────────────────┘   │
│   │   └─────────────────────────────────────────┘   │                                      │
│   └─────────────────────────────────────────────────┘                                      │
└────────────────────────────────────────────────────────────────────────────────────────────┘


              ┌─────────────────────────────────────────────┐
              │             SUPPORTING SERVICES             │
              │                                             │
              │  • CloudWatch Logs (Container Monitoring)   │
              │  • Application Auto Scaling (2-6 Tasks)     │
              │  • Service Discovery (Internal DNS)         │
              │  • Secrets Manager (Database Credentials)   │
              │  • AWS Backup (EFS Daily/Weekly)            │
              │  • S3 Bucket (ALB Access Logs)              │
              │  • IAM Roles (ECS Task & Execution)         │
              └─────────────────────────────────────────────┘
```

## 2. Network Flow & Security

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           TRAFFIC FLOW                                      │
└─────────────────────────────────────────────────────────────────────────────┘

Internet → ALB (Port 80/443)
    ↓
ALB Security Group (HTTP: 80, HTTPS: 443)
    ↓
Target Group Health Checks:
    • Port 8070: /         (accepts 200,302,303,404)
    • Port 8071: /healthcheck (accepts 200,404) - Internal Only
    ↓
ECS Security Group (Port 8070 from ALB only)
    ↓
Multiple Nexus IQ Containers (Private Subnets, Multi-AZ)
    ↓
    ├── Aurora Security Group (Port 5432 from ECS only)
    │   ↓
    │   Aurora PostgreSQL Cluster (DB Subnets, Multi-AZ)
    │
    └── EFS Security Group (Port 2049 from ECS only)
        ↓
        EFS File System (Multi-AZ with unique work directories)

┌─────────────────────────────────────────────────────────────────────────────┐
│                          SECURITY BOUNDARIES                                │
└─────────────────────────────────────────────────────────────────────────────┘

Public Zone:     │ Internet Gateway ← → ALB only
Private Zone:    │ NAT Gateways → ECS Tasks (no inbound from internet)
Database Zone:   │ ECS Tasks → Aurora only (completely isolated)
Storage Zone:    │ ECS Tasks → EFS only (encrypted in transit)

Security Groups (Least Privilege):
┌─────────────────┬──────────────────┬─────────────────┬──────────────────┐
│   Component     │    Inbound       │    Outbound     │    Protocol      │
├─────────────────┼──────────────────┼─────────────────┼──────────────────┤
│ ALB             │ Internet:80,443  │ ECS:8070        │ HTTP/HTTPS       │
│ ECS Tasks       │ ALB:8070         │ Aurora:5432     │ TCP              │
│                 │ ALB:8071 (health)│ EFS:2049        │ TCP/NFS          │
│                 │                  │ Internet:443    │ HTTPS (outbound) │
│ Aurora          │ ECS:5432         │ None            │ PostgreSQL       │
│ EFS             │ ECS:2049         │ None            │ NFS              │
└─────────────────┴──────────────────┴─────────────────┴──────────────────┘
```

## 3. Component Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           ECS FARGATE DEPLOYMENT                            │
└─────────────────────────────────────────────────────────────────────────────┘

ECS Cluster: ref-arch-iq-ha-cluster
    ↓
ECS Service: ref-arch-iq-ha-cluster-nexus-iq-service
    ├── Desired Count: 2-6 (Auto Scaling)
    ├── Launch Type: FARGATE
    ├── Platform Version: LATEST
    ├── Deployment: Rolling (200% max, 50% min healthy)
    ├── Service Discovery: nexus-iq.ref-arch-iq-ha-cluster.local
    └── Load Balancer Integration:
        └── Target Group: ref-arch-iq-ha-cluster-iq-tg (Port 8070)
    ↓
Task Definition: ref-arch-iq-ha-cluster-nexus-iq-server
    ├── CPU: 2048 (2 vCPU)
    ├── Memory: 4096 MB (4 GB)
    ├── Network Mode: awsvpc
    ├── Container: nexus-iq-server
    │   ├── Image: sonatypecommunity/nexus-iq-server:latest
    │   ├── Custom Startup Script:
    │   │   ├── Create unique work directory: /sonatype-work/clm-server-${HOSTNAME}
    │   │   ├── Create shared cluster directory: /sonatype-work/clm-cluster
    │   │   └── Generate custom config.yml with database configuration
    │   ├── Environment Variables:
    │   │   ├── DB_TYPE: postgresql
    │   │   ├── DB_HOST: <AURORA_ENDPOINT>
    │   │   ├── DB_PORT: 5432
    │   │   ├── DB_NAME: nexusiq
    │   │   └── CLUSTER_DIRECTORY: /sonatype-work/clm-cluster
    │   ├── Secrets (from Secrets Manager):
    │   │   ├── DB_USER
    │   │   └── DB_PASSWORD
    │   ├── Health Check: curl -f http://localhost:8070/
    │   └── Volume Mounts:
    │       └── /sonatype-work ← EFS (Shared Persistent Data)
    └── CloudWatch Logs: /ecs/ref-arch-iq-ha-cluster/nexus-iq-server

Auto Scaling Configuration:
    ├── Min Capacity: 2 tasks
    ├── Max Capacity: 6 tasks
    ├── CPU Target: 70%
    ├── Memory Target: 80%
    └── Scale Out/In Cooldown: 60s/300s

┌─────────────────────────────────────────────────────────────────────────────┐
│                            DATA PERSISTENCE                                 │
└─────────────────────────────────────────────────────────────────────────────┘

Database Layer:
┌─────────────────────────────────────────────────────────────────────────────┐
│ Aurora PostgreSQL Cluster (ref-arch-iq-ha-cluster-aurora-cluster)           │
│  ├── Writer Instance: db.r6g.large (AZ-1a)                                  │
│  ├── Reader Instance: db.r6g.large (AZ-1b)                                  │
│  ├── Version: PostgreSQL 15.4                                               │
│  ├── Multi-AZ: Yes (Cross-AZ replication)                                   │
│  ├── Storage: Encrypted, Auto-scaling enabled                               │
│  ├── Backup: Continuous, 7-day retention                                    │
│  ├── Failover: Automatic (~30 seconds)                                      │
│  └── Credentials: Stored in AWS Secrets Manager                             │
└─────────────────────────────────────────────────────────────────────────────┘

File Storage:
┌─────────────────────────────────────────────────────────────────────────────┐
│ EFS File System (ref-arch-iq-ha-cluster-efs)                                │
│  ├── Performance Mode: General Purpose                                      │
│  ├── Throughput: Provisioned (100 MiB/s)                                    │
│  ├── Encryption: Transit + At Rest                                          │
│  ├── Access Point: /sonatype-work (UID/GID: 997)                            │
│  ├── Mount Targets: Private subnets in all AZs                              │
│  ├── Directory Structure:                                                   │
│  │   ├── /sonatype-work/clm-server-${HOSTNAME}/ ← Unique per task           │
│  │   └── /sonatype-work/clm-cluster/ ← Shared cluster coordination          │
│  └── Backup: AWS Backup vault with daily/weekly policies                    │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 4. Operational Excellence

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              MONITORING                                     │
└─────────────────────────────────────────────────────────────────────────────┘

CloudWatch Integration:
├── Container Insights: Enabled on ECS Cluster
├── Application Logs: /ecs/ref-arch-iq-ha-cluster/nexus-iq-server
├── Log Retention: 30 days
├── Service Discovery: Health check monitoring
├── Auto Scaling Metrics:
│   ├── ECSServiceAverageCPUUtilization
│   ├── ECSServiceAverageMemoryUtilization
│   └── TargetGroupRequestCount
├── Target Group Metrics:
│   ├── HealthyHostCount (2-6 targets)
│   ├── UnHealthyHostCount
│   └── RequestCount
├── Aurora Monitoring:
│   ├── Performance Insights: Enabled
│   ├── Enhanced Monitoring: Enabled
│   └── CloudWatch Logs: /aws/rds/cluster/ref-arch-iq-ha-cluster-aurora-cluster/postgresql
└── ALB Access Logs: S3 bucket (90-day lifecycle)

┌─────────────────────────────────────────────────────────────────────────────┐
│                              AUTOMATION                                     │
└─────────────────────────────────────────────────────────────────────────────┘

Deployment Scripts:
├── tf-plan.sh   : Plan with MFA authentication
├── tf-apply.sh  : Deploy with MFA authentication
└── tf-destroy.sh: Enhanced cleanup with recovery point removal

IAM Roles:
├── ECS Execution Role: Pull images, write logs, access secrets
├── ECS Task Role: Application-specific permissions, EFS access
├── Auto Scaling Role: Manage service desired count
└── Service-Linked Role: ECS service management

Application Auto Scaling:
├── Target Tracking Policies: CPU and Memory based
├── Scale-Out Policy: Add tasks when thresholds exceeded
├── Scale-In Policy: Remove tasks when load decreases
└── Service Discovery: Automatic registration/deregistration

┌─────────────────────────────────────────────────────────────────────────────┐
│                         DISASTER RECOVERY                                   │
└─────────────────────────────────────────────────────────────────────────────┘

Backup Strategy:
├── Aurora: Continuous backups with point-in-time recovery (7-day retention)
├── EFS: AWS Backup vault with daily and weekly backup policies
├── Application State: Persisted in Aurora + EFS with clustering coordination
├── Infrastructure: Terraform state for rapid rebuild
└── Multi-AZ Deployment: Automatic failover for AZ outages

Recovery Objectives:
├── RTO (Recovery Time Objective): < 5 minutes for AZ failure
├── RPO (Recovery Point Objective): < 1 minute for data loss
├── Aurora Failover: ~30 seconds automatic promotion
└── ECS Task Recovery: Automatic replacement by service scheduler

Recovery Process:
1. AZ Failure: ECS automatically reschedules tasks to healthy AZs
2. Aurora Writer Failure: Automatic reader promotion (~30 seconds)
3. Complete Disaster: Restore Aurora from backup, deploy infrastructure
4. EFS data automatically available across all mount targets
5. Application starts with existing data and cluster coordination
```

## 5. Resource Naming Convention

All resources use the prefix `ref-arch-iq-ha-` for easy identification and distinction from single instance deployment:

| Component | Resource Name | Purpose |
|-----------|---------------|---------|
| **Networking** |
| VPC | `ref-arch-iq-ha-vpc` | Isolated network environment |
| Public Subnets | `ref-arch-iq-ha-public-subnet-*` | ALB placement |
| Private Subnets | `ref-arch-iq-ha-private-subnet-*` | ECS tasks |
| Database Subnets | `ref-arch-iq-ha-db-subnet-*` | Aurora isolation |
| **Compute** |
| ECS Cluster | `ref-arch-iq-ha-cluster` | Container orchestration |
| ECS Service | `ref-arch-iq-ha-cluster-nexus-iq-service` | Service management |
| Task Definition | `ref-arch-iq-ha-cluster-nexus-iq-server` | Container specification |
| **Load Balancing** |
| ALB | `ref-arch-iq-ha-cluster-alb` | Public-facing load balancer |
| Target Group | `ref-arch-iq-ha-cluster-iq-tg` | Application routing |
| **Storage** |
| Aurora Cluster | `ref-arch-iq-ha-cluster-aurora-cluster` | PostgreSQL cluster |
| Aurora Writer | `ref-arch-iq-ha-cluster-aurora-instance-1` | Primary database instance |
| Aurora Reader | `ref-arch-iq-ha-cluster-aurora-instance-2` | Read replica instance |
| EFS File System | `ref-arch-iq-ha-cluster-efs` | Persistent shared storage |
| **Security** |
| DB Secret | `ref-arch-iq-ha-cluster-db-credentials` | Database authentication |
| Security Groups | `ref-arch-iq-ha-cluster-*-sg` | Network access control |
| **Monitoring** |
| Log Group | `/ecs/ref-arch-iq-ha-cluster/nexus-iq-server` | Application logs |
| Service Discovery | `ref-arch-iq-ha-cluster.local` | Internal DNS namespace |
| **Auto Scaling** |
| Scaling Target | `ref-arch-iq-ha-cluster-autoscaling-target` | Auto scaling configuration |
| CPU Policy | `ref-arch-iq-ha-cluster-cpu-autoscaling` | CPU-based scaling |
| Memory Policy | `ref-arch-iq-ha-cluster-memory-autoscaling` | Memory-based scaling |
| **Backup** |
| Backup Vault | `ref-arch-iq-ha-cluster-efs-backup-vault` | EFS backup storage |
| Backup Plan | `ref-arch-iq-ha-cluster-backup-plan` | Backup scheduling |

