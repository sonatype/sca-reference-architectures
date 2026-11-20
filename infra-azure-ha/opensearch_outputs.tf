# Outputs for the OpenSearch cluster this configuration builds. Each is null when it builds none.

output "opensearch_data_node_count" {
  description = "Number of OpenSearch data nodes: the nodes this configuration builds, or opensearch_data_node_count for a cluster you bring with opensearch_create = false. The deploy sets the Nexus One shard counts from it: 1 with one data node, the data node count above that. Null when search_engine is \"builtin\"."
  value       = local.opensearch_enabled ? var.opensearch_data_node_count : null
}

output "opensearch_endpoint" {
  description = "Address IQ Server reaches OpenSearch at: the internal load balancer with three or more data nodes, the single node otherwise."
  value       = local.opensearch_enabled ? local.os_endpoint : null
}

output "opensearch_ca_certificate" {
  description = "The private certificate authority, PEM, that signed every OpenSearch node certificate. A public certificate and not a credential."
  value       = local.os_create ? local.os_ca_pem : null
}

output "opensearch_admin_secret_name" {
  description = "Name of the Key Vault secret holding the OpenSearch admin password."
  value       = local.os_create ? "os-admin-password" : null
}

output "opensearch_node_names" {
  description = "Names of the OpenSearch VMs, for az vm run-command when a node needs attention."
  value       = local.os_create ? sort([for n in local.os_nodes : n.name]) : null
}

output "opensearch_bootstrap_node" {
  description = "Name of the OpenSearch VM that creates the user IQ Server signs in as, when this configuration built the cluster. iq-post-deploy.sh waits for it before choosing OpenSearch."
  value       = local.os_create ? local.os_nodes[local.os_bootstrap_key].name : ""
}
