# Nexus IQ Server GCP Reference Architecture

## Deployment Profile

**Recommended for:**
- **Development, testing, and production environments**
- **Small to large organizations** with scalable deployment modes
- **Cloud-native deployments** seeking serverless and managed services
- **Organizations requiring high availability** and disaster recovery capabilities

**System Specifications:**
- **Single Mode**: 2 vCPU / 4GB RAM, single Cloud Run instance
- **HA Mode**: 2-10 autoscaling Cloud Run instances, regional database
- **Storage**: Cloud SQL PostgreSQL + Cloud Filestore NFS
- **Network**: Global load balancer with multi-region capability

## Overview

This reference architecture deploys Nexus IQ Server on Google Cloud Platform using cloud-native services (Cloud Run, Cloud SQL, Cloud Filestore) for operational excellence, scalability, and cost optimization. The architecture supports both single-instance deployments for development/testing and high-availability configurations for production workloads.

## Scaling Path

- **Single Instance**: 1 Cloud Run instance (up to 100 applications, development/testing)
- **High Availability**: 2-10 autoscaling instances (100-1000+ applications, production)
- **Enterprise Scale**: Multi-region deployment with global load balancing

## 1. High-Level Architecture

```
┌────────────────────────────────────────────────────────────────────────────────────────────┐
│                                      INTERNET                                             │
└───────────────────────────────────────────┬────────────────────────────────────────────────┘
                                            │
                                            │ HTTPS/HTTP (443/80)
                                            │
┌───────────────────────────────────────────▼────────────────────────────────────────────────┐
│                                    GOOGLE CLOUD                                           │
│   ┌────────────────────────────────────────────────────────────────────────────────────┐   │
│   │                         GLOBAL LOAD BALANCER                                      │   │
│   │   ┌──────────────────────────────────────────────────────────────────────────────┐ │   │
│   │   │                    HTTP(S) Load Balancer                                     │ │   │
│   │   │          SSL Termination • Health Checks • Cloud Armor                      │ │   │
│   │   │                   Backend Service → NEG Groups                              │ │   │
│   │   └───────────────────────────────────┬──────────────────────────────────────────┘ │   │
│   └───────────────────────────────────────┼────────────────────────────────────────────┘   │
│                                           │                                                │
│   ┌───────────────────────────────────────▼────────────────────────────────────────────┐   │
│   │                           CUSTOM VPC NETWORK                                      │   │
│   │                                                                                    │   │
│   │   ┌─────────────────────────────────────────────────────────────────────────────┐  │   │
│   │   │                        CLOUD RUN SERVICES                                   │  │   │
│   │   │   ┌──────────────────────────────────────────────────────────────────────┐  │  │   │
│   │   │   │              Nexus IQ Server Containers                              │  │  │   │
│   │   │   │   • Serverless Autoscaling (1-10 instances)                          │  │  │   │
│   │   │   │   • CPU: 2 cores, Memory: 4GB (configurable)                        │  │  │   │
│   │   │   │   • Port 8070: Application, Port 8071: Admin                         │  │  │   │
│   │   │   │   • VPC Connector for private network access                         │  │  │   │
│   │   │   └───────────────────────────────┬──────────────────────────────────────┘  │  │   │
│   │   └───────────────────────────────────┼─────────────────────────────────────────┘  │   │
│   └───────────────────────────────────────┼────────────────────────────────────────────┘   │
│                                           │                                                │
│                         ┌─────────────────┴────────────────┐                               │
│                         │                                  │                               │
│   ┌─────────────────────▼─────────────────────┐   ┌────────▼─────────────────────┐         │
│   │              DATA PERSISTENCE             │   │      PRIVATE NETWORKS        │         │
│   │                                           │   │                              │         │
│   │   ┌─────────────────────────────────────┐ │   │   ┌─────────────────────────┐│         │
│   │   │         CLOUD FILESTORE             │ │   │   │     CLOUD SQL           ││         │
│   │   │   • Managed NFS Storage             │ │   │   │   • PostgreSQL 15       ││         │
│   │   │   • /sonatype-work mount            │ │   │   │   • Regional HA         ││         │
│   │   │   • BASIC_SSD tier                  │ │   │   │   • Private IP only     ││         │
│   │   │   • Shared across instances         │ │   │   │   • Automated backups   ││         │
│   │   │   • 1TB+ capacity                   │ │   │   │   • Point-in-time       ││         │
│   │   └─────────────────────────────────────┘ │   │   │     recovery            ││         │
│   └─────────────────────────────────────────────┘   │   └─────────────────────────┘│         │
│                                                     └──────────────────────────────┘         │
│                                                                                            │
│              ┌─────────────────────────────────────────────┐                               │
│              │               SECURITY LAYER                │                               │
│              │                                             │                               │
│              │  • VPC Firewall Rules (Least Privilege)     │                               │
│              │  • Service Accounts & IAM Policies          │                               │
│              │  • Secret Manager (DB Credentials)          │                               │
│              │  • Cloud Armor (DDoS + WAF Protection)      │                               │
│              │  • Private Google Access                    │                               │
│              └─────────────────────────────────────────────┘                               │
│                                                                                            │
│              ┌─────────────────────────────────────────────┐                               │
│              │             OBSERVABILITY LAYER             │                               │
│              │                                             │                               │
│              │  • Cloud Logging (Centralized Logs)         │                               │
│              │  • Cloud Monitoring (Metrics & Dashboards)  │                               │
│              │  • Uptime Checks & SLO Monitoring           │                               │
│              │  • Alert Policies & Notification Channels   │                               │
│              │  • Error Reporting & Performance Insights   │                               │
│              └─────────────────────────────────────────────┘                               │
└────────────────────────────────────────────────────────────────────────────────────────────┘
```

