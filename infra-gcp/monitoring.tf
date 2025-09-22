# Cloud Logging Sink for Nexus IQ logs
resource "google_logging_project_sink" "iq_logs_sink" {
  name        = "nexus-iq-logs-sink"
  destination = "storage.googleapis.com/${google_storage_bucket.iq_logs.name}"
  filter      = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=~\"nexus-iq.*\""
  project     = var.gcp_project_id

  unique_writer_identity = true

  depends_on = [google_project_service.required_apis]
}

# IAM binding for logs sink to write to storage bucket
resource "google_storage_bucket_iam_member" "logs_sink_writer" {
  bucket = google_storage_bucket.iq_logs.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.iq_logs_sink.writer_identity
}

# Cloud Logging Sink for security logs
resource "google_logging_project_sink" "security_logs_sink" {
  name        = "nexus-iq-security-logs-sink"
  destination = "storage.googleapis.com/${google_storage_bucket.iq_logs.name}/security-logs"
  filter      = <<-EOT
    protoPayload.serviceName="compute.googleapis.com" OR
    protoPayload.serviceName="cloudsql.googleapis.com" OR
    protoPayload.serviceName="run.googleapis.com" OR
    protoPayload.serviceName="storage.googleapis.com" OR
    severity >= "WARNING"
  EOT
  project     = var.gcp_project_id

  unique_writer_identity = true
}

# IAM binding for security logs sink
resource "google_storage_bucket_iam_member" "security_logs_sink_writer" {
  bucket = google_storage_bucket.iq_logs.name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.security_logs_sink.writer_identity
}

