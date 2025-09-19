# Global External HTTP(S) Load Balancer
resource "google_compute_global_address" "iq_lb_ip" {
  name         = "ref-arch-iq-lb-ip"
  address_type = "EXTERNAL"
}

# Health check for Cloud Run service
resource "google_compute_health_check" "iq_health_check" {
  name                = "ref-arch-iq-health-check"
  timeout_sec         = 15
  check_interval_sec  = 30
  healthy_threshold   = 2
  unhealthy_threshold = 3

  http_health_check {
    port               = 8070
    request_path       = "/"
    proxy_header       = "NONE"
  }

  log_config {
    enable = true
  }
}

# Admin health check for port 8071 (optional)
resource "google_compute_health_check" "iq_admin_health_check" {
  name                = "ref-arch-iq-admin-health-check"
  timeout_sec         = 15
  check_interval_sec  = 30
  healthy_threshold   = 2
  unhealthy_threshold = 3

  http_health_check {
    port               = 8071
    request_path       = "/healthcheck"
    proxy_header       = "NONE"
  }

  log_config {
    enable = true
  }
}

# Backend service for Cloud Run
resource "google_compute_backend_service" "iq_backend_service" {
  name                    = "ref-arch-iq-backend-service"
  protocol                = "HTTP"
  port_name               = "http"
  timeout_sec             = 300
  enable_cdn              = var.enable_cdn
  connection_draining_timeout_sec = 300

  backend {
    group = google_compute_region_network_endpoint_group.iq_neg.id
  }

  health_checks = [google_compute_health_check.iq_health_check.id]

  log_config {
    enable      = true
    sample_rate = var.lb_log_sample_rate
  }

  iap {
    oauth2_client_id     = var.iap_oauth2_client_id
    oauth2_client_secret = var.iap_oauth2_client_secret
  }

  depends_on = [google_compute_region_network_endpoint_group.iq_neg]
}

# URL map for routing
resource "google_compute_url_map" "iq_url_map" {
  name            = "ref-arch-iq-url-map"
  default_service = google_compute_backend_service.iq_backend_service.id

  host_rule {
    hosts        = [var.domain_name != "" ? var.domain_name : "*"]
    path_matcher = "allpaths"
  }

  path_matcher {
    name            = "allpaths"
    default_service = google_compute_backend_service.iq_backend_service.id

    path_rule {
      paths   = ["/*"]
      service = google_compute_backend_service.iq_backend_service.id
    }
  }
}

# HTTPS target proxy
resource "google_compute_target_https_proxy" "iq_https_proxy" {
  count   = var.ssl_certificate_name != "" ? 1 : 0
  name    = "ref-arch-iq-https-proxy"
  url_map = google_compute_url_map.iq_url_map.id
  ssl_certificates = [
    var.ssl_certificate_name
  ]
}

# HTTP target proxy (for development or HTTP-only)
resource "google_compute_target_http_proxy" "iq_http_proxy" {
  name    = "ref-arch-iq-http-proxy"
  url_map = google_compute_url_map.iq_url_map.id
}

# Global forwarding rule for HTTPS
resource "google_compute_global_forwarding_rule" "iq_https_forwarding_rule" {
  count                 = var.ssl_certificate_name != "" ? 1 : 0
  name                  = "ref-arch-iq-https-forwarding-rule"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "443"
  target                = google_compute_target_https_proxy.iq_https_proxy[0].id
  ip_address            = google_compute_global_address.iq_lb_ip.id
}

# Global forwarding rule for HTTP
resource "google_compute_global_forwarding_rule" "iq_http_forwarding_rule" {
  name                  = "ref-arch-iq-http-forwarding-rule"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "80"
  target                = google_compute_target_http_proxy.iq_http_proxy.id
  ip_address            = google_compute_global_address.iq_lb_ip.id
}

# Cloud Armor security policy (optional)
resource "google_compute_security_policy" "iq_security_policy" {
  count = var.enable_cloud_armor ? 1 : 0
  name  = "ref-arch-iq-security-policy"

  # Default rule - allow all
  rule {
    action   = "allow"
    priority = "2147483647"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
    description = "Default rule"
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
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      enforce_on_key = "IP"
      rate_limit_threshold {
        count        = var.rate_limit_threshold
        interval_sec = 60
      }
      ban_duration_sec = 600
    }
    description = "Rate limiting rule"
  }

  # Block common attack patterns
  rule {
    action   = "deny(403)"
    priority = "900"
    match {
      expr {
        expression = "origin.region_code == 'CN'"
      }
    }
    description = "Block traffic from specific regions (example)"
  }

  adaptive_protection_config {
    layer_7_ddos_defense_config {
      enable = true
    }
  }
}

# Apply security policy to backend service
resource "google_compute_backend_service" "iq_backend_service_with_armor" {
  count                   = var.enable_cloud_armor ? 1 : 0
  name                    = "ref-arch-iq-backend-service-armor"
  protocol                = "HTTP"
  port_name               = "http"
  timeout_sec             = 300
  enable_cdn              = var.enable_cdn
  connection_draining_timeout_sec = 300
  security_policy         = google_compute_security_policy.iq_security_policy[0].id

  backend {
    group = google_compute_region_network_endpoint_group.iq_neg.id
  }

  health_checks = [google_compute_health_check.iq_health_check.id]

  log_config {
    enable      = true
    sample_rate = var.lb_log_sample_rate
  }

  depends_on = [google_compute_region_network_endpoint_group.iq_neg]
}