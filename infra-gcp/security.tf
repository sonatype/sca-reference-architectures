# VPC Firewall Rules (equivalent to AWS Security Groups)

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
    "130.211.0.0/22", # Google Load Balancer health check ranges
    "35.191.0.0/16"   # Google Load Balancer health check ranges
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
    ports    = ["8070", "8071", "5432", "2049"] # App ports, PostgreSQL, NFS
  }

  allow {
    protocol = "udp"
    ports    = ["2049", "111"] # NFS ports
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

# Allow SSH access from specific IP ranges (for maintenance)
resource "google_compute_firewall" "allow_ssh" {
  name    = "allow-ssh-nexus-iq"
  network = google_compute_network.iq_vpc.name
  project = var.gcp_project_id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.allowed_ssh_cidrs
  target_tags   = ["nexus-iq-maintenance"]

  description = "Allow SSH access for maintenance"
}

# Allow HTTPS/HTTP from internet to Load Balancer
resource "google_compute_firewall" "allow_http_https" {
  name    = "allow-http-https-nexus-iq"
  network = google_compute_network.iq_vpc.name
  project = var.gcp_project_id

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["nexus-iq-lb"]

  description = "Allow HTTP/HTTPS traffic from internet to load balancer"
}

# Allow egress from Cloud Run for external API calls
resource "google_compute_firewall" "allow_egress_cloudrun" {
  name      = "allow-egress-cloudrun"
  network   = google_compute_network.iq_vpc.name
  project   = var.gcp_project_id
  direction = "EGRESS"

  allow {
    protocol = "tcp"
    ports    = ["80", "443", "587", "25"] # HTTP, HTTPS, SMTP
  }

  allow {
    protocol = "udp"
    ports    = ["53"] # DNS
  }

  destination_ranges = ["0.0.0.0/0"]
  target_tags        = ["nexus-iq-service"]

  description = "Allow Cloud Run egress for external API calls and updates"
}

# Allow access to Google APIs through private Google access
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
    "199.36.153.8/30", # restricted.googleapis.com
    "199.36.153.4/30"  # private.googleapis.com
  ]

  description = "Allow access to Google APIs through private Google access"
}