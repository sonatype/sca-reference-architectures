# Nexus IQ Server GCP Monitoring and Observability Guide

This document provides comprehensive guidance for monitoring, logging, and observability of the Nexus IQ Server deployment on Google Cloud Platform, covering metrics, dashboards, alerting, and troubleshooting procedures.

## Monitoring Architecture Overview

The GCP deployment implements a **comprehensive observability strategy** using Google Cloud's native monitoring and logging services:

1. **Metrics Collection**: Cloud Monitoring for infrastructure and application metrics
2. **Log Aggregation**: Cloud Logging for centralized log management
3. **Distributed Tracing**: Cloud Trace for request tracing (optional)
4. **Error Tracking**: Cloud Error Reporting for error aggregation
5. **Uptime Monitoring**: Synthetic monitoring and SLO tracking
6. **Alerting**: Proactive notification and incident management

## 1. Metrics and Monitoring

### Cloud Monitoring Dashboard

The deployment automatically creates a comprehensive monitoring dashboard with the following panels:

```
┌─────────────────────────────────────────────────────────────────┐
│                    NEXUS IQ MONITORING DASHBOARD                │
└─────────────────────────────────────────────────────────────────┘

Application Health
├── Cloud Run Instance Count
├── Request Rate (requests/second)
├── Response Latency (95th percentile)
├── Error Rate (percentage)
└── CPU and Memory Utilization

Infrastructure Metrics
├── Database Connections
├── Database CPU/Memory Usage
├── Storage IOPS and Throughput
├── Network Traffic (ingress/egress)
└── Load Balancer Health

Business Metrics
├── Active Users
├── Application Scans
├── Policy Violations
├── Component Analysis Results
└── License Compliance Status
```

### Key Performance Indicators (KPIs)

**Application Performance**
```yaml
# Response Time SLI
response_time_sli:
  target: 95% of requests < 2 seconds
  measurement: HTTP request latency
  timeframe: Rolling 30 days

# Availability SLI  
availability_sli:
  target: 99.9% uptime
  measurement: Successful HTTP responses / Total requests
  timeframe: Rolling 30 days

# Error Rate SLI
error_rate_sli:
  target: < 1% error rate
  measurement: HTTP 5xx responses / Total requests
  timeframe: Rolling 7 days
```

**Infrastructure Performance**
```yaml
# Database Performance
database_performance:
  connection_utilization: < 80%
  query_response_time: < 100ms average
  connection_errors: < 0.1%

# Compute Performance
compute_performance:
  cpu_utilization: < 70% average
  memory_utilization: < 80% average
  instance_startup_time: < 30 seconds
```

### Metric Collection Configuration

```hcl
# Custom application metrics
resource "google_logging_metric" "iq_scan_requests" {
  name   = "ref-arch-iq-scan-requests"
  filter = "resource.type=cloud_run_revision AND jsonPayload.message=~\"scan.*completed\""

  metric_descriptor {
    metric_kind  = "DELTA"
    value_type   = "INT64"
    display_name = "Nexus IQ Scan Requests"
  }
  
  label_extractors = {
    "scan_type"    = "EXTRACT(jsonPayload.scan_type)"
    "application"  = "EXTRACT(jsonPayload.application_id)"
    "result"       = "EXTRACT(jsonPayload.scan_result)"
  }
}

# Performance metrics
resource "google_logging_metric" "iq_response_time" {
  name   = "ref-arch-iq-response-time"
  filter = "resource.type=cloud_run_revision AND httpRequest.status>=200 AND httpRequest.status<400"

  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "DOUBLE"
    unit        = "s"
  }

  value_extractor = "EXTRACT(httpRequest.latency)"
}
```

## 2. Logging Strategy

### Centralized Log Management

```
┌─────────────────────────────────────────────────────────────────┐
│                      LOG AGGREGATION FLOW                      │
└─────────────────────────────────────────────────────────────────┘

Application Logs (Cloud Run)
├── stdout/stderr → Cloud Logging
├── Structured JSON logging
├── Request/response logs
├── Application performance logs
└── Security event logs

Infrastructure Logs
├── Load Balancer → Access logs to Cloud Logging
├── Cloud SQL → Query logs, audit logs
├── VPC → Flow logs (optional)
├── Cloud NAT → NAT gateway logs
└── Firewall → Firewall logs

System Logs (Automatic)
├── Cloud Audit Logs → Admin activity, data access
├── Cloud Run → Service logs, build logs
├── Cloud SQL → Database logs, backup logs
└── Cloud Storage → Access logs, lifecycle logs
```

