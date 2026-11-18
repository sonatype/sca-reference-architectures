# The operator, its namespace, the secrets it reads, the storage class, and the cluster itself
# (charts/nexus-iq-opensearch). The operator's validating webhook is off, so cert-manager is not
# needed; the only cost is that the operator checks the cluster definition when it reconciles it
# rather than when it is applied.

resource "kubernetes_namespace" "opensearch" {
  count = local.opensearch_create ? 1 : 0

  metadata {
    name = local.os_namespace
  }

  depends_on = [azurerm_kubernetes_cluster_node_pool.user_pool]
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

  values = [yamlencode({
    webhook     = { enabled = false, certManager = { enabled = false } }
    legacyAPI   = { enabled = false }
    installCRDs = true
  })]

  depends_on = [azurerm_kubernetes_cluster_node_pool.user_pool]
}

# Premium SSD, created in the pod's zone, with read caching as the hand-built clusters used.
resource "kubernetes_storage_class" "opensearch" {
  count = local.opensearch_create ? 1 : 0

  metadata {
    name = "opensearch-premium"
  }

  storage_provisioner    = "disk.csi.azure.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    skuName     = "Premium_LRS"
    cachingMode = "ReadOnly"
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
  os_tolerations = [{ key = "dedicated", operator = "Equal", value = "opensearch", effect = "NoSchedule" }]

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
      storageClass         = "opensearch-premium"
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
      nodeSelector = { opensearch-role = "manager" }
      tolerations  = local.os_tolerations
    }
    nodePools = [local.os_pool["manager"], local.os_pool["data"]]
  })]

  # The cluster is removed before the operator, whose chart owns the custom resource definitions.
  depends_on = [
    helm_release.opensearch_operator,
    azurerm_kubernetes_cluster_node_pool.os_data,
    azurerm_kubernetes_cluster_node_pool.os_manager,
    kubernetes_storage_class.opensearch,
  ]
}
