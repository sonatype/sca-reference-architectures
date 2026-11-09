
resource "azurerm_key_vault" "iq_kv_ha" {
  name                = "kv${replace(lower(var.cluster_name), "-", "")}${random_string.kv_suffix.result}"
  location            = azurerm_resource_group.iq_rg.location
  resource_group_name = azurerm_resource_group.iq_rg.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = var.key_vault_sku_name


  soft_delete_retention_days = var.key_vault_soft_delete_retention_days
  purge_protection_enabled   = false


  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"


    virtual_network_subnet_ids = azurerm_subnet.private_subnets[*].id
  }

  tags = merge(var.common_tags, {
    Name = "kv${replace(lower(var.cluster_name), "-", "")}"
  })
}


resource "random_string" "kv_suffix" {
  length  = 8
  special = false
  upper   = false
}


resource "azurerm_key_vault_access_policy" "current_user" {
  key_vault_id = azurerm_key_vault.iq_kv_ha.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  secret_permissions = [
    "Get", "List", "Set", "Delete", "Recover", "Backup", "Restore", "Purge"
  ]

  certificate_permissions = [
    "Get", "List"
  ]
}


resource "azurerm_key_vault_access_policy" "container_app" {
  key_vault_id = azurerm_key_vault.iq_kv_ha.id
  tenant_id    = azurerm_container_app.iq_app_ha.identity[0].tenant_id
  object_id    = azurerm_container_app.iq_app_ha.identity[0].principal_id

  secret_permissions = [
    "Get", "List"
  ]

  depends_on = [azurerm_container_app.iq_app_ha]
}


resource "azurerm_key_vault_secret" "db_username" {
  name         = "db-username"
  value        = var.db_username
  key_vault_id = azurerm_key_vault.iq_kv_ha.id

  depends_on = [azurerm_key_vault_access_policy.current_user]

  tags = merge(var.common_tags, {
    Name = "db-username"
  })
}

resource "azurerm_key_vault_secret" "db_password" {
  name         = "db-password"
  value        = var.db_password
  key_vault_id = azurerm_key_vault.iq_kv_ha.id

  depends_on = [azurerm_key_vault_access_policy.current_user]

  tags = merge(var.common_tags, {
    Name = "db-password"
  })
}


resource "azurerm_key_vault_secret" "db_host" {
  name         = "db-host"
  value        = azurerm_postgresql_flexible_server.iq_db_ha.fqdn
  key_vault_id = azurerm_key_vault.iq_kv_ha.id

  depends_on = [azurerm_key_vault_access_policy.current_user]

  tags = merge(var.common_tags, {
    Name = "db-host"
  })
}

resource "azurerm_key_vault_secret" "db_name" {
  name         = "db-name"
  value        = azurerm_postgresql_flexible_server_database.iq_database_ha.name
  key_vault_id = azurerm_key_vault.iq_kv_ha.id

  depends_on = [azurerm_key_vault_access_policy.current_user]

  tags = merge(var.common_tags, {
    Name = "db-name"
  })
}


# The OpenSearch credentials follow the four database secrets above, so the
# vault stays the record of every credential this deployment holds. Nothing
# reads any of the six back: the container app receives its credentials as
# container app secrets, set from the variables. Both are created only when
# search_engine is "opensearch".

resource "azurerm_key_vault_secret" "opensearch_username" {
  count        = local.opensearch_enabled ? 1 : 0
  name         = "opensearch-username"
  value        = var.opensearch_username
  key_vault_id = azurerm_key_vault.iq_kv_ha.id

  depends_on = [azurerm_key_vault_access_policy.current_user]

  tags = merge(var.common_tags, {
    Name = "opensearch-username"
  })
}

resource "azurerm_key_vault_secret" "opensearch_password" {
  count        = local.opensearch_enabled ? 1 : 0
  name         = "opensearch-password"
  value        = var.opensearch_password
  key_vault_id = azurerm_key_vault.iq_kv_ha.id

  depends_on = [azurerm_key_vault_access_policy.current_user]

  tags = merge(var.common_tags, {
    Name = "opensearch-password"
  })
}