### Log Sinks and Routing

```hcl
# Application log sink for long-term storage
resource "google_logging_project_sink" "iq_application_logs" {
  name        = "ref-arch-iq-application-sink"
  destination = "storage.googleapis.com/${google_storage_bucket.log_archive.name}"
  
  filter = <<-EOT
    resource.type="cloud_run_revision" 
    AND resource.labels.service_name="ref-arch-iq-service"
    AND severity >= "INFO"
  EOT

  unique_writer_identity = true
  
  # Lifecycle for cost optimization
  bigquery_options {
    use_partitioned_tables = true
  }
}

# Security event sink for compliance
resource "google_logging_project_sink" "iq_security_logs" {
  name        = "ref-arch-iq-security-sink"
  destination = "bigquery.googleapis.com/projects/${var.gcp_project_id}/datasets/security_logs"
  
  filter = <<-EOT
    (resource.type="cloud_run_revision" OR resource.type="cloudsql_database")
    AND (severity="WARNING" OR severity="ERROR" OR severity="CRITICAL")
    AND (jsonPayload.message=~"authentication|authorization|access.*denied|security")
  EOT

  unique_writer_identity = true
}
```

### Structured Logging Best Practices

**JSON Log Format Example**
```json
{
  "timestamp": "2023-12-07T10:30:00.000Z",
  "severity": "INFO",
  "service": "nexus-iq-server",
  "version": "1.0.0",
  "requestId": "abc123-def456-ghi789",
  "userId": "admin@company.com",
  "action": "component_scan",
  "applicationId": "webapp-frontend",
  "scanId": "scan-789",
  "duration": 1234,
  "result": "success",
  "metrics": {
    "componentsScanned": 150,
    "vulnerabilitiesFound": 3,
    "policyViolations": 1
  },
  "labels": {
    "environment": "production",
    "region": "us-central1"
  }
}
```

**Log Levels and Usage**
```yaml
ERROR: 
  - Application failures
  - Authentication failures  
  - Database connection errors
  - Policy violations

WARN:
  - Performance degradation
  - Configuration issues
  - Deprecated feature usage
  - Resource constraints

INFO:
  - Successful operations
  - User actions
  - System state changes
  - Performance metrics

DEBUG:
  - Detailed request/response data
  - Internal processing details
  - Development troubleshooting
  - (Disabled in production)
```

## 3. Alerting and Notification

### Alert Policy Configuration

```hcl
# High error rate alert
resource "google_monitoring_alert_policy" "iq_high_error_rate" {
  display_name = "Nexus IQ High Error Rate"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "Error rate above 5%"
    
    condition_threshold {
      filter = <<-EOT
        resource.type="cloud_run_revision"
        AND resource.labels.service_name="ref-arch-iq-service"
        AND metric.type="run.googleapis.com/request_count"
        AND metric.labels.response_code_class="5xx"
      EOT
      
      duration        = "300s"  # 5 minutes
      comparison      = "COMPARISON_GT"
      threshold_value = 0.05    # 5% error rate

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["resource.labels.service_name"]
      }
    }
  }

  notification_channels = var.notification_channels
  
  alert_strategy {
    auto_close = "1800s"  # Auto-close after 30 minutes
    
    notification_rate_limit {
      period = "300s"  # Limit notifications to every 5 minutes
    }
  }

  documentation {
    content = <<-EOT
      High error rate detected in Nexus IQ Server.
      
      Troubleshooting steps:
      1. Check application logs: gcloud run services logs tail ref-arch-iq-service --region=us-central1
      2. Verify database connectivity
      3. Check resource utilization
      4. Review recent deployments
      
      Escalation: Contact DevOps team if error rate persists > 15 minutes
    EOT
    mime_type = "text/markdown"
  }
}

# Database connection alert
resource "google_monitoring_alert_policy" "iq_database_connections" {
  display_name = "Nexus IQ Database High Connection Count"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "Database connections > 80% of max"
    
    condition_threshold {
      filter = <<-EOT
        resource.type="cloudsql_database"
        AND metric.type="cloudsql.googleapis.com/database/postgresql/num_backends"
      EOT
      
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = var.alert_db_connections_threshold  # 80

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = var.notification_channels
}

# Service availability alert  
resource "google_monitoring_alert_policy" "iq_service_down" {
  display_name = "Nexus IQ Service Unavailable"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "Uptime check failure"
    
    condition_absent {
      filter = <<-EOT
        resource.type="uptime_url"
        AND metric.type="monitoring.googleapis.com/uptime_check/check_passed"
      EOT
      
      duration = "300s"  # 5 minutes of absence
      
      aggregations {
        alignment_period     = "60s"
        cross_series_reducer = "REDUCE_COUNT"
        per_series_aligner   = "ALIGN_RATE"
      }
    }
  }

  notification_channels = var.notification_channels
  
  alert_strategy {
    auto_close = "900s"  # Auto-close after 15 minutes
  }
}
```

