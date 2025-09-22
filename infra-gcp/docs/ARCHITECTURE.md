# Nexus IQ Server - GCP Architecture Guide

This document provides a detailed technical architecture overview of the Nexus IQ Server deployment on Google Cloud Platform.

## 📐 Architecture Overview

### High-Level Architecture Diagram

```
Internet
    │
    ▼
┌─────────────────────────────────────────────────────┐
│                Cloud Armor WAF                      │
│          (DDoS Protection, Rate Limiting)           │
└─────────────────┬───────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────┐
│               Global Load Balancer                  │
│        (SSL Termination, Health Checks)             │
└─────────────────┬───────────────────────────────────┘
                  │
    ┌─────────────┼─────────────┐
    │             │             │
    ▼             ▼             ▼
┌─────────┐   ┌─────────┐   ┌─────────┐
│Region A │   │Region B │   │Region C │
│Cloud Run│   │Cloud Run│   │Cloud Run│
└─────────┘   └─────────┘   └─────────┘
    │             │             │
    └─────────────┼─────────────┘
                  │
    ┌─────────────┼─────────────┐
    │             │             │
    ▼             ▼             ▼
┌─────────────────────────────────────────────────────┐
│                 Private VPC                         │
│  ┌───────────────┐  ┌─────────────┐  ┌─────────────┐│
│  │   Cloud SQL   │  │ Filestore   │  │   Secrets   ││
│  │  PostgreSQL   │  │    (NFS)    │  │  Manager    ││
│  │      HA       │  │             │  │             ││
│  └───────────────┘  └─────────────┘  └─────────────┘│
└─────────────────────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────┐
│               Cloud Storage                         │
│     (Backups, Logs, Configurations)                │
└─────────────────────────────────────────────────────┘
```

## 🏗️ Component Architecture

### 1. Frontend Layer

#### Global Load Balancer
- **Type**: HTTP(S) Load Balancer with global anycast IPs
- **Features**:
  - SSL/TLS termination with managed certificates
  - Global traffic distribution
  - Health check integration
  - CDN integration (optional)
- **Backend**: Serverless NEGs pointing to Cloud Run services

#### Cloud Armor WAF
- **Protection Level**: OWASP Top 10 + custom rules
- **Features**:
  - DDoS protection with adaptive thresholds
  - Geographic blocking capabilities
  - Rate limiting per IP/session
  - SQL injection and XSS protection
- **Integration**: Applied at load balancer level

### 2. Application Layer

#### Cloud Run Services

##### Single Instance Configuration
```yaml
Service: nexus-iq-server
Resources:
  CPU: 2000m (2 vCPU)
  Memory: 4Gi
  Scaling: 1-10 instances
  Concurrency: 80 requests/instance
  Timeout: 300 seconds

Networking:
  VPC Connector: nexus-iq-connector
  Egress: Private ranges only
  Ports: 8070 (HTTP), 8071 (Admin)
```

##### High Availability Configuration
```yaml
Service: nexus-iq-ha-server
Resources:
  CPU: 4000m (4 vCPU)
  Memory: 8Gi
  Scaling: 2-20 instances
  Concurrency: 80 requests/instance
  
Multi-Region:
  Primary: us-central1
  Secondary: us-east1
  Failover: Automatic via load balancer
```

#### Container Specifications
```dockerfile
Base Image: sonatypecommunity/nexus-iq-server:latest
Environment Variables:
  - JAVA_OPTS: JVM configuration
  - DB_TYPE: postgresql
  - DB_HOST: Cloud SQL private IP
  - DB_PORT: 5432
  - DB_NAME: nexusiq
  
Volume Mounts:
  - /sonatype-work: Filestore NFS mount
  
Health Checks:
  - Startup: HTTP GET / (60s delay, 10s timeout)
  - Liveness: HTTP GET / (30s interval, 10s timeout)
```

### 3. Data Layer

#### Cloud SQL PostgreSQL

##### Single Instance
```yaml
Configuration:
  Tier: db-custom-2-7680 (2 vCPU, 7.5GB RAM)
  Storage: 100GB SSD, auto-expand to 1TB
  Availability: Zonal
  
Networking:
  Type: Private IP only
  VPC: nexus-iq-vpc
  SSL: Required
  
Backup:
  Schedule: Daily at 03:00 UTC
  Retention: 7 days
  Point-in-time: 7 days
```