## 2. Network Architecture & Traffic Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           TRAFFIC FLOW DIAGRAM                             │
└─────────────────────────────────────────────────────────────────────────────┘

Internet Users
    │
    │ HTTPS/HTTP (443/80)
    ▼
┌─────────────────────────────────────┐
│        Global Load Balancer         │
│   • SSL Termination                 │
│   • Cloud Armor Protection          │
│   • Health Checks                   │
│   • Geographic Distribution         │
└─────────────────┬───────────────────┘
                  │
                  │ Forwarding Rules
                  ▼
┌─────────────────────────────────────┐
│       Backend Service               │
│   • Target Group Management        │
│   • Load Distribution               │
│   • Connection Draining             │
└─────────────────┬───────────────────┘
                  │
                  │ Round Robin / Least Connections
                  ▼
┌──────────────────────────────────────────────────────────────┐
│                    Network Endpoint Groups                   │
│        ┌──────────┐  ┌──────────┐  ┌──────────┐            │
│        │Cloud Run │  │Cloud Run │  │Cloud Run │            │
│        │Instance 1│  │Instance 2│  │Instance N│            │
│        │Port: 8070│  │Port: 8070│  │Port: 8070│            │
│        └─────┬────┘  └─────┬────┘  └─────┬────┘            │
└──────────────┼─────────────┼─────────────┼─────────────────┘
               │             │             │
               │    VPC Connector Access   │
               │             │             │
               ▼             ▼             ▼
┌───────────────────────────────────────────────────────────────┐
│                    PRIVATE VPC NETWORK                       │
│                                                               │
│   ┌─────────────────────┐         ┌───────────────────────┐   │
│   │   CLOUD FILESTORE   │◄────────┤   Database Access     │   │
│   │                     │         │                       │   │
│   │  NFS Mount:         │         │   Cloud SQL           │   │
│   │  /sonatype-work     │         │   • PostgreSQL        │   │
│   │                     │         │   • Private IP        │   │
│   │  Shared Storage     │         │   • Port 5432         │   │
│   │  1TB+ Capacity      │         │   • Connection Pool   │   │
│   └─────────────────────┘         └───────────────────────┘   │
└───────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                          SECURITY BOUNDARIES                               │
└─────────────────────────────────────────────────────────────────────────────┘

