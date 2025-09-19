# Firewall rule to allow HTTP/HTTPS traffic to load balancer
resource "google_compute_firewall" "allow_lb_access" {
  name    = "ref-arch-iq-allow-lb-access"
  network = google_compute_network.iq_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["iq-lb"]
  
  description = "Allow HTTP/HTTPS access to load balancer"
}

# Firewall rule to allow load balancer health checks
resource "google_compute_firewall" "allow_health_checks" {
  name    = "ref-arch-iq-allow-health-checks"
  network = google_compute_network.iq_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["8070", "8071"]
  }

  source_ranges = [
    "130.211.0.0/22",  # Google Cloud Load Balancer health check ranges
    "35.191.0.0/16"
  ]
  
  target_service_accounts = [google_service_account.iq_service_account.email]
  
  description = "Allow health checks from Google Cloud Load Balancer"
}

# Firewall rule to allow VPC Connector access to Cloud Run
resource "google_compute_firewall" "allow_vpc_connector" {
  name    = "ref-arch-iq-allow-vpc-connector"
  network = google_compute_network.iq_vpc.name

  allow {
    protocol = "tcp"
  }

  allow {
    protocol = "udp"
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [var.vpc_connector_cidr]
  target_tags   = ["vpc-connector"]
  
  description = "Allow VPC Connector access to services"
}

# Firewall rule for Cloud SQL access from Cloud Run
resource "google_compute_firewall" "allow_cloudsql_access" {
  name    = "ref-arch-iq-allow-cloudsql"
  network = google_compute_network.iq_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["5432"]
  }

  source_service_accounts = [google_service_account.iq_service_account.email]
  target_tags            = ["cloudsql"]
  
  description = "Allow Cloud Run to access Cloud SQL"
}

# Firewall rule for Cloud Filestore access
resource "google_compute_firewall" "allow_filestore_access" {
  name    = "ref-arch-iq-allow-filestore"
  network = google_compute_network.iq_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["2049"]  # NFS port
  }

  allow {
    protocol = "udp"
    ports    = ["2049"]
  }

  source_service_accounts = [google_service_account.iq_service_account.email]
  target_tags            = ["filestore"]
  
  description = "Allow NFS access to Cloud Filestore"
}

# Firewall rule to deny all other inbound traffic (implicit deny-all is already in place, this is explicit)
resource "google_compute_firewall" "deny_all_ingress" {
  name    = "ref-arch-iq-deny-all-ingress"
  network = google_compute_network.iq_vpc.name

  deny {
    protocol = "all"
  }

  source_ranges = ["0.0.0.0/0"]
  priority      = 65534
  
  description = "Explicit deny all ingress traffic (lowest priority)"
}

# Firewall rule to allow all egress traffic (default behavior, but explicit)
resource "google_compute_firewall" "allow_all_egress" {
  name      = "ref-arch-iq-allow-all-egress"
  network   = google_compute_network.iq_vpc.name
  direction = "EGRESS"

  allow {
    protocol = "all"
  }

  destination_ranges = ["0.0.0.0/0"]
  priority           = 1000
  
  description = "Allow all egress traffic"
}

# Firewall rule for SSH access to instances (if needed for debugging)
resource "google_compute_firewall" "allow_ssh" {
  count   = var.enable_ssh_access ? 1 : 0
  name    = "ref-arch-iq-allow-ssh"
  network = google_compute_network.iq_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.ssh_source_ranges
  target_tags   = ["ssh-allowed"]
  
  description = "Allow SSH access for debugging (optional)"
}

# Firewall rule for internal communication within VPC
resource "google_compute_firewall" "allow_internal" {
  name    = "ref-arch-iq-allow-internal"
  network = google_compute_network.iq_vpc.name

  allow {
    protocol = "tcp"
  }

  allow {
    protocol = "udp"
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [
    var.public_subnet_cidr,
    var.private_subnet_cidr,
    var.db_subnet_cidr
  ]
  
  description = "Allow internal communication within VPC"
}

# Security scanner exclusion (optional - for Nexus IQ specific paths)
resource "google_compute_security_policy" "iq_waf_policy" {
  count = var.enable_web_security_scanner ? 1 : 0
  name  = "ref-arch-iq-waf-policy"

  rule {
    action   = "allow"
    priority = "1000"
    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["0.0.0.0/0"]
      }
    }
    description = "Allow all traffic by default"
  }

  # Block known malicious user agents
  rule {
    action   = "deny(403)"
    priority = "900"
    match {
      expr {
        expression = "has(request.headers['user-agent']) && request.headers['user-agent'].contains('sqlmap')"
      }
    }
    description = "Block SQL injection tools"
  }

  # Rate limiting for login endpoints
  rule {
    action   = "rate_based_ban"
    priority = "800"
    match {
      expr {
        expression = "request.path.startswith('/login') || request.path.startswith('/api/v2/token')"
      }
    }
    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      enforce_on_key = "IP"
      rate_limit_threshold {
        count        = 10
        interval_sec = 60
      }
      ban_duration_sec = 300
    }
    description = "Rate limit authentication endpoints"
  }

  adaptive_protection_config {
    layer_7_ddos_defense_config {
      enable = true
    }
  }
}

# Network tags for better organization
locals {
  common_tags = {
    "nexus-iq"     = "true"
    "environment"  = var.environment
    "project"      = "sonatype-iq"
    "managed-by"   = "terraform"
  }
}