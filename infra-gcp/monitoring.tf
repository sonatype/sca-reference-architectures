# Cloud Logging sink for Cloud Run logs
resource "google_logging_project_sink" "iq_cloud_run_logs" {
  name        = "ref-arch-iq-cloud-run-sink"
  destination = "storage.googleapis.com/${google_storage_bucket.lb_logs.name}"
  
  filter = "resource.type=cloud_run_revision AND resource.labels.service_name=ref-arch-iq-service"

  unique_writer_identity = true
}

# Cloud Logging sink for database logs
resource "google_logging_project_sink" "iq_database_logs" {
  name        = "ref-arch-iq-database-sink"
  destination = "storage.googleapis.com/${google_storage_bucket.lb_logs.name}"
  
  filter = "resource.type=cloudsql_database AND resource.labels.database_id=${google_sql_database_instance.iq_db.name}"

  unique_writer_identity = true
}

# Log-based metrics for application monitoring
resource "google_logging_metric" "iq_error_rate" {
  name   = "ref-arch-iq-error-rate"
  filter = "resource.type=cloud_run_revision AND resource.labels.service_name=ref-arch-iq-service AND (severity=ERROR OR severity=CRITICAL)"

  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "DOUBLE"
    display_name = "Nexus IQ Error Rate"
  }

  label_extractors = {
    "severity" = "EXTRACT(severity)"
    "service"  = "EXTRACT(resource.labels.service_name)"
  }
}

resource "google_logging_metric" "iq_response_time" {
  name   = "ref-arch-iq-response-time"
  filter = "resource.type=cloud_run_revision AND resource.labels.service_name=ref-arch-iq-service AND httpRequest.status>=200 AND httpRequest.status<400"

  metric_descriptor {
    metric_kind = "GAUGE"
    value_type  = "DOUBLE"
    display_name = "Nexus IQ Response Time"
    unit = "s"
  }

  value_extractor = "EXTRACT(httpRequest.latency)"

  label_extractors = {
    "status" = "EXTRACT(httpRequest.status)"
    "method" = "EXTRACT(httpRequest.requestMethod)"
  }
}

# Monitoring dashboard for Nexus IQ
resource "google_monitoring_dashboard" "iq_dashboard" {
  dashboard_json = jsonencode({
    displayName = "Nexus IQ Server Dashboard"
    mosaicLayout = {
      tiles = [
        {
          width = 6
          height = 4
          widget = {
            title = "Cloud Run Instance Count"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"run.googleapis.com/container/instance_count\" resource.type=\"cloud_run_revision\" resource.label.service_name=\"ref-arch-iq-service\""
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_MEAN"
                    }
                  }
                }
                plotType = "LINE"
              }]
              timeshiftDuration = "0s"
              yAxis = {
                label = "Instance Count"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width = 6
          height = 4
          xPos = 6
          widget = {
            title = "Request Count"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"run.googleapis.com/request_count\" resource.type=\"cloud_run_revision\" resource.label.service_name=\"ref-arch-iq-service\""
                    aggregation = {
                      alignmentPeriod    = "60s"
                      perSeriesAligner   = "ALIGN_RATE"
                      crossSeriesReducer = "REDUCE_SUM"
                    }
                  }
                }
                plotType = "LINE"
              }]
              yAxis = {
                label = "Requests/sec"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width = 6
          height = 4
          yPos = 4
          widget = {
            title = "CPU Utilization"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"run.googleapis.com/container/cpu/utilizations\" resource.type=\"cloud_run_revision\" resource.label.service_name=\"ref-arch-iq-service\""
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_MEAN"
                    }
                  }
                }
                plotType = "LINE"
              }]
              yAxis = {
                label = "CPU Utilization"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width = 6
          height = 4
          xPos = 6
          yPos = 4
          widget = {
            title = "Memory Utilization"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"run.googleapis.com/container/memory/utilizations\" resource.type=\"cloud_run_revision\" resource.label.service_name=\"ref-arch-iq-service\""
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_MEAN"
                    }
                  }
                }
                plotType = "LINE"
              }]
              yAxis = {
                label = "Memory Utilization"
                scale = "LINEAR"
              }
            }
          }
        },
        {
          width = 12
          height = 4
          yPos = 8
          widget = {
            title = "Database Connections"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"cloudsql.googleapis.com/database/postgresql/num_backends\" resource.type=\"cloudsql_database\""
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_MEAN"
                    }
                  }
                }
                plotType = "LINE"
              }]
              yAxis = {
                label = "Active Connections"
                scale = "LINEAR"
              }
            }
          }
        }
      ]
    }
  })
}

