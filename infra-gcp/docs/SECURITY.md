# Nexus IQ Server - GCP Security Guide

This document outlines the comprehensive security implementation, best practices, and compliance features of the Nexus IQ Server deployment on Google Cloud Platform.

## 🔒 Security Architecture Overview

### Defense in Depth Strategy

```
┌─────────────────────────────────────────────────────┐
│                 Internet Layer                      │
│  • DDoS Protection (Cloud Armor)                   │
│  • Geographic Filtering                             │
│  • Rate Limiting                                    │
└─────────────────┬───────────────────────────────────┘
                  │
┌─────────────────┼───────────────────────────────────┐
│            Network Layer                            │
│  • WAF Rules (OWASP Top 10)                       │
│  • SSL/TLS Termination                             │
│  • IP Allowlisting                                 │
└─────────────────┬───────────────────────────────────┘
                  │
┌─────────────────┼───────────────────────────────────┐
│          Application Layer                          │
│  • Container Security                               │
│  • Secret Management                                │
│  • Identity & Access Management                     │
└─────────────────┬───────────────────────────────────┘
                  │
┌─────────────────┼───────────────────────────────────┐
│             Data Layer                              │
│  • Encryption at Rest                               │
│  • Encryption in Transit                            │
│  • Database Security                                │
└─────────────────────────────────────────────────────┘
```

## 🌐 Network Security

### VPC Security Configuration

#### Network Isolation
```yaml
VPC Configuration:
  Private Subnets: All application components
  Public Subnet: Load balancer only
  Network Segmentation: Separate subnets per tier
  
Private Google Access:
  Enabled: True
  Purpose: Access Google APIs without public IPs
  
VPC Peering:
  Enabled: False (not required)
  Alternative: Private Service Connect
```

#### Firewall Rules (Security Groups Equivalent)

##### Ingress Rules
```yaml
allow-lb-to-cloudrun:
  Direction: Ingress
  Priority: 1000
  Source Ranges: 
    - 130.211.0.0/22  # Google health check
    - 35.191.0.0/16   # Google health check
  Target Tags: nexus-iq-service
  Ports: 8070, 8071
  Protocol: TCP
  
allow-internal-nexus-iq:
  Direction: Ingress
  Priority: 1100
  Source Ranges:
    - 10.100.10.0/24  # Private subnet
    - 10.100.20.0/24  # Database subnet
  Ports: 8070, 8071, 5432, 2049
  Protocols: TCP, UDP, ICMP
  
allow-web-traffic-nexus-iq:
  Direction: Ingress
  Priority: 1200
  Source Ranges: 0.0.0.0/0
  Target Tags: nexus-iq-lb
  Ports: 80, 443
  Protocol: TCP
```

##### Egress Rules
```yaml
allow-egress-cloudrun:
  Direction: Egress
  Priority: 1000
  Target Tags: nexus-iq-service
  Destination Ranges: 0.0.0.0/0
  Ports: 80, 443, 587, 25, 53
  Protocols: TCP, UDP
  Purpose: External API access, updates, email
  
allow-google-apis:
  Direction: Egress
  Priority: 1100
  Destination Ranges:
    - 199.36.153.8/30   # restricted.googleapis.com
    - 199.36.153.4/30   # private.googleapis.com
  Ports: 443
  Protocol: TCP
```

##### Default Deny Rule
```yaml
deny-all-nexus-iq:
  Direction: Ingress
  Priority: 65534
  Source Ranges: 0.0.0.0/0
  Action: Deny
  Protocol: All
  Purpose: Explicit deny for unmatched traffic
```

### Cloud Armor WAF Configuration

#### Core Security Policies

##### Rate Limiting Rules
```yaml
rate-limiting-rule:
  Priority: 1000
  Action: rate_based_ban
  Rate Limit:
    Threshold: 100 requests/minute per IP
    Ban Duration: 600 seconds (10 minutes)
    Conform Action: Allow
    Exceed Action: Deny (429)
  
ddos-protection:
  Priority: 700
  Action: rate_based_ban
  Rate Limit:
    Threshold: 50 requests/minute per IP
    Ban Duration: 300 seconds (5 minutes)
    Advanced: Adaptive protection enabled
```

