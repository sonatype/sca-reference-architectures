# The parts of the OpenSearch cluster that differ between architectures: network, subnets,
# zones, the tag on the Nexus IQ Server instances and the secret naming.
# opensearch_cluster.tf and the other opensearch_*.tf files are the same in every Compute
# Engine architecture.

locals {
  os_prefix = local.app_name

  # Each zone has its own private subnet here. A cluster uses the configuration's zones; a
  # single node uses the first.
  os_default_zones = var.opensearch_data_node_count > 1 ? var.availability_zones : [var.availability_zones[0]]
  os_zones         = length(var.opensearch_zones) > 0 ? var.opensearch_zones : local.os_default_zones

  os_zones_valid  = alltrue([for z in local.os_zones : contains(var.availability_zones, z)])
  os_zone_subnets = [for z in local.os_zones : try(google_compute_subnetwork.private_subnets[index(var.availability_zones, z)].self_link, google_compute_subnetwork.private_subnets[0].self_link)]
  os_network      = google_compute_network.iq_ha_vpc.self_link
  os_labels       = var.common_tags

  # Secret ids in this architecture carry the deployment's random suffix.
  os_secret_suffix = "-${random_string.suffix.result}"
}
