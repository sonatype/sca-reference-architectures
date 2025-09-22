# Nexus IQ Server - GCP Monitoring & Observability Guide

This document provides comprehensive guidance on monitoring, observability, and operational insights for the Nexus IQ Server deployment on Google Cloud Platform.

## 📊 Monitoring Architecture Overview

### Observability Stack
```
┌─────────────────────────────────────────────────────┐
│                  Data Sources                       │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐    │
│  │ Cloud Run   │ │ Cloud SQL   │ │ Load Balancer│    │
│  │ Metrics     │ │ Metrics     │ │ Metrics      │    │
│  └─────────────┘ └─────────────┘ └─────────────┘    │
└─────────────────┬───────────────────────────────────┘
                  │
┌─────────────────┼───────────────────────────────────┐
│            Cloud Monitoring                         │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐    │
│  │ Dashboards  │ │ Alerting    │ │ SLOs        │    │
│  └─────────────┘ └─────────────┘ └─────────────┘    │
└─────────────────┬───────────────────────────────────┘
                  │
┌─────────────────┼───────────────────────────────────┐
│             Cloud Logging                           │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐    │
│  │ Log Sinks   │ │ Log Analysis│ │ Log Storage │    │
│  └─────────────┘ └─────────────┘ └─────────────┘    │
└─────────────────┬───────────────────────────────────┘
                  │
┌─────────────────┼───────────────────────────────────┐
│            Notification Channels                    │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐    │
│  │ Email       │ │ Slack       │ │ PagerDuty   │    │
│  └─────────────┘ └─────────────┘ └─────────────┘    │
└─────────────────────────────────────────────────────┘
```

## 📈 Metrics & Dashboards

### Built-in Dashboard Overview

The infrastructure automatically creates a comprehensive monitoring dashboard accessible via:
```bash
# Get dashboard URL
terraform output monitoring_dashboard_url

# Example URL
https://console.cloud.google.com/monitoring/dashboards/custom/DASHBOARD_ID?project=PROJECT_ID
```

### Dashboard Sections

#### 1. Cloud Run Metrics
```yaml
Request Count:
  Metric: run.googleapis.com/request_count
  Aggregation: Rate per second
  Group By: service_name
  Visualization: Line chart
  
Request Latencies:
  Metric: run.googleapis.com/request_latencies
  Aggregation: 95th percentile
  Unit: Milliseconds
  Visualization: Line chart
  
Container CPU Utilization:
  Metric: run.googleapis.com/container/cpu/utilizations
  Aggregation: Mean
  Unit: Percentage
  Visualization: Line chart
  
Container Memory Utilization:
  Metric: run.googleapis.com/container/memory/utilizations
  Aggregation: Mean
  Unit: Percentage
  Visualization: Line chart
  
Instance Count:
  Metric: run.googleapis.com/container/instance_count
  Aggregation: Mean
  Visualization: Stacked area chart
```

#### 2. Database Metrics
```yaml
CPU Utilization:
  Metric: cloudsql.googleapis.com/database/cpu/utilization
  Aggregation: Mean
  Unit: Percentage
  Alert Threshold: 80%
  
Memory Utilization:
  Metric: cloudsql.googleapis.com/database/memory/utilization
  Aggregation: Mean
  Unit: Percentage
  Alert Threshold: 80%
  
Connection Count:
  Metric: cloudsql.googleapis.com/database/postgresql/num_backends
  Aggregation: Mean
  Alert Threshold: 150 connections
  
Query Execution Time:
  Metric: cloudsql.googleapis.com/database/postgresql/insights/aggregate/execution_time
  Aggregation: Mean
  Unit: Microseconds
  
Deadlocks:
  Metric: cloudsql.googleapis.com/database/postgresql/deadlock_count
  Aggregation: Rate
  Alert: Any deadlocks
```

