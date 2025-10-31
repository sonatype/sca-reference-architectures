# Nexus IQ Server GCP Reference Architecture (Single Instance)

## Deployment Profile

**Recommended for:**
- **Development and testing environments**
- **Proof of concept deployments**
- **Small to medium organizations** with up to 100 onboarded applications
- **Low to moderate scan frequency** (up to 2-3 evaluations per minute)

**System Specifications:**
- 8 vCPU / 32GB RAM (Docker containerized on GCE)
- PostgreSQL 17 Cloud SQL (ENTERPRISE_PLUS)
- Cloud Filestore persistent storage (2.5TB)
- Single instance deployment with global load balancing

## Overview
This reference architecture deploys Nexus IQ Server on Google Cloud Platform using cloud-native services (GCE with Docker, Cloud SQL, Cloud Filestore) for operational excellence and security. This single-instance deployment provides a solid foundation for development, testing, and small to medium production workloads.

**⚠️ Important**: The official `sonatype/nexus-iq-server` Docker image supports database configuration via environment variables and config.yml generation for single instances. This architecture leverages Docker for consistent deployment and easier version management.

## Scaling Options
- **Current Deployment**: Single Instance (up to 100 applications)
- **Vertical Scaling**: Increase GCE machine type (e.g., e2-standard-16 for 16 vCPU, 64GB RAM)
- **Database Scaling**: Enable REGIONAL availability for multi-zone deployment
- **Storage Scaling**: Upgrade from BASIC_SSD to HIGH_SCALE_SSD for better performance

## 1. High-Level Architecture

```mermaid
graph TB
    subgraph Internet
        USER[Users]
    end
    
    subgraph "Google Cloud Platform"
        subgraph "Global Load Balancing"
            GLB[Global HTTP/HTTPS<br/>Load Balancer<br/>Static IP Address]
            HEALTH[Health Check<br/>TCP:8070]
        end
        
        subgraph "Custom VPC Network"
            subgraph "Public Subnet<br/>10.100.1.0/24"
                NAT[Cloud NAT<br/>Internet Gateway]
            end
            
            subgraph "Private Subnet<br/>10.100.10.0/24"
                subgraph "GCE Instance<br/>e2-standard-8"
                    DOCKER[Docker Container<br/>nexus-iq-server:latest<br/>Port 8070, 8071<br/>8 vCPU, 32GB RAM]
                end
                IG[Unmanaged<br/>Instance Group]
            end
            
            subgraph "Database Subnet<br/>10.100.20.0/24"
                CLOUDSQL[(Cloud SQL<br/>PostgreSQL 17<br/>db-perf-optimized-N-8<br/>8 vCPU, 100GB)]
            end
            
            subgraph "Storage Layer"
                FILESTORE[Cloud Filestore<br/>BASIC_SSD 2.5TB<br/>NFS Mount<br/>/sonatype-work]
            end
        end
        
        subgraph "Security & Operations"
            SM[Secret Manager<br/>Database Credentials]
            LOGGING[Cloud Logging<br/>Centralized Logs]
            MONITORING[Cloud Monitoring<br/>Metrics & Alerts]
            IAM[Service Accounts<br/>IAM Roles]
        end
    end
    
    USER -->|HTTP/HTTPS| GLB
    GLB -->|Backend Service| IG
    IG --> DOCKER
    HEALTH -.->|Health Probe| DOCKER
    DOCKER -->|Private IP<br/>Port 5432| CLOUDSQL
    DOCKER -->|NFS v3<br/>Port 2049| FILESTORE
    DOCKER -->|Secrets| SM
    DOCKER -->|Logs| LOGGING
    DOCKER -->|Metrics| MONITORING
    DOCKER -.->|Cloud NAT| NAT
    
    style GLB fill:#4285f4,stroke:#333,stroke-width:2px,color:#fff
    style DOCKER fill:#34a853,stroke:#333,stroke-width:2px,color:#fff
    style CLOUDSQL fill:#fbbc04,stroke:#333,stroke-width:2px,color:#fff
    style FILESTORE fill:#ea4335,stroke:#333,stroke-width:2px,color:#fff
```

## 2. Network Flow & Security

