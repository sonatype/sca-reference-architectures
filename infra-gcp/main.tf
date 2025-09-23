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
    "run.googleapis.com",
    "sqladmin.googleapis.com",
    "file.googleapis.com",
    "secretmanager.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com"
  ])

  project = var.gcp_project_id
  service = each.key

  disable_on_destroy = false
}

# Custom VPC Network
resource "google_compute_network" "iq_vpc" {
  name                    = "ref-arch-iq-vpc"
  auto_create_subnetworks = false
  mtu                     = 1460

  depends_on = [google_project_service.required_apis]
}

# Public subnet for load balancer
resource "google_compute_subnetwork" "public_subnet" {
  name          = "ref-arch-iq-public-subnet"
  ip_cidr_range = var.public_subnet_cidr
  network       = google_compute_network.iq_vpc.id
  region        = var.gcp_region

}

# Private subnet for Cloud Run and internal services
resource "google_compute_subnetwork" "private_subnet" {
  name                     = "ref-arch-iq-private-subnet"
  ip_cidr_range            = var.private_subnet_cidr
  network                  = google_compute_network.iq_vpc.id
  region                   = var.gcp_region
  private_ip_google_access = true
}

# Database subnet for Cloud SQL
resource "google_compute_subnetwork" "db_subnet" {
  name          = "ref-arch-iq-db-subnet"
  ip_cidr_range = var.db_subnet_cidr
  network       = google_compute_network.iq_vpc.id
  region        = var.gcp_region

  private_ip_google_access = true
}

# Cloud NAT for private subnet internet access
resource "google_compute_router" "iq_router" {
  name    = "ref-arch-iq-router"
  network = google_compute_network.iq_vpc.id
  region  = var.gcp_region
}

resource "google_compute_router_nat" "iq_nat" {
  name                               = "ref-arch-iq-nat"
  router                             = google_compute_router.iq_router.name
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
  name          = "ref-arch-iq-private-ip-address"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.iq_vpc.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.iq_vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]

  depends_on = [google_project_service.required_apis]
}

# VPC Connector for Cloud Run to VPC communication
resource "google_vpc_access_connector" "iq_connector" {
  name          = "ref-arch-iq-connector"
  ip_cidr_range = var.vpc_connector_cidr
  network       = google_compute_network.iq_vpc.name
  region        = var.gcp_region

  depends_on = [google_project_service.required_apis]
}

# Random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}