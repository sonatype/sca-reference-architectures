terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

provider "google-beta" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

# Enable required APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "compute.googleapis.com",
    "sqladmin.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "servicenetworking.googleapis.com",
    "secretmanager.googleapis.com"
  ])

  project = var.gcp_project_id
  service = each.key

  disable_on_destroy = false
}

# Custom VPC Network for HA deployment
resource "google_compute_network" "iq_ha_vpc" {
  name                    = "ref-arch-iq-ha-vpc"
  auto_create_subnetworks = false
  mtu                     = 1460

  depends_on = [google_project_service.required_apis]
}

# Public subnet for load balancer
resource "google_compute_subnetwork" "public_subnet" {
  name          = "ref-arch-iq-ha-public-subnet"
  ip_cidr_range = var.public_subnet_cidr
  network       = google_compute_network.iq_ha_vpc.id
  region        = var.gcp_region
}

# Private subnets for Compute Engine instances (multi-zone)
resource "google_compute_subnetwork" "private_subnets" {
  count                    = length(var.availability_zones)
  name                     = "ref-arch-iq-ha-private-subnet-${var.availability_zones[count.index]}"
  ip_cidr_range            = var.private_subnet_cidrs[count.index]
  network                  = google_compute_network.iq_ha_vpc.id
  region                   = var.gcp_region
  private_ip_google_access = true
}

# Database subnet for Cloud SQL
resource "google_compute_subnetwork" "db_subnet" {
  name                     = "ref-arch-iq-ha-db-subnet"
  ip_cidr_range            = var.db_subnet_cidr
  network                  = google_compute_network.iq_ha_vpc.id
  region                   = var.gcp_region
  private_ip_google_access = true
}

# Cloud NAT for private subnet internet access
resource "google_compute_router" "iq_ha_router" {
  name    = "ref-arch-iq-ha-router"
  network = google_compute_network.iq_ha_vpc.id
  region  = var.gcp_region
}

resource "google_compute_router_nat" "iq_ha_nat" {
  name                               = "ref-arch-iq-ha-nat"
  router                             = google_compute_router.iq_ha_router.name
  region                             = var.gcp_region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Private Service Connection for Cloud SQL
resource "google_compute_global_address" "private_ip_address" {
  name          = "ref-arch-iq-ha-private-ip-address"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.iq_ha_vpc.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.iq_ha_vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
  deletion_policy         = "ABANDON"

  depends_on = [google_project_service.required_apis]
}

# Random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}