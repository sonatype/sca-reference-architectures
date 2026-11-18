# The OpenSearch cluster Nexus IQ Server uses when search_engine = "opensearch" and
# opensearch_create is not false: data pods and three cluster manager pods, each on its own AKS
# node in a dedicated node pool, run by the OpenSearch Kubernetes Operator.
# Nexus IQ Server reaches the data pods only, through the Service nexus-iq-opensearch-data-http.

locals {
  opensearch_create = local.opensearch_enabled && coalesce(var.opensearch_create, true)

  os_namespace    = "nexus-iq-opensearch"
  os_cluster_name = "nexus-iq-opensearch"
  os_data_service = "nexus-iq-opensearch-data-http"
  os_endpoint     = local.opensearch_create ? "${local.os_data_service}.${local.os_namespace}.svc.cluster.local" : var.opensearch_endpoint

  # Memory of the VM sizes this configuration publishes. A size not listed needs
  # opensearch_data_heap_gb or opensearch_manager_heap_gb, and gets the smallest pod.
  os_vm_memory_gb = {
    Standard_D2pls_v6 = 4
    Standard_D4pls_v6 = 8
    Standard_D2ps_v6  = 8
    Standard_D4ps_v6  = 16
    Standard_D8ps_v6  = 32
    Standard_E2ps_v6  = 16
    Standard_E4ps_v6  = 32
    Standard_E8ps_v6  = 64
  }
  os_type   = { data = var.opensearch_data_instance_type, manager = var.opensearch_manager_instance_type }
  os_mem_gb = { for role, type in local.os_type : role => lookup(local.os_vm_memory_gb, type, 0) }
  os_vcpu   = { for role, type in local.os_type : role => tonumber(try(regex("^Standard_[A-Z]([0-9]+)", type)[0], "0")) }

  # What a pod can be given on the node. The node reports about 95% of the VM's memory. AKS keeps
  # 750 MB of that for the kubelet and eviction (20 MB per pod at 30 pods, plus 150 MB). AKS's
  # own daemon pods, with Container insights and Azure network policy on, request 1.2 GB and
  # 0.52 vCPU on every node, so 1,300 MB is kept for them. The operator's setup jobs run on the
  # cluster manager nodes and take 300 MB more there. CPU allows for those requests and the
  # kubelet's CPU reservation.
  os_pod_mem_mb = {
    for role, m in local.os_mem_gb : role => max(1024, floor(1024 * m * 0.95) - 750 - 1300 - (role == "manager" ? 300 : 0))
  }
  os_pod_cpu_m = { for role, v in local.os_vcpu : role => max(250, v * 1000 - 750) }

  # Half of the VM's memory, at most 31 GB, at most three quarters of the pod's memory, and at least
  # 640 MB of the pod left outside the heap: OpenSearch 3.7 with its bundled plugins uses about
  # 480 MB beyond the heap, so a small pod at three quarters is killed for running out of memory.
  os_heap_mb = {
    data    = var.opensearch_data_heap_gb != null ? var.opensearch_data_heap_gb * 1024 : min(31 * 1024, local.os_mem_gb["data"] * 512, floor(local.os_pod_mem_mb["data"] * 0.75), local.os_pod_mem_mb["data"] - 640)
    manager = var.opensearch_manager_heap_gb != null ? var.opensearch_manager_heap_gb * 1024 : min(31 * 1024, local.os_mem_gb["manager"] * 512, floor(local.os_pod_mem_mb["manager"] * 0.75), local.os_pod_mem_mb["manager"] - 640)
  }

  os_iq_username = local.opensearch_create && var.opensearch_username == "" ? "iq-server" : var.opensearch_username
  os_iq_password = local.opensearch_create && var.opensearch_password == "" ? random_password.os_iq[0].result : var.opensearch_password
  os_ca_pem      = local.opensearch_create ? tls_self_signed_cert.os_ca[0].cert_pem : ""

  # A replica needs a second data node.
  os_index_replicas = local.opensearch_create ? min(var.opensearch_index_replicas, var.opensearch_data_node_count - 1) : var.opensearch_index_replicas
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
      error_message = "The OpenSearch heap could not be derived from the VM sizes. Set opensearch_data_heap_gb and opensearch_manager_heap_gb."
    }
    precondition {
      condition     = alltrue([for t in values(local.os_type) : can(regex("^Standard_[A-Z][0-9]+[a-z]*p[a-z]*_v[0-9]+$", t))])
      error_message = "The OpenSearch node pools run Arm nodes, so opensearch_data_instance_type and opensearch_manager_instance_type must be Arm VM sizes, such as Standard_D2ps_v6."
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