```mermaid
graph LR
    subgraph "Internet Zone"
        INTERNET[Internet Traffic<br/>Port 80/443]
    end
    
    subgraph "Public Zone"
        LB[Global Load Balancer<br/>External IP]
        FW_LB[Firewall: allow-http-https<br/>0.0.0.0/0:80,443]
    end
    
    subgraph "Private Zone"
        GCE[GCE Instance<br/>No External IP]
        FW_HC[Firewall: allow-health-check<br/>130.211.0.0/22:8070,8071]
        FW_LB_INST[Firewall: allow-lb<br/>0.0.0.0/0:8070]
        FW_INT[Firewall: allow-internal<br/>VPC CIDR:8070,8071,5432,2049]
    end
    
    subgraph "Database Zone"
        SQL[(Cloud SQL<br/>Private IP Only)]
    end
    
    subgraph "Storage Zone"
        FS[Cloud Filestore<br/>VPC Private Access]
    end
    
    INTERNET --> FW_LB
    FW_LB --> LB
    LB --> FW_LB_INST
    FW_LB_INST --> GCE
    FW_HC -.->|Health Probes| GCE
    FW_INT --> GCE
    GCE -->|Port 5432<br/>Private| SQL
    GCE -->|NFS Port 2049<br/>Private| FS
    
    style INTERNET fill:#e8f4f8
    style LB fill:#4285f4,color:#fff
    style GCE fill:#34a853,color:#fff
    style SQL fill:#fbbc04,color:#fff
    style FS fill:#ea4335,color:#fff
```

### Security Boundaries

```mermaid
graph TD
    subgraph "Security Layers"
        A[Public Zone: Internet Gateway] -->|"Firewall Rules"| B[Load Balancer Only]
        B -->|"Health Checks Only"| C[Private Zone: GCE Instances]
        C -->|"Private IP Only"| D[Database Zone: Cloud SQL]
        C -->|"VPC Access Only"| E[Storage Zone: Filestore]
        C -->|"Cloud NAT"| F[Outbound Internet]
    end
    
    style A fill:#fff4e6
    style B fill:#e3f2fd
    style C fill:#e8f5e9
    style D fill:#fff3e0
    style E fill:#fce4ec
    style F fill:#f3e5f5
```

### Firewall Rules Table

| Component | Inbound | Outbound | Protocol | Source/Destination |
|-----------|---------|----------|----------|-------------------|
| Load Balancer | Internet:80,443 | GCE:8070 | HTTP | 0.0.0.0/0 |
| GCE Instance | LB:8070 | SQL:5432 | TCP | VPC CIDR |
| GCE Instance | Health:8070,8071 | Filestore:2049 | TCP/NFS | GCP Health Check IPs |
| Cloud SQL | GCE:5432 | None | PostgreSQL | Private Subnet |
| Cloud Filestore | GCE:2049 | None | NFS | Private Subnet |

## 3. Component Architecture

```mermaid
graph TB
    subgraph "Compute Layer"
        subgraph "GCE Instance: nexus-iq-server"
            BOOT[Boot Disk<br/>Debian 12<br/>100GB SSD]
            STARTUP[Startup Script<br/>Install Docker<br/>Mount Filestore<br/>Launch Container]
            
            subgraph "Docker Container"
                IMAGE[Image: sonatype/nexus-iq-server:latest]
                PORTS[Ports: 8070, 8071]
                ENV[Environment Variables<br/>DB_HOST, DB_PORT, DB_NAME<br/>DB_USERNAME, DB_PASSWORD<br/>JAVA_OPTS]
                VOLUMES[Volume Mounts<br/>/sonatype-work<br/>/var/log/nexus-iq-server]
            end
        end
        
        IG[Unmanaged Instance Group<br/>Single Instance<br/>Named Port: http:8070]
    end
    
    subgraph "Load Balancing"
        BACKEND[Backend Service<br/>Protocol: HTTP<br/>Timeout: 30s<br/>Connection Draining: 60s]
        HC[Health Check<br/>TCP:8070<br/>Interval: 10s<br/>Timeout: 5s]
        URLMAP[URL Map<br/>Default Service Routing]
        PROXY_HTTP[HTTP Proxy<br/>Port 80]
        PROXY_HTTPS[HTTPS Proxy<br/>Port 443]
        SSL[Managed SSL Certificate<br/>Google-managed]
        FWD_HTTP[Forwarding Rule HTTP:80]
        FWD_HTTPS[Forwarding Rule HTTPS:443]
        IP[Global Static IP<br/>External Address]
    end
    
    BOOT --> STARTUP
    STARTUP --> IMAGE
    IMAGE --> PORTS
    IMAGE --> ENV
    IMAGE --> VOLUMES
    
    IG --> BACKEND
    HC --> BACKEND
    BACKEND --> URLMAP
    URLMAP --> PROXY_HTTP
    URLMAP --> PROXY_HTTPS
    SSL --> PROXY_HTTPS
    PROXY_HTTP --> FWD_HTTP
    PROXY_HTTPS --> FWD_HTTPS
    FWD_HTTP --> IP
    FWD_HTTPS --> IP
    
    style IMAGE fill:#34a853,color:#fff
    style BACKEND fill:#4285f4,color:#fff
    style IP fill:#ea4335,color:#fff
```