##### Geographic Filtering
```yaml
geo-blocking-rule:
  Priority: 600
  Action: Deny (403)
  Expression: >
    origin.region_code == 'CN' ||
    origin.region_code == 'RU' ||
    origin.region_code == 'KP'
  Description: Block high-risk countries
  Configurable: Via terraform.tfvars
```

##### OWASP Protection Rules
```yaml
owasp-protection:
  Priority: 800
  Action: Deny (403)
  Preconfigured Rules:
    - XSS (Cross-site scripting)
    - SQLi (SQL injection)
    - LFI (Local file inclusion)
    - RFI (Remote file inclusion)
    - RCE (Remote code execution)
    - Method enforcement
  Expression: >
    evaluatePreconfiguredExpr('xss-stable') ||
    evaluatePreconfiguredExpr('sqli-stable') ||
    evaluatePreconfiguredExpr('lfi-stable') ||
    evaluatePreconfiguredExpr('rfi-stable') ||
    evaluatePreconfiguredExpr('rce-stable') ||
    evaluatePreconfiguredExpr('methodenforcement-stable')
```

##### Custom Security Rules
```yaml
block-malicious-ips:
  Priority: 500
  Action: Deny (403)
  Source IPs: Configurable blocklist
  Purpose: Known malicious IP ranges
  
header-validation:
  Priority: 900
  Action: Deny (403)
  Expression: >
    !has(request.headers['user-agent']) ||
    request.headers['user-agent'].size() > 512 ||
    request.headers['user-agent'].contains('sqlmap') ||
    request.headers['user-agent'].contains('nikto')
  Purpose: Block suspicious user agents
```

## 🔐 Identity & Access Management

### Service Account Security

#### Principle of Least Privilege
```yaml
nexus-iq-service:
  Purpose: Main application service account
  Roles:
    - roles/cloudsql.client           # Database access only
    - roles/secretmanager.secretAccessor  # Secrets access only
    - roles/logging.logWriter         # Write logs only
    - roles/monitoring.metricWriter   # Write metrics only
    - roles/storage.admin            # Backup bucket access
    - roles/file.editor              # Filestore access
    - roles/cloudkms.cryptoKeyEncrypterDecrypter  # KMS access
  
nexus-iq-lb:
  Purpose: Load balancer service account
  Roles:
    - roles/run.invoker              # Invoke Cloud Run only
    - roles/logging.logWriter        # Write access logs
    
nexus-iq-monitoring:
  Purpose: Monitoring service account
  Roles:
    - roles/logging.viewer           # Read logs
    - roles/monitoring.viewer        # Read metrics
    - roles/compute.viewer           # View compute resources
```

#### Custom IAM Role
```yaml
nexusIqOperator:
  Title: Nexus IQ Operator
  Description: Custom role for Nexus IQ operations
  Permissions:
    - cloudsql.instances.get
    - cloudsql.instances.list
    - cloudsql.databases.get
    - cloudsql.databases.list
    - run.services.get
    - run.services.list
    - storage.buckets.get
    - storage.objects.create
    - storage.objects.delete
    - storage.objects.get
    - storage.objects.list
    - secretmanager.versions.access
    - file.instances.get
    - file.snapshots.create
    - monitoring.timeSeries.create
    - logging.logEntries.create
```

### User Access Management

#### Administrative Access
```yaml
Admin Users:
  Roles:
    - roles/compute.admin
    - roles/cloudsql.admin
    - roles/run.admin
    - roles/storage.admin
    - roles/secretmanager.admin
  Authentication: Google SSO required
  MFA: Enforced
  
Developer Users:
  Roles:
    - roles/compute.viewer
    - roles/cloudsql.viewer
    - roles/run.viewer
    - roles/logging.viewer
    - roles/monitoring.viewer
  Authentication: Google SSO required
  Access: Read-only for troubleshooting
```

#### Workload Identity (Optional)
```yaml
Kubernetes Integration:
  Service Account: nexus-iq-service
  Namespace: nexus-iq
  Binding: Workload Identity enabled
  Purpose: Future Kubernetes migration path
```

