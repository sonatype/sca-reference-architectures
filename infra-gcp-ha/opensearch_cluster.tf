# The OpenSearch cluster Nexus IQ Server uses when search_engine = "opensearch" and
# opensearch_create is not false. One node at XS and S. At M and above, three data nodes
# behind an internal passthrough load balancer, and three dedicated cluster manager nodes.
# The same file is used in every Compute Engine architecture; opensearch_root.tf holds the
# parts that differ.

locals {
  opensearch_create = local.opensearch_enabled && coalesce(var.opensearch_create, var.opensearch_endpoint == "")
  os_cluster        = local.opensearch_create && var.opensearch_data_node_count > 1
  os_manager_count  = local.os_cluster ? 3 : 0

  # Memory per vCPU of the standard, highmem and highcpu shapes, used to derive the heap.
  os_gb_per_vcpu = { standard = 4, highmem = 8, highcpu = 2 }
  os_data_mem_gb = try(
    tonumber(regex("^[a-z0-9]+-(standard|highmem|highcpu)-([0-9]+)", var.opensearch_data_instance_type)[1]) *
    local.os_gb_per_vcpu[regex("^[a-z0-9]+-(standard|highmem|highcpu)-([0-9]+)", var.opensearch_data_instance_type)[0]],
    0
  )
  os_mgr_mem_gb = try(
    tonumber(regex("^[a-z0-9]+-(standard|highmem|highcpu)-([0-9]+)", var.opensearch_manager_instance_type)[1]) *
    local.os_gb_per_vcpu[regex("^[a-z0-9]+-(standard|highmem|highcpu)-([0-9]+)", var.opensearch_manager_instance_type)[0]],
    0
  )

  # Half of the machine's memory, at most 31 GB, unless set.
  os_data_heap_gb = var.opensearch_data_heap_gb != null ? var.opensearch_data_heap_gb : min(31, floor(local.os_data_mem_gb / 2))
  os_mgr_heap_gb  = var.opensearch_manager_heap_gb != null ? var.opensearch_manager_heap_gb : min(31, floor(local.os_mgr_mem_gb / 2))

  # A single node has its own name, and so its own address and disk. A node is set up only at
  # first boot, so moving between one and three or more data nodes replaces every data node.
  os_data_nodes = {
    for i in range(local.opensearch_create ? var.opensearch_data_node_count : 0) :
    (local.os_cluster ? "${local.os_prefix}-os-data-${i + 1}" : "${local.os_prefix}-os-solo-1") => {
      role       = "data"
      zone_index = i % length(local.os_zones)
      roles      = local.os_cluster ? ["data", "ingest"] : ["cluster_manager", "data", "ingest"]
      type       = var.opensearch_data_instance_type
      heap_gb    = local.os_data_heap_gb
      bootstrap  = !local.os_cluster
    }
  }
  os_manager_nodes = {
    for i in range(local.os_manager_count) :
    "${local.os_prefix}-os-mgr-${i + 1}" => {
      role       = "manager"
      zone_index = i % length(local.os_zones)
      roles      = ["cluster_manager"]
      type       = var.opensearch_manager_instance_type
      heap_gb    = local.os_mgr_heap_gb
      bootstrap  = i == 0
    }
  }
  os_nodes = merge(local.os_data_nodes, local.os_manager_nodes)

  os_bootstrap_node = one([for k, v in local.os_nodes : k if v.bootstrap])
  os_data_zones     = distinct([for k, v in local.os_data_nodes : local.os_zones[v.zone_index]])

  os_org      = "${local.os_prefix}-opensearch"
  os_admin_dn = "CN=admin,O=${local.os_org}"
  os_nodes_dn = "CN=${local.os_prefix}-os-*,O=${local.os_org}"

  os_lb_ip    = local.os_cluster ? google_compute_address.os_lb[0].address : null
  os_node_ips = { for k, v in google_compute_address.os : k => v.address }

  # What Nexus IQ Server is pointed at, created here or brought by you.
  os_endpoint     = local.opensearch_create ? (local.os_cluster ? local.os_lb_ip : local.os_node_ips[local.os_bootstrap_node]) : var.opensearch_endpoint
  os_iq_username  = local.opensearch_create && var.opensearch_username == "" ? "iq-server" : var.opensearch_username
  os_iq_password  = local.opensearch_create && var.opensearch_password == "" ? random_password.os_iq[0].result : var.opensearch_password
  os_ca_pem       = local.opensearch_create ? tls_self_signed_cert.os_ca[0].cert_pem : var.opensearch_ca_certificate
  os_admin_secret = "${local.os_prefix}-os-admin-password${local.os_secret_suffix}"

  # A replica needs a second data node, so a created single node gets none.
  os_index_replicas = local.opensearch_create ? min(var.opensearch_index_replicas, var.opensearch_data_node_count - 1) : var.opensearch_index_replicas
}

resource "random_password" "os_admin" {
  count            = local.opensearch_create && var.opensearch_admin_password == "" ? 1 : 0
  length           = 32
  special          = true
  override_special = "-_.~!#%^*+="
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
}

resource "random_password" "os_iq" {
  count            = local.opensearch_create && var.opensearch_password == "" ? 1 : 0
  length           = 32
  special          = true
  override_special = "-_.~!#%^*+="
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
}

locals {
  os_admin_password = local.opensearch_create ? (var.opensearch_admin_password != "" ? var.opensearch_admin_password : random_password.os_admin[0].result) : ""
}