### Docker Container Startup Flow

```mermaid
sequenceDiagram
    participant GCE as GCE Instance
    participant STARTUP as Startup Script
    participant DOCKER as Docker Engine
    participant FILESTORE as Cloud Filestore
    participant SQL as Cloud SQL
    participant CONTAINER as IQ Container
    
    GCE->>STARTUP: Boot Instance
    STARTUP->>STARTUP: Install Docker Engine
    STARTUP->>STARTUP: Install NFS Client
    STARTUP->>FILESTORE: Mount NFS (vers=3)
    FILESTORE-->>STARTUP: Mounted at /mnt/sonatype-work
    STARTUP->>STARTUP: Create Directories<br/>(sonatype-work/, logs/)
    STARTUP->>STARTUP: Generate docker-entrypoint.sh<br/>(config.yml with DB creds)
    STARTUP->>DOCKER: Pull sonatype/nexus-iq-server:latest
    DOCKER-->>STARTUP: Image Downloaded
    STARTUP->>DOCKER: docker run -d<br/>--name nexus-iq-server<br/>--restart always<br/>-p 8070:8070 -p 8071:8071<br/>-e DB_HOST, DB_PASSWORD, etc.<br/>-v /mnt/sonatype-work:/sonatype-work
    DOCKER->>CONTAINER: Start Container
    CONTAINER->>CONTAINER: Execute docker-entrypoint.sh<br/>(Generate config.yml)
    CONTAINER->>SQL: Connect to Database
    SQL-->>CONTAINER: Connection Established
    CONTAINER->>CONTAINER: Start Nexus IQ Server<br/>java -jar nexus-iq-server.jar
    CONTAINER-->>GCE: Port 8070, 8071 Ready
```

## 4. Data Persistence

```mermaid
graph TD
    subgraph "Database Layer"
        subgraph "Cloud SQL: nexus-iq-db"
            DB_CONFIG[Configuration<br/>PostgreSQL 17<br/>db-perf-optimized-N-8<br/>8 vCPU, ENTERPRISE_PLUS<br/>100GB PD-SSD<br/>Auto-resize enabled]
            DB_HA[Availability<br/>ZONAL or REGIONAL<br/>Private IP Only<br/>SSL: ENCRYPTED_ONLY]
            DB_BACKUP[Backup Configuration<br/>Automated Daily Backups<br/>7-day Retention<br/>Point-in-Time Recovery<br/>Transaction Log: 7 days]
            DB_MAINT[Maintenance Window<br/>Sunday 04:00<br/>Update Track: Stable]
            DB_INSIGHTS[Query Insights<br/>Performance Monitoring<br/>Query String Length: 1024<br/>Record Client Address]
        end
    end
    
    subgraph "File Storage Layer"
        subgraph "Cloud Filestore: nexus-iq-filestore"
            FS_CONFIG[Configuration<br/>BASIC_SSD Tier<br/>2.5TB Capacity<br/>Share: nexus_iq_data<br/>Protocol: NFS v3]
            FS_ACCESS[Access Control<br/>IP Range: Private Subnet<br/>Mode: READ_WRITE<br/>Squash: NO_ROOT_SQUASH]
            FS_NETWORK[Network<br/>VPC Peered<br/>Private IP<br/>MODE_IPV4]
            FS_MOUNT[Mount Points<br/>/mnt/sonatype-work/sonatype-work<br/>/mnt/sonatype-work/logs]
        end
    end
    
    subgraph "Secrets Management"
        SM[Secret Manager<br/>nexus-iq-db-credentials<br/>JSON: username, password,<br/>host, port, database]
    end
    
    DB_CONFIG --> DB_HA
    DB_HA --> DB_BACKUP
    DB_BACKUP --> DB_MAINT
    DB_MAINT --> DB_INSIGHTS
    
    FS_CONFIG --> FS_ACCESS
    FS_ACCESS --> FS_NETWORK
    FS_NETWORK --> FS_MOUNT
    
    style DB_CONFIG fill:#fbbc04,color:#fff
    style FS_CONFIG fill:#ea4335,color:#fff
    style SM fill:#9c27b0,color:#fff
```

