output "opensearch_created" {
  description = "Whether this configuration built the OpenSearch cluster"
  value       = local.opensearch_create
}

output "opensearch_data_node_count" {
  description = "Number of OpenSearch data nodes, which the shard counts follow: the nodes this configuration builds, or opensearch_data_node_count as set for a cluster you bring. Null when the built-in index is in use."
  value       = local.opensearch_enabled ? var.opensearch_data_node_count : null
}

output "opensearch_namespace" {
  description = "Kubernetes namespace of the OpenSearch cluster, when this configuration built it"
  value       = local.opensearch_create ? local.os_namespace : null
}

output "opensearch_admin_secret_name" {
  description = "Kubernetes secret in opensearch_namespace holding the OpenSearch admin user name and password, when this configuration built the cluster"
  value       = local.opensearch_create ? kubernetes_secret.os_admin[0].metadata[0].name : null
}

output "opensearch_pod_sizing" {
  description = "CPU in millicores, memory in MiB and Java heap in MiB of each OpenSearch data and cluster manager pod, derived from the node sizes, when this configuration built the cluster"
  value = local.opensearch_create ? {
    for role in ["data", "manager"] : role => {
      cpu_millicores = local.os_pod_cpu_m[role]
      memory_mib     = local.os_pod_mem_mb[role]
      heap_mib       = local.os_heap_mb[role]
    }
  } : null
}
