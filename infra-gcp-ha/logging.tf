# Cloud Logging configuration for Nexus IQ HA
# Aggregates 5 log types: application, request, audit, policy-violation, and container stderr

# Log bucket for centralized log storage
resource "google_logging_project_bucket_config" "iq_ha_logs" {
  project        = var.gcp_project_id
  location       = "global"
  retention_days = var.log_retention_days
  bucket_id      = "nexus-iq-ha-logs-${random_string.suffix.result}"

  description = "Centralized log bucket for Nexus IQ HA application logs"
}

# Log sink for Docker container logs (stderr/stdout)
resource "google_logging_project_sink" "iq_ha_container_logs" {
  name        = "nexus-iq-ha-container-logs-${random_string.suffix.result}"
  project     = var.gcp_project_id
  destination = "logging.googleapis.com/${google_logging_project_bucket_config.iq_ha_logs.id}"

  filter = <<-EOT
    resource.type="gce_instance"
    labels."compute.googleapis.com/resource_name"=~"nexus-iq-ha.*"
    logName:"docker"
  EOT

  unique_writer_identity = true
}

# IAM binding to allow the log sink to write to the log bucket
# Note: writer_identity already has permissions via unique_writer_identity = true
# This explicit binding is not needed when unique_writer_identity is enabled

# Log-based metric: Error count
resource "google_logging_metric" "iq_ha_error_count" {
  name        = "nexus-iq-ha-error-count"
  project     = var.gcp_project_id
  description = "Count of ERROR level logs from Nexus IQ HA instances"

  filter = <<-EOT
    resource.type="gce_instance"
    labels."compute.googleapis.com/resource_name"=~"nexus-iq-ha.*"
    severity="ERROR"
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"

    labels {
      key         = "instance_name"
      value_type  = "STRING"
      description = "Instance name"
    }
  }

  label_extractors = {
    "instance_name" = "EXTRACT(labels.\"compute.googleapis.com/resource_name\")"
  }
}

# Log-based metric: Warning count
resource "google_logging_metric" "iq_ha_warning_count" {
  name        = "nexus-iq-ha-warning-count"
  project     = var.gcp_project_id
  description = "Count of WARNING level logs from Nexus IQ HA instances"

  filter = <<-EOT
    resource.type="gce_instance"
    labels."compute.googleapis.com/resource_name"=~"nexus-iq-ha.*"
    severity="WARNING"
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"

    labels {
      key         = "instance_name"
      value_type  = "STRING"
      description = "Instance name"
    }
  }

  label_extractors = {
    "instance_name" = "EXTRACT(labels.\"compute.googleapis.com/resource_name\")"
  }
}

# Alert policy: High error rate
# COMMENTED OUT: Cannot be created until the log-based metric has data (10+ minutes after deployment)
# To enable: Uncomment this resource and run terraform apply after the infrastructure has been running
# and generating logs for at least 10 minutes
#
# resource "google_monitoring_alert_policy" "iq_ha_high_error_rate" {
#   project      = var.gcp_project_id
#   display_name = "Nexus IQ HA - High Error Rate"
#   combiner     = "OR"
#
#   conditions {
#     display_name = "Error count exceeds 50 per minute"
#
#     condition_threshold {
#       filter          = "metric.type=\"logging.googleapis.com/user/nexus-iq-ha-error-count\" resource.type=\"gce_instance\""
#       duration        = "300s"
#       comparison      = "COMPARISON_GT"
#       threshold_value = 50
#
#       aggregations {
#         alignment_period   = "60s"
#         per_series_aligner = "ALIGN_RATE"
#       }
#     }
#   }
#
#   notification_channels = []
#
#   alert_strategy {
#     auto_close = "1800s"
#   }
#
#   documentation {
#     content   = "Nexus IQ HA instance is generating more than 50 errors per minute. Check instance logs and health status."
#     mime_type = "text/markdown"
#   }
#
#   enabled = true
#
#   depends_on = [google_logging_metric.iq_ha_error_count]
# }

# Alert policy: Container restart
resource "google_monitoring_alert_policy" "iq_ha_container_restart" {
  project      = var.gcp_project_id
  display_name = "Nexus IQ HA - Container Restart Detected"
  combiner     = "OR"

  conditions {
    display_name = "Docker container restarted"

    condition_matched_log {
      filter = <<-EOT
        resource.type="gce_instance"
        labels."compute.googleapis.com/resource_name"=~"nexus-iq-ha.*"
        textPayload=~"Starting Nexus IQ Server HA Docker Installation"
      EOT
    }
  }

  notification_channels = []

  alert_strategy {
    auto_close = "1800s"
    notification_rate_limit {
      period = "300s"
    }
  }

  documentation {
    content   = "Nexus IQ HA Docker container has restarted. This could indicate a crash or manual restart. Check startup logs."
    mime_type = "text/markdown"
  }

  enabled = true
}

# Alert policy: NFS mount failure
resource "google_monitoring_alert_policy" "iq_ha_nfs_mount_failure" {
  project      = var.gcp_project_id
  display_name = "Nexus IQ HA - NFS Mount Failure"
  combiner     = "OR"

  conditions {
    display_name = "NFS mount failed after retries"

    condition_matched_log {
      filter = <<-EOT
        resource.type="gce_instance"
        labels."compute.googleapis.com/resource_name"=~"nexus-iq-ha.*"
        textPayload=~"FATAL: NFS mount failed after 5 attempts"
      EOT
    }
  }

  notification_channels = []

  alert_strategy {
    auto_close = "1800s"
    notification_rate_limit {
      period = "300s"
    }
  }

  documentation {
    content   = "Nexus IQ HA instance failed to mount Cloud Filestore NFS after 5 attempts. Check Filestore status and network connectivity."
    mime_type = "text/markdown"
  }

  enabled = true
}

# Log view for easy filtering of IQ Server logs
resource "google_logging_log_view" "iq_ha_view" {
  name        = "nexus-iq-ha-view"
  bucket      = google_logging_project_bucket_config.iq_ha_logs.id
  description = "Filtered view of Nexus IQ HA application logs"

  # Simple filter - only resource type restriction (labels not allowed in view filters)
  filter = "resource.type=gce_instance"
}