External Zone:    │ Global Load Balancer ← → Internet
Cloud Run Zone:   │ Serverless containers (no direct external access)
Storage Zone:     │ Private NFS + Database (internal access only)
Management Zone:  │ Service accounts, secrets, monitoring

Firewall Rules (Ingress):
┌─────────────────┬──────────────────┬─────────────────┬──────────────────┐
│   Source        │    Target        │     Ports       │    Protocol      │
├─────────────────┼──────────────────┼─────────────────┼──────────────────┤
│ 0.0.0.0/0       │ Load Balancer    │ 80, 443         │ HTTP/HTTPS       │
│ Google LB       │ Cloud Run        │ 8070, 8071      │ HTTP             │
│ Health Checks   │ Cloud Run        │ 8070, 8071      │ HTTP             │
│ Cloud Run       │ Cloud SQL        │ 5432            │ PostgreSQL       │
│ Cloud Run       │ Cloud Filestore  │ 2049            │ NFS              │
│ VPC Connector   │ Private Network  │ ALL             │ VPC Internal     │
└─────────────────┴──────────────────┴─────────────────┴──────────────────┘
```

## 3. Component Architecture Details

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           COMPUTE ARCHITECTURE                             │
└─────────────────────────────────────────────────────────────────────────────┘

Cloud Run Service: ref-arch-iq-service
├── Deployment Configuration
│   ├── Single Mode: min=1, max=1 instances
│   ├── HA Mode: min=2, max=10 instances
│   ├── CPU Allocation: 2 vCPU (2000m)
│   ├── Memory Allocation: 4GB (4Gi)
│   └── Max Concurrency: 1000 requests/instance
│
├── Container Configuration
│   ├── Image: sonatypecommunity/nexus-iq-server:latest
│   ├── Ports: 8070 (app), 8071 (admin)
│   ├── Environment Variables:
│   │   ├── JAVA_OPTS: -Xmx3g -Djava.util.prefs.userRoot=/sonatype-work/javaprefs
│   │   ├── DB_TYPE: postgresql
│   │   ├── DB_HOST: <cloud-sql-private-ip>
│   │   ├── DB_PORT: 5432
│   │   └── DB_NAME: nexusiq
│   └── Secrets (from Secret Manager):
│       ├── DB_USER
│       └── DB_PASSWORD
│
├── Networking
│   ├── VPC Connector: ref-arch-iq-connector
│   ├── Egress: All traffic through VPC
│   ├── Private IP: VPC internal communication
│   └── No direct external access
│
├── Storage Mounts
│   └── Volume: iq-data
│       ├── Type: NFS (Cloud Filestore)
│       ├── Mount Path: /sonatype-work
│       ├── Server: <filestore-ip>
│       └── Export: /nexus_iq_data
│
├── Health Checks
│   ├── Startup Probe:
│   │   ├── Path: /
│   │   ├── Port: 8070
│   │   ├── Initial Delay: 120s
│   │   └── Failure Threshold: 10
│   └── Liveness Probe:
│       ├── Path: /
│       ├── Port: 8070
│       ├── Period: 30s
│       └── Failure Threshold: 3
│
└── Autoscaling Behavior
    ├── Scale Up: Based on CPU, memory, request count
    ├── Scale Down: Gradual with connection draining
    ├── Cold Starts: Optimized with minimum instances
    └── Traffic Splitting: 100% to latest revision

┌─────────────────────────────────────────────────────────────────────────────┐
│                            DATA ARCHITECTURE                               │
└─────────────────────────────────────────────────────────────────────────────┘

Database Layer (Cloud SQL):
┌─────────────────────────────────────────────────────────────────────────────┐
│ Primary Instance: ref-arch-iq-database-<random>                             │
│  ├── Engine: PostgreSQL 15                                                 │
│  ├── Tier: db-custom-2-4096 (2 vCPU, 4GB RAM)                             │
│  ├── Storage: PD-SSD, 100GB initial, auto-resize to 1TB                   │
│  ├── Availability:                                                         │
│  │   ├── Single Mode: Zonal (single zone)                                  │
│  │   └── HA Mode: Regional (automatic failover)                            │
│  ├── Backup Configuration:                                                 │
│  │   ├── Automated daily backups                                           │
│  │   ├── 7-day retention period                                            │
│  │   ├── Point-in-time recovery enabled                                    │
│  │   └── Transaction log retention: 7 days                                 │
│  ├── Security:                                                             │
│  │   ├── Private IP only (no public access)                                │
│  │   ├── VPC peering for connectivity                                      │
│  │   ├── SSL/TLS encryption in transit                                     │
│  │   ├── Encryption at rest (automatic)                                    │
│  │   └── IAM database authentication (optional)                            │
│  └── Monitoring:                                                           │
│      ├── Query insights enabled                                            │
│      ├── Performance insights                                              │
│      └── Connection monitoring                                             │
└─────────────────────────────────────────────────────────────────────────────┘

Read Replica (HA Mode Only):
┌─────────────────────────────────────────────────────────────────────────────┐
│ Replica Instance: ref-arch-iq-database-replica-<random>                     │
│  ├── Location: Secondary region (us-east1)                                 │
│  ├── Purpose: Read operations, disaster recovery                           │
│  ├── Replication: Asynchronous from primary                                │
│  └── Failover: Manual promotion to primary                                 │
└─────────────────────────────────────────────────────────────────────────────┘

File Storage Layer (Cloud Filestore):
┌─────────────────────────────────────────────────────────────────────────────┐
│ Filestore Instance: ref-arch-iq-filestore                                   │
│  ├── Tier: BASIC_SSD (1TB minimum)                                         │
│  ├── Location: Single zone (same as Cloud Run)                             │
│  ├── Network: VPC native connectivity                                      │
│  ├── Mount: /nexus_iq_data                                                 │
│  ├── Protocol: NFSv3                                                       │
│  ├── Access Control:                                                       │
│  │   ├── IP Range: Private subnet CIDR                                     │
│  │   ├── Access Mode: READ_WRITE                                           │
│  │   └── Root Squash: NO_ROOT_SQUASH                                       │
│  ├── Performance:                                                          │
│  │   ├── Throughput: Up to 480 MB/s                                        │
│  │   ├── IOPS: Up to 30,000                                                │
│  │   └── Latency: Sub-millisecond                                          │
│  └── Backup:                                                               │
│      ├── Snapshots: Manual/scheduled                                       │
│      └── Cross-region replication: Optional                                │
└─────────────────────────────────────────────────────────────────────────────┘

Object Storage (Cloud Storage):
┌─────────────────────────────────────────────────────────────────────────────┐
│ Backup Bucket: ref-arch-iq-backups-<random>                                │
│  ├── Purpose: Application backups, exports                                 │
│  ├── Storage Class: Standard → Nearline → Coldline                         │
│  ├── Lifecycle: 30 day retention, tiered storage                           │
│  └── Encryption: Google-managed keys                                       │
│                                                                             │
│ Logs Bucket: ref-arch-iq-lb-logs-<random>                                  │
│  ├── Purpose: Load balancer access logs                                    │
│  ├── Lifecycle: 90 day retention                                           │
│  └── Access: Load balancer service account only                            │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 4. Network Topology

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        VPC NETWORK TOPOLOGY                                │
└─────────────────────────────────────────────────────────────────────────────┘

VPC Network: ref-arch-iq-vpc
├── Region: us-central1 (configurable)
├── Routing Mode: Regional
├── MTU: 1460 bytes
└── Subnets:

    ┌─────────────────────────────────────────────────────────────────┐
    │                      PUBLIC SUBNET                              │
    │  Name: ref-arch-iq-public-subnet                                │
    │  CIDR: 10.0.1.0/24                                             │
    │  Purpose: Load balancer frontend                                │
    │  Resources:                                                     │
    │    • Global Load Balancer (anycast IP)                         │
    │    • Cloud NAT gateway                                          │
    │  Internet Access: Yes (egress only)                            │
    └─────────────────────────────────────────────────────────────────┘
                                │
                                │ Forwarding Rules
                                ▼
    ┌─────────────────────────────────────────────────────────────────┐
    │                     PRIVATE SUBNET                              │
    │  Name: ref-arch-iq-private-subnet                               │
    │  CIDR: 10.0.2.0/24                                             │
    │  Purpose: Cloud Run services                                   │
    │  Resources:                                                     │
    │    • Cloud Run instances (via VPC Connector)                   │
    │    • VPC Connector: 10.0.4.0/28                                │
    │  Internet Access: Via Cloud NAT (egress only)                  │
    │  Private Google Access: Enabled                                │
    └─────────────────────────────────────────────────────────────────┘
                                │
                                │ Private Connectivity
                                ▼
    ┌─────────────────────────────────────────────────────────────────┐
    │                    DATABASE SUBNET                              │
    │  Name: ref-arch-iq-db-subnet                                    │
    │  CIDR: 10.0.3.0/24                                             │
    │  Purpose: Cloud SQL instances                                  │
    │  Resources:                                                     │
    │    • Cloud SQL PostgreSQL (private IP)                         │
    │    • Read replicas (HA mode)                                   │
    │  Internet Access: None                                         │
    │  Private Service Connect: Enabled                              │
    └─────────────────────────────────────────────────────────────────┘

Secondary IP Ranges (for future Kubernetes if needed):
├── services-range: 10.1.0.0/16
└── pods-range: 10.2.0.0/16

Cloud Router & NAT:
├── Router: ref-arch-iq-router
├── NAT Gateway: ref-arch-iq-nat
├── NAT IP Allocation: Automatic
└── Logging: Errors only

VPC Peering:
├── Private Service Connection
├── Purpose: Cloud SQL private access
├── Peered Network: servicenetworking.googleapis.com
└── IP Range: 10.x.0.0/16 (Google managed)
```

