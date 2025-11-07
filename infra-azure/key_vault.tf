
resource "azurerm_key_vault" "iq_kv" {
  name                        = "kv-ref-arch-iq-${random_string.kv_suffix.result}"
  location                    = azurerm_resource_group.iq_rg.location
  resource_group_name         = azurerm_resource_group.iq_rg.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false
  sku_name                    = var.key_vault_sku_name


  network_acls {
    bypass         = "AzureServices"
    default_action = "Allow"
  }

  tags = {
    Name = "kv-ref-arch-iq"
  }
}


resource "random_string" "kv_suffix" {
  length  = 6
  special = false
  upper   = false
}


resource "azurerm_key_vault_access_policy" "current_user" {
  key_vault_id = azurerm_key_vault.iq_kv.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  key_permissions = [
    "Get", "List", "Update", "Create", "Import", "Delete", "Recover", "Backup", "Restore"
  ]

  secret_permissions = [
    "Get", "List", "Set", "Delete", "Recover", "Backup", "Restore", "Purge"
  ]

  certificate_permissions = [
    "Get", "List"
  ]
}


resource "azurerm_key_vault_access_policy" "container_app" {
  key_vault_id = azurerm_key_vault.iq_kv.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_container_app.iq_app.identity[0].principal_id

  secret_permissions = [
    "Get", "List"
  ]

  depends_on = [azurerm_container_app.iq_app]
}