#### 3. Load Balancer Metrics
```yaml
Request Count:
  Metric: loadbalancing.googleapis.com/https/request_count
  Aggregation: Rate per second
  Group By: backend_name
  
Request Latencies:
  Metric: loadbalancing.googleapis.com/https/request_latencies
  Aggregation: 95th percentile
  Unit: Milliseconds
  
Error Rate:
  Metric: loadbalancing.googleapis.com/https/request_count
  Filter: response_code_class="5xx"
  Aggregation: Rate
  
Backend Latencies:
  Metric: loadbalancing.googleapis.com/https/backend_latencies
  Aggregation: 95th percentile
  Unit: Milliseconds
```

#### 4. Storage Metrics
```yaml
Filestore Operations:
  Metric: file.googleapis.com/nfs/server/read_bytes_count
  Metric: file.googleapis.com/nfs/server/write_bytes_count
  Aggregation: Rate
  Unit: Bytes per second
  
Cloud Storage Operations:
  Metric: storage.googleapis.com/api/request_count
  Group By: bucket_name, method
  Aggregation: Rate per minute
  
Storage Usage:
  Metric: storage.googleapis.com/storage/total_bytes
  Group By: bucket_name
  Unit: Bytes
```

### Custom Application Metrics

#### Application-Level Monitoring
```yaml
Application Errors:
  Source: Application logs
  Metric: nexus_iq_application_errors
  Type: Counter
  Labels: service_name, severity
  
Slow Database Queries:
  Source: Application logs  
  Metric: nexus_iq_slow_database_queries
  Type: Counter
  Threshold: >5 seconds
  
User Sessions:
  Source: Application logs
  Metric: nexus_iq_active_sessions
  Type: Gauge
  
Scan Processing Time:
  Source: Application logs
  Metric: nexus_iq_scan_duration
  Type: Histogram
  Buckets: [1s, 5s, 30s, 60s, 300s]
```

## 🚨 Alerting Configuration

### Alert Policies Overview

The monitoring system includes several pre-configured alert policies:

#### 1. High CPU Usage Alert
```yaml
Policy Name: Nexus IQ High CPU Usage
Conditions:
  - Cloud Run CPU > 80% for 5 minutes
  - Cloud SQL CPU > 80% for 5 minutes
Combiner: OR
Notification Channels: Email, Slack, PagerDuty
Auto Close: 24 hours
```

#### 2. High Memory Usage Alert
```yaml
Policy Name: Nexus IQ High Memory Usage
Conditions:
  - Cloud Run Memory > 80% for 5 minutes
  - Cloud SQL Memory > 80% for 5 minutes
Combiner: OR
Notification Channels: Email, Slack, PagerDuty
Auto Close: 24 hours
```

#### 3. High Error Rate Alert
```yaml
Policy Name: Nexus IQ High Error Rate
Conditions:
  - 4xx errors > 10/minute for 5 minutes
  - 5xx errors > 10/minute for 5 minutes
Combiner: OR
Notification Channels: Email, Slack, PagerDuty
Auto Close: 24 hours
```

#### 4. Database Connection Alert
```yaml
Policy Name: Nexus IQ Database Connection Issues
Conditions:
  - Active connections > 150 for 5 minutes
Notification Channels: Email, Slack
Auto Close: 24 hours
```

#### 5. Service Availability Alert
```yaml
Policy Name: Nexus IQ Service Down
Conditions:
  - Uptime check fails for 5 minutes
Notification Channels: Email, Slack, PagerDuty
Auto Close: 24 hours
Priority: Critical
```

### Notification Channels

#### Email Configuration
```yaml
Channel Type: email
Configuration:
  email_address: admin@example.com
  display_name: Nexus IQ Email Notifications
Enabled: Configurable via alert_email_addresses variable
```

#### Slack Integration
```yaml
Channel Type: slack
Configuration:
  webhook_url: https://hooks.slack.com/services/...
  display_name: Nexus IQ Slack Notifications
Setup:
  1. Create Slack webhook in your workspace
  2. Set slack_webhook_url variable in terraform.tfvars
  3. Apply configuration
```

#### PagerDuty Integration
```yaml
Channel Type: pagerduty
Configuration:
  service_key: YOUR_PAGERDUTY_SERVICE_KEY
  display_name: Nexus IQ PagerDuty Notifications
Setup:
  1. Create PagerDuty service
  2. Get integration key
  3. Set pagerduty_service_key variable
  4. Apply configuration
```

