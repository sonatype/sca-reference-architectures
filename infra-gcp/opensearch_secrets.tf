# Secret Manager holds every key, certificate and password the nodes need. Each node reads
# them at boot with the OpenSearch service account, which can read only these secrets, the
# certificate authority and the Nexus IQ Server user's password.

resource "google_service_account" "opensearch" {
  count        = local.opensearch_create ? 1 : 0
  account_id   = "${local.os_prefix}-os"
  display_name = "OpenSearch nodes"
  description  = "Reads the OpenSearch node secrets at boot"
  project      = var.gcp_project_id
}

locals {
  # Secret names, which decide the resource addresses, kept apart from the values, which are sensitive.
  os_secret_names = local.opensearch_create ? concat(
    flatten([for k in keys(local.os_nodes) : ["${k}-key", "${k}-crt"]]),
    ["${local.os_prefix}-os-admin-key", "${local.os_prefix}-os-admin-crt", "${local.os_prefix}-os-admin-password"],
  ) : []

  os_secret_data = local.opensearch_create ? merge(
    { for k in keys(local.os_nodes) : "${k}-key" => tls_private_key.os_node[k].private_key_pem_pkcs8 },
    { for k in keys(local.os_nodes) : "${k}-crt" => tls_locally_signed_cert.os_node[k].cert_pem },
    {
      "${local.os_prefix}-os-admin-key"      = tls_private_key.os_admin[0].private_key_pem_pkcs8
      "${local.os_prefix}-os-admin-crt"      = tls_locally_signed_cert.os_admin[0].cert_pem
      "${local.os_prefix}-os-admin-password" = local.os_admin_password
    },
  ) : {}
}

resource "google_secret_manager_secret" "os" {
  for_each  = toset(local.os_secret_names)
  secret_id = "${each.key}${local.os_secret_suffix}"
  project   = var.gcp_project_id
  labels    = local.os_labels

  replication {
    auto {}
  }

  depends_on = [google_project_service.required_apis]
}

resource "google_secret_manager_secret_version" "os" {
  for_each    = toset(local.os_secret_names)
  secret      = google_secret_manager_secret.os[each.key].id
  secret_data = local.os_secret_data[each.key]
}

resource "google_secret_manager_secret_iam_member" "os" {
  for_each  = toset(local.os_secret_names)
  secret_id = google_secret_manager_secret.os[each.key].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.opensearch[0].email}"
  project   = var.gcp_project_id
}

# The certificate authority and the Nexus IQ Server user's password are the secrets search.tf
# already keeps for the server.
resource "google_secret_manager_secret_iam_member" "os_ca" {
  count     = local.opensearch_create ? 1 : 0
  secret_id = google_secret_manager_secret.opensearch_ca[0].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.opensearch[0].email}"
  project   = var.gcp_project_id
}

resource "google_secret_manager_secret_iam_member" "os_iq_password" {
  count     = local.opensearch_create ? 1 : 0
  secret_id = google_secret_manager_secret.opensearch_password[0].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.opensearch[0].email}"
  project   = var.gcp_project_id
}
