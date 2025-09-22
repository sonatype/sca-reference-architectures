# Network Outputs
output "vpc_id" {
  description = "ID of the VPC network"
  value       = google_compute_network.iq_vpc.id
}

output "vpc_name" {
  description = "Name of the VPC network"
  value       = google_compute_network.iq_vpc.name
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = google_compute_subnetwork.public_subnet.id
}

output "private_subnet_id" {
  description = "ID of the private subnet"
  value       = google_compute_subnetwork.private_subnet.id
}

output "db_subnet_id" {
  description = "ID of the database subnet"
  value       = google_compute_subnetwork.db_subnet.id
}

# Cloud Run Outputs
output "iq_service_url" {
  description = "URL of the Nexus IQ Cloud Run service"
  value       = google_cloud_run_service.iq_service.status[0].url
}

output "iq_service_name" {
  description = "Name of the Nexus IQ Cloud Run service"
  value       = google_cloud_run_service.iq_service.name
}

output "iq_ha_service_url" {
  description = "URL of the Nexus IQ HA Cloud Run service"
  value       = var.enable_ha ? google_cloud_run_service.iq_ha_service[0].status[0].url : null
}

output "iq_ha_service_name" {
  description = "Name of the Nexus IQ HA Cloud Run service"
  value       = var.enable_ha ? google_cloud_run_service.iq_ha_service[0].name : null
}

# Load Balancer Outputs
output "load_balancer_ip" {
  description = "External IP address of the load balancer"
  value       = google_compute_global_address.iq_lb_ip.address
}

output "load_balancer_name" {
  description = "Name of the load balancer"
  value       = google_compute_url_map.iq_url_map.name
}

output "load_balancer_ha_ip" {
  description = "External IP address of the HA load balancer"
  value       = var.enable_ha ? google_compute_global_address.iq_ha_lb_ip[0].address : null
}

output "nexus_iq_url" {
  description = "Public URL to access Nexus IQ Server"
  value = var.domain_name != "" ? (var.enable_ssl ? "https://${var.domain_name}" : "http://${var.domain_name}") : (var.enable_ssl ? "https://${google_compute_global_address.iq_lb_ip.address}" : "http://${google_compute_global_address.iq_lb_ip.address}")
}

output "nexus_iq_ha_url" {
  description = "Public URL to access Nexus IQ HA Server"
  value = var.enable_ha ? (var.domain_name_ha != "" ? (var.enable_ssl ? "https://${var.domain_name_ha}" : "http://${var.domain_name_ha}") : (var.enable_ssl ? "https://${google_compute_global_address.iq_ha_lb_ip[0].address}" : "http://${google_compute_global_address.iq_ha_lb_ip[0].address}")) : null
}

# Database Outputs
output "database_instance_name" {
  description = "Name of the Cloud SQL instance"
  value       = google_sql_database_instance.iq_db.name
}

output "database_connection_name" {
  description = "Connection name of the Cloud SQL instance"
  value       = google_sql_database_instance.iq_db.connection_name
}

output "database_private_ip" {
  description = "Private IP address of the database"
  value       = google_sql_database_instance.iq_db.private_ip_address
  sensitive   = true
}

output "database_ha_instance_name" {
  description = "Name of the Cloud SQL HA instance"
  value       = var.enable_ha ? google_sql_database_instance.iq_ha_db[0].name : null
}

output "database_ha_connection_name" {
  description = "Connection name of the Cloud SQL HA instance"
  value       = var.enable_ha ? google_sql_database_instance.iq_ha_db[0].connection_name : null
}

output "database_ha_private_ip" {
  description = "Private IP address of the HA database"
  value       = var.enable_ha ? google_sql_database_instance.iq_ha_db[0].private_ip_address : null
  sensitive   = true
}

output "database_read_replica_name" {
  description = "Name of the read replica instance"
  value       = var.enable_read_replica ? google_sql_database_instance.iq_read_replica[0].name : null
}

# Storage Outputs
output "filestore_instance_name" {
  description = "Name of the Filestore instance"
  value       = google_filestore_instance.iq_filestore.name
}