## 5. Security Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           SECURITY LAYERS                                  │
└─────────────────────────────────────────────────────────────────────────────┘

Defense in Depth Strategy:

Layer 1: Internet & Edge Security
┌─────────────────────────────────────────────────────────────────────────────┐
│ Cloud Armor Security Policy                                                │
│  ├── DDoS Protection: L3/L4 + L7 adaptive protection                       │
│  ├── Rate Limiting: 100 requests/minute per IP                             │
│  ├── Geo-blocking: Configurable country/region filtering                   │
│  ├── WAF Rules:                                                            │
│  │   ├── SQL injection protection                                          │
│  │   ├── XSS attack prevention                                             │
│  │   ├── Bot management                                                    │
│  │   └── Custom security rules                                             │
│  └── IP Allowlist/Blocklist: Configurable                                 │
│                                                                             │
│ SSL/TLS Termination                                                         │
│  ├── Google-managed certificates                                           │
│  ├── TLS 1.2+ enforcement                                                  │
│  ├── HSTS headers                                                          │
│  └── Perfect Forward Secrecy                                               │
└─────────────────────────────────────────────────────────────────────────────┘

Layer 2: Network Security
┌─────────────────────────────────────────────────────────────────────────────┐
│ VPC Firewall Rules                                                         │
│  ├── Default: Deny all ingress, allow all egress                           │
│  ├── Load Balancer Access:                                                 │
│  │   ├── allow-lb-access: Internet → LB (80, 443)                          │
│  │   └── allow-health-checks: Google ranges → Services                     │
│  ├── Service Communication:                                                │
│  │   ├── allow-cloudsql-access: Cloud Run → Database (5432)               │
│  │   ├── allow-filestore-access: Cloud Run → NFS (2049)                   │
│  │   └── allow-vpc-connector: VPC Connector traffic                        │
│  └── Internal Communication:                                               │
│      └── allow-internal: VPC internal (all protocols)                     │
│                                                                             │
│ Network Isolation                                                          │
│  ├── Private Subnets: No direct internet access                            │
│  ├── Private Google Access: Google APIs via private IPs                    │
│  ├── VPC Connector: Secure Cloud Run to VPC communication                 │
│  └── Service Networking: Private database connectivity                     │
└─────────────────────────────────────────────────────────────────────────────┘

