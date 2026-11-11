# Search backend. With search_engine = "opensearch", IQ Server uses an OpenSearch
# cluster you run yourself, named by opensearch_endpoint; this configuration creates
# none. render-values.sh writes the outputs below into the Helm values.
# README.md, "Search Backend", gives the cluster specification.

locals {
  opensearch_enabled = var.search_engine == "opensearch"

  # https makes IQ Server open a TLS connection, and the JVM in every pod must trust the
  # cluster's certificate: see README.md, "Trusting a private certificate authority".
  opensearch_scheme = var.opensearch_use_tls ? "https" : "http"

  opensearch_uri = "${local.opensearch_scheme}://${var.opensearch_endpoint}:${var.opensearch_port}"
}

# Ingress to an OpenSearch cluster inside this VPC, on nodes tagged "nexus-iq-opensearch".
# The cluster is VPC-native, so pods send from their alias IPs and the nodes from their
# own address; both ranges are needed. A cluster outside the VPC is not affected.
resource "google_compute_firewall" "allow_opensearch" {
  count   = local.opensearch_enabled ? 1 : 0
  name    = "${local.cluster_name}-allow-opensearch"
  network = google_compute_network.iq_vpc.name
  project = var.gcp_project_id

  allow {
    protocol = "tcp"
    ports    = [tostring(var.opensearch_port)]
  }

  source_ranges = [
    var.gke_pods_cidr,
    google_compute_subnetwork.public_subnet.ip_cidr_range
  ]
  target_tags = ["nexus-iq-opensearch"]

  description = "Allow Nexus IQ Server pods to reach a self-managed OpenSearch cluster in this VPC"

  # A precondition, since a validation comparing two variables needs Terraform 1.9.
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
