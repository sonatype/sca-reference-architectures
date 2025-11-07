# Firewall rule to allow health checks from Google Cloud Load Balancer
resource "google_compute_firewall" "allow_health_check" {
  name    = "ref-arch-iq-ha-allow-health-check"
  network = google_compute_network.iq_ha_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["8070", "8071"]
  }

  # Google Cloud health check source ranges
  source_ranges = [
    "130.211.0.0/22",
    "35.191.0.0/16"
  ]

  target_tags = ["nexus-iq-ha", "allow-health-check"]

  description = "Allow health checks from Google Cloud Load Balancer"
}

# Firewall rule to allow load balancer traffic
resource "google_compute_firewall" "allow_load_balancer" {
  name    = "ref-arch-iq-ha-allow-load-balancer"
  network = google_compute_network.iq_ha_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["8070"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["nexus-iq-ha"]

  description = "Allow traffic from load balancer to Nexus IQ instances"
}

# Firewall rule for internal communication between instances
resource "google_compute_firewall" "allow_internal" {
  name    = "ref-arch-iq-ha-allow-internal"
  network = google_compute_network.iq_ha_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["8070", "8071"]
  }

  allow {
    protocol = "icmp"
  }

  # Allow traffic from private subnet ranges
  source_ranges = var.private_subnet_cidrs
  target_tags   = ["nexus-iq-ha"]

  description = "Allow internal communication between Nexus IQ instances"
}

# Firewall rule for SSH access (optional, for debugging)
resource "google_compute_firewall" "allow_ssh" {
  name    = "ref-arch-iq-ha-allow-ssh"
  network = google_compute_network.iq_ha_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.allowed_ssh_cidrs
  target_tags   = ["nexus-iq-ha", "allow-ssh"]

  description = "Allow SSH access to Nexus IQ instances"
}

# Firewall rule to deny all other inbound traffic (implicit deny)
resource "google_compute_firewall" "deny_all" {
  name     = "ref-arch-iq-ha-deny-all"
  network  = google_compute_network.iq_ha_vpc.name
  priority = 65534

  deny {
    protocol = "all"
  }

  source_ranges = ["0.0.0.0/0"]

  description = "Deny all other inbound traffic (default deny rule)"
}

# Firewall rule to allow outbound internet access for instances
resource "google_compute_firewall" "allow_outbound" {
  name      = "ref-arch-iq-ha-allow-outbound"
  network   = google_compute_network.iq_ha_vpc.name
  direction = "EGRESS"

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  allow {
    protocol = "tcp"
    ports    = ["5432"] # PostgreSQL
  }

  allow {
    protocol = "udp"
    ports    = ["53"] # DNS
  }

  destination_ranges = ["0.0.0.0/0"]
  target_tags        = ["nexus-iq-ha"]

  description = "Allow outbound internet access for Nexus IQ instances"
}

# Firewall rule to allow NFS traffic to Cloud Filestore
resource "google_compute_firewall" "allow_nfs" {
  name    = "ref-arch-iq-ha-allow-nfs"
  network = google_compute_network.iq_ha_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["111", "2049"]
  }

  allow {
    protocol = "udp"
    ports    = ["111", "2049"]
  }

  source_ranges = var.private_subnet_cidrs
  target_tags   = ["nexus-iq-ha"]

  description = "Allow NFS traffic to Cloud Filestore for shared storage"
}