Layer 3: Identity & Access Management
┌─────────────────────────────────────────────────────────────────────────────┐
│ Service Accounts (Least Privilege)                                         │
│  ├── Cloud Run Service Account:                                            │
│  │   ├── cloudsql.client                                                  │
│  │   ├── secretmanager.secretAccessor                                     │
│  │   ├── logging.logWriter                                                │
│  │   ├── monitoring.metricWriter                                          │
│  │   └── storage.objectAdmin (backup bucket only)                         │
│  ├── Load Balancer Service Account:                                        │
│  │   └── logging.logWriter (access logs only)                             │
│  └── Custom IAM Role:                                                      │
│      └── Minimal permissions for IQ operations                             │
│                                                                             │
│ Workload Identity (Optional)                                               │
│  ├── Kubernetes service account binding                                    │
│  ├── Pod-level identity mapping                                            │
│  └── Cross-service authentication                                          │
└─────────────────────────────────────────────────────────────────────────────┘

Layer 4: Application Security
┌─────────────────────────────────────────────────────────────────────────────┐
│ Secret Management                                                          │
│  ├── Secret Manager:                                                       │
│  │   ├── Database credentials                                              │
│  │   ├── API keys and tokens                                               │
│  │   └── Application secrets                                               │
│  ├── Automatic rotation: Configurable                                     │
│  ├── Audit logging: All access logged                                     │
│  └── Encryption: Google-managed keys                                       │
│                                                                             │
│ Container Security                                                         │
│  ├── Base Image: Official Sonatype images                                 │
│  ├── Vulnerability Scanning: Automatic                                    │
│  ├── Runtime Security: gVisor sandbox                                     │
│  └── Resource Limits: CPU/memory constraints                              │
└─────────────────────────────────────────────────────────────────────────────┘

