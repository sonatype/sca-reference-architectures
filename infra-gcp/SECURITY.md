# Nexus IQ Server GCP Security Guide

This document provides comprehensive security guidance for the Nexus IQ Server deployment on Google Cloud Platform, covering security best practices, configuration recommendations, and compliance considerations.

## Security Architecture Overview

The GCP deployment implements a **defense-in-depth security strategy** with multiple layers of protection:

1. **Edge Security**: Cloud Armor WAF/DDoS protection
2. **Network Security**: VPC isolation, firewall rules, private connectivity
3. **Identity Security**: Service accounts, IAM policies, least privilege access
4. **Application Security**: Container security, secret management
5. **Data Security**: Encryption at rest and in transit, backup security
6. **Operational Security**: Monitoring, alerting, audit logging

## 1. Network Security

### VPC Security Configuration

```hcl
# Secure VPC configuration
resource "google_compute_network" "iq_vpc" {
  name                    = "ref-arch-iq-vpc"
  auto_create_subnetworks = false  # Explicit subnet control
  mtu                     = 1460   # Optimized for GCP
}
```

**Security Benefits:**
- **Custom VPC**: Full control over network topology
- **No auto-subnets**: Explicit subnet design prevents accidental exposure
- **Optimized MTU**: Reduces fragmentation and improves performance

### Subnet Isolation Strategy

```
┌─────────────────────────────────────────────────────────────────┐
│                    NETWORK SECURITY ZONES                      │
└─────────────────────────────────────────────────────────────────┘

Public Zone (10.0.1.0/24)
├── Purpose: Load balancer only
├── Internet Access: Inbound HTTP/HTTPS only
├── Resources: Global Load Balancer (anycast)
└── Security: Cloud Armor protection

Private Zone (10.0.2.0/24)  
├── Purpose: Cloud Run services
├── Internet Access: Outbound only via Cloud NAT
├── Resources: Application containers
└── Security: VPC firewall rules, service accounts

Database Zone (10.0.3.0/24)
├── Purpose: Cloud SQL instances
├── Internet Access: None (private IP only)
├── Resources: PostgreSQL database
└── Security: Private service networking, encryption

Management Zone (10.0.4.0/28)
├── Purpose: VPC Connector
├── Internet Access: None
├── Resources: Serverless VPC access
└── Security: Minimal CIDR, specific routing
```

### Firewall Rules (Least Privilege)

```hcl
# Example: Restrictive database access
resource "google_compute_firewall" "allow_cloudsql_access" {
  name    = "ref-arch-iq-allow-cloudsql"
  network = google_compute_network.iq_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["5432"]
  }

  # Only allow Cloud Run service account
  source_service_accounts = [google_service_account.iq_service_account.email]
  target_tags            = ["cloudsql"]
}
```

**Security Principles Applied:**
- **Default Deny**: Implicit deny-all ingress policy
- **Explicit Allow**: Only required traffic explicitly permitted
- **Service Account Based**: Source/target by service account (not IP)
- **Port Specific**: Minimal port exposure
- **Protocol Specific**: Only required protocols allowed

### Recommended Firewall Configuration

| Rule Name | Source | Target | Ports | Purpose | Priority |
|-----------|--------|--------|-------|---------|----------|
| `allow-lb-access` | 0.0.0.0/0 | LB | 80,443 | Public HTTP/HTTPS | 1000 |
| `allow-health-checks` | Google LB ranges | Services | 8070,8071 | Health checks | 1000 |
| `allow-cloudsql-access` | Cloud Run SA | Database | 5432 | DB connectivity | 1000 |
| `allow-filestore-access` | Cloud Run SA | NFS | 2049 | File storage | 1000 |
| `allow-internal` | VPC CIDRs | VPC | All | Internal comms | 1000 |
| `deny-all-ingress` | 0.0.0.0/0 | All | All | Explicit deny | 65534 |

## 2. Identity and Access Management (IAM)

### Service Account Security

