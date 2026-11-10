
output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.iq_rg.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.iq_rg.location
}


output "vnet_id" {
  description = "ID of the Virtual Network"
  value       = azurerm_virtual_network.iq_vnet.id
}

output "vnet_name" {
  description = "Name of the Virtual Network"
  value       = azurerm_virtual_network.iq_vnet.name
}

output "vnet_address_space" {
  description = "Address space of the Virtual Network"
  value       = azurerm_virtual_network.iq_vnet.address_space
}


output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = azurerm_subnet.public_subnet.id
}

output "private_subnet_id" {
  description = "ID of the private subnet"
  value       = azurerm_subnet.private_subnet.id
}

output "db_subnet_id" {
  description = "ID of the database subnet"
  value       = azurerm_subnet.db_subnet.id
}



output "container_app_environment_id" {
  description = "ID of the Container App Environment"
  value       = azurerm_container_app_environment.iq_env.id
}

output "container_app_id" {
  description = "ID of the Container App"
  value       = azurerm_container_app.iq_app.id
}



output "db_server_name" {
  description = "Name of the PostgreSQL server"
  value       = azurerm_postgresql_flexible_server.iq_db.name
}


output "db_server_id" {
  description = "ID of the PostgreSQL server"
  value       = azurerm_postgresql_flexible_server.iq_db.id
}


output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.iq_storage.name
}


output "file_share_name" {
  description = "Name of the file share"
  value       = azurerm_storage_share.iq_file_share.name
}


output "key_vault_id" {
  description = "ID of the Key Vault"
  value       = azurerm_key_vault.iq_kv.id
}



output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.iq_logs.id
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.iq_logs.name
}


output "application_insights_id" {
  description = "ID of Application Insights"
  value       = var.enable_monitoring ? azurerm_application_insights.iq_insights[0].id : null
}


output "application_url" {
  description = "URL to access Nexus IQ Server"
  value       = "https://${azurerm_container_app.iq_app.ingress[0].fqdn}"
}


output "public_nsg_id" {
  description = "ID of the public network security group"
  value       = azurerm_network_security_group.public_nsg.id
}

output "private_nsg_id" {
  description = "ID of the private network security group"
  value       = azurerm_network_security_group.private_nsg.id
}

output "db_nsg_id" {
  description = "ID of the database network security group"
  value       = azurerm_network_security_group.db_nsg.id
}


output "search_engine" {
  description = "Which search backend IQ Server is configured to use"
  value       = var.search_engine
}

output "opensearch_uri" {
  description = "The OpenSearch URI written into IQ Server's config.yml. Null when search_engine is 'lucene'."
  value       = local.opensearch_enabled ? local.opensearch_uri : null
}

output "opensearch_index_replicas" {
  description = "Replicas per Nexus One index shard written as nexusOne.connection.nexusOneIndexReplicas. Null when search_engine is 'lucene'."
  value       = local.opensearch_enabled ? var.opensearch_index_replicas : null
}