# Cloud Monitoring Dashboard for Nexus IQ
resource "google_monitoring_dashboard" "iq_dashboard" {
  dashboard_json = jsonencode({
    displayName = "Nexus IQ Server Dashboard"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Cloud Run Request Count"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=~\"nexus-iq.*\""
                      aggregation = {
                        alignmentPeriod  = "60s"
                        perSeriesAligner = "ALIGN_RATE"
                        crossSeriesReducer = "REDUCE_SUM"
                        groupByFields = ["resource.labels.service_name"]
                      }
                    }
                    unitOverride = "1/s"
                  }
                  plotType = "LINE"
                }
              ]
              timeshiftDuration  = "0s"
              yAxis = {
                label = "Requests/sec"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width  = 6
          height = 4
          xPos   = 6
          widget = {
            title = "Cloud Run Request Latencies"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=~\"nexus-iq.*\" AND metric.type=\"run.googleapis.com/request_latencies\""
                      aggregation = {
                        alignmentPeriod    = "60s"
                        perSeriesAligner   = "ALIGN_DELTA"
                        crossSeriesReducer = "REDUCE_PERCENTILE_95"
                        groupByFields      = ["resource.labels.service_name"]
                      }
                    }
                    unitOverride = "ms"
                  }
                  plotType = "LINE"
                }
              ]
              yAxis = {
                label = "Latency (ms)"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width  = 6
          height = 4
          yPos   = 4
          widget = {
            title = "Cloud SQL CPU Utilization"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloudsql_database\" AND metric.type=\"cloudsql.googleapis.com/database/cpu/utilization\""
                      aggregation = {
                        alignmentPeriod    = "60s"
                        perSeriesAligner   = "ALIGN_MEAN"
                        crossSeriesReducer = "REDUCE_MEAN"
                        groupByFields      = ["resource.labels.database_id"]
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              yAxis = {
                label = "CPU Utilization"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width  = 6
          height = 4
          xPos   = 6
          yPos   = 4
          widget = {
            title = "Cloud SQL Memory Utilization"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloudsql_database\" AND metric.type=\"cloudsql.googleapis.com/database/memory/utilization\""
                      aggregation = {
                        alignmentPeriod    = "60s"
                        perSeriesAligner   = "ALIGN_MEAN"
                        crossSeriesReducer = "REDUCE_MEAN"
                        groupByFields      = ["resource.labels.database_id"]
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              yAxis = {
                label = "Memory Utilization"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width  = 12
          height = 4
          yPos   = 8
          widget = {
            title = "Error Rate by Service"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=~\"nexus-iq.*\" AND metric.type=\"run.googleapis.com/request_count\" AND metric.labels.response_code_class=\"4xx\""
                      aggregation = {
                        alignmentPeriod    = "60s"
                        perSeriesAligner   = "ALIGN_RATE"
                        crossSeriesReducer = "REDUCE_SUM"
                        groupByFields      = ["resource.labels.service_name"]
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              yAxis = {
                label = "4xx Errors/sec"
                scale = "LINEAR"
              }
            }
          }
        }
      ]
    }
  })
  project = var.gcp_project_id
}

# Alerting Policy for High CPU Usage
resource "google_monitoring_alert_policy" "high_cpu_alert" {
  display_name = "Nexus IQ High CPU Usage"
  project      = var.gcp_project_id
  combiner     = "OR"

  conditions {
    display_name = "Cloud Run CPU Utilization"
    condition_threshold {
      filter          = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=~\"nexus-iq.*\" AND metric.type=\"run.googleapis.com/container/cpu/utilizations\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = var.cpu_alert_threshold

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }

      trigger {
        count = 1
      }
    }
  }

  conditions {
    display_name = "Cloud SQL CPU Utilization"
    condition_threshold {
      filter          = "resource.type=\"cloudsql_database\" AND metric.type=\"cloudsql.googleapis.com/database/cpu/utilization\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = var.db_cpu_alert_threshold

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = [
    google_monitoring_notification_channel.email[0].name
  ]

  alert_strategy {
    auto_close = "86400s"  # 24 hours
  }

  enabled = var.enable_monitoring_alerts
}

# Alerting Policy for High Memory Usage
resource "google_monitoring_alert_policy" "high_memory_alert" {
  display_name = "Nexus IQ High Memory Usage"
  project      = var.gcp_project_id
  combiner     = "OR"

  conditions {
    display_name = "Cloud Run Memory Utilization"
    condition_threshold {
      filter          = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=~\"nexus-iq.*\" AND metric.type=\"run.googleapis.com/container/memory/utilizations\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = var.memory_alert_threshold

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }

      trigger {
        count = 1
      }
    }
  }

  conditions {
    display_name = "Cloud SQL Memory Utilization"
    condition_threshold {
      filter          = "resource.type=\"cloudsql_database\" AND metric.type=\"cloudsql.googleapis.com/database/memory/utilization\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = var.db_memory_alert_threshold

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = [
    google_monitoring_notification_channel.email[0].name
  ]

  alert_strategy {
    auto_close = "86400s"
  }

  enabled = var.enable_monitoring_alerts
}

# Alerting Policy for High Error Rate
resource "google_monitoring_alert_policy" "high_error_rate_alert" {
  display_name = "Nexus IQ High Error Rate"
  project      = var.gcp_project_id
  combiner     = "OR"

  conditions {
    display_name = "4xx Error Rate"
    condition_threshold {
      filter          = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=~\"nexus-iq.*\" AND metric.type=\"run.googleapis.com/request_count\" AND metric.labels.response_code_class=\"4xx\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = var.error_rate_alert_threshold

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
      }

      trigger {
        count = 1
      }
    }
  }

  conditions {
    display_name = "5xx Error Rate"
    condition_threshold {
      filter          = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=~\"nexus-iq.*\" AND metric.type=\"run.googleapis.com/request_count\" AND metric.labels.response_code_class=\"5xx\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = var.error_rate_alert_threshold

      aggregations {
        alignment_period     = "60s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = [
    google_monitoring_notification_channel.email[0].name
  ]

  alert_strategy {
    auto_close = "86400s"
  }

  enabled = var.enable_monitoring_alerts
}

# Alerting Policy for Database Connection Issues
resource "google_monitoring_alert_policy" "database_connection_alert" {
  display_name = "Nexus IQ Database Connection Issues"
  project      = var.gcp_project_id
  combiner     = "OR"

  conditions {
    display_name = "Database Connection Count"
    condition_threshold {
      filter          = "resource.type=\"cloudsql_database\" AND metric.type=\"cloudsql.googleapis.com/database/postgresql/num_backends\""
      duration        = "300s"
      comparison      = "COMPARISON_GREATER_THAN"
      threshold_value = var.db_connection_alert_threshold

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = [
    google_monitoring_notification_channel.email[0].name
  ]

  alert_strategy {
    auto_close = "86400s"
  }

  enabled = var.enable_monitoring_alerts
}

# Notification Channel for Email Alerts
resource "google_monitoring_notification_channel" "email" {
  count        = length(var.alert_email_addresses) > 0 ? 1 : 0
  display_name = "Nexus IQ Email Notifications"
  type         = "email"
  project      = var.gcp_project_id

  labels = {
    email_address = var.alert_email_addresses[0]
  }

  enabled = var.enable_monitoring_alerts
}

# Notification Channel for Slack (optional)
resource "google_monitoring_notification_channel" "slack" {
  count        = var.slack_webhook_url != "" ? 1 : 0
  display_name = "Nexus IQ Slack Notifications"
  type         = "slack"
  project      = var.gcp_project_id

  labels = {
    url = var.slack_webhook_url
  }

  enabled = var.enable_monitoring_alerts
}

# Notification Channel for PagerDuty (optional)
resource "google_monitoring_notification_channel" "pagerduty" {
  count        = var.pagerduty_service_key != "" ? 1 : 0
  display_name = "Nexus IQ PagerDuty Notifications"
  type         = "pagerduty"
  project      = var.gcp_project_id

  labels = {
    service_key = var.pagerduty_service_key
  }

  enabled = var.enable_monitoring_alerts
}

# Uptime Check for Nexus IQ Service
resource "google_monitoring_uptime_check_config" "iq_uptime_check" {
  display_name = "Nexus IQ Uptime Check"
  project      = var.gcp_project_id
  timeout      = "10s"
  period       = "60s"

  http_check {
    path         = "/"
    port         = "443"
    use_ssl      = var.enable_ssl
    validate_ssl = var.enable_ssl
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

  selected_regions = var.uptime_check_regions
}

# Uptime Check Alert Policy
resource "google_monitoring_alert_policy" "uptime_check_alert" {
  display_name = "Nexus IQ Service Down"
  project      = var.gcp_project_id
  combiner     = "OR"

  conditions {
    display_name = "Uptime check failed"
    condition_threshold {
      filter         = "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND resource.type=\"uptime_url\""
      duration       = "300s"
      comparison     = "COMPARISON_EQUAL"
      threshold_value = 0

      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_FRACTION_TRUE"
        cross_series_reducer = "REDUCE_MEAN"
        group_by_fields      = ["resource.labels.project_id"]
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = concat(
    length(var.alert_email_addresses) > 0 ? [google_monitoring_notification_channel.email[0].name] : [],
    var.slack_webhook_url != "" ? [google_monitoring_notification_channel.slack[0].name] : [],
    var.pagerduty_service_key != "" ? [google_monitoring_notification_channel.pagerduty[0].name] : []
  )

  alert_strategy {
    auto_close = "86400s"
  }

  enabled = var.enable_monitoring_alerts
}

# SLO for Request Latency
resource "google_monitoring_slo" "request_latency_slo" {
  service      = google_monitoring_service.iq_service.service_id
  slo_id       = "request-latency-slo"
  display_name = "Request Latency SLO"

  request_based_sli {
    distribution_cut {
      distribution_filter = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=~\"nexus-iq.*\" AND metric.type=\"run.googleapis.com/request_latencies\""
      range {
        max = var.slo_latency_threshold_ms
      }
    }
  }

  goal          = var.slo_target
  rolling_period = "86400s"  # 24 hours
}

# SLO for Error Rate
resource "google_monitoring_slo" "error_rate_slo" {
  service      = google_monitoring_service.iq_service.service_id
  slo_id       = "error-rate-slo"
  display_name = "Error Rate SLO"

  request_based_sli {
    good_total_ratio {
      total_service_filter = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=~\"nexus-iq.*\" AND metric.type=\"run.googleapis.com/request_count\""
      good_service_filter  = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=~\"nexus-iq.*\" AND metric.type=\"run.googleapis.com/request_count\" AND metric.labels.response_code_class!=\"5xx\""
    }
  }

  goal          = var.slo_target
  rolling_period = "86400s"
}

# Service for SLOs
resource "google_monitoring_service" "iq_service" {
  service_id   = "nexus-iq-service"
  display_name = "Nexus IQ Service"
  project      = var.gcp_project_id
}

# Custom Metrics for Application-specific monitoring
resource "google_logging_metric" "application_errors" {
  name   = "nexus_iq_application_errors"
  filter = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=~\"nexus-iq.*\" AND (severity=\"ERROR\" OR jsonPayload.level=\"ERROR\")"
  project = var.gcp_project_id

  label_extractors = {
    "service_name" = "EXTRACT(resource.labels.service_name)"
    "severity"     = "EXTRACT(severity)"
  }

  metric_descriptor {
    metric_kind = "COUNTER"
    value_type  = "INT64"
    display_name = "Nexus IQ Application Errors"
  }
}

# Custom Metrics for Database Query Performance
resource "google_logging_metric" "slow_database_queries" {
  name   = "nexus_iq_slow_database_queries"
  filter = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=~\"nexus-iq.*\" AND jsonPayload.message=~\".*slow query.*\""
  project = var.gcp_project_id

  metric_descriptor {
    metric_kind = "COUNTER"
    value_type  = "INT64"
    display_name = "Nexus IQ Slow Database Queries"
  }
}