### Storage Allocation

```mermaid
pie title Storage Distribution (Total: ~2.7TB)
    "Cloud Filestore (Application Data)" : 2500
    "Cloud SQL (Database)" : 100
    "GCE Boot Disk" : 100
```

## 5. Operational Excellence

```mermaid
graph TB
    subgraph "Monitoring & Logging"
        subgraph "Cloud Logging"
            LOG_STARTUP[Startup Script Logs<br/>Serial Console Output]
            LOG_DOCKER[Docker Container Logs<br/>Application Logs]
            LOG_LB[Load Balancer Logs<br/>Request/Response Logs]
            LOG_SQL[Cloud SQL Logs<br/>Query Performance]
        end
        
        subgraph "Cloud Monitoring"
            MON_GCE[GCE Instance Metrics<br/>CPU, Memory, Disk, Network]
            MON_SQL[Cloud SQL Metrics<br/>Connections, Queries, Replication]
            MON_FS[Filestore Metrics<br/>IOPS, Throughput, Capacity]
            MON_LB[Load Balancer Metrics<br/>Request Rate, Latency, Health]
        end
    end
    
    subgraph "Automation & IAM"
        subgraph "Service Accounts"
            SA_IQ[nexus-iq-service<br/>Roles: cloudsql.client,<br/>secretmanager.secretAccessor,<br/>logging.logWriter,<br/>file.editor,<br/>monitoring.metricWriter]
            SA_DB[nexus-iq-database<br/>Roles: logging.logWriter,<br/>monitoring.metricWriter]
        end
        
        subgraph "Deployment Scripts"
            SCRIPT_PLAN[gcp-plan.sh<br/>Preview Changes]
            SCRIPT_APPLY[gcp-apply.sh<br/>Deploy Infrastructure]
            SCRIPT_DESTROY[destroy.sh<br/>Cleanup Resources]
        end
    end
    
    LOG_STARTUP --> MON_GCE
    LOG_DOCKER --> MON_GCE
    LOG_LB --> MON_LB
    LOG_SQL --> MON_SQL
    
    SA_IQ --> SCRIPT_APPLY
    SA_DB --> SCRIPT_APPLY
    
    style LOG_STARTUP fill:#e8f5e9
    style MON_GCE fill:#e3f2fd
    style SA_IQ fill:#fff3e0
```

### Disaster Recovery Strategy

```mermaid
graph LR
    subgraph "Backup Components"
        B1[Cloud SQL<br/>Automated Backups<br/>7-day retention]
        B2[Cloud SQL<br/>Point-in-Time Recovery<br/>7-day transaction logs]
        B3[Cloud Filestore<br/>Snapshot Support<br/>Manual/Scheduled]
        B4[Terraform State<br/>Infrastructure as Code<br/>Version Control]
    end
    
    subgraph "Recovery Process"
        R1[Restore SQL<br/>from Backup]
        R2[Deploy Infrastructure<br/>terraform apply]
        R3[Mount Filestore<br/>Automatic via Terraform]
        R4[Start IQ Server<br/>Automatic via Startup Script]
    end
    
    B1 --> R1
    B2 --> R1
    B3 --> R3
    B4 --> R2
    R1 --> R4
    R2 --> R3
    R3 --> R4
    
    style B1 fill:#4285f4,color:#fff
    style R4 fill:#34a853,color:#fff
```

