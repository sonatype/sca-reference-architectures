output "opensearch_created" {
  description = "Whether this configuration built the OpenSearch cluster"
  value       = local.opensearch_create
}

output "opensearch_data_node_count" {
  description = "Number of OpenSearch data nodes, which the shard counts follow: the nodes this configuration builds, or opensearch_data_node_count as set for a cluster you bring. Null when the built-in index is in use."
  value       = local.opensearch_enabled ? var.opensearch_data_node_count : null
}

output "opensearch_endpoint" {
  description = "Address Nexus IQ Server reaches OpenSearch on: the internal load balancer at M and above, the node itself at XS and S"
  value       = local.opensearch_enabled ? local.os_endpoint : null
}

output "opensearch_username" {
  description = "OpenSearch user Nexus IQ Server authenticates as"
  value       = local.opensearch_enabled ? local.os_iq_username : null
}

output "opensearch_ca_certificate" {
  description = "PEM certificate of the authority that signed the OpenSearch node certificates, when this configuration built the cluster"
  value       = local.opensearch_create ? tls_self_signed_cert.os_ca[0].cert_pem : null
}

output "opensearch_admin_password_secret_name" {
  description = "Secret Manager secret holding the OpenSearch admin password, when this configuration built the cluster"
  value       = local.opensearch_create ? google_secret_manager_secret.os["${local.os_prefix}-os-admin-password"].secret_id : null
}

output "opensearch_node_names" {
  description = "Names of the OpenSearch instances, when this configuration built the cluster"
  value       = keys(local.os_nodes)
}

output "opensearch_bootstrap_node" {
  description = "Name of the OpenSearch instance that creates the user Nexus IQ Server signs in as, when this configuration built the cluster. iq-post-deploy.sh waits for it before choosing OpenSearch."
  value       = local.opensearch_create ? local.os_bootstrap_node : ""
}

output "opensearch_bootstrap_zone" {
  description = "Zone of the instance named by opensearch_bootstrap_node, when this configuration built the cluster"
  value       = local.opensearch_create ? local.os_zones[local.os_nodes[local.os_bootstrap_node].zone_index] : ""
}
