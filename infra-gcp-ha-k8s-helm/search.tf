# Search backend for Sonatype IQ Server.
#
# Setting search_engine to "opensearch" points IQ at an OpenSearch cluster you run yourself:
# Google Cloud has no managed OpenSearch service, so there is no first-party cluster to create here
# and this configuration does not provision one. You supply the endpoint of a cluster you have
# already built, which keeps the cluster, and the index data in it, independent of Terraform runs
# here.
#
# Unlike the two Compute Engine roots, the `search:` block is not written by a startup script. The
# Helm chart renders config.yml inside the pod, so render-values.sh reads the outputs below and
# writes them into a generated values file. See README.md, "Search Backend".

locals {
  opensearch_enabled = var.search_engine == "opensearch"

  # http or https decides whether IQ Server opens a TLS connection. With TLS, the cluster's
  # certificate must be trusted by the JVM in every pod: see README.md, "Trusting a private
  # certificate authority".
  opensearch_scheme = var.opensearch_use_tls ? "https" : "http"

  opensearch_uri = "${local.opensearch_scheme}://${var.opensearch_endpoint}:${var.opensearch_port}"
}

# Google Cloud denies all ingress that no rule allows, so an OpenSearch cluster built inside this
# VPC needs a rule of its own. Tag each OpenSearch node "nexus-iq-opensearch" to pick this up.
#
# Both sources are needed: this cluster is VPC-native, so a pod's own alias IP is the source
# address of traffic it sends, while anything running on the node itself uses the node address.
#
# A cluster outside this VPC is reached over whatever path you have built to it, and this rule has
# no effect on it. This root declares no egress rule, so egress needs nothing added.
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