### Alert Customization

#### Modifying Alert Thresholds
```hcl
# In terraform.tfvars
cpu_alert_threshold = 0.8          # 80%
memory_alert_threshold = 0.8       # 80%
error_rate_alert_threshold = 10    # 10 errors/minute
db_connection_alert_threshold = 150 # connections
```

#### Adding Custom Alerts
```hcl
# Example: Disk Space Alert
resource "google_monitoring_alert_policy" "disk_space_alert" {
  display_name = "High Disk Usage"
  combiner     = "OR"
  
  conditions {
    display_name = "Cloud SQL Disk Usage"
    condition_threshold {
      filter          = "resource.type=\"cloudsql_database\" AND metric.type=\"cloudsql.googleapis.com/database/disk/utilization\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = 0.85
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.email[0].name]
}
```

## 📋 Service Level Objectives (SLOs)

### Pre-configured SLOs

#### Request Latency SLO
```yaml
SLO Name: Request Latency SLO
Service: Nexus IQ Service
Type: Request-based
SLI: Distribution cut
Measurement:
  - Good requests: Latency < 1000ms
  - Total requests: All requests
Target: 99.5% of requests under 1000ms
Period: Rolling 24 hours
```

#### Error Rate SLO
```yaml
SLO Name: Error Rate SLO
Service: Nexus IQ Service
Type: Request-based
SLI: Good/Total ratio
Measurement:
  - Good requests: Non-5xx responses
  - Total requests: All requests
Target: 99.5% success rate
Period: Rolling 24 hours
```

### SLO Monitoring
```bash
# View SLO status
gcloud monitoring slos list --service=nexus-iq-service

# Get SLO details
gcloud monitoring slos describe request-latency-slo \
  --service=nexus-iq-service
```

### Custom SLOs

#### Availability SLO
```hcl
resource "google_monitoring_slo" "availability_slo" {
  service      = google_monitoring_service.iq_service.service_id
  slo_id       = "availability-slo"
  display_name = "Service Availability SLO"
  
  windows_based_sli {
    window_period = "300s"
    good_bad_metric_filter = "resource.type=\"uptime_url\" AND metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\""
  }
  
  goal          = 0.999  # 99.9%
  rolling_period = "86400s"
}
```

## 📝 Logging & Log Analysis

### Log Collection Strategy

#### Application Logs
```yaml
Source: Cloud Run containers
Format: JSON structured logs
Retention: 30 days (configurable)
Export: Cloud Storage for long-term retention

Log Levels:
  - ERROR: Application errors, exceptions
  - WARN: Warning conditions, deprecated features
  - INFO: General information, user actions
  - DEBUG: Detailed debugging information
```

#### System Logs
```yaml
Cloud Run Logs:
  - Container startup/shutdown
  - Resource allocation
  - Health check results
  
Cloud SQL Logs:
  - Connection logs
  - Query logs (optional)
  - Error logs
  - Slow query logs
  
Load Balancer Logs:
  - Request logs
  - Health check logs
  - SSL certificate logs
```

#### Security Logs
```yaml
Audit Logs:
  - Admin activity logs (always enabled)
  - Data access logs (configurable)
  - System event logs
  
VPC Flow Logs:
  - Network traffic analysis
  - Security monitoring
  - Performance analysis
  
Firewall Logs:
  - Allowed/denied connections
  - Rule hit counts
  - Security events
```

### Log Sinks Configuration

#### Primary Log Sink
```yaml
Sink Name: nexus-iq-logs-sink
Destination: Cloud Storage bucket
Filter: >
  resource.type="cloud_run_revision" AND
  resource.labels.service_name=~"nexus-iq.*"
Writer Identity: Unique service account
```

#### Security Log Sink
```yaml
Sink Name: nexus-iq-security-logs-sink
Destination: Cloud Storage bucket (security-logs/)
Filter: >
  protoPayload.serviceName="compute.googleapis.com" OR
  protoPayload.serviceName="cloudsql.googleapis.com" OR
  severity >= "WARNING"
Writer Identity: Unique service account
```