### Notification Channels

```hcl
# Email notifications
resource "google_monitoring_notification_channel" "email" {
  count        = length(var.alert_email_addresses)
  display_name = "Email Notification ${count.index + 1}"
  type         = "email"
  
  labels = {
    email_address = var.alert_email_addresses[count.index]
  }

  user_labels = {
    environment = var.environment
    service     = "nexus-iq"
  }
}

# Slack notifications (webhook)
resource "google_monitoring_notification_channel" "slack" {
  count        = var.slack_webhook_url != "" ? 1 : 0
  display_name = "Slack Notifications"
  type         = "slack"
  
  labels = {
    channel_name = var.slack_channel
    url          = var.slack_webhook_url
  }
}

# PagerDuty integration
resource "google_monitoring_notification_channel" "pagerduty" {
  count        = var.pagerduty_service_key != "" ? 1 : 0
  display_name = "PagerDuty Escalation"
  type         = "pagerduty"
  
  labels = {
    service_key = var.pagerduty_service_key
  }
}
```

### Alert Severity Levels

```yaml
# Alert categorization
CRITICAL:
  - Service completely unavailable
  - Database connection lost
  - Data corruption detected
  - Security breach detected
  Response: Immediate (5 minutes)
  Escalation: Page on-call engineer

HIGH:
  - High error rate (>5%)
  - Performance degradation (>3s response time)
  - Resource exhaustion (>90% utilization)
  - Authentication system issues
  Response: Within 15 minutes
  Escalation: Email + Slack notifications

MEDIUM:
  - Moderate error rate (2-5%)
  - Resource constraints (70-90% utilization)
  - Non-critical feature failures
  - Performance warnings
  Response: Within 1 hour
  Escalation: Email notifications

LOW:
  - Minor performance issues
  - Configuration warnings
  - Capacity planning alerts
  - Maintenance reminders
  Response: Within 4 hours
  Escalation: Daily summary report
```

## 4. Uptime Monitoring and SLOs

### Synthetic Monitoring

```hcl
# HTTP uptime check
resource "google_monitoring_uptime_check_config" "iq_uptime_check" {
  display_name = "Nexus IQ Service Uptime Check"
  timeout      = "10s"
  period       = "300s"  # Check every 5 minutes

  http_check {
    path           = "/"
    port           = var.ssl_certificate_name != "" ? 443 : 80
    use_ssl        = var.ssl_certificate_name != ""
    request_method = "GET"
    
    headers = {
      "User-Agent" = "GoogleHC/1.0 (Nexus-IQ-Uptime-Check)"
    }
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.gcp_project_id
      host       = var.domain_name != "" ? var.domain_name : google_compute_global_address.iq_lb_ip.address
    }
  }

  content_matchers {
    content = "Nexus IQ Server"
    matcher = "CONTAINS_STRING"
  }

  checker_type = "STATIC_IP_CHECKERS"
  
  selected_regions = [
    "USA",
    "EUROPE", 
    "ASIA_PACIFIC"
  ]
}

# API endpoint monitoring
resource "google_monitoring_uptime_check_config" "iq_api_check" {
  display_name = "Nexus IQ API Health Check"
  timeout      = "10s"
  period       = "300s"

  http_check {
    path           = "/api/v2/applications"
    port           = var.ssl_certificate_name != "" ? 443 : 80
    use_ssl        = var.ssl_certificate_name != ""
    request_method = "GET"
    
    auth_info {
      type     = "basic_auth"
      username = "admin"
      password = "admin123"  # Should be parameterized in production
    }
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.gcp_project_id
      host       = var.domain_name != "" ? var.domain_name : google_compute_global_address.iq_lb_ip.address
    }
  }

  content_matchers {
    content = "applications"
    matcher = "CONTAINS_STRING"
  }
}
```