## 6. Resource Naming Convention

All resources use the prefix `ref-arch-iq-` or `nexus-iq-` for easy identification:

| Component | Resource Name | Purpose |
|-----------|---------------|---------|
| **Networking** |
| VPC | `ref-arch-iq-vpc` | Isolated network environment |
| Public Subnet | `ref-arch-iq-public-subnet` | Load balancer placement |
| Private Subnet | `ref-arch-iq-private-subnet` | GCE instances |
| Database Subnet | `ref-arch-iq-db-subnet` | Cloud SQL isolation |
| Cloud Router | `ref-arch-iq-router` | Cloud NAT routing |
| Cloud NAT | `ref-arch-iq-nat` | Outbound internet access |
| **Compute** |
| GCE Instance | `nexus-iq-server` | Docker host |
| Instance Group | `nexus-iq-instance-group` | Load balancer backend |
| Machine Type | `e2-standard-8` | 8 vCPU, 32GB RAM |
| **Load Balancing** |
| Global IP | `nexus-iq-lb-ip` | Static external IP |
| Backend Service | `nexus-iq-backend` | Traffic distribution |
| Health Check | `nexus-iq-lb-health-check` | TCP probe on port 8070 |
| URL Map | `nexus-iq-url-map` | Request routing |
| HTTP Proxy | `nexus-iq-http-proxy` | HTTP traffic handling |
| HTTPS Proxy | `nexus-iq-https-proxy` | HTTPS traffic handling |
| Forwarding Rule HTTP | `nexus-iq-http-forwarding-rule` | Port 80 forwarding |
| Forwarding Rule HTTPS | `nexus-iq-https-forwarding-rule` | Port 443 forwarding |
| SSL Certificate | `nexus-iq-ssl-cert` | Managed SSL certificate |
| **Storage** |
| Cloud SQL Instance | `nexus-iq-db-<random>` | PostgreSQL database |
| Database | `nexusiq` | Application database |
| Filestore Instance | `nexus-iq-filestore` | NFS shared storage |
| File Share | `nexus_iq_data` | Shared data volume |
| **Security** |
| Service Account (IQ) | `nexus-iq-service` | GCE instance identity |
| Service Account (DB) | `nexus-iq-database` | Database operations |
| Secret | `nexus-iq-db-credentials` | Database credentials |
| Firewall Rules | `nexus-iq-*`, `allow-*` | Network access control |

## 7. Docker Container Architecture

```mermaid
graph TD
    subgraph "Docker Container: sonatype/nexus-iq-server:latest"
        subgraph "Container Runtime"
            ENTRYPOINT[Custom Entrypoint<br/>/docker-entrypoint.sh]
            CONFIG_GEN[Generate config.yml<br/>Substitute environment variables<br/>Database configuration]
            JAVA_APP[Start Application<br/>java -jar nexus-iq-server.jar<br/>-c /etc/nexus-iq-server/config.yml]
        end
        
        subgraph "Environment Variables"
            ENV_DB[DB_HOST, DB_PORT<br/>DB_NAME, DB_USERNAME<br/>DB_PASSWORD]
            ENV_JAVA[JAVA_OPTS<br/>-Xmx48g -Xms48g<br/>-Djava.util.prefs.userRoot]
            ENV_SECURITY[NEXUS_SECURITY_RANDOMPASSWORD=false]
        end
        
        subgraph "Volume Mounts"
            VOL_WORK[/sonatype-work<br/>← /mnt/sonatype-work/sonatype-work<br/>Application data, config, work]
            VOL_LOGS[/var/log/nexus-iq-server<br/>← /mnt/sonatype-work/logs<br/>Application logs]
        end
        
        subgraph "Exposed Ports"
            PORT_APP[Port 8070<br/>Application HTTP]
            PORT_ADMIN[Port 8071<br/>Admin HTTP]
        end
    end
    
    ENTRYPOINT --> CONFIG_GEN
    CONFIG_GEN --> JAVA_APP
    
    ENV_DB --> CONFIG_GEN
    ENV_JAVA --> JAVA_APP
    ENV_SECURITY --> JAVA_APP
    
    VOL_WORK --> JAVA_APP
    VOL_LOGS --> JAVA_APP
    
    JAVA_APP --> PORT_APP
    JAVA_APP --> PORT_ADMIN
    
    style ENTRYPOINT fill:#4285f4,color:#fff
    style JAVA_APP fill:#34a853,color:#fff
    style VOL_WORK fill:#ea4335,color:#fff
```