Layer 5: Data Security
┌─────────────────────────────────────────────────────────────────────────────┐
│ Encryption                                                                 │
│  ├── Data in Transit:                                                      │
│  │   ├── TLS 1.2+ for all external connections                            │
│  │   ├── VPC internal traffic encryption                                  │
│  │   └── Database connections: SSL/TLS                                     │
│  ├── Data at Rest:                                                         │
│  │   ├── Cloud SQL: Automatic encryption                                  │
│  │   ├── Cloud Filestore: Automatic encryption                            │
│  │   ├── Cloud Storage: Google-managed keys                               │
│  │   └── Optional: Customer-managed keys (CMEK)                           │
│  └── Key Management:                                                       │
│      ├── Google Cloud KMS integration                                     │
│      ├── Key rotation: Automatic                                          │
│      └── Hardware Security Modules (HSM)                                  │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 6. Operational Excellence

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        MONITORING & OBSERVABILITY                          │
└─────────────────────────────────────────────────────────────────────────────┘

Cloud Monitoring Integration:
├── Service Metrics:
│   ├── Cloud Run: Instance count, CPU, memory, request latency
│   ├── Cloud SQL: Connections, query performance, replication lag
│   ├── Load Balancer: Request count, error rate, latency distribution
│   └── Cloud Filestore: IOPS, throughput, capacity utilization
│
├── Custom Dashboards:
│   ├── Application Health Overview
│   ├── Infrastructure Resource Utilization
│   ├── Database Performance Metrics
│   └── Security & Compliance Status
│
├── Log Aggregation:
│   ├── Cloud Run: Application logs, container logs
│   ├── Load Balancer: Access logs, security events
│   ├── Database: Query logs, audit logs
│   └── VPC: Flow logs, firewall logs
│
├── Alert Policies:
│   ├── High CPU/Memory Utilization (>80%)
│   ├── High Error Rate (>5%)
│   ├── Database Connection Issues
│   ├── Service Unavailability
│   └── Security Policy Violations
│
└── SLO/SLI Monitoring:
    ├── Availability SLO: 99.9% uptime
    ├── Response Time SLI: 95% < 2 seconds
    ├── Error Rate SLI: < 1% of requests
    └── Database Performance SLI: Query time < 100ms