```hcl
# Principle of least privilege service account
resource "google_service_account" "iq_service_account" {
  account_id   = "ref-arch-iq-service"
  display_name = "Nexus IQ Server Service Account"
}

# Minimal required permissions
resource "google_project_iam_member" "iq_cloudsql_client" {
  project = var.gcp_project_id
  role    = "roles/cloudsql.client"  # Database access only
  member  = "serviceAccount:${google_service_account.iq_service_account.email}"
}
```

### IAM Security Best Practices

**1. Service Account Separation**
```
iq-service-account
├── Purpose: Application runtime
├── Permissions: Database, secrets, logging
└── Scope: Minimal required access

lb-service-account  
├── Purpose: Load balancer operations
├── Permissions: Log writing only    
└── Scope: Access logs only
```

**2. Custom IAM Roles**
```hcl
resource "google_project_iam_custom_role" "iq_custom_role" {
  role_id = "ref_arch_iq_custom_role"
  title   = "Nexus IQ Server Custom Role"
  
  permissions = [
    "cloudsql.instances.connect",
    "secretmanager.versions.access",
    "storage.objects.create",      # Backups only
    "storage.objects.get",         # Backups only
    "logging.logEntries.create"
  ]
}
```

**3. IAM Security Checklist**
- [ ] No overprivileged service accounts
- [ ] Regular access reviews (quarterly)
- [ ] Service account key rotation (avoid long-lived keys)
- [ ] Workload Identity where applicable
- [ ] IAM conditions for additional constraints

### Workload Identity Configuration

```hcl
# For future Kubernetes integration
resource "google_service_account_iam_member" "workload_identity_binding" {
  count              = var.enable_workload_identity ? 1 : 0
  service_account_id = google_service_account.iq_service_account.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.gcp_project_id}.svc.id.goog[${var.kubernetes_namespace}/${var.kubernetes_service_account}]"
}
```

## 3. Data Security

### Encryption Strategy

**Encryption at Rest**
```
Database (Cloud SQL)
├── Automatic encryption with Google-managed keys
├── Optional: Customer-managed encryption keys (CMEK)
├── Encrypted backups and replicas
└── Transparent data encryption (TDE)

File Storage (Cloud Filestore)  
├── Automatic encryption at rest
├── Google-managed encryption keys
├── Encrypted snapshots
└── In-transit encryption via TLS

Object Storage (Cloud Storage)
├── Server-side encryption (automatic)
├── Customer-supplied encryption keys (optional)
├── Object versioning with encryption
└── Lifecycle management with encryption
```

**Encryption in Transit**
```
External Traffic
├── TLS 1.2+ enforcement at load balancer
├── Perfect Forward Secrecy (PFS)
├── HSTS headers for HTTPS enforcement
└── Certificate management via Google-managed certs

Internal Traffic
├── Cloud Run ↔ Cloud SQL: SSL/TLS
├── Cloud Run ↔ Cloud Filestore: TLS
├── VPC internal: Google's internal encryption
└── Service mesh encryption (optional)
```

### Secret Management

```hcl
# Secure secret storage
resource "google_secret_manager_secret" "db_credentials" {
  secret_id = "ref-arch-iq-db-credentials"
  
  replication {
    auto {}  # Multi-region replication for availability
  }
}

# Environment variable injection (secure)
env {
  name = "DB_PASSWORD"
  value_source {
    secret_key_ref {
      secret  = google_secret_manager_secret.db_password.secret_id
      version = "latest"  # Always use latest version
    }
  }
}
```

**Secret Security Best Practices:**
- **No hardcoded secrets** in code or configuration
- **Automatic rotation** where possible
- **Versioned secrets** with rollback capability
- **Audit logging** for all secret access
- **Least privilege access** to secrets
- **Regional replication** for high availability

### Database Security Configuration

