# Search backend. With search_engine = "opensearch", IQ Server uses an OpenSearch
# cluster you run yourself, named by opensearch_endpoint; this configuration creates
# none. scripts/startup.sh writes the search: block into config.yml.
# README.md, "Search Backend", gives the cluster specification.
# Every instance in the group reads the same endpoint, so they share one index.

locals {
  opensearch_enabled = var.search_engine == "opensearch"

  # https makes IQ Server open a TLS connection, and the JVM must trust the cluster's
  # certificate: see README.md, "Trusting a private certificate authority".
  opensearch_scheme = var.opensearch_use_tls ? "https" : "http"

  opensearch_uri = "${local.opensearch_scheme}://${var.opensearch_endpoint}:${var.opensearch_port}"
}

# The OpenSearch password, read from Secret Manager at boot rather than written into the
# instance template's metadata.
resource "google_secret_manager_secret" "opensearch_password" {
  count     = local.opensearch_enabled ? 1 : 0
  secret_id = "${local.app_name}-opensearch-password-${random_string.suffix.result}"
  project   = var.gcp_project_id

  replication {
    auto {}
  }

  labels = merge(var.common_tags, {
    component = "nexus-iq-ha-opensearch-password"
  })

  depends_on = [google_project_service.required_apis]
}

resource "google_secret_manager_secret_version" "opensearch_password" {
  count       = local.opensearch_enabled ? 1 : 0
  secret      = google_secret_manager_secret.opensearch_password[0].id
  secret_data = var.opensearch_password
}

# Secret Manager access is granted per secret in this root (iam.tf).
resource "google_secret_manager_secret_iam_member" "iq_compute_opensearch_password" {
  count     = local.opensearch_enabled ? 1 : 0
  secret_id = google_secret_manager_secret.opensearch_password[0].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.iq_compute_service.email}"
  project   = var.gcp_project_id
}

# A private certificate authority for the cluster, read from Secret Manager at boot.
# Not needed for a certificate from a public authority.
locals {
  opensearch_private_ca = local.opensearch_enabled && var.opensearch_use_tls && var.opensearch_ca_certificate != ""
}

resource "google_secret_manager_secret" "opensearch_ca" {
  count     = local.opensearch_private_ca ? 1 : 0
  secret_id = "${local.app_name}-opensearch-ca-${random_string.suffix.result}"
  project   = var.gcp_project_id

  replication {
    auto {}
  }

  labels = merge(var.common_tags, {
    component = "nexus-iq-ha-opensearch-ca"
  })

  depends_on = [google_project_service.required_apis]
}

resource "google_secret_manager_secret_version" "opensearch_ca" {
  count       = local.opensearch_private_ca ? 1 : 0
  secret      = google_secret_manager_secret.opensearch_ca[0].id
  secret_data = var.opensearch_ca_certificate
}

resource "google_secret_manager_secret_iam_member" "iq_compute_opensearch_ca" {
  count     = local.opensearch_private_ca ? 1 : 0
  secret_id = google_secret_manager_secret.opensearch_ca[0].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.iq_compute_service.email}"
  project   = var.gcp_project_id
}

# Ingress to an OpenSearch cluster inside this VPC, on nodes tagged "nexus-iq-opensearch",
# above this root's deny-all ingress rule at 65534. A cluster outside the VPC is not affected.
resource "google_compute_firewall" "allow_opensearch" {
  count   = local.opensearch_enabled ? 1 : 0
  name    = "${local.infra_name}-allow-opensearch"
  network = google_compute_network.iq_ha_vpc.name

  allow {
    protocol = "tcp"
    ports    = [tostring(var.opensearch_port)]
  }

  source_tags = ["nexus-iq-ha"]
  target_tags = ["nexus-iq-opensearch"]

  description = "Allow Nexus IQ Server to reach a self-managed OpenSearch cluster in this VPC"

  lifecycle {
    precondition {
      condition     = length(var.opensearch_endpoint) > 0
      error_message = "opensearch_endpoint must be set when search_engine is 'opensearch'."
    }

    precondition {
      condition     = length(var.opensearch_username) > 0
      error_message = "opensearch_username must be set when search_engine is 'opensearch'."
    }

    precondition {
      condition     = length(var.opensearch_password) > 0
      error_message = "opensearch_password must be set when search_engine is 'opensearch'."
    }
  }
}