### Docker Container Lifecycle

```mermaid
stateDiagram-v2
    [*] --> ImagePull: docker pull
    ImagePull --> ContainerCreate: docker run -d
    ContainerCreate --> EntrypointExec: Execute entrypoint
    EntrypointExec --> ConfigGen: Generate config.yml
    ConfigGen --> JavaStart: Start IQ Server
    JavaStart --> Running: Listening on 8070, 8071
    Running --> HealthCheck: TCP Probe :8070
    HealthCheck --> Running: Healthy
    HealthCheck --> Unhealthy: Failed
    Unhealthy --> Restart: --restart always
    Restart --> EntrypointExec
    Running --> Stopped: docker stop
    Stopped --> [*]
```

## 8. Cost Optimization

```mermaid
graph TB
    subgraph "Monthly Cost Breakdown (us-central1)"
        C1[GCE Instance<br/>e2-standard-8<br/>~$240/month]
        C2[Cloud SQL<br/>db-perf-optimized-N-8<br/>ENTERPRISE_PLUS<br/>~$1,200/month]
        C3[Cloud Filestore<br/>BASIC_SSD 2.5TB<br/>~$500/month]
        C4[Global Load Balancer<br/>Forwarding Rules + Traffic<br/>~$20/month]
        C5[Network Egress<br/>Estimated traffic<br/>~$50/month]
        C6[Cloud Logging & Monitoring<br/>Standard metrics<br/>~$10/month]
        
        TOTAL[Total Monthly Cost<br/>~$2,020/month]
    end
    
    C1 --> TOTAL
    C2 --> TOTAL
    C3 --> TOTAL
    C4 --> TOTAL
    C5 --> TOTAL
    C6 --> TOTAL
    
    subgraph "Cost Optimization Options"
        O1[Reduce Filestore to 1TB BASIC_SSD<br/>Save ~$300/month]
        O2[Use db-custom-8-32768 ENTERPRISE<br/>Save ~$600/month]
        O3[Reduce GCE to e2-standard-4<br/>Save ~$120/month]
        O4[Schedule instance stop non-business hours<br/>Save ~50% on compute]
        O5[Use committed use discounts<br/>Save ~30% on compute & SQL]
        
        SAVINGS[Potential Savings<br/>~$1,020/month<br/>Total: ~$1,000/month]
    end
    
    O1 --> SAVINGS
    O2 --> SAVINGS
    O3 --> SAVINGS
    O4 --> SAVINGS
    O5 --> SAVINGS
    
    style TOTAL fill:#ea4335,color:#fff
    style SAVINGS fill:#34a853,color:#fff
```

## 9. Health Check and Load Balancing Flow

```mermaid
sequenceDiagram
    participant User as User/Client
    participant GLB as Global Load Balancer
    participant HC as Health Check
    participant IG as Instance Group
    participant GCE as GCE Instance
    participant DOCKER as Docker Container
    
    User->>GLB: HTTP Request<br/>http://EXTERNAL_IP/
    GLB->>GLB: Check Backend Health
    
    par Health Check Loop
        loop Every 10 seconds
            HC->>GCE: TCP Probe :8070
            GCE->>DOCKER: Forward to Container
            DOCKER-->>GCE: SYN-ACK (Healthy)
            GCE-->>HC: Healthy Response
            HC->>GLB: Mark Backend Healthy
        end
    end
    
    GLB->>IG: Route to Instance Group
    IG->>GCE: Forward to Named Port :8070
    GCE->>DOCKER: Container Port 8070
    DOCKER->>DOCKER: Process Request
    DOCKER-->>GCE: HTTP Response
    GCE-->>IG: Response
    IG-->>GLB: Response
    GLB-->>User: HTTP Response
    
    Note over HC,DOCKER: Health Check: TCP:8070<br/>Interval: 10s, Timeout: 5s<br/>Healthy Threshold: 2<br/>Unhealthy Threshold: 3
```

