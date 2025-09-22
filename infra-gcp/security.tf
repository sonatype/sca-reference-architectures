# VPC Firewall Rules

# Allow ingress from Load Balancer to Cloud Run (Health Checks)
resource "google_compute_firewall" "allow_lb_to_cloudrun" {
  name    = "allow-lb-to-cloudrun"
  network = google_compute_network.iq_vpc.name
  project = var.gcp_project_id

  allow {
    protocol = "tcp"
    ports    = ["8070", "8071"]
  }

  source_ranges = [
    "130.211.0.0/22",  # Google Load Balancer health check ranges
    "35.191.0.0/16"    # Google Load Balancer health check ranges
  ]

  target_tags = ["nexus-iq-service"]

  description = "Allow health checks from Google Load Balancer to Cloud Run services"
}

# Allow internal communication within VPC
resource "google_compute_firewall" "allow_internal" {
  name    = "allow-internal-nexus-iq"
  network = google_compute_network.iq_vpc.name
  project = var.gcp_project_id

  allow {
    protocol = "tcp"
    ports    = ["8070", "8071", "5432", "2049"]  # App ports, PostgreSQL, NFS
  }

  allow {
    protocol = "udp"
    ports    = ["2049", "111"]  # NFS ports
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [
    var.private_subnet_cidr,
    var.public_subnet_cidr,
    var.db_subnet_cidr
  ]

  description = "Allow internal communication within VPC for Nexus IQ infrastructure"
}

# Allow SSH access from bastion or admin networks (optional)
resource "google_compute_firewall" "allow_ssh" {
  count   = var.enable_ssh_access ? 1 : 0
  name    = "allow-ssh-nexus-iq"
  network = google_compute_network.iq_vpc.name
  project = var.gcp_project_id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.ssh_source_ranges
  target_tags   = ["ssh-allowed"]

  description = "Allow SSH access to instances with ssh-allowed tag"
}

# Allow HTTPS/HTTP from internet to Load Balancer
resource "google_compute_firewall" "allow_web_traffic" {
  name    = "allow-web-traffic-nexus-iq"
  network = google_compute_network.iq_vpc.name
  project = var.gcp_project_id

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["nexus-iq-lb"]

  description = "Allow HTTP/HTTPS traffic from internet to Load Balancer"
}

# Deny all other traffic (explicit deny rule)
resource "google_compute_firewall" "deny_all" {
  name     = "deny-all-nexus-iq"
  network  = google_compute_network.iq_vpc.name
  project  = var.gcp_project_id
  priority = 65534

  deny {
    protocol = "all"
  }

  source_ranges = ["0.0.0.0/0"]

  description = "Explicit deny rule for all traffic not explicitly allowed"
}

# Allow egress for Cloud Run to access external services
resource "google_compute_firewall" "allow_egress_cloudrun" {
  name      = "allow-egress-cloudrun"
  network   = google_compute_network.iq_vpc.name
  project   = var.gcp_project_id
  direction = "EGRESS"

  allow {
    protocol = "tcp"
    ports    = ["80", "443", "587", "25"]  # HTTP, HTTPS, SMTP
  }

  allow {
    protocol = "udp"
    ports    = ["53"]  # DNS
  }

  destination_ranges = ["0.0.0.0/0"]
  target_tags        = ["nexus-iq-service"]

  description = "Allow Cloud Run egress for external API calls and updates"
}

# Allow egress to Google APIs
resource "google_compute_firewall" "allow_google_apis" {
  name      = "allow-google-apis"
  network   = google_compute_network.iq_vpc.name
  project   = var.gcp_project_id
  direction = "EGRESS"

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }

  destination_ranges = [
    "199.36.153.8/30",    # restricted.googleapis.com
    "199.36.153.4/30"     # private.googleapis.com
  ]

  description = "Allow access to Google APIs through private Google access"
}

# Security Group equivalent - Network Tags
locals {
  security_tags = {
    nexus_iq_service = "nexus-iq-service"
    nexus_iq_lb      = "nexus-iq-lb"
    ssh_allowed      = "ssh-allowed"
    database         = "database"
    filestore        = "filestore"
  }
}

# Cloud Armor WAF Rules (additional security layer)
resource "google_compute_security_policy_rule" "block_malicious_ips" {
  count           = var.enable_cloud_armor && length(var.blocked_ip_ranges) > 0 ? 1 : 0
  security_policy = google_compute_security_policy.iq_security_policy[0].name
  priority        = 500

  match {
    versioned_expr = "SRC_IPS_V1"
    config {
      src_ip_ranges = var.blocked_ip_ranges
    }
  }

  action      = "deny(403)"
  description = "Block known malicious IP ranges"
}

# Geo-blocking rule
resource "google_compute_security_policy_rule" "geo_blocking" {
  count           = var.enable_cloud_armor && length(var.blocked_countries) > 0 ? 1 : 0
  security_policy = google_compute_security_policy.iq_security_policy[0].name
  priority        = 600

  match {
    expr {
      expression = join(" || ", [for country in var.blocked_countries : "origin.region_code == '${country}'"])
    }
  }

  action      = "deny(403)"
  description = "Block traffic from specified countries"
}

