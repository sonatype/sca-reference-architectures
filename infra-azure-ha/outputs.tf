
output "application_gateway_url" {
  description = "Application Gateway URL for accessing Nexus IQ Server HA cluster"
  value       = "http://${azurerm_public_ip.app_gw_pip_ha.fqdn != null ? azurerm_public_ip.app_gw_pip_ha.fqdn : azurerm_public_ip.app_gw_pip_ha.ip_address}"
}

output "application_gateway_fqdn" {
  description = "Application Gateway public IP FQDN"
  value       = azurerm_public_ip.app_gw_pip_ha.fqdn
}


output "container_app_url" {
  description = "Container App direct URL for HA cluster"
  value       = "https://${azurerm_container_app.iq_app_ha.ingress[0].fqdn}"
}

output "container_app_fqdn" {
  description = "Container App FQDN"
  value       = azurerm_container_app.iq_app_ha.ingress[0].fqdn
}


output "ha_configuration" {
  description = "High Availability configuration details"
  value = {
    min_replicas       = var.iq_min_replicas
    max_replicas       = var.iq_max_replicas
    availability_zones = var.app_gateway_zones
    database_ha_mode   = var.db_high_availability_mode
    storage_redundancy = var.storage_account_replication_type
  }
}


output "database_endpoint" {
  description = "PostgreSQL Flexible Server endpoint (Zone-redundant)"
  value       = azurerm_postgresql_flexible_server.iq_db_ha.fqdn
  sensitive   = false
}

output "database_name" {
  description = "Database name for Nexus IQ Server"
  value       = azurerm_postgresql_flexible_server_database.iq_database_ha.name
}

output "database_ha_status" {
  description = "Database High Availability configuration"
  value = {
    ha_mode              = azurerm_postgresql_flexible_server.iq_db_ha.high_availability[0].mode
    primary_zone         = azurerm_postgresql_flexible_server.iq_db_ha.zone
    standby_zone         = azurerm_postgresql_flexible_server.iq_db_ha.high_availability[0].standby_availability_zone
    geo_redundant_backup = azurerm_postgresql_flexible_server.iq_db_ha.geo_redundant_backup_enabled
  }
}


output "storage_account_name" {
  description = "Storage account name for HA file share"
  value       = azurerm_storage_account.iq_storage_ha.name
}

output "file_share_name" {
  description = "Azure Files share name for clustering"
  value       = azurerm_storage_share.iq_data_ha.name
}

output "storage_redundancy" {
  description = "Storage redundancy configuration"
  value       = azurerm_storage_account.iq_storage_ha.account_replication_type
}


output "key_vault_uri" {
  description = "Key Vault URI for secrets management"
  value       = azurerm_key_vault.iq_kv_ha.vault_uri
  sensitive   = false
}


output "container_app_environment_id" {
  description = "Container App Environment ID"
  value       = azurerm_container_app_environment.iq_env_ha.id
}

output "container_app_environment_default_domain" {
  description = "Container App Environment default domain"
  value       = azurerm_container_app_environment.iq_env_ha.default_domain
}


output "log_analytics_workspace_id" {
  description = "Log Analytics Workspace ID for monitoring"
  value       = azurerm_log_analytics_workspace.iq_logs_ha.id
}


output "application_insights_instrumentation_key" {
  description = "Application Insights instrumentation key"
  value       = var.enable_monitoring ? azurerm_application_insights.iq_insights_ha[0].instrumentation_key : null
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Application Insights connection string"
  value       = var.enable_monitoring ? azurerm_application_insights.iq_insights_ha[0].connection_string : null
  sensitive   = true
}


output "virtual_network_id" {
  description = "Virtual Network ID"
  value       = azurerm_virtual_network.iq_vnet.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs for Container Apps (Multi-zone)"
  value       = azurerm_subnet.private_subnets[*].id
}

output "public_subnet_ids" {
  description = "Public subnet IDs for Application Gateway (Multi-zone)"
  value       = azurerm_subnet.public_subnets[*].id
}


output "resource_group_name" {
  description = "Resource group name"
  value       = azurerm_resource_group.iq_rg.name
}

output "resource_group_location" {
  description = "Resource group location"
  value       = azurerm_resource_group.iq_rg.location
}


output "ha_deployment_summary" {
  description = "High Availability deployment summary"
  value = {
    deployment_type      = "high-availability"
    container_replicas   = "${var.iq_min_replicas}-${var.iq_max_replicas}"
    database_type        = "PostgreSQL Flexible Server"
    database_ha          = var.db_high_availability_mode
    storage_type         = "Azure Files Premium"
    storage_redundancy   = var.storage_account_replication_type
    load_balancer_type   = "Application Gateway v2"
    availability_zones   = join(", ", var.app_gateway_zones)
    auto_scaling_enabled = "Yes"
    monitoring_enabled   = var.enable_monitoring ? "Yes" : "No"
    backup_enabled       = var.enable_backup ? "Yes" : "No"
  }
}