## 🔑 Encryption & Key Management

### Encryption at Rest

#### Cloud KMS Configuration
```yaml
Key Ring: nexus-iq-keyring
Location: us-central1
Keys:
  nexus-iq-storage-key:
    Purpose: Cloud Storage encryption
    Algorithm: GOOGLE_SYMMETRIC_ENCRYPTION
    Rotation: 90 days
    Protection Level: SOFTWARE
    
  nexus-iq-database-key:
    Purpose: Cloud SQL encryption (optional CMEK)
    Algorithm: GOOGLE_SYMMETRIC_ENCRYPTION
    Rotation: 90 days
    Protection Level: SOFTWARE
    
IAM Bindings:
  Storage Service Account:
    - roles/cloudkms.cryptoKeyEncrypterDecrypter
  SQL Service Account:
    - roles/cloudkms.cryptoKeyEncrypterDecrypter
```

#### Data Encryption Coverage
```yaml
Cloud SQL:
  Method: Google-managed + CMEK (optional)
  Algorithm: AES-256
  Scope: Database files, backups, logs
  
Cloud Storage:
  Method: CMEK required
  Algorithm: AES-256
  Scope: Application backups, logs, configs
  
Cloud Filestore:
  Method: Google-managed
  Algorithm: AES-256
  Scope: NFS data
  
Secret Manager:
  Method: Google-managed
  Algorithm: AES-256
  Scope: Database credentials, API keys
```

### Encryption in Transit

#### TLS Configuration
```yaml
Client to Load Balancer:
  Protocol: TLS 1.2+ only
  Cipher Suites: Strong ciphers only
  Certificate: Google-managed SSL
  HSTS: Enabled
  
Load Balancer to Cloud Run:
  Protocol: HTTP/2 over Google backbone
  Encryption: Automatic (Google infrastructure)
  
Cloud Run to Cloud SQL:
  Protocol: TLS with Cloud SQL Proxy
  Certificate Validation: Required
  
Internal Communications:
  Method: Google backbone encryption
  Algorithm: AES encryption in transit
```

## 🛡️ Container Security

### Binary Authorization (Optional)

#### Policy Configuration
```yaml
Admission Policy:
  Evaluation Mode: REQUIRE_ATTESTATION
  Enforcement Mode: ENFORCED_BLOCK_AND_AUDIT_LOG
  
Attestor Configuration:
  Name: nexus-iq-attestor
  Public Key: PGP key for image signing
  Authority: Container Analysis Note
  
Allowlist Patterns:
  - gcr.io/PROJECT_ID/*
  - us.gcr.io/PROJECT_ID/*
  
Blocked: All unsigned images
```

#### Container Image Security
```yaml
Base Image Scanning:
  Enabled: Container Analysis API
  Frequency: On push and daily
  Vulnerabilities: Critical and High blocked
  
Image Attestation:
  Required: Production deployments
  Method: PGP signature verification
  Authority: Designated signing key
  
Registry Security:
  Private Registry: Recommended
  Access Control: IAM-based
  Vulnerability Scanning: Automatic
```

### Runtime Security
```yaml
Cloud Run Security Context:
  Run as Non-root: Enforced
  Read-only Root Filesystem: Recommended
  Resource Limits: CPU and memory capped
  
Security Policies:
  Network Policies: VPC firewall rules
  Pod Security: Cloud Run security model
  Secrets Management: Secret Manager integration
```

## 💾 Data Security

### Database Security

#### Cloud SQL Security Features
```yaml
Network Security:
  Private IP: Required (no public IP)
  SSL/TLS: Required for all connections
  Authorized Networks: VPC subnets only
  
Authentication:
  Database Users: Strong passwords required
  Service Accounts: IAM-based authentication
  Connection: Cloud SQL Proxy required
  
Auditing:
  Query Logs: Enabled for security events
  Connection Logs: All connections logged
  Failed Attempts: Logged and monitored
  
Backup Security:
  Encryption: At rest encryption
  Retention: 7 days minimum
  Cross-region: Optional for DR
```