### Service Level Objectives (SLOs)

```hcl
# Service definition for SLOs
resource "google_monitoring_service" "iq_service" {
  service_id   = "ref-arch-iq-service"
  display_name = "Nexus IQ Server Service"
  
  user_labels = {
    environment = var.environment
    version     = "1.0"
    team        = "platform-engineering"
  }
}

# Availability SLO (99.9% uptime)
resource "google_monitoring_slo" "iq_availability_slo" {
  service      = google_monitoring_service.iq_service.service_id
  display_name = "Nexus IQ Availability SLO"
  
  request_based_sli {
    good_total_ratio {
      total_service_filter = <<-EOT
        resource.type="cloud_run_revision"
        AND resource.labels.service_name="ref-arch-iq-service"
      EOT
      
      good_service_filter = <<-EOT
        resource.type="cloud_run_revision"
        AND resource.labels.service_name="ref-arch-iq-service"
        AND metric.labels.response_code_class="2xx"
      EOT
    }
  }

  goal                = var.availability_slo_target  # 0.999
  rolling_period      = "2592000s"  # 30 days
  calendar_period     = "MONTH"
  
  user_labels = {
    criticality = "high"
    service     = "nexus-iq"
  }
}

# Latency SLO (95% of requests < 2s)
resource "google_monitoring_slo" "iq_latency_slo" {
  service      = google_monitoring_service.iq_service.service_id
  display_name = "Nexus IQ Latency SLO"
  
  request_based_sli {
    distribution_cut {
      distribution_filter = <<-EOT
        resource.type="cloud_run_revision"
        AND resource.labels.service_name="ref-arch-iq-service"
        AND metric.type="run.googleapis.com/request_latencies"
      EOT
      
      range {
        min = 0
        max = 2000  # 2 seconds in milliseconds
      }
    }
  }

  goal           = 0.95   # 95% of requests
  rolling_period = "2592000s"  # 30 days
}
```

### Error Budget Alerting

```hcl
# SLO burn rate alert
resource "google_monitoring_alert_policy" "iq_slo_burn_rate" {
  display_name = "Nexus IQ SLO Error Budget Burn Rate"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "Fast burn rate - 2% budget consumed in 1 hour"
    
    condition_threshold {
      filter = <<-EOT
        resource.type="gce_instance"
        AND metric.type="serviceruntime.googleapis.com/api/request_count"
        AND metric.labels.response_code!="200"
      EOT
      
      duration        = "3600s"  # 1 hour
      comparison      = "COMPARISON_GT" 
      threshold_value = 0.02     # 2% error budget

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  notification_channels = var.notification_channels
  
  alert_strategy {
    auto_close = "86400s"  # 24 hours
  }
}
```

## 5. Performance Monitoring

### Application Performance Monitoring (APM)

```hcl
# Performance insights configuration
resource "google_logging_metric" "iq_operation_duration" {
  name   = "ref-arch-iq-operation-duration"
  filter = <<-EOT
    resource.type="cloud_run_revision"
    AND jsonPayload.operation_type IS NOT NULL
    AND jsonPayload.duration IS NOT NULL
  EOT

  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "DOUBLE"
    unit        = "ms"
    display_name = "Nexus IQ Operation Duration"
  }

  value_extractor = "EXTRACT(jsonPayload.duration)"
  
  label_extractors = {
    "operation_type" = "EXTRACT(jsonPayload.operation_type)"
    "user_id"       = "EXTRACT(jsonPayload.user_id)"
    "application"   = "EXTRACT(jsonPayload.application_id)"
  }
}

# Database query performance
resource "google_logging_metric" "iq_db_query_time" {
  name   = "ref-arch-iq-db-query-time"
  filter = <<-EOT
    resource.type="cloudsql_database"
    AND jsonPayload.message=~"slow query"
    AND jsonPayload.query_time IS NOT NULL
  EOT

  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "DOUBLE"
    unit        = "s"
  }

  value_extractor = "EXTRACT(jsonPayload.query_time)"
}
```

