terraform {
  required_version = ">= 1.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

provider "kubernetes" {
  host                   = "https://${google_container_cluster.iq_gke.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.iq_gke.master_auth[0].cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = "https://${google_container_cluster.iq_gke.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(google_container_cluster.iq_gke.master_auth[0].cluster_ca_certificate)
  }
}

data "google_client_config" "default" {}

resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

locals {
  common_tags = {
    environment = var.environment
    project     = "nexus-iq-server-ha"
    terraform   = "true"
    deployment  = "gke-helm"
  }

  cluster_name = var.cluster_name
}

resource "google_project_service" "required_apis" {
  for_each = toset([
    "compute.googleapis.com",
    "container.googleapis.com",
    "sqladmin.googleapis.com",
    "servicenetworking.googleapis.com",
    "file.googleapis.com",
    "secretmanager.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
  ])

  service            = each.key
  disable_on_destroy = false
}

resource "google_compute_network" "iq_vpc" {
  name                    = "${local.cluster_name}-vpc"
  auto_create_subnetworks = false
  project                 = var.gcp_project_id

  depends_on = [google_project_service.required_apis]
}

resource "google_compute_subnetwork" "public_subnet" {
  name          = "${local.cluster_name}-public-subnet"
  ip_cidr_range = var.public_subnet_cidr
  region        = var.gcp_region
  network       = google_compute_network.iq_vpc.id
  project       = var.gcp_project_id

  secondary_ip_range {
    range_name    = "gke-pods"
    ip_cidr_range = var.gke_pods_cidr
  }

  secondary_ip_range {
    range_name    = "gke-services"
    ip_cidr_range = var.gke_services_cidr
  }
}

resource "google_compute_subnetwork" "private_subnet" {
  count         = length(var.private_subnet_cidrs)
  name          = "${local.cluster_name}-private-subnet-${count.index + 1}"
  ip_cidr_range = var.private_subnet_cidrs[count.index]
  region        = var.gcp_region
  network       = google_compute_network.iq_vpc.id
  project       = var.gcp_project_id

  private_ip_google_access = true
}

resource "google_compute_global_address" "private_ip_address" {
  name          = "${local.cluster_name}-private-ip"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.iq_vpc.id
  project       = var.gcp_project_id

  depends_on = [google_project_service.required_apis]
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.iq_vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]

  depends_on = [google_project_service.required_apis]
}

resource "google_compute_router" "iq_router" {
  name    = "${local.cluster_name}-router"
  region  = var.gcp_region
  network = google_compute_network.iq_vpc.id
  project = var.gcp_project_id

  bgp {
    asn = 64514
  }
}

resource "google_compute_router_nat" "iq_nat" {
  name                               = "${local.cluster_name}-nat"
  router                             = google_compute_router.iq_router.name
  region                             = var.gcp_region
  project                            = var.gcp_project_id
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
