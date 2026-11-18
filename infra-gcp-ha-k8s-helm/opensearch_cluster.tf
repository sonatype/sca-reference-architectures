# The OpenSearch cluster Nexus IQ Server uses when search_engine = "opensearch" and
# opensearch_create is not false: three data pods and three cluster manager pods, each on its
# own GKE node in a dedicated node pool, run by the OpenSearch Kubernetes Operator.
# Nexus IQ Server reaches the data pods only, through the Service nexus-iq-opensearch-data-http.

locals {
  opensearch_create = local.opensearch_enabled && coalesce(var.opensearch_create, true)

  os_namespace    = "nexus-iq-opensearch"
  os_cluster_name = "nexus-iq-opensearch"
  os_data_service = "nexus-iq-opensearch-data-http"
  os_endpoint     = local.opensearch_create ? "${local.os_data_service}.${local.os_namespace}.svc.cluster.local" : var.opensearch_endpoint

  os_zones = length(var.opensearch_zones) > 0 ? var.opensearch_zones : (
    length(data.google_compute_zones.opensearch) > 0 ? slice(sort(data.google_compute_zones.opensearch[0].names), 0, 3) : []
  )

  # Memory of the machine type, from its vCPU count: 4 GB a vCPU for standard, 8 for highmem, 2 for highcpu.
  os_gb_per_vcpu = { standard = 4, highmem = 8, highcpu = 2 }
  os_shape = {
    for role, type in { data = var.opensearch_data_instance_type, manager = var.opensearch_manager_instance_type } :
    role => try(regex("^[a-z0-9]+-(standard|highmem|highcpu)-([0-9]+)", type), ["standard", "0"])
  }
  os_vcpu   = { for role, s in local.os_shape : role => tonumber(s[1]) }
  os_mem_gb = { for role, s in local.os_shape : role => tonumber(s[1]) * local.os_gb_per_vcpu[s[0]] }

  # What a pod can be given on the node. The node reports about 95% of the machine type's memory
  # (96.9% on c4a-standard-2 and 95.7% on c4a-standard-1). GKE reserves part of the machine type's
  # memory for the kubelet (255 MB below 1 GB, otherwise 25% of the first 4 GB, 20% of the next
  # 4, 10% of the next 8, 6% of the next 112 and 2% above) and 100 MB for eviction. GKE's own
  # daemon pods (kube-proxy, network policy, logging, metrics, Managed Prometheus, node local DNS,
  # the disk and Filestore drivers) request 850 MB and 539m CPU on every node; 900 MB and 550m
  # are left for them, and 50 MB more of memory as headroom. GKE reserves CPU for the kubelet too:
  # 6% of the first core, 1% of the next, 0.5% of the next two and 0.25% of every core above four.
  os_kubelet_mib = {
    for role, m in local.os_mem_gb : role => m < 1 ? 255 : 1024 * (
      0.25 * min(m, 4) + 0.2 * min(max(m - 4, 0), 4) + 0.1 * min(max(m - 8, 0), 8) + 0.06 * min(max(m - 16, 0), 112) + 0.02 * max(m - 128, 0)
    )
  }
  os_pod_mem_mb = { for role, m in local.os_mem_gb : role => max(1024, floor(1024 * m * 0.95 - local.os_kubelet_mib[role] - 100 - 900 - 50)) }
  os_pod_cpu_m = {
    for role, v in local.os_vcpu : role => max(250, floor(
      v * 1000 - 60 - 10 * min(max(v - 1, 0), 1) - 5 * min(max(v - 2, 0), 2) - 2.5 * max(v - 4, 0) - 550
    ))
  }

  # Half of the machine's memory, at most 31 GB, at most three quarters of the pod's memory, and at
  # least 640 MB of the pod left outside the heap: OpenSearch 3.7 with its bundled plugins uses
  # about 480 MB beyond the heap.
  os_heap_mb = {
    data    = var.opensearch_data_heap_gb != null ? var.opensearch_data_heap_gb * 1024 : min(31 * 1024, local.os_mem_gb["data"] * 512, floor(local.os_pod_mem_mb["data"] * 0.75), local.os_pod_mem_mb["data"] - 640)
    manager = var.opensearch_manager_heap_gb != null ? var.opensearch_manager_heap_gb * 1024 : min(31 * 1024, local.os_mem_gb["manager"] * 512, floor(local.os_pod_mem_mb["manager"] * 0.75), local.os_pod_mem_mb["manager"] - 640)
  }

  os_iq_username = local.opensearch_create && var.opensearch_username == "" ? "iq-server" : var.opensearch_username
  os_iq_password = local.opensearch_create && var.opensearch_password == "" ? random_password.os_iq[0].result : var.opensearch_password
  os_ca_pem      = local.opensearch_create ? tls_self_signed_cert.os_ca[0].cert_pem : var.opensearch_ca_certificate

  # A replica needs a second data node.
  os_index_replicas = local.opensearch_create ? min(var.opensearch_index_replicas, var.opensearch_data_node_count - 1) : var.opensearch_index_replicas

  os_hyperdisk = { for role, type in { data = var.opensearch_data_instance_type, manager = var.opensearch_manager_instance_type } : role => can(regex("^(n4|n4a|n4d|c4|c4a|c4d)-", type)) }
  os_arm       = can(regex("^(n4a|c4a|t2a)-", var.opensearch_data_instance_type))
  general_arm  = can(regex("^(n4a|c4a|t2a)-", var.node_instance_type))
}

data "google_compute_zones" "opensearch" {
  count   = local.opensearch_create && length(var.opensearch_zones) == 0 ? 1 : 0
  region  = var.gcp_region
  project = var.gcp_project_id
  status  = "UP"
}

# The certificate authority the operator signs every node certificate with. Terraform makes it,
# so it can hand the same certificate to Nexus IQ Server.
resource "tls_private_key" "os_ca" {
  count     = local.opensearch_create ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "os_ca" {
  count                 = local.opensearch_create ? 1 : 0
  private_key_pem       = tls_private_key.os_ca[0].private_key_pem
  is_ca_certificate     = true
  validity_period_hours = 87600

  subject {
    common_name  = "${local.os_cluster_name}-ca"
    organization = local.os_cluster_name
  }

  allowed_uses = ["cert_signing", "crl_signing", "digital_signature"]

  lifecycle {
    precondition {
      condition     = var.opensearch_use_tls && var.opensearch_port == 9200
      error_message = "When this configuration builds the OpenSearch cluster, opensearch_use_tls must be true and opensearch_port 9200."
    }
    precondition {
      condition     = local.os_heap_mb["data"] >= 512 && local.os_heap_mb["manager"] >= 512
      error_message = "The OpenSearch heap could not be derived from the machine types. Set opensearch_data_heap_gb and opensearch_manager_heap_gb."
    }
  }
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