output "filestore_ip_address" {
  description = "IP address of the Filestore instance"
  value       = google_filestore_instance.iq_filestore.networks[0].ip_addresses[0]
}

output "filestore_ha_instance_name" {
  description = "Name of the Filestore HA instance"
  value       = var.enable_ha ? google_filestore_instance.iq_ha_filestore[0].name : null
}

output "filestore_ha_ip_address" {
  description = "IP address of the Filestore HA instance"
  value       = var.enable_ha ? google_filestore_instance.iq_ha_filestore[0].networks[0].ip_addresses[0] : null
}

output "backup_bucket_name" {
  description = "Name of the backup storage bucket"
  value       = google_storage_bucket.iq_backups.name
}

output "logs_bucket_name" {
  description = "Name of the logs storage bucket"
  value       = google_storage_bucket.iq_logs.name
}

output "lb_logs_bucket_name" {
  description = "Name of the load balancer logs storage bucket"
  value       = google_storage_bucket.lb_logs.name
}

output "config_backup_bucket_name" {
  description = "Name of the configuration backup storage bucket"
  value       = google_storage_bucket.iq_config_backup.name
}

output "terraform_state_bucket_name" {
  description = "Name of the Terraform state storage bucket"
  value       = var.create_terraform_state_bucket ? google_storage_bucket.terraform_state[0].name : null
}

# Security Outputs
output "kms_key_ring_name" {
  description = "Name of the KMS key ring"
  value       = google_kms_key_ring.iq_keyring.name
}

output "storage_kms_key_name" {
  description = "Name of the storage KMS key"
  value       = google_kms_crypto_key.iq_storage_key.name
}

output "database_kms_key_name" {
  description = "Name of the database KMS key"
  value       = google_kms_crypto_key.iq_database_key.name
}

output "cloud_armor_policy_name" {
  description = "Name of the Cloud Armor security policy"
  value       = var.enable_cloud_armor ? google_compute_security_policy.iq_security_policy[0].name : null
}

# IAM Outputs
output "iq_service_account_email" {
  description = "Email of the Nexus IQ service account"
  value       = google_service_account.iq_service.email
}

output "load_balancer_service_account_email" {
  description = "Email of the load balancer service account"
  value       = google_service_account.iq_load_balancer.email
}

output "sql_proxy_service_account_email" {
  description = "Email of the SQL proxy service account"
  value       = google_service_account.iq_sql_proxy.email
}

output "monitoring_service_account_email" {
  description = "Email of the monitoring service account"
  value       = google_service_account.iq_monitoring.email
}

# Secret Manager Outputs
output "db_credentials_secret_name" {
  description = "Name of the database credentials secret"
  value       = google_secret_manager_secret.db_credentials.secret_id
}

output "db_ha_credentials_secret_name" {
  description = "Name of the database HA credentials secret"
  value       = var.enable_ha ? google_secret_manager_secret.db_ha_credentials[0].secret_id : null
}

output "service_account_key_secret_name" {
  description = "Name of the service account key secret"
  value       = var.create_service_account_keys ? google_secret_manager_secret.iq_service_key[0].secret_id : null
}

# Monitoring Outputs
output "monitoring_dashboard_url" {
  description = "URL of the Cloud Monitoring dashboard"
  value       = "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.iq_dashboard.id}?project=${var.gcp_project_id}"
}

output "uptime_check_name" {
  description = "Name of the uptime check"
  value       = google_monitoring_uptime_check_config.iq_uptime_check.display_name
}

output "alert_policy_names" {
  description = "Names of the monitoring alert policies"
  value = var.enable_monitoring_alerts ? [
    google_monitoring_alert_policy.high_cpu_alert.display_name,
    google_monitoring_alert_policy.high_memory_alert.display_name,
    google_monitoring_alert_policy.high_error_rate_alert.display_name,
    google_monitoring_alert_policy.database_connection_alert.display_name,
    google_monitoring_alert_policy.uptime_check_alert.display_name
  ] : []
}