### Log Analysis Queries

#### Common Log Queries

##### Application Errors
```sql
resource.type="cloud_run_revision"
resource.labels.service_name="nexus-iq-server"
severity="ERROR"
timestamp >= "2024-01-01T00:00:00Z"
```

##### Database Connection Issues
```sql
resource.type="cloudsql_database"
protoPayload.methodName="cloudsql.instances.connect"
protoPayload.authenticationInfo.principalEmail!=""
severity="ERROR"
```

##### High Latency Requests
```sql
resource.type="http_load_balancer"
httpRequest.latency > "2s"
timestamp >= "2024-01-01T00:00:00Z"
```

##### Security Events
```sql
protoPayload.serviceName="cloudresourcemanager.googleapis.com"
protoPayload.methodName="SetIamPolicy"
protoPayload.authenticationInfo.principalEmail!=""
```

#### Log-based Metrics

##### Application Error Rate
```yaml
Metric Name: nexus_iq_application_errors
Filter: >
  resource.type="cloud_run_revision" AND
  resource.labels.service_name=~"nexus-iq.*" AND
  (severity="ERROR" OR jsonPayload.level="ERROR")
Label Extractors:
  service_name: EXTRACT(resource.labels.service_name)
  severity: EXTRACT(severity)
Type: Counter
```

##### Slow Database Queries
```yaml
Metric Name: nexus_iq_slow_database_queries
Filter: >
  resource.type="cloud_run_revision" AND
  resource.labels.service_name=~"nexus-iq.*" AND
  jsonPayload.message=~".*slow query.*"
Type: Counter
```

## 🔍 Uptime Monitoring

### Health Check Configuration

#### External Uptime Checks
```yaml
Check Name: Nexus IQ Uptime Check
Type: HTTP/HTTPS
Target: Load balancer IP or domain
Path: /
Port: 443 (HTTPS) or 80 (HTTP)
Timeout: 10 seconds
Period: 60 seconds

Content Matchers:
  - Contains: "Nexus IQ Server"
  - Status Code: 200

Regions: USA, Europe, Asia Pacific
```

#### Internal Health Checks
```yaml
Load Balancer Health Check:
  Path: /
  Port: 8070
  Interval: 30 seconds
  Timeout: 10 seconds
  Healthy Threshold: 2
  Unhealthy Threshold: 3

Cloud Run Health Checks:
  Startup Probe:
    Path: /
    Initial Delay: 60 seconds
    Period: 10 seconds
    Failure Threshold: 12
  
  Liveness Probe:
    Path: /
    Initial Delay: 120 seconds
    Period: 30 seconds
    Failure Threshold: 3
```

### Availability Reporting

#### SLA Monitoring
```yaml
Target Availability:
  Single Instance: 99.5%
  HA Instance: 99.9%

Measurement Period: Rolling 30 days
Exclusions:
  - Planned maintenance
  - Force majeure events
  - Customer-caused downtime

Reporting:
  Frequency: Monthly
  Recipients: Operations team
  Format: Automated dashboard
```

## 🛠️ Operational Monitoring

### Performance Monitoring

#### Key Performance Indicators (KPIs)
```yaml
Response Time:
  Target: <2 seconds (95th percentile)
  Measurement: Load balancer metrics
  
Throughput:
  Target: 1000+ requests/minute
  Measurement: Cloud Run request count
  
Error Rate:
  Target: <0.5%
  Measurement: HTTP 5xx responses
  
Database Performance:
  Query Time: <100ms average
  Connection Pool: <80% utilization
  
Resource Utilization:
  CPU: <70% average
  Memory: <80% average
  Storage: <85% utilization
```

#### Capacity Planning Metrics
```yaml
Growth Trends:
  - Monthly active users
  - Request volume growth
  - Data storage growth
  - Resource utilization trends

Scaling Triggers:
  - CPU > 70% for sustained periods
  - Memory > 80% for sustained periods
  - Response time > 2 seconds
  - Error rate > 1%

Capacity Alerts:
  - 80% resource utilization warning
  - 90% resource utilization critical
  - Storage 85% full warning
  - Database connection 80% warning
```