```hcl
resource "google_sql_database_instance" "iq_db" {
  name             = "ref-arch-iq-database"
  database_version = "POSTGRES_15"
  
  settings {
    # Security configurations
    deletion_protection_enabled = true
    
    ip_configuration {
      ipv4_enabled                                  = false  # No public IP
      private_network                               = google_compute_network.iq_vpc.id
      enable_private_path_for_google_cloud_services = true
    }
    
    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7
      backup_retention_settings {
        retained_backups = 30
      }
    }
    
    # Database audit logging
    database_flags {
      name  = "log_connections"
      value = "on"
    }
    
    database_flags {
      name  = "log_disconnections" 
      value = "on"
    }
    
    database_flags {
      name  = "log_statement"
      value = "all"  # Consider 'ddl' for production
    }
  }
}
```

## 4. Application Security

### Container Security

**1. Base Image Security**
```dockerfile
# Use official, minimal images
FROM sonatypecommunity/nexus-iq-server:latest

# Best practices applied by Sonatype:
# - Non-root user execution
# - Minimal attack surface
# - Regular security updates
# - Signed images
```

**2. Runtime Security (gVisor)**
```hcl
# Cloud Run provides gVisor sandboxing automatically
resource "google_cloud_run_v2_service" "iq_service" {
  template {
    # gVisor sandbox isolation (automatic)
    # Kernel-level isolation
    # Reduced attack surface
  }
}
```

**3. Resource Constraints**
```hcl
resources {
  limits = {
    cpu    = var.iq_cpu     # Prevent resource exhaustion
    memory = var.iq_memory  # Limit memory usage
  }
}
```

### Security Headers Configuration

```hcl
# Security headers via load balancer
resource "google_compute_url_map" "iq_url_map" {
  name = "ref-arch-iq-url-map"
  
  # Security headers can be added via Cloud Armor rules
  default_service = google_compute_backend_service.iq_backend_service.id
}
```

**Recommended Security Headers:**
```http
Strict-Transport-Security: max-age=31536000; includeSubDomains
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
X-XSS-Protection: 1; mode=block
Content-Security-Policy: default-src 'self'
Referrer-Policy: strict-origin-when-cross-origin
```

## 5. Cloud Armor Security

### Web Application Firewall (WAF)

```hcl
resource "google_compute_security_policy" "iq_security_policy" {
  name = "ref-arch-iq-security-policy"

  # Rate limiting
  rule {
    action   = "rate_based_ban"
    priority = "1000"
    
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      enforce_on_key = "IP"
      
      rate_limit_threshold {
        count        = var.rate_limit_threshold  # 100 requests/minute
        interval_sec = 60
      }
      
      ban_duration_sec = 600  # 10 minute ban
    }
  }

  # Block common attack patterns
  rule {
    action   = "deny(403)"
    priority = "900"
    
    match {
      expr {
        expression = "has(request.headers['user-agent']) && request.headers['user-agent'].contains('sqlmap')"
      }
    }
  }

  # Geographic restrictions (optional)
  rule {
    action   = "deny(403)" 
    priority = "800"
    
    match {
      expr {
        expression = "origin.region_code == 'CN'"  # Example: block China
      }
    }
  }

  # Adaptive DDoS protection
  adaptive_protection_config {
    layer_7_ddos_defense_config {
      enable = true
    }
  }
}
```

### Cloud Armor Security Features

**1. DDoS Protection**
- **Layer 3/4 Protection**: Network-level attack mitigation
- **Layer 7 Protection**: Application-level attack detection
- **Adaptive Protection**: ML-based anomaly detection
- **Global Network**: Google's edge network absorption

**2. WAF Rules**
- **OWASP Top 10**: Pre-configured rules for common attacks
- **Bot Management**: Legitimate bot vs. malicious bot detection
- **Rate Limiting**: IP-based and user-based rate limiting
- **Geo-blocking**: Country/region-based access control

**3. Custom Security Rules**
```hcl
# Authentication endpoint protection
rule {
  action   = "rate_based_ban"
  priority = "800"
  
  match {
    expr {
      expression = "request.path.startswith('/login') || request.path.startswith('/api/v2/token')"
    }
  }
  
  rate_limit_options {
    conform_action = "allow"
    exceed_action  = "deny(429)"
    enforce_on_key = "IP"
    
    rate_limit_threshold {
      count        = 10   # 10 login attempts per minute
      interval_sec = 60
    }
    
    ban_duration_sec = 300  # 5 minute ban
  }
}
```