# DDoS protection rule
resource "google_compute_security_policy_rule" "ddos_protection" {
  count           = var.enable_cloud_armor ? 1 : 0
  security_policy = google_compute_security_policy.iq_security_policy[0].name
  priority        = 700

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
      count        = var.ddos_rate_limit_count
      interval_sec = var.ddos_rate_limit_interval
    }

    ban_duration_sec = var.ddos_ban_duration
  }

  action      = "rate_based_ban"
  description = "DDoS protection with rate limiting"
}

# OWASP Top 10 protection rules
resource "google_compute_security_policy_rule" "owasp_protection" {
  count           = var.enable_cloud_armor && var.enable_owasp_rules ? 1 : 0
  security_policy = google_compute_security_policy.iq_security_policy[0].name
  priority        = 800

  match {
    expr {
      expression = <<-EOT
        evaluatePreconfiguredExpr('xss-stable') ||
        evaluatePreconfiguredExpr('sqli-stable') ||
        evaluatePreconfiguredExpr('lfi-stable') ||
        evaluatePreconfiguredExpr('rfi-stable') ||
        evaluatePreconfiguredExpr('rce-stable') ||
        evaluatePreconfiguredExpr('methodenforcement-stable')
      EOT
    }
  }

  action      = "deny(403)"
  description = "OWASP Top 10 protection rules"
}

# Custom header validation rule
resource "google_compute_security_policy_rule" "header_validation" {
  count           = var.enable_cloud_armor && var.enable_header_validation ? 1 : 0
  security_policy = google_compute_security_policy.iq_security_policy[0].name
  priority        = 900

  match {
    expr {
      expression = <<-EOT
        !has(request.headers['user-agent']) ||
        request.headers['user-agent'].size() > 512 ||
        request.headers['user-agent'].contains('bot') ||
        request.headers['user-agent'].contains('crawler')
      EOT
    }
  }

  action      = "deny(403)"
  description = "Block requests with suspicious or missing user agents"
}

# Identity-Aware Proxy (IAP) Configuration (optional)
resource "google_iap_web_iam_binding" "iq_iap_binding" {
  count   = var.enable_iap ? 1 : 0
  project = var.gcp_project_id
  role    = "roles/iap.httpsResourceAccessor"
  members = var.iap_allowed_users
}

# Binary Authorization Policy (for container security)
resource "google_binary_authorization_policy" "iq_policy" {
  count   = var.enable_binary_authorization ? 1 : 0
  project = var.gcp_project_id

  default_admission_rule {
    evaluation_mode         = "REQUIRE_ATTESTATION"
    enforcement_mode        = "ENFORCED_BLOCK_AND_AUDIT_LOG"
    require_attestations_by = [google_binary_authorization_attestor.iq_attestor[0].name]
  }

  admission_whitelist_patterns {
    name_pattern = "gcr.io/${var.gcp_project_id}/*"
  }

  admission_whitelist_patterns {
    name_pattern = "us.gcr.io/${var.gcp_project_id}/*"
  }
}

# Binary Authorization Attestor
resource "google_binary_authorization_attestor" "iq_attestor" {
  count   = var.enable_binary_authorization ? 1 : 0
  name    = "nexus-iq-attestor"
  project = var.gcp_project_id

  attestation_authority_note {
    note_reference = google_container_analysis_note.iq_note[0].name
    public_keys {
      ascii_armored_pgp_public_key = var.pgp_public_key
    }
  }

  description = "Attestor for Nexus IQ Server container images"
}

# Container Analysis Note
resource "google_container_analysis_note" "iq_note" {
  count   = var.enable_binary_authorization ? 1 : 0
  name    = "nexus-iq-attestation-note"
  project = var.gcp_project_id

  attestation_authority {
    hint {
      human_readable_name = "Nexus IQ Attestor"
    }
  }
}

# VPC Flow Logs (for network monitoring)
resource "google_compute_subnetwork" "private_subnet_with_flow_logs" {
  name          = "${google_compute_subnetwork.private_subnet.name}-flow-logs"
  ip_cidr_range = var.private_subnet_cidr
  network       = google_compute_network.iq_vpc.id
  region        = var.gcp_region

  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata            = "INCLUDE_ALL_METADATA"
  }

  depends_on = [google_compute_subnetwork.private_subnet]
}

# Cloud Security Command Center notifications (if available)
resource "google_security_center_notification_config" "iq_scc_notification" {
  count           = var.enable_scc_notifications ? 1 : 0
  config_id       = "nexus-iq-scc-notification"
  organization    = var.organization_id
  description     = "Security Command Center notifications for Nexus IQ"
  pubsub_topic    = "projects/${var.gcp_project_id}/topics/scc-notifications"
  streaming_config {
    filter = "resource.type=\"gce_instance\" OR resource.type=\"cloud_run_revision\""
  }
}