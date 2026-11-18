# Certificates for the OpenSearch cluster: one private authority, one certificate per node, and an
# admin certificate for the security tool. Made here rather than on the nodes, because a node cannot
# sign its own certificate and IQ Server needs the authority to trust the cluster. Keys are held in
# Terraform state, like every password this configuration creates, and reach the nodes only through
# Key Vault.

resource "tls_private_key" "os_ca" {
  count     = local.os_create ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "os_ca" {
  count           = local.os_create ? 1 : 0
  private_key_pem = tls_private_key.os_ca[0].private_key_pem

  subject {
    common_name  = "${local.os_prefix}-ca"
    organization = local.os_organization
  }

  is_ca_certificate     = true
  validity_period_hours = 87600
  allowed_uses          = ["cert_signing", "crl_signing"]
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
    common_name  = each.value.name
    organization = local.os_organization
  }

  dns_names = [each.value.name]
  # A data node behind the load balancer is reached at the balancer's address as well as its own.
  ip_addresses = each.value.has_data && local.os_cluster ? [each.value.ip, local.os_lb_ip] : [each.value.ip]
}

resource "tls_locally_signed_cert" "os_node" {
  for_each           = local.os_nodes
  cert_request_pem   = tls_cert_request.os_node[each.key].cert_request_pem
  ca_private_key_pem = tls_private_key.os_ca[0].private_key_pem
  ca_cert_pem        = tls_self_signed_cert.os_ca[0].cert_pem

  validity_period_hours = 17520
  allowed_uses          = ["digital_signature", "key_encipherment", "server_auth", "client_auth"]
}

resource "tls_private_key" "os_admin" {
  count     = local.os_create ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "os_admin" {
  count           = local.os_create ? 1 : 0
  private_key_pem = tls_private_key.os_admin[0].private_key_pem

  subject {
    common_name  = "admin"
    organization = local.os_organization
  }
}

resource "tls_locally_signed_cert" "os_admin" {
  count              = local.os_create ? 1 : 0
  cert_request_pem   = tls_cert_request.os_admin[0].cert_request_pem
  ca_private_key_pem = tls_private_key.os_ca[0].private_key_pem
  ca_cert_pem        = tls_self_signed_cert.os_ca[0].cert_pem

  validity_period_hours = 17520
  allowed_uses          = ["digital_signature", "key_encipherment", "client_auth"]
}

resource "random_password" "os_admin" {
  count            = local.os_create && var.opensearch_admin_password == "" ? 1 : 0
  length           = 32
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
  override_special = "!#%*-_=+"
}

resource "random_password" "os_iq" {
  count            = local.os_create && var.opensearch_password == "" ? 1 : 0
  length           = 32
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
  override_special = "!#%*-_=+"
}