#### Database Hardening
```yaml
PostgreSQL Configuration:
  ssl: on
  log_connections: on
  log_disconnections: on
  log_checkpoints: on
  log_statement: 'mod'  # Log modifications
  
Password Policy:
  Minimum Length: 12 characters
  Complexity: Mixed case, numbers, symbols
  Rotation: 90 days recommended
  
Connection Limits:
  Max Connections: Configured per instance size
  Idle Timeout: 600 seconds
  Statement Timeout: 300 seconds
```

### File Storage Security

#### Filestore Security
```yaml
Access Control:
  Network: Private VPC only
  Protocol: NFSv3 with security
  Export Options:
    - IP Ranges: Private subnet only
    - Access Mode: READ_WRITE
    - Squash Mode: NO_ROOT_SQUASH
    - Anonymous UID: 65534
    
Encryption:
  At Rest: Google-managed keys
  In Transit: NFS over secure network
  
Backup:
  Snapshots: Manual and automated
  Retention: 30 days default
  Cross-region: Optional
```

#### Cloud Storage Security
```yaml
Bucket Configuration:
  Public Access: Blocked (uniform bucket-level access)
  IAM: Principle of least privilege
  Versioning: Enabled
  
Lifecycle Management:
  Backup Retention: 30 days
  Log Retention: 90 days
  Automatic Deletion: Old versions
  
Access Logging:
  Enabled: All bucket access
  Destination: Separate logging bucket
  Retention: 365 days
```

## 🔍 Security Monitoring & Auditing

### Audit Logging

#### Comprehensive Audit Trail
```yaml
Admin Activity Logs:
  Scope: All administrative actions
  Retention: 400 days (cannot be disabled)
  Content: Who, what, when, where
  
Data Access Logs:
  Scope: Data read/write operations
  Retention: 30 days (configurable)
  Services: Cloud SQL, Cloud Storage
  
System Events:
  Scope: System-level events
  Retention: 30 days
  Content: Service starts, stops, errors
  
Security Events:
  Scope: Authentication, authorization
  Retention: 90 days
  Alerting: Real-time for critical events
```

#### Log Analysis
```yaml
SIEM Integration:
  Export: Pub/Sub or Cloud Storage
  Format: JSON structured logs
  Destinations: Third-party SIEM tools
  
Automated Analysis:
  Anomaly Detection: Cloud Logging Insights
  Pattern Matching: Log-based metrics
  Alerting: Custom log-based alerts
  
Compliance Reporting:
  Schedule: Monthly automated reports
  Content: Access patterns, policy violations
  Distribution: Security team, compliance
```

### Security Monitoring

#### Real-time Monitoring
```yaml
Security Dashboard:
  Metrics:
    - Failed authentication attempts
    - Unusual access patterns
    - Resource modifications
    - Network anomalies
  
Alert Policies:
  Critical: Immediate notification (email, SMS)
  High: 15-minute notification
  Medium: Daily digest
  
Integration:
  SIEM: Log export for correlation
  SOC: Alert forwarding
  Incident Response: Automated workflows
```

#### Threat Detection
```yaml
Cloud Security Command Center:
  Enabled: Organization level
  Findings: Security misconfigurations
  Assets: Inventory and compliance
  
Custom Detection Rules:
  Brute Force: Multiple failed logins
  Privilege Escalation: Role changes
  Data Exfiltration: Unusual data access
  Lateral Movement: Cross-service access
```

## 📋 Compliance & Standards

### Security Frameworks

#### SOC 2 Type II
```yaml
Trust Principles:
  Security: Access controls, encryption
  Availability: 99.9% uptime SLA
  Processing Integrity: Data accuracy
  Confidentiality: Data protection
  Privacy: PII handling (if applicable)
  
Evidence Collection:
  Automated: Policy compliance checks
  Manual: Quarterly access reviews
  Documentation: All procedures documented
```

#### ISO 27001
```yaml
Security Controls:
  Physical: Google data center security
  Logical: Access controls, encryption
  Administrative: Policies, procedures
  
Risk Management:
  Assessment: Quarterly risk reviews
  Treatment: Risk mitigation plans
  Monitoring: Continuous monitoring
  
Incident Management:
  Detection: Automated and manual
  Response: Defined procedures
  Recovery: Business continuity plans
```

