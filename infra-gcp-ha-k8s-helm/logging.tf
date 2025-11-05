resource "google_logging_project_bucket_config" "nexus_iq_logs" {
  project        = var.gcp_project_id
  location       = var.gcp_region
  retention_days = var.log_retention_days
  bucket_id      = "${local.cluster_name}-logs-${random_string.suffix.result}"

  depends_on = [google_project_service.required_apis]
}

resource "google_logging_project_sink" "nexus_iq_logs_sink" {
  name        = "${local.cluster_name}-logs-sink"
  project     = var.gcp_project_id
  destination = "logging.googleapis.com/${google_logging_project_bucket_config.nexus_iq_logs.id}"

  filter = <<-EOT
    resource.type="k8s_container"
    resource.labels.cluster_name="${local.cluster_name}"
    resource.labels.namespace_name="nexus-iq"
  EOT

  unique_writer_identity = true
}

resource "google_logging_metric" "error_count" {
  name    = "${local.cluster_name}-error-count"
  project = var.gcp_project_id

  filter = <<-EOT
    resource.type="k8s_container"
    resource.labels.cluster_name="${local.cluster_name}"
    resource.labels.namespace_name="nexus-iq"
    severity>=ERROR
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
    display_name = "Nexus IQ HA Error Count"
  }
}

resource "google_logging_metric" "warning_count" {
  name    = "${local.cluster_name}-warning-count"
  project = var.gcp_project_id

  filter = <<-EOT
    resource.type="k8s_container"
    resource.labels.cluster_name="${local.cluster_name}"
    resource.labels.namespace_name="nexus-iq"
    severity=WARNING
  EOT

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
    display_name = "Nexus IQ HA Warning Count"
  }
}

resource "google_monitoring_alert_policy" "pod_restart_alert" {
  display_name = "${local.cluster_name}-pod-restart-alert"
  project      = var.gcp_project_id
  combiner     = "OR"

  conditions {
    display_name = "Pod Restart Rate"

    condition_threshold {
      filter          = "resource.type=\"k8s_pod\" AND resource.labels.cluster_name=\"${local.cluster_name}\" AND resource.labels.namespace_name=\"nexus-iq\" AND metric.type=\"kubernetes.io/container/restart_count\""
      duration        = "60s"
      comparison      = "COMPARISON_GT"
      threshold_value = 2

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  documentation {
    content = "Nexus IQ Server HA pod is restarting frequently in cluster ${local.cluster_name}"
  }

  enabled = var.enable_monitoring_alerts
}

resource "google_monitoring_alert_policy" "high_error_rate" {
  display_name = "${local.cluster_name}-high-error-rate"
  project      = var.gcp_project_id
  combiner     = "OR"

  conditions {
    display_name = "High Error Rate"

    condition_threshold {
      filter          = "metric.type=\"logging.googleapis.com/user/${local.cluster_name}-error-count\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 10

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  documentation {
    content = "Nexus IQ Server HA is experiencing high error rates in cluster ${local.cluster_name}"
  }

  enabled = var.enable_monitoring_alerts
}
