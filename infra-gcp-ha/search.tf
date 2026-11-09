# Search backend for Sonatype IQ Server.
#
# IQ Server reads its search backend from the `search:` block in config.yml, written by
# scripts/startup.sh. Setting search_engine to "opensearch" points IQ at an OpenSearch cluster
# you run yourself: Google Cloud has no managed OpenSearch service, so there is no first-party
# cluster to create here and this configuration does not provision one. You supply the endpoint
# of a cluster you have already built, which keeps the cluster, and the index data in it,
# independent of Terraform runs here.
#
# Every instance in the managed instance group reads the same endpoint and the same credential, so
# the whole group shares one index.
#
# See README.md, "Search Backend", for the cluster specification to build against and for the
# operational work a self-managed cluster carries.

locals {
  opensearch_enabled = var.search_engine == "opensearch"

  # http or https decides whether IQ Server opens a TLS connection. With TLS, the cluster's
  # certificate must be trusted by the JVM: see README.md, "Trusting a private certificate
  # authority".
  opensearch_scheme = var.opensearch_use_tls ? "https" : "http"

  opensearch_uri = "${local.opensearch_scheme}://${var.opensearch_endpoint}:${var.opensearch_port}"
}

# The OpenSearch password, held in Secret Manager and read by each instance at boot rather than
# written into the instance template's metadata, which every instance in the group exposes.
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

# This root grants Secret Manager access one secret at a time (iam.tf), so the new secret needs
# its own grant.
resource "google_secret_manager_secret_iam_member" "iq_compute_opensearch_password" {
  count     = local.opensearch_enabled ? 1 : 0
  secret_id = google_secret_manager_secret.opensearch_password[0].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.iq_compute_service.email}"
  project   = var.gcp_project_id
}

# A private certificate authority for the cluster, held in Secret Manager so each instance can add
# it to a copy of the JVM trust store at boot. Not needed for a certificate from a public authority.
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

# Google Cloud denies all ingress that no rule allows, and this root adds a deny-all ingress rule
# of its own at priority 65534, so an OpenSearch cluster built inside this VPC needs a rule. Tag
# each OpenSearch node "nexus-iq-opensearch" to pick this up. A cluster outside this VPC is
# reached over whatever path you have built to it, and this rule has no effect on it.
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

  # Checked here rather than in a variable validation block, because a validation comparing two
  # variables needs Terraform 1.9 and this root sets required_version to >= 1.2.
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
