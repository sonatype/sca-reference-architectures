# Cloud Logging for Compute Engine instances
resource "google_logging_project_sink" "iq_ha_compute_logs" {
  name        = "ref-arch-iq-ha-compute-logs"
  description = "Sink for Nexus IQ HA Compute Engine logs"

  # Send logs to Cloud Logging
  destination = "logging.googleapis.com/projects/${var.gcp_project_id}/logs/nexus-iq-ha"

  # Filter for Nexus IQ related logs
  filter = <<-EOT
    resource.type="gce_instance" AND
    resource.labels.instance_name=~"nexus-iq-ha-.*"
  EOT

  # Use a unique writer identity
  unique_writer_identity = true
}

# Monitoring dashboard for Nexus IQ HA
resource "google_monitoring_dashboard" "iq_ha_dashboard" {
  dashboard_json = jsonencode({
    displayName = "Nexus IQ HA Monitoring Dashboard"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Instance Health"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"gce_instance\" AND resource.label.instance_name=~\"nexus-iq-ha-.*\""
                      aggregation = {
                        alignmentPeriod  = "60s"
                        perSeriesAligner = "ALIGN_MEAN"
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              yAxis = {
                label = "CPU Utilization"
              }
            }
          }
        },
        {
          width  = 6
          height = 4
          xPos   = 6
          widget = {
            title = "Load Balancer Requests"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"https_lb_rule\""
                      aggregation = {
                        alignmentPeriod  = "60s"
                        perSeriesAligner = "ALIGN_RATE"
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              yAxis = {
                label = "Requests per second"
              }
            }
          }
        },
        {
          width  = 6
          height = 4
          yPos   = 4
          widget = {
            title = "Database Connections"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloudsql_database\" AND resource.label.database_id=\"${var.gcp_project_id}:${google_sql_database_instance.iq_ha_db.name}\""
                      aggregation = {
                        alignmentPeriod  = "60s"
                        perSeriesAligner = "ALIGN_MEAN"
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              yAxis = {
                label = "Active Connections"
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
            title = "Instance Group Size"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"gce_instance_group\" AND resource.label.instance_group_name=\"${google_compute_region_instance_group_manager.iq_mig.name}\""
                      aggregation = {
                        alignmentPeriod  = "60s"
                        perSeriesAligner = "ALIGN_MEAN"
                      }
                    }
                  }
                  plotType = "LINE"
                }
              ]
              yAxis = {
                label = "Number of Instances"
              }
            }
          }
        }
      ]
    }
  })
}

# Uptime check for the load balancer
resource "google_monitoring_uptime_check_config" "iq_ha_uptime_check" {
  display_name = "Nexus IQ HA Uptime Check"
  timeout      = "10s"
  period       = "60s"

  http_check {
    use_ssl        = var.enable_ssl
    path           = "/"
    port           = var.enable_ssl ? 443 : 80
    request_method = "GET"
    validate_ssl   = var.enable_ssl
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.gcp_project_id
      host       = var.domain_name != "" ? var.domain_name : google_compute_global_address.iq_ha_lb_ip.address
    }
  }

  checker_type = "STATIC_IP_CHECKERS"
  selected_regions = [
    "USA",
    "EUROPE",
    "ASIA_PACIFIC"
  ]
}

# Alert policy for instance health
resource "google_monitoring_alert_policy" "iq_ha_instance_health" {
  display_name = "Nexus IQ HA - Instance Health Alert"
  enabled      = "true"
  combiner     = "OR"

  conditions {
    display_name = "Instance Down"

    condition_threshold {
      filter          = "resource.type=\"gce_instance\" AND resource.label.instance_name=~\"nexus-iq-ha-.*\""
      duration        = "300s"
      comparison      = "COMPARISON_LT"
      threshold_value = 1

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = []

  alert_strategy {
    auto_close = "1800s"
  }
}

# Alert policy for high CPU usage
resource "google_monitoring_alert_policy" "iq_ha_high_cpu" {
  display_name = "Nexus IQ HA - High CPU Usage"
  enabled      = "true"
  combiner     = "OR"

  conditions {
    display_name = "High CPU Usage"

    condition_threshold {
      filter          = "resource.type=\"gce_instance\" AND resource.label.instance_name=~\"nexus-iq-ha-.*\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0.8

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = []

  alert_strategy {
    auto_close = "1800s"
  }
}

# Alert policy for load balancer errors
resource "google_monitoring_alert_policy" "iq_ha_lb_errors" {
  display_name = "Nexus IQ HA - Load Balancer Errors"
  enabled      = "true"
  combiner     = "OR"

  conditions {
    display_name = "High Error Rate"

    condition_threshold {
      filter          = "resource.type=\"https_lb_rule\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0.05 # 5% error rate

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  notification_channels = []

  alert_strategy {
    auto_close = "1800s"
  }
}

# Alert policy for database connectivity
resource "google_monitoring_alert_policy" "iq_ha_db_connectivity" {
  display_name = "Nexus IQ HA - Database Connectivity"
  enabled      = "true"
  combiner     = "OR"

  conditions {
    display_name = "Database Connection Issues"

    condition_threshold {
      filter          = "resource.type=\"cloudsql_database\" AND resource.label.database_id=\"${var.gcp_project_id}:${google_sql_database_instance.iq_ha_db.name}\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 180 # 90% of max connections

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MEAN"
      }
    }
  }

  notification_channels = []

  alert_strategy {
    auto_close = "1800s"
  }
}

# Cloud Logging sink for application logs
resource "google_logging_project_sink" "iq_ha_app_logs" {
  name        = "ref-arch-iq-ha-app-logs"
  description = "Sink for Nexus IQ HA application logs"

  # Send to BigQuery for analysis (optional)
  destination = "bigquery.googleapis.com/projects/${var.gcp_project_id}/datasets/nexus_iq_ha_logs"

  # Filter for application logs
  filter = <<-EOT
    resource.type="gce_instance" AND
    resource.labels.instance_name=~"nexus-iq-ha-.*" AND
    (jsonPayload.message=~".*nexus.*" OR jsonPayload.message=~".*IQ.*")
  EOT

  unique_writer_identity = true
}

# BigQuery dataset for log analysis (optional)
resource "google_bigquery_dataset" "iq_ha_logs" {
  dataset_id  = "nexus_iq_ha_logs"
  description = "Dataset for Nexus IQ HA log analysis"
  location    = var.gcp_region

  labels = merge(var.common_tags, {
    component = "nexus-iq-ha-logging"
  })

  # Automatically delete old data
  default_table_expiration_ms = 2592000000 # 30 days
}

# Grant logging sink permission to write to BigQuery
resource "google_bigquery_dataset_iam_member" "iq_ha_logs_writer" {
  dataset_id = google_bigquery_dataset.iq_ha_logs.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = google_logging_project_sink.iq_ha_app_logs.writer_identity
}