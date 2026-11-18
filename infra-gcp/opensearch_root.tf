# The parts of the OpenSearch cluster that differ between architectures: network, subnets,
# zones, the tag on the Nexus IQ Server instances and its service account.
# opensearch_cluster.tf is the same file in every Compute Engine architecture.

# Zones the region offers, for spreading three data nodes when opensearch_zones is empty.
data "google_compute_zones" "opensearch" {
  count   = local.opensearch_create && var.opensearch_data_node_count > 1 && length(var.opensearch_zones) == 0 ? 1 : 0
  region  = var.gcp_region
  project = var.gcp_project_id
  status  = "UP"
}

locals {
  os_prefix = local.app_name

  # One node runs in the server's own zone; a cluster takes the first three zones of the region.
  os_default_zones = var.opensearch_data_node_count > 1 ? (
    length(data.google_compute_zones.opensearch) > 0 ? slice(sort(data.google_compute_zones.opensearch[0].names), 0, 3) : []
  ) : [var.gcp_zone]

  os_zones = length(var.opensearch_zones) > 0 ? var.opensearch_zones : local.os_default_zones

  # This architecture has one regional private subnet, which every zone shares.
  os_zones_valid   = true
  os_zone_subnets  = [for z in local.os_zones : google_compute_subnetwork.iq_private_subnet.self_link]
  os_zone_cidrs    = [for z in local.os_zones : var.private_subnet_cidr]
  os_network       = google_compute_network.iq_vpc.self_link
  os_iq_tag        = "nexus-iq-server"
  os_iq_sa_email   = google_service_account.iq_service.email
  os_labels        = {}
  os_secret_suffix = ""
}