┌─────────────────────────────────────────────────────────────────────────────┐
│                          AUTOMATION & DEPLOYMENT                           │
└─────────────────────────────────────────────────────────────────────────────┘

Infrastructure as Code:
├── Terraform Configuration:
│   ├── Modular design with clear separation
│   ├── Environment-specific variables
│   ├── State management with remote backend
│   └── CI/CD pipeline integration
│
├── Deployment Scripts:
│   ├── deploy.sh: Complete infrastructure deployment
│   ├── destroy.sh: Safe infrastructure teardown
│   ├── gcp-plan.sh: Change planning and validation
│   └── gcp-apply.sh: Controlled deployment execution
│
├── Configuration Management:
│   ├── Environment variables via terraform.tfvars
│   ├── Secret management via Secret Manager
│   ├── Feature flags for optional components
│   └── Rolling deployments with zero downtime
│
└── Backup & Recovery:
    ├── Automated database backups (daily)
    ├── Point-in-time recovery capability
    ├── Configuration backup to Cloud Storage
    └── Disaster recovery procedures

┌─────────────────────────────────────────────────────────────────────────────┐
│                            DISASTER RECOVERY                               │
└─────────────────────────────────────────────────────────────────────────────┘

Recovery Strategies:
├── Database Recovery:
│   ├── RTO: 15 minutes (automated failover in HA mode)
│   ├── RPO: 5 minutes (point-in-time recovery)
│   ├── Cross-region read replicas
│   └── Automated backup validation
│
├── Application Recovery:
│   ├── Multi-zone deployment
│   ├── Stateless architecture (Cloud Run)
│   ├── Shared storage (Cloud Filestore)
│   └── Load balancer health checks
│
├── Data Recovery:
│   ├── File system snapshots
│   ├── Application-level backups
│   ├── Cross-region data replication
│   └── Recovery testing procedures
│
└── Business Continuity:
    ├── Runbook automation
    ├── Incident response procedures
    ├── Communication protocols
    └── Regular DR testing
```

## 7. Scaling Patterns

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           SCALING ARCHITECTURE                             │
└─────────────────────────────────────────────────────────────────────────────┘

Horizontal Scaling (Cloud Run):
├── Autoscaling Triggers:
│   ├── CPU Utilization (>70% scale up, <30% scale down)
│   ├── Memory Utilization (>80% scale up, <40% scale down)
│   ├── Request Queue Depth (>100 pending requests)
│   └── Custom Metrics (application-specific)
│
├── Scaling Configuration:
│   ├── Single Mode: min=1, max=1 instances
│   ├── HA Mode: min=2, max=10 instances
│   ├── Scale-up: 1 instance per 30 seconds
│   ├── Scale-down: Gradual with 5-minute cooldown
│   └── Connection Draining: 30 seconds
│
└── Cold Start Optimization:
    ├── Minimum instances to reduce cold starts
    ├── Pre-warmed instances during peak hours
    ├── Optimized container startup time
    └── Startup probe tuning

Vertical Scaling (Resources):
├── CPU Scaling:
│   ├── Development: 1-2 vCPU
│   ├── Production: 2-4 vCPU
│   └── Enterprise: 4-8 vCPU
│
├── Memory Scaling:
│   ├── Development: 2-4 GB
│   ├── Production: 4-8 GB
│   └── Enterprise: 8-16 GB
│
└── Storage Scaling:
    ├── Database: Auto-resize enabled (100GB → 1TB)
    ├── File Storage: Manual scaling (1TB+)
    └── Object Storage: Unlimited capacity

Database Scaling:
├── Read Scaling:
│   ├── Read replicas in secondary regions
│   ├── Connection pooling
│   ├── Query optimization
│   └── Caching strategies
│
├── Write Scaling:
│   ├── Single primary instance
│   ├── Connection pooling
│   ├── Batch operations
│   └── Async processing where possible
│
└── Storage Scaling:
    ├── Automatic storage increase
    ├── Performance scaling (IOPS)
    ├── Backup storage management
    └── Archive old data strategies

Global Scaling (Multi-Region):
├── Load Balancer:
│   ├── Global anycast IP
│   ├── Geographic routing
│   ├── Regional backend services
│   └── Cross-region failover
│
├── Data Replication:
│   ├── Database read replicas
│   ├── File storage replication
│   ├── Configuration synchronization
│   └── Backup distribution
│
└── Monitoring:
    ├── Global monitoring dashboard
    ├── Regional performance metrics
    ├── Cross-region latency tracking
    └── Regional capacity planning
```