## 6. Monitoring and Security Operations

### Security Monitoring

```hcl
# Security-focused log metrics
resource "google_logging_metric" "security_events" {
  name   = "ref-arch-iq-security-events"
  filter = "resource.type=cloud_run_revision AND (severity=WARNING OR severity=ERROR) AND (jsonPayload.message=~\"authentication|authorization|access.*denied\")"

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
}

# Failed authentication alerts
resource "google_monitoring_alert_policy" "failed_auth_alert" {
  display_name = "Nexus IQ Failed Authentication Attempts"
  
  conditions {
    display_name = "High failed authentication rate"
    
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/ref-arch-iq-security-events\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 10  # More than 10 failed attempts in 5 minutes
    }
  }
}
```

### Audit Logging

**1. Cloud Audit Logs (Automatic)**
```
Admin Activity Logs
├── IAM policy changes
├── Resource creation/deletion
├── Configuration changes
└── Security policy modifications

Data Access Logs  
├── Database queries (optional)
├── Secret Manager access
├── Storage bucket access
└── Network access patterns

System Event Logs
├── Service disruptions
├── Resource availability events
├── Maintenance events
└── Security alerts
```

**2. Application Audit Logging**
```hcl
# Structured logging for security events
resource "google_logging_project_sink" "security_sink" {
  name        = "ref-arch-iq-security-sink"
  destination = "storage.googleapis.com/${google_storage_bucket.security_logs.name}"
  
  filter = "severity>=WARNING AND (resource.type=cloud_run_revision OR resource.type=cloudsql_database)"
  
  unique_writer_identity = true
}
```

### Security Incident Response

**1. Automated Response**
```hcl
# Cloud Function for automated incident response
resource "google_cloudfunctions_function" "security_response" {
  name        = "ref-arch-iq-security-response"
  description = "Automated security incident response"
  runtime     = "python39"

  # Triggered by security alerts
  event_trigger {
    event_type = "providers/cloud.pubsub/eventTypes/topic.publish"
    resource   = google_pubsub_topic.security_alerts.name
  }
}
```

**2. Incident Response Playbook**
```
High-Level Incident Response Process:

1. Detection
   ├── Automated monitoring alerts
   ├── Security policy violations  
   ├── Anomaly detection triggers
   └── Manual security reviews

2. Assessment
   ├── Threat classification
   ├── Impact analysis
   ├── Scope determination
   └── Evidence collection

3. Containment
   ├── Network isolation
   ├── Service account suspension
   ├── Access revocation
   └── Traffic filtering

4. Eradication
   ├── Vulnerability patching
   ├── Configuration remediation
   ├── Malware removal
   └── Security policy updates

5. Recovery
   ├── Service restoration
   ├── Monitoring enhancement
   ├── Configuration validation
   └── Performance verification

6. Lessons Learned
   ├── Post-incident review
   ├── Process improvements
   ├── Security enhancements
   └── Training updates
```

## 7. Compliance and Governance

### Compliance Framework Support

**SOC 2 Type II Compliance**
```
Security Controls:
├── Access Controls: IAM, service accounts, MFA
├── Logical Security: Firewall rules, VPC isolation
├── Data Protection: Encryption, backup, retention
├── Monitoring: Continuous monitoring, alerting
└── Incident Response: Automated response, logging

Availability Controls:
├── High Availability: Multi-zone deployment
├── Backup and Recovery: Automated backups, DR
├── Capacity Management: Autoscaling, monitoring
├── Performance: Load balancing, optimization
└── Maintenance: Automated updates, patching
```

**GDPR Compliance Support**
```
Data Protection Measures:
├── Data Encryption: At rest and in transit
├── Access Controls: Role-based access, auditing
├── Data Retention: Automated lifecycle policies
├── Right to Erasure: Data deletion capabilities
├── Data Portability: Export and backup features
├── Breach Notification: Automated alerting
└── Privacy by Design: Minimal data collection
```

