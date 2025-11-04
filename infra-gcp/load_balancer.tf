# Global IP address for the load balancer
resource "google_compute_global_address" "iq_lb_ip" {
  name         = "nexus-iq-lb-ip"
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


# Backend service for GCE instance group
resource "google_compute_backend_service" "iq_backend" {
  name                            = "nexus-iq-backend"
  project                         = var.gcp_project_id
  protocol                        = "HTTP"
  port_name                       = "http"
  timeout_sec                     = 30
  enable_cdn                      = false
  connection_draining_timeout_sec = 60
  health_checks                   = [google_compute_health_check.iq_lb_health_check.id]

  backend {
    group           = google_compute_instance_group.iq_group.self_link
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }

  log_config {
    enable      = true
    sample_rate = 1.0
  }

  depends_on = [google_project_service.required_apis]
}

# Health Check for Load Balancer
resource "google_compute_health_check" "iq_lb_health_check" {
  name                = "nexus-iq-lb-health-check"
  project             = var.gcp_project_id
  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3

  tcp_health_check {
    port = 8070
  }
}


# URL Map for routing
resource "google_compute_url_map" "iq_url_map" {
  name            = "nexus-iq-url-map"
  project         = var.gcp_project_id
  default_service = google_compute_backend_service.iq_backend.id

}

# HTTPS Proxy
resource "google_compute_target_https_proxy" "iq_https_proxy" {
  count   = var.enable_ssl ? 1 : 0
  name    = "nexus-iq-https-proxy"
  project = var.gcp_project_id
  url_map = google_compute_url_map.iq_url_map.id

  ssl_certificates = var.domain_name != "" ? [google_compute_managed_ssl_certificate.iq_ssl_cert[0].id] : []
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
    strip_query            = false
    https_redirect         = true
  }
}

# Global Forwarding Rule for HTTPS
resource "google_compute_global_forwarding_rule" "iq_https_forwarding_rule" {
  count                 = var.enable_ssl ? 1 : 0
  name                  = "nexus-iq-https-forwarding-rule"
  project               = var.gcp_project_id
  target                = google_compute_target_https_proxy.iq_https_proxy[0].id
  port_range            = "443"
  ip_address            = google_compute_global_address.iq_lb_ip.address
  load_balancing_scheme = "EXTERNAL"
}

# Global Forwarding Rule for HTTP
resource "google_compute_global_forwarding_rule" "iq_http_forwarding_rule" {
  name                  = "nexus-iq-http-forwarding-rule"
  project               = var.gcp_project_id
  target                = google_compute_target_http_proxy.iq_http_proxy.id
  port_range            = "80"
  ip_address            = google_compute_global_address.iq_lb_ip.address
  load_balancing_scheme = "EXTERNAL"
}

