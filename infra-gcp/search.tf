# Search backend for Sonatype IQ Server.
#
# IQ Server reads its search backend from the `search:` block in config.yml, written by
# scripts/startup.sh. Setting search_engine to "opensearch" points IQ at an OpenSearch cluster
# you run yourself: Google Cloud has no managed OpenSearch service, so there is no first-party
# cluster to create here and this configuration does not provision one. You supply the endpoint
# of a cluster you have already built, which keeps the cluster, and the index data in it,
# independent of Terraform runs here.
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

# The OpenSearch password, held in Secret Manager and read by the instance at boot rather than
# written into instance metadata. The GCE service account already holds
# roles/secretmanager.secretAccessor project wide (iam.tf), so no further grant is needed.
resource "google_secret_manager_secret" "opensearch_password" {
  count     = local.opensearch_enabled ? 1 : 0
  secret_id = "${local.app_name}-opensearch-password"
  project   = var.gcp_project_id

  replication {
    auto {}
  }

  depends_on = [google_project_service.required_apis]
}

resource "google_secret_manager_secret_version" "opensearch_password" {
  count       = local.opensearch_enabled ? 1 : 0
  secret      = google_secret_manager_secret.opensearch_password[0].id
  secret_data = var.opensearch_password
}

# Google Cloud denies all ingress that no rule allows, so an OpenSearch cluster built inside this
# VPC needs a rule of its own. Tag each OpenSearch node "nexus-iq-opensearch" to pick this up. A
# cluster outside this VPC is reached over whatever path you have built to it, and this rule has
# no effect on it.
resource "google_compute_firewall" "allow_opensearch" {
  count   = local.opensearch_enabled ? 1 : 0
  name    = "allow-opensearch-${local.app_name}"
  network = google_compute_network.iq_vpc.name
  project = var.gcp_project_id

  allow {
    protocol = "tcp"
    ports    = [tostring(var.opensearch_port)]
  }

  source_tags = ["nexus-iq-server"]
  target_tags = ["nexus-iq-opensearch"]

  description = "Allow Nexus IQ Server to reach a self-managed OpenSearch cluster in this VPC"

  # Checked here rather than in a variable validation block, because a validation comparing two
  # variables needs Terraform 1.9 and this root sets required_version to >= 1.0.
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
