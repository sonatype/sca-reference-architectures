# Global IP address for the load balancer
resource "google_compute_global_address" "iq_lb_ip" {
  name         = "nexus-iq-lb-ip"
  address_type = "EXTERNAL"
  project      = var.gcp_project_id

  depends_on = [google_project_service.required_apis]
}

# Global IP address for HA load balancer (optional)
resource "google_compute_global_address" "iq_ha_lb_ip" {
  count        = var.enable_ha ? 1 : 0
  name         = "nexus-iq-ha-lb-ip"
  address_type = "EXTERNAL"
  project      = var.gcp_project_id

  depends_on = [google_project_service.required_apis]
}

# SSL Certificate (managed by Google)
resource "google_compute_managed_ssl_certificate" "iq_ssl_cert" {
  count   = var.enable_ssl && var.domain_name != "" ? 1 : 0
  name    = "nexus-iq-ssl-cert"
  project = var.gcp_project_id

  managed {
    domains = [var.domain_name]
  }
}

# SSL Certificate for HA (managed by Google)
resource "google_compute_managed_ssl_certificate" "iq_ha_ssl_cert" {
  count   = var.enable_ha && var.enable_ssl && var.domain_name_ha != "" ? 1 : 0
  name    = "nexus-iq-ha-ssl-cert"
  project = var.gcp_project_id

  managed {
    domains = [var.domain_name_ha]
  }
}

# Backend service for Cloud Run (Single instance)
resource "google_compute_backend_service" "iq_backend" {
  name                            = "nexus-iq-backend"
  project                         = var.gcp_project_id
  protocol                        = "HTTP"
  port_name                       = "http"
  timeout_sec                     = var.backend_timeout_sec
  enable_cdn                      = var.enable_cdn
  connection_draining_timeout_sec = 60

  backend {
    group = google_compute_region_network_endpoint_group.iq_neg.id
  }

  health_checks = [google_compute_health_check.iq_health_check.id]

  log_config {
    enable      = true
    sample_rate = var.backend_log_sample_rate
  }

  security_policy = var.enable_cloud_armor ? google_compute_security_policy.iq_security_policy[0].id : null

  depends_on = [google_project_service.required_apis]
}

# Backend service for Cloud Run (HA)
resource "google_compute_backend_service" "iq_ha_backend" {
  count                           = var.enable_ha ? 1 : 0
  name                            = "nexus-iq-ha-backend"
  project                         = var.gcp_project_id
  protocol                        = "HTTP"
  port_name                       = "http"
  timeout_sec                     = var.backend_timeout_sec
  enable_cdn                      = var.enable_cdn
  connection_draining_timeout_sec = 60

  backend {
    group = google_compute_region_network_endpoint_group.iq_ha_neg[0].id
  }

  health_checks = [google_compute_health_check.iq_ha_health_check[0].id]

  log_config {
    enable      = true
    sample_rate = var.backend_log_sample_rate
  }

  security_policy = var.enable_cloud_armor ? google_compute_security_policy.iq_security_policy[0].id : null

  depends_on = [google_project_service.required_apis]
}

# Network Endpoint Group for Cloud Run (Single instance)
resource "google_compute_region_network_endpoint_group" "iq_neg" {
  name                  = "nexus-iq-neg"
  network_endpoint_type = "SERVERLESS"
  region                = var.gcp_region
  project               = var.gcp_project_id

  cloud_run {
    service = google_cloud_run_service.iq_service.name
  }
}

# Network Endpoint Group for Cloud Run (HA)
resource "google_compute_region_network_endpoint_group" "iq_ha_neg" {
  count                 = var.enable_ha ? 1 : 0
  name                  = "nexus-iq-ha-neg"
  network_endpoint_type = "SERVERLESS"
  region                = var.gcp_region
  project               = var.gcp_project_id

  cloud_run {
    service = google_cloud_run_service.iq_ha_service[0].name
  }
}

# Health check for the backend service
resource "google_compute_health_check" "iq_health_check" {
  name               = "nexus-iq-health-check"
  project            = var.gcp_project_id
  check_interval_sec = var.health_check_interval
  timeout_sec        = var.health_check_timeout

  http_health_check {
    port               = 8070
    request_path       = "/"
    response           = ""
    proxy_header       = "NONE"
  }

  log_config {
    enable = true
  }
}

# Health check for HA backend service
resource "google_compute_health_check" "iq_ha_health_check" {
  count              = var.enable_ha ? 1 : 0
  name               = "nexus-iq-ha-health-check"
  project            = var.gcp_project_id
  check_interval_sec = var.health_check_interval
  timeout_sec        = var.health_check_timeout

  http_health_check {
    port               = 8070
    request_path       = "/"
    response           = ""
    proxy_header       = "NONE"
  }

  log_config {
    enable = true
  }
}