##### High Availability
```yaml
Configuration:
  Tier: db-custom-4-15360 (4 vCPU, 15GB RAM)
  Storage: 200GB SSD, auto-expand to 2TB
  Availability: Regional (multi-zone)
  
Replication:
  Sync: Regional replicas in same region
  Async: Read replicas in other regions (optional)
  
Failover:
  Type: Automatic
  RTO: ~60-120 seconds
  RPO: Near zero (sync replication)
```

#### Cloud Filestore (NFS)

##### Standard Configuration
```yaml
Instance: nexus-iq-filestore
Tier: BASIC_SSD
Capacity: 1TB (expandable)
Performance: 100 MB/s read/write
Network: Private VPC access only
Mount: /nexus_iq_data
```

##### HA Configuration
```yaml
Instance: nexus-iq-ha-filestore
Tier: HIGH_SCALE_SSD
Capacity: 2TB
Performance: 1000+ MB/s read/write
Availability: Multi-zone backup
```

### 4. Storage Layer

#### Cloud Storage Buckets

##### Backup Storage
```yaml
Bucket: nexus-iq-backups-{random}
Location: Regional (same as compute)
Storage Class: Standard
Lifecycle:
  - Delete after 30 days
  - Version limit: 10 versions
Encryption: Customer-managed KMS key
```

##### Log Storage
```yaml
Bucket: nexus-iq-logs-{random}
Location: Regional
Storage Class: Nearline (for cost optimization)
Lifecycle:
  - Move to Coldline after 30 days
  - Delete after 90 days
```

### 5. Network Architecture

#### VPC Design
```yaml
VPC: nexus-iq-vpc
CIDR: 10.100.0.0/16
MTU: 1460

Subnets:
  Public (Load Balancer):
    CIDR: 10.100.1.0/24
    Region: us-central1
    
  Private (Cloud Run):
    CIDR: 10.100.10.0/24
    Private Google Access: Enabled
    
  Database:
    CIDR: 10.100.20.0/24
    Private Service Connect: Enabled
    
Secondary Ranges:
  Services: 10.100.30.0/24
  Pods: 10.100.40.0/24
```

#### VPC Connector
```yaml
Connector: nexus-iq-connector
CIDR: 10.100.50.0/28
Throughput: 200-1000 Mbps
Instances: 2-10 (auto-scaled)
Purpose: Cloud Run to VPC communication
```

#### Cloud NAT
```yaml
NAT Gateway: nexus-iq-nat
Router: nexus-iq-router
IP Allocation: Auto-assigned
Logging: Errors only
Purpose: Egress for private resources
```

### 6. Security Architecture

#### Identity & Access Management

##### Service Accounts
```yaml
Nexus IQ Service Account:
  Name: nexus-iq-service
  Roles:
    - Cloud SQL Client
    - Secret Manager Accessor
    - Storage Admin (buckets)
    - Filestore Editor
    - KMS Crypto Key Encrypter/Decrypter
    
Load Balancer Service Account:
  Name: nexus-iq-lb
  Roles:
    - Cloud Run Invoker
    - Logging Writer
```

##### Custom IAM Role
```yaml
Role: nexusIqOperator
Permissions:
  - cloudsql.instances.get/list
  - run.services.get/list
  - storage.objects.*
  - secretmanager.versions.access
  - monitoring.timeSeries.create
```

#### Encryption

##### Data at Rest
```yaml
Cloud SQL: Google-managed encryption + CMEK
Cloud Storage: Customer-managed KMS keys
Filestore: Google-managed encryption
Secrets: Automatic encryption

KMS Configuration:
  Key Ring: nexus-iq-keyring
  Keys:
    - nexus-iq-storage-key (Storage)
    - nexus-iq-database-key (Database)
  Rotation: 90 days
```

##### Data in Transit
```yaml
Client to LB: TLS 1.2+ (managed certificates)
LB to Cloud Run: HTTP/2 over Google backbone
Cloud Run to SQL: TLS with Cloud SQL Proxy
All internal: Google's encrypted backbone
```

#### Network Security

##### Firewall Rules
```yaml
Allow Load Balancer Health Checks:
  Source: 130.211.0.0/22, 35.191.0.0/16
  Target: Cloud Run services
  Ports: 8070, 8071
  
Allow Internal Communication:
  Source: VPC CIDR blocks
  Target: Internal resources
  Ports: 5432 (PostgreSQL), 2049 (NFS)
  
Deny All Default:
  Priority: 65534
  Action: Deny all other traffic
```

### 7. Monitoring Architecture

#### Observability Stack

