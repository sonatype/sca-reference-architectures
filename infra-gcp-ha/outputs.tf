# Load Balancer outputs
output "load_balancer_ip" {
  description = "External IP address of the load balancer"
  value       = google_compute_global_address.iq_ha_lb_ip.address
}

output "load_balancer_url" {
  description = "URL to access Nexus IQ Server via load balancer"
  value       = var.enable_ssl ? "https://${var.domain_name != "" ? var.domain_name : google_compute_global_address.iq_ha_lb_ip.address}" : "http://${google_compute_global_address.iq_ha_lb_ip.address}"
}

output "load_balancer_admin_url" {
  description = "Admin URL for Nexus IQ Server (access via SSH tunnel)"
  value       = var.enable_ssl ? "https://${var.domain_name != "" ? var.domain_name : google_compute_global_address.iq_ha_lb_ip.address}:8071" : "http://${google_compute_global_address.iq_ha_lb_ip.address}:8071"
}

# Database outputs
output "database_connection_name" {
  description = "Cloud SQL instance connection name"
  value       = google_sql_database_instance.iq_ha_db.connection_name
}

output "database_private_ip" {
  description = "Private IP address of the database"
  value       = google_sql_database_instance.iq_ha_db.private_ip_address
  sensitive   = true
}

output "database_name" {
  description = "Name of the database"
  value       = google_sql_database.iq_ha_database.name
}

output "database_replica_connection_name" {
  description = "Cloud SQL read replica connection name (if enabled)"
  value       = var.enable_read_replica ? google_sql_database_instance.iq_ha_db_replica[0].connection_name : null
}

# Compute Engine outputs
output "instance_group_manager_id" {
  description = "ID of the regional instance group manager"
  value       = google_compute_region_instance_group_manager.iq_mig.id
}

output "instance_group_manager_name" {
  description = "Name of the regional instance group manager"
  value       = google_compute_region_instance_group_manager.iq_mig.name
}

output "instance_template_id" {
  description = "ID of the instance template"
  value       = google_compute_instance_template.iq_template.id
}

# Network outputs
output "vpc_id" {
  description = "ID of the VPC network"
  value       = google_compute_network.iq_ha_vpc.id
}

output "vpc_name" {
  description = "Name of the VPC network"
  value       = google_compute_network.iq_ha_vpc.name
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = google_compute_subnetwork.private_subnets[*].id
}

output "private_subnet_names" {
  description = "Names of the private subnets"
  value       = google_compute_subnetwork.private_subnets[*].name
}

# Storage outputs  
output "filestore_ip" {
  description = "IP address of the Cloud Filestore instance"
  value       = google_filestore_instance.iq_ha_filestore.networks[0].ip_addresses[0]
}

output "filestore_name" {
  description = "Name of the Cloud Filestore instance"
  value       = google_filestore_instance.iq_ha_filestore.name
}

output "nfs_mount_point" {
  description = "NFS mount path for applications"
  value       = "${google_filestore_instance.iq_ha_filestore.networks[0].ip_addresses[0]}:/nexus_iq_ha_data"
}

# Service Account outputs
output "compute_service_account_email" {
  description = "Email of the compute service account"
  value       = google_service_account.iq_compute_service.email
}

output "load_balancer_service_account_email" {
  description = "Email of the load balancer service account"
  value       = google_service_account.iq_load_balancer.email
}

# Secret Manager outputs
output "db_credentials_secret_id" {
  description = "ID of the database credentials secret"
  value       = google_secret_manager_secret.db_credentials.secret_id
  sensitive   = true
}

output "db_password_secret_id" {
  description = "ID of the database password secret"
  value       = google_secret_manager_secret.db_password.secret_id
  sensitive   = true
}

# Health Check outputs
output "health_check_id" {
  description = "ID of the health check for auto healing"
  value       = google_compute_health_check.iq_health_check.id
}

output "lb_health_check_id" {
  description = "ID of the load balancer health check"
  value       = google_compute_health_check.iq_lb_health_check.id
}

# Auto Scaling outputs
output "autoscaler_id" {
  description = "ID of the regional autoscaler"
  value       = google_compute_region_autoscaler.iq_autoscaler.id
}

output "min_instances" {
  description = "Minimum number of instances"
  value       = var.iq_min_instances
}

output "max_instances" {
  description = "Maximum number of instances"
  value       = var.iq_max_instances
}

output "target_instances" {
  description = "Target number of instances"
  value       = var.iq_target_instances
}

# SSL Certificate outputs (if enabled)
output "ssl_certificate_id" {
  description = "ID of the managed SSL certificate (if enabled)"
  value       = var.enable_ssl && var.domain_name != "" ? google_compute_managed_ssl_certificate.iq_ha_ssl_cert[0].id : null
}

output "ssl_certificate_status" {
  description = "Status of the managed SSL certificate (if enabled)"
  value       = var.enable_ssl && var.domain_name != "" ? google_compute_managed_ssl_certificate.iq_ha_ssl_cert[0].certificate_id : null
}

# Monitoring outputs
output "monitoring_dashboard_id" {
  description = "ID of the monitoring dashboard"
  value       = google_monitoring_dashboard.iq_ha_dashboard.id
}

output "uptime_check_id" {
  description = "ID of the uptime check"
  value       = google_monitoring_uptime_check_config.iq_ha_uptime_check.name
}

# Region and Zone information
output "deployment_region" {
  description = "GCP region where resources are deployed"
  value       = var.gcp_region
}

output "availability_zones" {
  description = "Availability zones used for deployment"
  value       = var.availability_zones
}

# Project information
output "project_id" {
  description = "GCP project ID"
  value       = var.gcp_project_id
}

# Summary information
output "deployment_summary" {
  description = "Summary of the HA deployment"
  value = {
    load_balancer_url    = var.enable_ssl ? "https://${var.domain_name != "" ? var.domain_name : google_compute_global_address.iq_ha_lb_ip.address}" : "http://${google_compute_global_address.iq_ha_lb_ip.address}"
    min_instances        = var.iq_min_instances
    max_instances        = var.iq_max_instances
    database_type        = "PostgreSQL ${var.postgres_version}"
    database_ha          = var.db_availability_type
    ssl_enabled          = var.enable_ssl
    monitoring_enabled   = true
    auto_scaling_enabled = true
    backup_enabled       = true
  }
}