### Security Governance

**1. Security Policies**
```yaml
# Example security policy (YAML format)
security_policy:
  password_policy:
    min_length: 12
    complexity: high
    rotation_days: 90
    
  access_policy:
    mfa_required: true
    session_timeout: 60
    max_failed_attempts: 5
    
  data_policy:
    encryption_required: true
    backup_retention: 30
    log_retention: 90
```

**2. Regular Security Assessments**
```
Monthly Security Reviews:
├── Access review and cleanup
├── Vulnerability scanning
├── Configuration drift detection
└── Security metrics analysis

Quarterly Security Audits:
├── Penetration testing
├── Compliance assessment
├── Security policy review
└── Incident response testing

Annual Security Certifications:
├── SOC 2 Type II audit
├── ISO 27001 assessment
├── Industry-specific compliance
└── Third-party security assessment
```

## 8. Security Configuration Checklist

### Pre-Deployment Security Checklist

**Network Security**
- [ ] Custom VPC with explicit subnets
- [ ] Firewall rules follow least privilege
- [ ] Private IP for database access
- [ ] VPC connector for secure Cloud Run access
- [ ] Cloud NAT for controlled egress
- [ ] No public IPs on application resources

**Identity and Access**  
- [ ] Service accounts with minimal permissions
- [ ] No service account keys (use Workload Identity)
- [ ] Custom IAM roles where needed
- [ ] Regular access reviews scheduled
- [ ] MFA enabled for human access

**Data Protection**
- [ ] Encryption at rest enabled (automatic)
- [ ] Encryption in transit configured
- [ ] Database private IP only
- [ ] Secrets stored in Secret Manager
- [ ] Backup encryption enabled
- [ ] Data retention policies configured

**Application Security**
- [ ] Container security scanning enabled
- [ ] Resource limits configured
- [ ] Health checks implemented
- [ ] Security headers configured
- [ ] Input validation in application

**Monitoring and Logging**
- [ ] Security monitoring configured
- [ ] Audit logging enabled
- [ ] Alert policies for security events
- [ ] Log retention policies set
- [ ] Incident response procedures documented

### Post-Deployment Security Validation

**Network Testing**
```bash
# Verify no direct database access
nmap -p 5432 <database-private-ip>  # Should timeout

# Verify firewall rules
gcloud compute firewall-rules list --filter="network:ref-arch-iq-vpc"

# Test Cloud Armor rules
curl -H "User-Agent: sqlmap" https://your-domain.com  # Should return 403
```

**Access Testing**
```bash
# Verify service account permissions
gcloud projects get-iam-policy PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:*iq-service*"

# Test secret access
gcloud secrets versions access latest --secret="ref-arch-iq-db-credentials"
```

**Security Testing**
```bash
# SSL/TLS configuration test
sslscan your-domain.com

# Security headers test  
curl -I https://your-domain.com

# Vulnerability scanning
gcloud beta container images scan IMAGE_URL
```

## 9. Security Best Practices Summary

### Architecture Security
1. **Defense in Depth**: Multiple security layers
2. **Zero Trust**: Verify everything, trust nothing
3. **Least Privilege**: Minimal required access
4. **Fail Secure**: Default deny policies
5. **Separation of Duties**: Role-based access control

### Operational Security
1. **Continuous Monitoring**: Real-time security monitoring
2. **Automated Response**: Rapid incident response
3. **Regular Updates**: Keep systems patched and updated
4. **Security Training**: Regular team security training
5. **Incident Preparedness**: Regular DR and security drills

### Data Security
1. **Encryption Everywhere**: Data at rest and in transit
2. **Secret Management**: Centralized secret storage
3. **Data Classification**: Understand data sensitivity
4. **Backup Security**: Encrypted and tested backups
5. **Data Retention**: Appropriate retention policies

This security guide provides a comprehensive framework for securing your Nexus IQ Server deployment on GCP. Regular review and updates of these security measures are essential for maintaining a robust security posture.