### Resource Utilization Monitoring

```hcl
# CPU utilization alert
resource "google_monitoring_alert_policy" "iq_high_cpu" {
  display_name = "Nexus IQ High CPU Usage"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "CPU utilization > 80%"
    
    condition_threshold {
      filter = <<-EOT
        resource.type="cloud_run_revision"
        AND resource.labels.service_name="ref-arch-iq-service"
        AND metric.type="run.googleapis.com/container/cpu/utilizations"
      EOT
      
      duration        = "600s"  # 10 minutes
      comparison      = "COMPARISON_GT"
      threshold_value = var.alert_cpu_threshold  # 0.8

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = var.notification_channels
}

# Memory utilization alert
resource "google_monitoring_alert_policy" "iq_high_memory" {
  display_name = "Nexus IQ High Memory Usage"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "Memory utilization > 85%"
    
    condition_threshold {
      filter = <<-EOT
        resource.type="cloud_run_revision"
        AND resource.labels.service_name="ref-arch-iq-service"
        AND metric.type="run.googleapis.com/container/memory/utilizations"
      EOT
      
      duration        = "600s"
      comparison      = "COMPARISON_GT"
      threshold_value = var.alert_memory_threshold  # 0.85
    }
  }

  notification_channels = var.notification_channels
}
```

## 6. Security Monitoring

### Security Event Detection

```hcl
# Authentication failure monitoring
resource "google_logging_metric" "iq_auth_failures" {
  name   = "ref-arch-iq-auth-failures"
  filter = <<-EOT
    resource.type="cloud_run_revision"
    AND (jsonPayload.message=~"authentication.*failed" OR 
         jsonPayload.message=~"login.*failed" OR
         jsonPayload.message=~"unauthorized.*access")
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    display_name = "Authentication Failures"
  }
  
  label_extractors = {
    "source_ip" = "EXTRACT(httpRequest.remoteIp)"
    "user_agent" = "EXTRACT(httpRequest.userAgent)"
    "username" = "EXTRACT(jsonPayload.username)"
  }
}

# Suspicious activity detection
resource "google_monitoring_alert_policy" "iq_suspicious_activity" {
  display_name = "Nexus IQ Suspicious Activity"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "High authentication failure rate"
    
    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/ref-arch-iq-auth-failures\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 10  # 10+ failures in 5 minutes

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
        group_by_fields    = ["metric.labels.source_ip"]
      }
    }
  }

  notification_channels = var.notification_channels
  
  documentation {
    content = <<-EOT
      Potential brute force attack detected.
      
      Investigation steps:
      1. Check source IP: gcloud logging read "resource.type=cloud_run_revision AND jsonPayload.message=~\"authentication.*failed\"" --limit=50
      2. Review user agent patterns
      3. Consider IP blocking via Cloud Armor
      4. Check for account lockouts
      
      Escalation: Contact security team immediately
    EOT
    mime_type = "text/markdown"
  }
}
```

### Compliance Monitoring

```hcl
# Data access monitoring
resource "google_logging_metric" "iq_data_access" {
  name   = "ref-arch-iq-data-access"
  filter = <<-EOT
    resource.type="cloudsql_database"
    AND protoPayload.methodName=~"cloudsql.instances.connect"
    OR jsonPayload.message=~"data.*export|backup.*download"
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
  
  label_extractors = {
    "user" = "EXTRACT(protoPayload.authenticationInfo.principalEmail)"
    "action" = "EXTRACT(protoPayload.methodName)"
  }
}

# Configuration change monitoring  
resource "google_logging_metric" "iq_config_changes" {
  name   = "ref-arch-iq-config-changes"
  filter = <<-EOT
    resource.type="cloud_run_revision"
    AND (jsonPayload.message=~"configuration.*changed" OR
         jsonPayload.message=~"policy.*modified" OR
         jsonPayload.message=~"user.*role.*changed")
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
}
```

