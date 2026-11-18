# IQ Server's initial admin password, kept in Key Vault. container_app.tf also
# holds it as a Container App secret and hands it to the container as
# NXIQ_INITIAL_ADMIN_PASSWORD, which IQ Server reads on its first start only.
resource "azurerm_key_vault_secret" "iq_admin_password" {
  name         = "iq-admin-initial-password"
  value        = var.iq_admin_initial_password
  key_vault_id = azurerm_key_vault.iq_kv.id

  depends_on = [azurerm_key_vault_access_policy.current_user]

  tags = merge(var.common_tags, {
    Name = "iq-admin-initial-password"
  })
}

output "iq_admin_initial_password" {
  description = "The initial admin password IQ Server was given, read by iq-post-deploy.sh"
  value       = var.iq_admin_initial_password
  sensitive   = true
}