#### NIST Cybersecurity Framework
```yaml
Identify:
  Asset Management: Inventory all resources
  Risk Assessment: Regular vulnerability scans
  Governance: Security policies
  
Protect:
  Access Control: IAM and MFA
  Data Security: Encryption at rest/transit
  Information Protection: DLP policies
  
Detect:
  Anomaly Detection: SIEM and monitoring
  Security Monitoring: 24/7 SOC
  Detection Processes: Incident procedures
  
Respond:
  Response Planning: Incident response plan
  Communications: Stakeholder notification
  Analysis: Forensic capabilities
  
Recover:
  Recovery Planning: Business continuity
  Improvements: Lessons learned
  Communications: Status updates
```

### Regulatory Compliance

#### GDPR (If Applicable)
```yaml
Data Protection:
  Encryption: AES-256 at rest and transit
  Access Controls: Role-based access
  Data Minimization: Only necessary data
  
Privacy Rights:
  Right to Access: Data export capabilities
  Right to Erasure: Data deletion procedures
  Right to Portability: Data export formats
  
Breach Notification:
  Detection: Automated monitoring
  Assessment: 72-hour evaluation
  Notification: Regulatory and individual
```

#### PCI DSS (If Applicable)
```yaml
Requirements:
  Network Security: Firewalls and segmentation
  Cardholder Data: Encryption and access controls
  Vulnerability Management: Regular scanning
  Access Control: Strong authentication
  Monitoring: Logs and file integrity
  
Validation:
  Self-Assessment: Annual questionnaire
  External Scan: Quarterly vulnerability scans
  Penetration Testing: Annual testing
```

## 🚨 Incident Response

### Security Incident Procedures

#### Incident Classification
```yaml
Critical (P1):
  Examples: Data breach, system compromise
  Response Time: 15 minutes
  Escalation: CISO, executive team
  
High (P2):
  Examples: Service disruption, attempted breach
  Response Time: 1 hour
  Escalation: Security team, operations
  
Medium (P3):
  Examples: Policy violation, suspicious activity
  Response Time: 4 hours
  Escalation: Security team
  
Low (P4):
  Examples: Security alerts, minor issues
  Response Time: 24 hours
  Escalation: Security analyst
```

#### Response Workflow
```yaml
Detection:
  Automated: SIEM alerts, monitoring
  Manual: User reports, security team
  
Assessment:
  Triage: Initial classification
  Investigation: Evidence collection
  Impact: Business impact assessment
  
Containment:
  Isolation: Affected systems
  Preservation: Evidence and logs
  Communication: Stakeholder notification
  
Recovery:
  Remediation: Fix vulnerabilities
  Restoration: Service restoration
  Validation: Security verification
  
Lessons Learned:
  Analysis: Root cause analysis
  Improvements: Process enhancements
  Documentation: Incident report
```

## 🛠️ Security Best Practices

### Operational Security

#### Regular Security Tasks
```yaml
Daily:
  - Monitor security alerts
  - Review access logs
  - Check system health
  
Weekly:
  - Security metric reports
  - Vulnerability scan review
  - Access review spot checks
  
Monthly:
  - Full access review
  - Security policy updates
  - Incident response testing
  
Quarterly:
  - Risk assessment update
  - Security training
  - Disaster recovery testing
  
Annually:
  - Penetration testing
  - Security audit
  - Policy comprehensive review
```

#### Security Configuration Management
```yaml
Infrastructure as Code:
  Version Control: All security configs in Git
  Review Process: Pull request reviews
  Approval: Security team sign-off
  
Change Management:
  Documentation: All changes documented
  Testing: Security impact assessment
  Rollback: Automated rollback capability
  
Compliance Checking:
  Automated: Policy compliance scanning
  Manual: Regular configuration audits
  Remediation: Automatic where possible
```

This comprehensive security guide ensures that the Nexus IQ Server deployment on GCP meets enterprise security requirements while maintaining operational efficiency and compliance with industry standards.