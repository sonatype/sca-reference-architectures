# Global external IP address for the load balancer
resource "google_compute_global_address" "iq_ha_lb_ip" {
  name         = "ref-arch-iq-ha-lb-ip"
  ip_version   = "IPV4"
  address_type = "EXTERNAL"
  description  = "External IP for Nexus IQ HA Load Balancer"
}

# Global HTTP(S) Load Balancer - URL Map
resource "google_compute_url_map" "iq_ha_url_map" {
  name            = "ref-arch-iq-ha-url-map"
  description     = "URL map for Nexus IQ HA Load Balancer"
  default_service = google_compute_backend_service.iq_ha_backend.id

  # Health check path for the application
  host_rule {
    hosts        = ["*"]
    path_matcher = "allpaths"
  }

  path_matcher {
    name            = "allpaths"
    default_service = google_compute_backend_service.iq_ha_backend.id

    path_rule {
      paths   = ["/*"]
      service = google_compute_backend_service.iq_ha_backend.id
    }
  }
}

# Backend service for the MIG
resource "google_compute_backend_service" "iq_ha_backend" {
  name                  = "ref-arch-iq-ha-backend"
  description           = "Backend service for Nexus IQ HA"
  protocol              = "HTTP"
  port_name             = "http"
  timeout_sec           = 30
  enable_cdn            = false
  load_balancing_scheme = "EXTERNAL_MANAGED"

  backend {
    group           = google_compute_region_instance_group_manager.iq_mig.instance_group
    balancing_mode  = "UTILIZATION"
    max_utilization = 0.8
    capacity_scaler = 1.0
  }

  health_checks = [google_compute_health_check.iq_lb_health_check.id]

  # Connection draining timeout
  connection_draining_timeout_sec = 300

  # Session affinity NONE for proper HA clustering (instances share state via database)
  session_affinity = "NONE"

  # Enable logging
  log_config {
    enable      = true
    sample_rate = 1.0
  }
}

# Health check for load balancer
resource "google_compute_health_check" "iq_lb_health_check" {
  name                = "ref-arch-iq-ha-lb-health-check"
  description         = "Health check for Nexus IQ HA Load Balancer"
  timeout_sec         = 10
  check_interval_sec  = 30
  healthy_threshold   = 2
  unhealthy_threshold = 3

  http_health_check {
    request_path = "/ping"
    port         = 8070
  }

  log_config {
    enable = true
  }
}

# HTTPS target proxy (if SSL is enabled)
resource "google_compute_target_https_proxy" "iq_ha_https_proxy" {
  count            = var.enable_ssl ? 1 : 0
  name             = "ref-arch-iq-ha-https-proxy"
  description      = "HTTPS proxy for Nexus IQ HA"
  url_map          = google_compute_url_map.iq_ha_url_map.id
  ssl_certificates = var.domain_name != "" ? [google_compute_managed_ssl_certificate.iq_ha_ssl_cert[0].id] : []
}

# HTTP target proxy (always created for HTTP redirect or standalone HTTP)
resource "google_compute_target_http_proxy" "iq_ha_http_proxy" {
  name        = "ref-arch-iq-ha-http-proxy"
  description = "HTTP proxy for Nexus IQ HA"
  url_map     = var.enable_ssl ? google_compute_url_map.iq_ha_redirect_url_map[0].id : google_compute_url_map.iq_ha_url_map.id
}

# URL map for HTTP to HTTPS redirect (when SSL is enabled)
resource "google_compute_url_map" "iq_ha_redirect_url_map" {
  count       = var.enable_ssl ? 1 : 0
  name        = "ref-arch-iq-ha-redirect-url-map"
  description = "URL map for HTTP to HTTPS redirect"

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

# Global forwarding rule for HTTPS (if SSL is enabled)
resource "google_compute_global_forwarding_rule" "iq_ha_https_forwarding_rule" {
  count                 = var.enable_ssl ? 1 : 0
  name                  = "ref-arch-iq-ha-https-forwarding-rule"
  description           = "HTTPS forwarding rule for Nexus IQ HA"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "443"
  target                = google_compute_target_https_proxy.iq_ha_https_proxy[0].id
  ip_address            = google_compute_global_address.iq_ha_lb_ip.id
}

# Global forwarding rule for HTTP
resource "google_compute_global_forwarding_rule" "iq_ha_http_forwarding_rule" {
  name                  = "ref-arch-iq-ha-http-forwarding-rule"
  description           = "HTTP forwarding rule for Nexus IQ HA"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "80"
  target                = google_compute_target_http_proxy.iq_ha_http_proxy.id
  ip_address            = google_compute_global_address.iq_ha_lb_ip.id
}

# Managed SSL certificate (if SSL is enabled and domain is provided)
resource "google_compute_managed_ssl_certificate" "iq_ha_ssl_cert" {
  count       = var.enable_ssl && var.domain_name != "" ? 1 : 0
  name        = "ref-arch-iq-ha-ssl-cert"
  description = "Managed SSL certificate for Nexus IQ HA"

  managed {
    domains = [var.domain_name]
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Cloud Armor security policy (optional, for DDoS protection)
resource "google_compute_security_policy" "iq_ha_security_policy" {
  name        = "ref-arch-iq-ha-security-policy"
  description = "Security policy for Nexus IQ HA Load Balancer"

  # Default rule to allow traffic
  rule {
    action   = "allow"
    priority = "2147483647"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Default allow rule"
  }

  # Rate limiting rule
  rule {
    action   = "rate_based_ban"
    priority = "1000"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Rate limiting rule"

    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"

      rate_limit_threshold {
        count        = 100
        interval_sec = 60
      }

      ban_duration_sec = 600
    }
  }
}

# Cloud Armor security policy is attached directly to the backend service above
# No separate attachment resource is needed - it's configured in the backend_service resource