### Cost Monitoring

#### Cost Tracking
```yaml
Budget Alerts:
  Monthly Budget: Configurable
  Alert Thresholds: 50%, 90%, 100%
  Recipients: Finance and operations teams

Cost Breakdown:
  - Compute (Cloud Run): ~40%
  - Database (Cloud SQL): ~30%
  - Storage (Filestore + Cloud Storage): ~15%
  - Networking (Load Balancer): ~10%
  - Monitoring & Logging: ~5%

Optimization Monitoring:
  - Idle resource detection
  - Over-provisioned instances
  - Unused storage
  - Inefficient queries
```

## 📱 Monitoring Dashboards

### Operations Dashboard

#### Dashboard Sections
```yaml
Overview:
  - Service health status
  - Key performance metrics
  - Current alerts
  - Resource utilization summary

Application Performance:
  - Request rates and latencies
  - Error rates by service
  - Active user sessions
  - Cache hit rates

Infrastructure Health:
  - CPU and memory utilization
  - Database performance
  - Storage usage
  - Network throughput

Business Metrics:
  - Scans processed per hour
  - User activity metrics
  - Feature usage statistics
  - License utilization
```

#### Custom Dashboard Creation
```bash
# Export existing dashboard
gcloud monitoring dashboards list
gcloud monitoring dashboards describe DASHBOARD_ID

# Create custom dashboard
gcloud monitoring dashboards create --config=dashboard.json
```

### Executive Dashboard

#### High-Level Metrics
```yaml
Availability:
  - Service uptime percentage
  - Mean time to recovery (MTTR)
  - Mean time between failures (MTBF)

Performance:
  - Average response time
  - 95th percentile response time
  - Throughput (requests/hour)

Business Impact:
  - Active users
  - Scans completed
  - Cost per scan
  - ROI metrics
```

## 🔧 Troubleshooting Guide

### Common Issues & Solutions

#### High Response Times
```yaml
Symptoms:
  - Load balancer latency > 2 seconds
  - User complaints about slow performance

Investigation:
  1. Check Cloud Run CPU/memory utilization
  2. Review database query performance
  3. Check network connectivity
  4. Analyze slow query logs

Solutions:
  - Scale up Cloud Run resources
  - Optimize database queries
  - Add database read replicas
  - Implement caching
```

#### High Error Rates
```yaml
Symptoms:
  - HTTP 5xx errors increasing
  - Application error logs growing

Investigation:
  1. Check application logs for exceptions
  2. Review database connection status
  3. Check file system availability
  4. Verify external service dependencies

Solutions:
  - Restart failed services
  - Scale database connections
  - Check file system permissions
  - Implement circuit breakers
```

#### Resource Exhaustion
```yaml
Symptoms:
  - CPU/memory alerts firing
  - Service becoming unresponsive

Investigation:
  1. Check resource utilization trends
  2. Identify resource-intensive operations
  3. Review scaling configuration
  4. Analyze memory leaks

Solutions:
  - Increase resource limits
  - Optimize application code
  - Implement auto-scaling
  - Add more instances
```

### Monitoring Best Practices

#### Dashboard Design
```yaml
Golden Signals:
  - Latency: Response time metrics
  - Traffic: Request rate metrics  
  - Errors: Error rate metrics
  - Saturation: Resource utilization

Dashboard Principles:
  - Keep it simple and focused
  - Use consistent time ranges
  - Color-code by severity
  - Include context and thresholds
```

#### Alert Management
```yaml
Alert Hygiene:
  - Regular review of alert policies
  - Tune thresholds to reduce noise
  - Ensure actionable alerts only
  - Document runbooks for each alert

Escalation:
  - Tier alerts by severity
  - Define clear escalation paths
  - Implement automated acknowledgments
  - Track mean time to resolution
```

This comprehensive monitoring guide ensures optimal observability, quick issue resolution, and proactive system health management for your Nexus IQ Server deployment on GCP.