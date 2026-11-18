# What opensearch_cluster.tf needs from this root, so that file is the same in both Azure VM roots.

locals {
  # Read through the access policy so every secret waits for Terraform's own right to write it.
  os_key_vault_id    = azurerm_key_vault_access_policy.current_user.key_vault_id
  os_key_vault_uri   = azurerm_key_vault.iq_kv.vault_uri
  os_iq_subnet_cidrs = [var.private_subnet_cidr]
  os_tags            = var.common_tags
}