# SSL Certificate Outputs
output "ssl_certificate_name" {
  description = "Name of the SSL certificate"
  value       = var.enable_ssl && var.domain_name != "" ? google_compute_managed_ssl_certificate.iq_ssl_cert[0].name : null
}

output "ssl_certificate_ha_name" {
  description = "Name of the SSL certificate for HA"
  value       = var.enable_ha && var.enable_ssl && var.domain_name_ha != "" ? google_compute_managed_ssl_certificate.iq_ha_ssl_cert[0].name : null
}

# Domain Mapping Outputs
output "cloud_run_domain_mapping" {
  description = "Cloud Run domain mapping name"
  value       = var.custom_domain != "" ? google_cloud_run_domain_mapping.iq_domain[0].name : null
}

output "cloud_run_ha_domain_mapping" {
  description = "Cloud Run HA domain mapping name"
  value       = var.enable_ha && var.custom_domain_ha != "" ? google_cloud_run_domain_mapping.iq_ha_domain[0].name : null
}

# Project Information Outputs
output "project_id" {
  description = "GCP Project ID"
  value       = var.gcp_project_id
}

output "project_number" {
  description = "GCP Project Number"
  value       = data.google_project.current.number
}

output "region" {
  description = "GCP Region"
  value       = var.gcp_region
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

# Resource Identifiers for Automation
output "all_resource_ids" {
  description = "Map of all major resource IDs for automation scripts"
  value = {
    vpc                    = google_compute_network.iq_vpc.id
    public_subnet         = google_compute_subnetwork.public_subnet.id
    private_subnet        = google_compute_subnetwork.private_subnet.id
    db_subnet            = google_compute_subnetwork.db_subnet.id
    iq_service           = google_cloud_run_service.iq_service.name
    iq_ha_service        = var.enable_ha ? google_cloud_run_service.iq_ha_service[0].name : null
    database             = google_sql_database_instance.iq_db.name
    database_ha          = var.enable_ha ? google_sql_database_instance.iq_ha_db[0].name : null
    filestore            = google_filestore_instance.iq_filestore.name
    filestore_ha         = var.enable_ha ? google_filestore_instance.iq_ha_filestore[0].name : null
    load_balancer_ip     = google_compute_global_address.iq_lb_ip.address
    load_balancer_ha_ip  = var.enable_ha ? google_compute_global_address.iq_ha_lb_ip[0].address : null
    backup_bucket        = google_storage_bucket.iq_backups.name
    logs_bucket          = google_storage_bucket.iq_logs.name
    kms_keyring          = google_kms_key_ring.iq_keyring.id
  }
}

# Connection Information for Applications
output "connection_info" {
  description = "Connection information for external applications"
  value = {
    nexus_iq_url         = var.domain_name != "" ? (var.enable_ssl ? "https://${var.domain_name}" : "http://${var.domain_name}") : (var.enable_ssl ? "https://${google_compute_global_address.iq_lb_ip.address}" : "http://${google_compute_global_address.iq_lb_ip.address}")
    nexus_iq_ha_url      = var.enable_ha ? (var.domain_name_ha != "" ? (var.enable_ssl ? "https://${var.domain_name_ha}" : "http://${var.domain_name_ha}") : (var.enable_ssl ? "https://${google_compute_global_address.iq_ha_lb_ip[0].address}" : "http://${google_compute_global_address.iq_ha_lb_ip[0].address}")) : null
    database_host        = google_sql_database_instance.iq_db.private_ip_address
    database_name        = var.db_name
    database_port        = 5432
    filestore_ip         = google_filestore_instance.iq_filestore.networks[0].ip_addresses[0]
    filestore_path       = "/nexus_iq_data"
  }
  sensitive = true
}

# Deployment Information
output "deployment_info" {
  description = "Deployment information for reference"
  value = {
    terraform_version    = ">=1.0"
    gcp_provider_version = "~>5.0"
    deployment_date      = timestamp()
    configuration_mode   = var.enable_ha ? "High Availability" : "Single Instance"
    ssl_enabled          = var.enable_ssl
    cloud_armor_enabled  = var.enable_cloud_armor
    monitoring_enabled   = var.enable_monitoring_alerts
  }
}