## 7. Business Metrics Monitoring

### Application-Specific Metrics

```hcl
# Scan completion metrics
resource "google_logging_metric" "iq_scan_completions" {
  name   = "ref-arch-iq-scan-completions"
  filter = <<-EOT
    resource.type="cloud_run_revision"
    AND jsonPayload.event_type="scan_completed"
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    display_name = "Scan Completions"
  }
  
  label_extractors = {
    "scan_result"   = "EXTRACT(jsonPayload.scan_result)"
    "application"   = "EXTRACT(jsonPayload.application_id)"
    "scan_type"     = "EXTRACT(jsonPayload.scan_type)"
    "component_count" = "EXTRACT(jsonPayload.component_count)"
  }
}

# Policy violation metrics
resource "google_logging_metric" "iq_policy_violations" {
  name   = "ref-arch-iq-policy-violations"
  filter = <<-EOT
    resource.type="cloud_run_revision"
    AND jsonPayload.event_type="policy_violation"
    AND jsonPayload.violation_level IS NOT NULL
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
  }
  
  label_extractors = {
    "violation_level" = "EXTRACT(jsonPayload.violation_level)"
    "policy_name"     = "EXTRACT(jsonPayload.policy_name)"
    "application"     = "EXTRACT(jsonPayload.application_id)"
  }
}
```

### Business Intelligence Dashboards

```hcl
# Business metrics dashboard
resource "google_monitoring_dashboard" "iq_business_dashboard" {
  dashboard_json = jsonencode({
    displayName = "Nexus IQ Business Metrics"
    
    mosaicLayout = {
      tiles = [
        {
          width = 6
          height = 4
          widget = {
            title = "Daily Scan Volume"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"logging.googleapis.com/user/ref-arch-iq-scan-completions\""
                    aggregation = {
                      alignmentPeriod    = "86400s"  # Daily
                      perSeriesAligner   = "ALIGN_SUM"
                      crossSeriesReducer = "REDUCE_SUM"
                    }
                  }
                }
                plotType = "LINE"
              }]
            }
          }
        },
        {
          width = 6
          height = 4
          xPos = 6
          widget = {
            title = "Policy Violations by Severity"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"logging.googleapis.com/user/ref-arch-iq-policy-violations\""
                    aggregation = {
                      alignmentPeriod    = "3600s"  # Hourly
                      perSeriesAligner   = "ALIGN_SUM"
                      crossSeriesReducer = "REDUCE_SUM"
                      groupByFields      = ["metric.labels.violation_level"]
                    }
                  }
                }
                plotType = "STACKED_AREA"
              }]
            }
          }
        }
      ]
    }
  })
}
```

## 8. Troubleshooting and Diagnostics

### Log Analysis Queries

**Common Log Queries**
```bash
# View recent application errors
gcloud logging read "
  resource.type=cloud_run_revision 
  AND resource.labels.service_name=ref-arch-iq-service 
  AND severity>=ERROR
" --limit=50 --format=json

# Check database connection issues
gcloud logging read "
  resource.type=cloud_run_revision 
  AND jsonPayload.message=~'database.*connection|connection.*timeout'
" --limit=20

# Monitor authentication events
gcloud logging read "
  resource.type=cloud_run_revision 
  AND (jsonPayload.message=~'login|authentication|session')
" --limit=30

# Performance analysis
gcloud logging read "
  resource.type=cloud_run_revision 
  AND httpRequest.latency > '2s'
" --limit=25
```

**Database Performance Analysis**
```bash
# Slow query analysis
gcloud logging read "
  resource.type=cloudsql_database
  AND jsonPayload.message=~'slow query'
" --limit=10

# Connection pool status
gcloud sql operations list --instance=ref-arch-iq-database

# Database metrics
gcloud monitoring metrics list --filter="metric.type:cloudsql"
```

### Performance Diagnostic Commands