## 10. Security Architecture

```mermaid
graph TB
    subgraph "Defense in Depth"
        subgraph "Layer 1: Network Perimeter"
            L1_FW[Firewall Rules<br/>VPC Firewall]
            L1_LB[Global Load Balancer<br/>DDoS Protection]
        end
        
        subgraph "Layer 2: Compute Security"
            L2_NOEXT[No External IP<br/>Private Subnet Only]
            L2_SA[Service Account<br/>Least Privilege IAM]
            L2_NAT[Cloud NAT<br/>Controlled Egress]
        end
        
        subgraph "Layer 3: Data Security"
            L3_SQL[Cloud SQL<br/>Private IP, SSL Required<br/>Encrypted at Rest]
            L3_FS[Filestore<br/>VPC Private Access<br/>Encrypted]
            L3_SM[Secret Manager<br/>Database Credentials<br/>Encrypted, Access Controlled]
        end
        
        subgraph "Layer 4: Application Security"
            L4_DOCKER[Docker Container<br/>Official Sonatype Image<br/>Isolated Runtime]
            L4_CONFIG[Config Management<br/>Environment Variables<br/>Generated config.yml]
        end
        
        subgraph "Layer 5: Monitoring & Audit"
            L5_LOG[Cloud Logging<br/>Audit Logs, Access Logs]
            L5_MON[Cloud Monitoring<br/>Anomaly Detection]
        end
    end
    
    L1_FW --> L2_NOEXT
    L1_LB --> L2_NOEXT
    L2_NOEXT --> L3_SQL
    L2_SA --> L3_SM
    L2_NAT --> L4_DOCKER
    L3_SQL --> L4_CONFIG
    L3_FS --> L4_CONFIG
    L3_SM --> L4_CONFIG
    L4_DOCKER --> L5_LOG
    L4_CONFIG --> L5_MON
    
    style L1_FW fill:#e3f2fd
    style L2_NOEXT fill:#e8f5e9
    style L3_SQL fill:#fff3e0
    style L4_DOCKER fill:#fce4ec
    style L5_LOG fill:#f3e5f5
```

### IAM Role Hierarchy

```mermaid
graph LR
    subgraph "Service Account: nexus-iq-service"
        R1[roles/cloudsql.client<br/>Connect to Cloud SQL]
        R2[roles/secretmanager.secretAccessor<br/>Read database credentials]
        R3[roles/logging.logWriter<br/>Write application logs]
        R4[roles/file.editor<br/>Access Filestore]
        R5[roles/monitoring.metricWriter<br/>Write custom metrics]
    end
    
    subgraph "Service Account: nexus-iq-database"
        R6[roles/logging.logWriter<br/>Write database logs]
        R7[roles/monitoring.metricWriter<br/>Write database metrics]
    end
    
    GCE[GCE Instance<br/>nexus-iq-server] --> R1
    GCE --> R2
    GCE --> R3
    GCE --> R4
    GCE --> R5
    
    SQL[Cloud SQL<br/>nexus-iq-db] --> R6
    SQL --> R7
    
    style GCE fill:#34a853,color:#fff
    style SQL fill:#fbbc04,color:#fff
```

## 11. Deployment Workflow