##### Metrics Collection
```yaml
Sources:
  - Cloud Run: Request metrics, resource utilization
  - Cloud SQL: Query performance, connections
  - Load Balancer: Request rates, latencies
  - Custom: Application-specific metrics

Storage:
  - Cloud Monitoring: Real-time metrics
  - BigQuery: Long-term analytics (optional)
```

##### Logging Pipeline
```yaml
Sources:
  - Cloud Run: Application logs
  - Cloud SQL: Query logs, error logs
  - VPC: Flow logs (optional)
  - Security: Audit logs, firewall logs

Processing:
  - Cloud Logging: Centralized collection
  - Log Router: Filtering and routing
  - Pub/Sub: Real-time processing (optional)
```

##### Alerting Framework
```yaml
Alert Policies:
  - High CPU/Memory: >80% for 5 minutes
  - Error Rate: >10 errors/minute
  - Database Connections: >150 active
  - Service Down: Failed health checks
  
Notification Channels:
  - Email: Immediate alerts
  - Slack: Team notifications
  - PagerDuty: Critical incidents
```

## 🔄 Data Flow Diagrams

### Request Flow
```
1. Client Request → Cloud Armor (WAF filtering)
2. Cloud Armor → Global Load Balancer (SSL termination)
3. Load Balancer → Cloud Run (via Serverless NEG)
4. Cloud Run → Cloud SQL (via VPC connector)
5. Cloud Run → Filestore (NFS mount)
6. Response path reverses the flow
```

### Data Persistence Flow
```
1. Application Data → Filestore (/sonatype-work)
2. Database Data → Cloud SQL (user data, configs)
3. Logs → Cloud Logging → Cloud Storage
4. Backups → Cloud Storage (encrypted)
5. Metrics → Cloud Monitoring
```

## 🔧 Scaling Patterns

### Horizontal Scaling
```yaml
Cloud Run Autoscaling:
  Trigger: CPU utilization > 70%
  Min Instances: 1 (single), 2 (HA)
  Max Instances: 10 (single), 20 (HA)
  Scale-up: 30 seconds
  Scale-down: 15 minutes (gradual)
```

### Vertical Scaling
```yaml
Resource Limits:
  CPU: 1000m - 4000m (configurable)
  Memory: 2Gi - 8Gi (configurable)
  
Database Scaling:
  CPU: 2-64 vCPUs
  Memory: 7.5GB - 416GB
  Storage: Auto-expand enabled
```

### Multi-Region Scaling
```yaml
Primary Region: us-central1
Secondary Regions: us-east1, europe-west1
Load Distribution: Latency-based routing
Failover: Automatic health check based
```

## 🏛️ Compliance & Governance

### Security Compliance
- **SOC 2 Type II**: Cloud provider certifications
- **ISO 27001**: Security management standards
- **PCI DSS**: If handling payment data
- **GDPR**: Data protection compliance

### Operational Governance
- **Infrastructure as Code**: All resources defined in Terraform
- **Version Control**: Git-based configuration management
- **Change Management**: Pull request workflow
- **Audit Trail**: All changes logged and tracked

### Cost Governance
- **Resource Tagging**: Consistent labeling strategy
- **Budget Alerts**: Automated cost monitoring
- **Right-sizing**: Regular resource optimization
- **Reserved Capacity**: Committed use discounts for predictable workloads

## 🔍 Performance Characteristics

### Expected Performance
```yaml
Response Times:
  - Web Interface: <2 seconds (p95)
  - API Calls: <500ms (p95)
  - File Operations: <1 second (p95)

Throughput:
  - Concurrent Users: 100-500
  - Scans per Hour: 1000-10000
  - Database QPS: 1000-5000

Availability:
  - Single Instance: 99.5%
  - HA Configuration: 99.9%
  - RTO: <5 minutes
  - RPO: <1 minute
```

### Capacity Planning
```yaml
Small Deployment (1-10 users):
  - Cloud Run: 1-3 instances
  - CPU: 1000m per instance
  - Memory: 2Gi per instance
  - Database: db-custom-1-3840

Medium Deployment (10-50 users):
  - Cloud Run: 2-8 instances
  - CPU: 2000m per instance
  - Memory: 4Gi per instance
  - Database: db-custom-2-7680

Large Deployment (50+ users):
  - Cloud Run: 5-20 instances
  - CPU: 4000m per instance
  - Memory: 8Gi per instance
  - Database: db-custom-4-15360 (HA)
```

This architecture provides a robust, scalable, and secure foundation for running Nexus IQ Server on Google Cloud Platform, leveraging cloud-native services for optimal performance and operational efficiency.