## 8. Cost Optimization

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          COST BREAKDOWN & OPTIMIZATION                     │
└─────────────────────────────────────────────────────────────────────────────┘

Monthly Cost Estimates (us-central1):

Single Instance Mode:
├── Cloud Run (2 vCPU, 4GB, 1 instance):
│   ├── vCPU: 2 × $0.024/hour × 730 hours = $35
│   ├── Memory: 4GB × $0.0025/hour × 730 hours = $7
│   ├── Requests: 1M requests × $0.0000004 = $0.40
│   └── Subtotal: ~$42
│
├── Cloud SQL (db-custom-2-4096, single zone):
│   ├── Instance: $0.0875/hour × 730 hours = $64
│   ├── Storage: 100GB × $0.17/month = $17
│   ├── Backup: 100GB × $0.08/month = $8
│   └── Subtotal: ~$89
│
├── Cloud Filestore (1TB BASIC_SSD):
│   └── Storage: 1024GB × $0.20/month = $205
│
├── Load Balancer:
│   ├── Forwarding Rules: 1 × $18/month = $18
│   ├── Data Processing: 1TB × $0.008/GB = $8
│   └── Subtotal: ~$26
│
├── Networking & Other:
│   ├── VPC Connector: $0.36/hour × 730 = $263
│   ├── Cloud NAT: $45/month + data charges
│   ├── Secret Manager: $6/month
│   └── Monitoring & Logging: $20/month
│   └── Subtotal: ~$334
│
└── TOTAL SINGLE MODE: ~$696/month

High Availability Mode:
├── Cloud Run (2-10 instances, average 4):
│   └── Cost: $42 × 4 = ~$168
│
├── Cloud SQL (regional, with replica):
│   ├── Primary: $89 × 2 (regional multiplier) = $178
│   ├── Read Replica: $64 + $17 = $81
│   └── Subtotal: ~$259
│
├── Other services: Similar to single mode
│
└── TOTAL HA MODE: ~$1,062/month

Cost Optimization Strategies:
├── Reserved Capacity:
│   ├── Committed Use Discounts: Up to 57% off
│   ├── Sustained Use Discounts: Automatic
│   └── Preemptible instances where applicable
│
├── Resource Optimization:
│   ├── Right-sizing based on monitoring
│   ├── Autoscaling to minimize idle resources
│   ├── Scheduled scaling for predictable patterns
│   └── Regular cost reviews and optimization
│
├── Storage Optimization:
│   ├── Lifecycle policies for backups
│   ├── Data archival strategies
│   ├── Compression and deduplication
│   └── Regional vs. multi-regional storage
│
└── Monitoring & Alerting:
    ├── Budget alerts and spending limits
    ├── Cost anomaly detection
    ├── Resource utilization monitoring
    └── Regular cost optimization reviews
```

## 9. Deployment Patterns

### Blue-Green Deployment
- Cloud Run traffic splitting capabilities
- Database migration strategies
- Rollback procedures

### Canary Deployment  
- Gradual traffic shifting
- Monitoring and validation
- Automated rollback triggers

### Multi-Environment Strategy
- Development, staging, production separation
- Environment-specific configurations
- Promotion pipelines

This architecture provides a robust, scalable, and secure foundation for running Nexus IQ Server on Google Cloud Platform, leveraging cloud-native services for optimal performance and operational efficiency.