# The operator, its namespace, the secrets it reads, the storage class, and the cluster itself
# (charts/nexus-iq-opensearch). The operator's validating webhook is off, so cert-manager is not
# needed; the only cost is that the operator checks the cluster definition when it reconciles it
# rather than when it is applied.

resource "kubernetes_namespace" "opensearch" {
  count = local.opensearch_create ? 1 : 0

  metadata {
    name = local.os_namespace
  }

  depends_on = [google_container_node_pool.iq_node_pool]
}

resource "helm_release" "opensearch_operator" {
  count            = local.opensearch_create ? 1 : 0
  name             = "opensearch-operator"
  repository       = "https://opensearch-project.github.io/opensearch-k8s-operator/"
  chart            = "opensearch-operator"
  version          = var.opensearch_operator_chart_version
  namespace        = "opensearch-operator-system"
  create_namespace = true
  wait             = true
  timeout          = 600

  # The operator runs on the general node pool, which is Arm by default.
  values = [yamlencode({
    webhook     = { enabled = false, certManager = { enabled = false } }
    legacyAPI   = { enabled = false }
    installCRDs = true
    tolerations = [{ key = "kubernetes.io/arch", operator = "Equal", value = "arm64", effect = "NoSchedule" }]
  })]

  depends_on = [google_container_node_pool.iq_node_pool]
}

resource "kubernetes_storage_class" "opensearch" {
  count = local.opensearch_create ? 1 : 0

  metadata {
    name = "opensearch-hyperdisk"
  }

  storage_provisioner    = "pd.csi.storage.gke.io"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type = local.os_hyperdisk["data"] ? "hyperdisk-balanced" : "pd-balanced"
  }
}

resource "kubernetes_secret" "os_ca" {
  count = local.opensearch_create ? 1 : 0

  metadata {
    name      = "nexus-iq-opensearch-ca"
    namespace = kubernetes_namespace.opensearch[0].metadata[0].name
  }

  data = {
    "ca.crt" = tls_self_signed_cert.os_ca[0].cert_pem
    "ca.key" = tls_private_key.os_ca[0].private_key_pem
  }
}

resource "kubernetes_secret" "os_admin" {
  count = local.opensearch_create ? 1 : 0

  metadata {
    name      = "nexus-iq-opensearch-admin"
    namespace = kubernetes_namespace.opensearch[0].metadata[0].name
  }

  data = {
    username = "admin"
    password = var.opensearch_admin_password != "" ? var.opensearch_admin_password : random_password.os_admin[0].result
  }
}

resource "kubernetes_secret" "os_iq_user" {
  count = local.opensearch_create ? 1 : 0

  metadata {
    name      = "nexus-iq-opensearch-iq-user"
    namespace = kubernetes_namespace.opensearch[0].metadata[0].name
  }

  data = {
    username = local.os_iq_username
    password = local.os_iq_password
  }
}

locals {
  os_tolerations = concat(
    [{ key = "dedicated", operator = "Equal", value = "opensearch", effect = "NoSchedule" }],
    local.os_arm ? [{ key = "kubernetes.io/arch", operator = "Equal", value = "arm64", effect = "NoSchedule" }] : [],
  )

  os_pool = {
    for role, p in {
      manager = { component = "masters", replicas = 3, roles = ["cluster_manager"], disk = var.opensearch_manager_disk_gb }
      data    = { component = "data", replicas = var.opensearch_data_node_count, roles = ["data", "ingest"], disk = var.opensearch_data_disk_gb }
    } :
    role => {
      component            = p.component
      replicas             = p.replicas
      roles                = p.roles
      diskSize             = "${p.disk}Gi"
      jvm                  = "-Xms${local.os_heap_mb[role]}m -Xmx${local.os_heap_mb[role]}m"
      storageClass         = "opensearch-hyperdisk"
      nodeSelector         = { opensearch-role = role }
      tolerations          = local.os_tolerations
      requiredAntiAffinity = true
      zoneSpread           = true
      resources = {
        requests = { cpu = "${local.os_pod_cpu_m[role]}m", memory = "${local.os_pod_mem_mb[role]}Mi" }
        limits   = { memory = "${local.os_pod_mem_mb[role]}Mi" }
      }
    }
  }
}

resource "helm_release" "opensearch_cluster" {
  count     = local.opensearch_create ? 1 : 0
  name      = "nexus-iq-opensearch"
  chart     = "${path.module}/charts/nexus-iq-opensearch"
  namespace = kubernetes_namespace.opensearch[0].metadata[0].name
  wait      = true
  timeout   = 2400

  values = [yamlencode({
    clusterName            = local.os_cluster_name
    version                = var.opensearch_version
    dataServiceName        = local.os_data_service
    dataNodePool           = "data"
    caSecret               = kubernetes_secret.os_ca[0].metadata[0].name
    adminCredentialsSecret = kubernetes_secret.os_admin[0].metadata[0].name
    setVMMaxMapCount       = false
    zoneAwareness          = true
    iqUser = {
      secret = kubernetes_secret.os_iq_user[0].metadata[0].name
    }
    jobs = {
      tolerations = local.general_arm ? [{ key = "kubernetes.io/arch", operator = "Equal", value = "arm64", effect = "NoSchedule" }] : []
    }
    # The bootstrap pod and the two jobs do not fit beside a cluster manager pod on a manager node,
    # so they run on the general node pool, which takes Hyperdisk only on the N4 and C4 series, and
    # Hyperdisk is at least 4 GB.
    bootstrap = {
      tolerations  = local.general_arm ? [{ key = "kubernetes.io/arch", operator = "Equal", value = "arm64", effect = "NoSchedule" }] : []
      storageClass = kubernetes_storage_class.opensearch[0].metadata[0].name
      diskSize     = "4Gi"
      jvm          = "-Xms512m -Xmx512m"
      resources    = { requests = { cpu = "250m", memory = "1Gi" }, limits = { memory = "1Gi" } }
      # The general node pool does not set vm.max_map_count. The bootstrap pod holds no data, so it
      # runs without memory-mapped index files, which also skips OpenSearch's check of that setting.
      env = [{ name = "node.store.allow_mmap", value = "false" }]
    }
    nodePools = [local.os_pool["manager"], local.os_pool["data"]]
  })]

  # The cluster is removed before the operator, whose chart owns the custom resource definitions.
  depends_on = [
    helm_release.opensearch_operator,
    google_container_node_pool.os,
    kubernetes_storage_class.opensearch,
  ]
}