```mermaid
graph TD
    START[Start Deployment] --> INIT[terraform init]
    INIT --> PLAN[terraform plan<br/>Review changes]
    PLAN --> APPLY[terraform apply<br/>Create resources]
    
    APPLY --> API[Enable GCP APIs<br/>compute, sqladmin, file, etc.]
    API --> VPC[Create VPC & Subnets<br/>Public, Private, Database]
    VPC --> NAT[Create Cloud Router & NAT<br/>Internet gateway]
    NAT --> FW[Create Firewall Rules<br/>allow-internal, allow-ssh, etc.]
    FW --> SA[Create Service Accounts<br/>nexus-iq-service, nexus-iq-database]
    SA --> IAM[Assign IAM Roles<br/>cloudsql.client, secretmanager.accesseor, etc.]
    IAM --> FS[Create Cloud Filestore<br/>BASIC_SSD 2.5TB NFS share]
    FS --> SQL[Create Cloud SQL<br/>PostgreSQL 17 ENTERPRISE_PLUS]
    SQL --> SM[Store Credentials in Secret Manager<br/>nexus-iq-db-credentials]
    SM --> GCE[Create GCE Instance<br/>e2-standard-8 Debian 12]
    GCE --> STARTUP[Execute Startup Script<br/>Install Docker, Mount Filestore, Launch Container]
    STARTUP --> DOCKER[Docker Container Running<br/>nexus-iq-server:latest]
    DOCKER --> IG[Create Instance Group<br/>Add GCE instance]
    IG --> HEALTH[Create Health Check<br/>TCP:8070]
    HEALTH --> BACKEND[Create Backend Service<br/>Add instance group]
    BACKEND --> LB[Create Load Balancer<br/>Global IP, URL Map, Proxies, Forwarding Rules]
    LB --> SSL{SSL Enabled?}
    SSL -->|Yes| CERT[Create Managed SSL Certificate<br/>domain_name]
    SSL -->|No| READY[Deployment Complete]
    CERT --> READY
    
    READY --> OUTPUT[terraform output<br/>load_balancer_ip, nexus_iq_url]
    OUTPUT --> ACCESS[Access Nexus IQ Server<br/>http://EXTERNAL_IP<br/>admin/admin123]
    
    style START fill:#4285f4,color:#fff
    style DOCKER fill:#34a853,color:#fff
    style READY fill:#ea4335,color:#fff
    style ACCESS fill:#fbbc04,color:#fff
```

## 12. Version Management & Updates

```mermaid
graph LR
    subgraph "Update Methods"
        M1[Method 1: Terraform<br/>Update terraform.tfvars<br/>terraform apply<br/>Recreate instance]
        M2[Method 2: Rolling Update<br/>SSH to instance<br/>Pull new image<br/>Restart container]
        M3[Method 3: Quick Restart<br/>gcloud compute ssh<br/>sudo reboot<br/>Startup script runs]
    end
    
    subgraph "Version Sources"
        DOCKER_HUB[Docker Hub<br/>hub.docker.com/r/sonatype/nexus-iq-server]
        TAGS[Available Tags<br/>latest, 1.196.0, 1.197.0, etc.]
    end
    
    subgraph "Deployment Flow"
        PULL[docker pull<br/>sonatype/nexus-iq-server:TAG]
        STOP[docker stop nexus-iq-server]
        RM[docker rm nexus-iq-server]
        RUN[docker run<br/>New container with new image]
        VERIFY[Verify application<br/>docker logs, docker ps]
    end
    
    DOCKER_HUB --> TAGS
    TAGS --> M1
    TAGS --> M2
    TAGS --> M3
    
    M1 --> PULL
    M2 --> PULL
    M3 --> PULL
    
    PULL --> STOP
    STOP --> RM
    RM --> RUN
    RUN --> VERIFY
    
    style DOCKER_HUB fill:#4285f4,color:#fff
    style RUN fill:#34a853,color:#fff
    style VERIFY fill:#fbbc04,color:#fff
```

## Summary

This GCP reference architecture provides:

- **Cloud-Native Design**: Leveraging GCE with Docker, Cloud SQL, and Cloud Filestore
- **Security Best Practices**: VPC isolation, private networking, IAM roles, Secret Manager
- **Operational Excellence**: Cloud Logging, Cloud Monitoring, automated backups
- **Cost Optimization**: Right-sized resources, flexible scaling options
- **Reliability**: Health checks, automated backups, disaster recovery

**This single-instance Docker-based architecture delivers excellent performance, security, and operational efficiency for Nexus IQ Server deployments on Google Cloud Platform.**
