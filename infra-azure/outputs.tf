
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


output "application_gateway_public_ip" {
  description = "Public IP address of the Application Gateway"
  value       = azurerm_public_ip.app_gateway_pip.ip_address
}

output "application_gateway_fqdn" {
  description = "FQDN of the Application Gateway"
  value       = azurerm_public_ip.app_gateway_pip.fqdn
}

output "application_gateway_id" {
  description = "ID of the Application Gateway"
  value       = azurerm_application_gateway.iq_app_gateway.id
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
  value       = azurerm_public_ip.app_gateway_pip.fqdn != null ? "http://${azurerm_public_ip.app_gateway_pip.fqdn}" : "http://${azurerm_public_ip.app_gateway_pip.ip_address}"
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