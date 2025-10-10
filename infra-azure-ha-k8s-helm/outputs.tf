output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.iq_rg.name
}

output "aks_cluster_name" {
  description = "Name of the AKS cluster"
  value       = azurerm_kubernetes_cluster.iq_aks.name
}

output "aks_cluster_id" {
  description = "ID of the AKS cluster"
  value       = azurerm_kubernetes_cluster.iq_aks.id
}

output "aks_kube_config" {
  description = "Kubernetes configuration for AKS cluster"
  value       = azurerm_kubernetes_cluster.iq_aks.kube_config_raw
  sensitive   = true
}

output "aks_cluster_endpoint" {
  description = "Endpoint for the AKS cluster"
  value       = azurerm_kubernetes_cluster.iq_aks.kube_config.0.host
  sensitive   = true
}

output "aks_node_resource_group" {
  description = "Resource group for AKS nodes"
  value       = azurerm_kubernetes_cluster.iq_aks.node_resource_group
}

# Database Outputs
output "postgres_server_name" {
  description = "Name of the PostgreSQL Flexible Server"
  value       = azurerm_postgresql_flexible_server.iq_db.name
}

output "postgres_server_fqdn" {
  description = "FQDN of the PostgreSQL Flexible Server"
  value       = azurerm_postgresql_flexible_server.iq_db.fqdn
}

output "postgres_database_name" {
  description = "Name of the PostgreSQL database"
  value       = azurerm_postgresql_flexible_server_database.iq_database.name
}

output "postgres_connection_string" {
  description = "PostgreSQL connection string"
  value       = "postgresql://${var.database_username}@${azurerm_postgresql_flexible_server.iq_db.name}:${var.database_password}@${azurerm_postgresql_flexible_server.iq_db.fqdn}:5432/${azurerm_postgresql_flexible_server_database.iq_database.name}?sslmode=require"
  sensitive   = true
}

# Storage Outputs
output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.iq_storage.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.iq_storage.id
}

output "storage_share_name" {
  description = "Name of the Azure Files share for data"
  value       = azurerm_storage_share.iq_data.name
}

output "storage_cluster_share_name" {
  description = "Name of the Azure Files share for cluster coordination"
  value       = azurerm_storage_share.iq_cluster.name
}

# Application Gateway Outputs
output "application_gateway_name" {
  description = "Name of the Application Gateway"
  value       = azurerm_application_gateway.appgw.name
}

output "application_gateway_id" {
  description = "ID of the Application Gateway"
  value       = azurerm_application_gateway.appgw.id
}

output "application_gateway_public_ip" {
  description = "Public IP address of the Application Gateway"
  value       = azurerm_public_ip.appgw_pip.ip_address
}

output "application_gateway_fqdn" {
  description = "FQDN of the Application Gateway"
  value       = azurerm_public_ip.appgw_pip.fqdn
}

# Network Outputs
output "vnet_id" {
  description = "ID of the Virtual Network"
  value       = azurerm_virtual_network.iq_vnet.id
}

output "vnet_name" {
  description = "Name of the Virtual Network"
  value       = azurerm_virtual_network.iq_vnet.name
}

output "aks_subnet_id" {
  description = "ID of the AKS subnet"
  value       = azurerm_subnet.aks_subnet.id
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = azurerm_subnet.public_subnet.id
}

output "db_subnet_id" {
  description = "ID of the database subnet"
  value       = azurerm_subnet.db_subnet.id
}

# Monitoring Outputs
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
  value       = azurerm_application_insights.iq_insights.id
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = azurerm_application_insights.iq_insights.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = azurerm_application_insights.iq_insights.connection_string
  sensitive   = true
}

# Deployment Information
# output "nexus_iq_namespace" {
#   description = "Kubernetes namespace for Nexus IQ Server"
#   value       = kubernetes_namespace.nexus_iq.metadata[0].name
# }

output "nexus_iq_url" {
  description = "URL to access Nexus IQ Server (after Helm deployment)"
  value       = "http://${azurerm_public_ip.appgw_pip.fqdn != null && azurerm_public_ip.appgw_pip.fqdn != "" ? azurerm_public_ip.appgw_pip.fqdn : azurerm_public_ip.appgw_pip.ip_address}"
}

# kubectl command
output "kubectl_config_command" {
  description = "Command to configure kubectl"
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.iq_rg.name} --name ${azurerm_kubernetes_cluster.iq_aks.name}"
}

# Helm deployment hints
output "helm_install_command" {
  description = "Command to install Nexus IQ Server using Helm"
  value       = "./helm-install.sh"
}

# High Availability Status
output "ha_configuration" {
  description = "High Availability configuration summary"
  value = {
    aks_zones             = local.availability_zones
    database_ha_mode      = var.db_high_availability_mode
    storage_replication   = var.storage_account_replication_type
    appgw_zones           = local.availability_zones
    min_replicas          = var.nexus_iq_replica_count
    geo_redundant_backups = var.db_geo_redundant_backup_enabled
  }
}