**Cloud Run Service Analysis**
```bash
# Service status and configuration
gcloud run services describe ref-arch-iq-service --region=us-central1

# Current revision details
gcloud run revisions list --service=ref-arch-iq-service --region=us-central1

# Traffic allocation
gcloud run services describe ref-arch-iq-service --region=us-central1 \
  --format="value(spec.traffic[].percent,spec.traffic[].revisionName)"

# Service logs (real-time)
gcloud run services logs tail ref-arch-iq-service --region=us-central1
```

**Load Balancer Analysis**
```bash
# Backend service health
gcloud compute backend-services get-health ref-arch-iq-backend-service --global

# Target group status
gcloud compute target-groups list

# Load balancer metrics
gcloud monitoring metrics list --filter="metric.type:loadbalancing"
```

### Diagnostic Runbooks

**High Response Time Investigation**
```yaml
symptoms:
  - Response time > 3 seconds
  - Users reporting slow performance
  
investigation_steps:
  1. Check Cloud Run metrics:
     - CPU utilization
     - Memory utilization  
     - Instance count
  
  2. Database analysis:
     - Connection count
     - Query performance
     - Lock contention
  
  3. Network analysis:
     - Load balancer latency
     - Network endpoint health
     - VPC connectivity
  
  4. Application analysis:
     - Recent deployments
     - Configuration changes
     - Resource limits

resolution_steps:
  1. Scale Cloud Run instances if CPU/memory high
  2. Optimize database queries if DB is bottleneck
  3. Increase resource limits if hitting constraints
  4. Review and optimize application code
```

**Service Unavailability Investigation**
```yaml
symptoms:
  - Service returning 5xx errors
  - Health checks failing
  - Users cannot access application

investigation_steps:
  1. Check service status:
     - Cloud Run service health
     - Load balancer status
     - Database connectivity
  
  2. Review recent changes:
     - Deployments
     - Configuration updates
     - Infrastructure changes
  
  3. Check resource constraints:
     - Memory/CPU limits
     - Database connections
     - Storage capacity
  
  4. Network connectivity:
     - VPC configuration
     - Firewall rules
     - DNS resolution

resolution_steps:
  1. Rollback recent deployment if needed
  2. Scale resources if constraint identified
  3. Fix configuration if misconfigured
  4. Escalate to platform team if infrastructure issue
```

## 9. Monitoring Best Practices

### Metric Design Principles

**1. Four Golden Signals**
```yaml
Latency:
  - Response time for successful requests
  - Response time for failed requests
  - Time to first byte (TTFB)

Traffic:
  - Requests per second
  - Active users
  - Database queries per second

Errors:
  - Rate of failed requests (5xx errors)
  - Rate of failed database connections
  - Application-specific error rates

Saturation:
  - CPU utilization
  - Memory utilization
  - Database connection pool usage
```

**2. SLI/SLO Framework**
```yaml
Availability_SLI:
  definition: "Percentage of successful HTTP requests"
  measurement: "(2xx + 3xx responses) / total responses"
  target: "99.9% over 30 days"

Latency_SLI:
  definition: "95th percentile response time"
  measurement: "95% of requests complete within threshold" 
  target: "< 2 seconds for 95% of requests"

Quality_SLI:
  definition: "Scan accuracy and completeness"
  measurement: "Successful scans / total scan attempts"
  target: "99.5% scan success rate"
```

### Alert Strategy

**Alert Fatigue Prevention**
```yaml
Alert_Prioritization:
  P1_Critical:
    - Service completely down
    - Data corruption
    - Security breaches
    response_time: "< 5 minutes"
    
  P2_High:
    - Degraded performance
    - High error rates
    - Resource constraints
    response_time: "< 30 minutes"
    
  P3_Medium:
    - Warning thresholds
    - Capacity planning
    - Non-critical failures
    response_time: "< 4 hours"

Alert_Grouping:
  - Group related alerts by component
  - Use alert dependencies
  - Implement alert suppression during maintenance
  - Set appropriate alert cooldown periods
```

This comprehensive monitoring guide provides the foundation for maintaining visibility into your Nexus IQ Server deployment on GCP, enabling proactive issue detection and resolution while supporting continuous improvement of system reliability and performance.