# Alert policies for monitoring
resource "google_monitoring_alert_policy" "iq_high_error_rate" {
  display_name = "Nexus IQ High Error Rate"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "Error rate above threshold"
    
    condition_threshold {
      filter          = "resource.type=cloud_run_revision AND resource.label.service_name=ref-arch-iq-service"
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = var.alert_error_rate_threshold

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  notification_channels = var.notification_channels

  alert_strategy {
    auto_close = "1800s"
  }
}

resource "google_monitoring_alert_policy" "iq_high_cpu" {
  display_name = "Nexus IQ High CPU Usage"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "CPU utilization above threshold"
    
    condition_threshold {
      filter          = "resource.type=cloud_run_revision AND resource.label.service_name=ref-arch-iq-service AND metric.type=run.googleapis.com/container/cpu/utilizations"
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = var.alert_cpu_threshold

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = var.notification_channels

  alert_strategy {
    auto_close = "1800s"
  }
}

resource "google_monitoring_alert_policy" "iq_high_memory" {
  display_name = "Nexus IQ High Memory Usage"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "Memory utilization above threshold"
    
    condition_threshold {
      filter          = "resource.type=cloud_run_revision AND resource.label.service_name=ref-arch-iq-service AND metric.type=run.googleapis.com/container/memory/utilizations"
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = var.alert_memory_threshold

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = var.notification_channels

  alert_strategy {
    auto_close = "1800s"
  }
}

resource "google_monitoring_alert_policy" "iq_database_connections" {
  display_name = "Nexus IQ Database Connection Alert"
  combiner     = "OR"
  enabled      = true

  conditions {
    display_name = "High database connections"
    
    condition_threshold {
      filter          = "resource.type=cloudsql_database AND metric.type=cloudsql.googleapis.com/database/postgresql/num_backends"
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = var.alert_db_connections_threshold

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = var.notification_channels

  alert_strategy {
    auto_close = "1800s"
  }
}

# Notification channel (email)
resource "google_monitoring_notification_channel" "email" {
  count        = length(var.alert_email_addresses)
  display_name = "Email Notification ${count.index + 1}"
  type         = "email"
  
  labels = {
    email_address = var.alert_email_addresses[count.index]
  }

  enabled = true
}

# Uptime check for service availability
resource "google_monitoring_uptime_check_config" "iq_uptime_check" {
  display_name = "Nexus IQ Service Uptime Check"
  timeout      = "10s"
  period       = "300s"

  http_check {
    path           = "/"
    port           = 80
    request_method = "GET"
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
}

# SLO and SLI definitions
resource "google_monitoring_slo" "iq_availability_slo" {
  service      = google_monitoring_service.iq_service.service_id
  display_name = "Nexus IQ Availability SLO"
  
  request_based_sli {
    good_total_ratio {
      total_service_filter = "resource.type=cloud_run_revision AND resource.label.service_name=ref-arch-iq-service"
      good_service_filter  = "resource.type=cloud_run_revision AND resource.label.service_name=ref-arch-iq-service AND metric.label.response_code_class=2xx"
    }
  }

  goal = var.availability_slo_target
  rolling_period = "2592000s"  # 30 days
}

resource "google_monitoring_service" "iq_service" {
  service_id   = "ref-arch-iq-service"
  display_name = "Nexus IQ Server Service"
}

# Custom metrics for business logic (if needed)
resource "google_logging_metric" "iq_scan_requests" {
  name   = "ref-arch-iq-scan-requests"
  filter = "resource.type=cloud_run_revision AND resource.labels.service_name=ref-arch-iq-service AND jsonPayload.message=~\"scan.*completed\""

  metric_descriptor {
    metric_kind  = "DELTA"
    value_type   = "INT64"
    display_name = "Nexus IQ Scan Requests"
  }
}