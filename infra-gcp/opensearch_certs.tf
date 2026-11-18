# Certificates for the OpenSearch cluster, made by Terraform: a private authority, one
# certificate per node, and an admin certificate for the security plugin's admin tools.
# The keys are in Terraform state and in Secret Manager, never in instance metadata.

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
    common_name  = "${local.os_org}-ca"
    organization = local.os_org
  }

  allowed_uses = ["cert_signing", "crl_signing", "digital_signature"]
}

resource "tls_private_key" "os_node" {
  for_each  = local.os_nodes
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "os_node" {
  for_each        = local.os_nodes
  private_key_pem = tls_private_key.os_node[each.key].private_key_pem

  subject {
    common_name  = each.key
    organization = local.os_org
  }

  dns_names = [each.key, "localhost"]
  # A data node behind the load balancer also answers on the load balancer's address.
  ip_addresses = compact([
    google_compute_address.os[each.key].address,
    "127.0.0.1",
    each.value.role == "data" ? local.os_lb_ip : "",
  ])
}

resource "tls_locally_signed_cert" "os_node" {
  for_each              = local.os_nodes
  cert_request_pem      = tls_cert_request.os_node[each.key].cert_request_pem
  ca_private_key_pem    = tls_private_key.os_ca[0].private_key_pem
  ca_cert_pem           = tls_self_signed_cert.os_ca[0].cert_pem
  validity_period_hours = 17520
  early_renewal_hours   = 720

  allowed_uses = ["digital_signature", "key_encipherment", "server_auth", "client_auth"]
}

resource "tls_private_key" "os_admin" {
  count     = local.opensearch_create ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "os_admin" {
  count           = local.opensearch_create ? 1 : 0
  private_key_pem = tls_private_key.os_admin[0].private_key_pem

  subject {
    common_name  = "admin"
    organization = local.os_org
  }
}

resource "tls_locally_signed_cert" "os_admin" {
  count                 = local.opensearch_create ? 1 : 0
  cert_request_pem      = tls_cert_request.os_admin[0].cert_request_pem
  ca_private_key_pem    = tls_private_key.os_ca[0].private_key_pem
  ca_cert_pem           = tls_self_signed_cert.os_ca[0].cert_pem
  validity_period_hours = 17520
  early_renewal_hours   = 720

  allowed_uses = ["digital_signature", "key_encipherment", "client_auth"]
}