# URL Map for routing
resource "google_compute_url_map" "iq_url_map" {
  name            = "nexus-iq-url-map"
  project         = var.gcp_project_id
  default_service = google_compute_backend_service.iq_backend.id

  # Route for HA service if enabled
  dynamic "host_rule" {
    for_each = var.enable_ha && var.domain_name_ha != "" ? [1] : []
    content {
      hosts        = [var.domain_name_ha]
      path_matcher = "ha-matcher"
    }
  }

  dynamic "path_matcher" {
    for_each = var.enable_ha && var.domain_name_ha != "" ? [1] : []
    content {
      name            = "ha-matcher"
      default_service = google_compute_backend_service.iq_ha_backend[0].id
    }
  }
}

# HTTPS Proxy
resource "google_compute_target_https_proxy" "iq_https_proxy" {
  count   = var.enable_ssl ? 1 : 0
  name    = "nexus-iq-https-proxy"
  project = var.gcp_project_id
  url_map = google_compute_url_map.iq_url_map.id

  ssl_certificates = concat(
    var.domain_name != "" ? [google_compute_managed_ssl_certificate.iq_ssl_cert[0].id] : [],
    var.enable_ha && var.domain_name_ha != "" ? [google_compute_managed_ssl_certificate.iq_ha_ssl_cert[0].id] : []
  )
}

# HTTP Proxy (for HTTP to HTTPS redirect or non-SSL)
resource "google_compute_target_http_proxy" "iq_http_proxy" {
  name    = "nexus-iq-http-proxy"
  project = var.gcp_project_id
  url_map = var.enable_ssl ? google_compute_url_map.iq_redirect_url_map[0].id : google_compute_url_map.iq_url_map.id
}

# URL Map for HTTP to HTTPS redirect
resource "google_compute_url_map" "iq_redirect_url_map" {
  count   = var.enable_ssl ? 1 : 0
  name    = "nexus-iq-redirect-url-map"
  project = var.gcp_project_id

  default_url_redirect {
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query           = false
    https_redirect        = true
  }
}

# Global Forwarding Rule for HTTPS
resource "google_compute_global_forwarding_rule" "iq_https_forwarding_rule" {
  count                 = var.enable_ssl ? 1 : 0
  name                  = "nexus-iq-https-forwarding-rule"
  project               = var.gcp_project_id
  target                = google_compute_target_https_proxy.iq_https_proxy[0].id
  port_range           = "443"
  ip_address           = google_compute_global_address.iq_lb_ip.address
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

# Global Forwarding Rule for HTTP
resource "google_compute_global_forwarding_rule" "iq_http_forwarding_rule" {
  name                  = "nexus-iq-http-forwarding-rule"
  project               = var.gcp_project_id
  target                = google_compute_target_http_proxy.iq_http_proxy.id
  port_range           = "80"
  ip_address           = google_compute_global_address.iq_lb_ip.address
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

# Cloud Armor Security Policy
resource "google_compute_security_policy" "iq_security_policy" {
  count   = var.enable_cloud_armor ? 1 : 0
  name    = "nexus-iq-security-policy"
  project = var.gcp_project_id

  description = "Security policy for Nexus IQ Server"

  # Default rule
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
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      enforce_on_key = "IP"
      rate_limit_threshold {
        count        = var.rate_limit_threshold_count
        interval_sec = var.rate_limit_threshold_interval
      }
      ban_duration_sec = var.rate_limit_ban_duration
    }
    description = "Rate limiting rule"
  }

  # Block common attack patterns
  rule {
    action   = "deny(403)"
    priority = "2000"
    match {
      expr {
        expression = "origin.region_code == 'CN' || origin.region_code == 'RU'"
      }
    }
    description = "Block traffic from certain regions"
  }

  # SQL Injection protection
  rule {
    action   = "deny(403)"
    priority = "3000"
    match {
      expr {
        expression = "has(request.headers['user-agent']) && request.headers['user-agent'].contains('sqlmap')"
      }
    }
    description = "Block SQL injection attempts"
  }

  adaptive_protection_config {
    layer_7_ddos_defense_config {
      enable          = true
      rule_visibility = "STANDARD"
    }
  }
}

# Cloud CDN Cache Policy (if CDN is enabled)
resource "google_compute_backend_bucket" "iq_cdn_bucket" {
  count       = var.enable_cdn ? 1 : 0
  name        = "nexus-iq-cdn-bucket"
  project     = var.gcp_project_id
  bucket_name = google_storage_bucket.iq_logs.name
  enable_cdn  = true
}