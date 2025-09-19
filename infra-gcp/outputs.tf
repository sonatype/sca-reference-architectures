# Network Outputs
output "vpc_network_name" {
  description = "Name of the VPC network"
  value       = google_compute_network.iq_vpc.name
}

output "vpc_network_id" {
  description = "ID of the VPC network"
  value       = google_compute_network.iq_vpc.id
}

output "public_subnet_name" {
  description = "Name of the public subnet"
  value       = google_compute_subnetwork.public_subnet.name
}

output "private_subnet_name" {
  description = "Name of the private subnet"
  value       = google_compute_subnetwork.private_subnet.name
}

output "db_subnet_name" {
  description = "Name of the database subnet"
  value       = google_compute_subnetwork.db_subnet.name
}

output "vpc_connector_name" {
  description = "Name of the VPC connector"
  value       = google_vpc_access_connector.iq_connector.name
}

# Cloud Run Outputs
output "cloud_run_service_name" {
  description = "Name of the Cloud Run service"
  value       = google_cloud_run_v2_service.iq_service.name
}

output "cloud_run_service_url" {
  description = "URL of the Cloud Run service"
  value       = google_cloud_run_v2_service.iq_service.uri
}

output "cloud_run_service_id" {
  description = "ID of the Cloud Run service"
  value       = google_cloud_run_v2_service.iq_service.id
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

output "application_url" {
  description = "URL to access Nexus IQ Server"
  value       = var.ssl_certificate_name != "" ? "https://${var.domain_name != "" ? var.domain_name : google_compute_global_address.iq_lb_ip.address}" : "http://${var.domain_name != "" ? var.domain_name : google_compute_global_address.iq_lb_ip.address}"
}

output "backend_service_name" {
  description = "Name of the backend service"
  value       = google_compute_backend_service.iq_backend_service.name
}

# Database Outputs
output "database_instance_name" {
  description = "Name of the Cloud SQL instance"
  value       = google_sql_database_instance.iq_db.name
}

output "database_instance_connection_name" {
  description = "Connection name of the Cloud SQL instance"
  value       = google_sql_database_instance.iq_db.connection_name
}

output "database_private_ip" {
  description = "Private IP address of the database"
  value       = google_sql_database_instance.iq_db.private_ip_address
  sensitive   = true
}

output "database_name" {
  description = "Name of the database"
  value       = google_sql_database.iq_database.name
}

output "database_replica_name" {
  description = "Name of the database replica (if enabled)"
  value       = var.iq_deployment_mode == "ha" && var.enable_read_replica ? google_sql_database_instance.iq_db_replica[0].name : null
}

# Storage Outputs
output "filestore_instance_name" {
  description = "Name of the Cloud Filestore instance"
  value       = google_filestore_instance.iq_filestore.name
}

output "filestore_ip_address" {
  description = "IP address of the Cloud Filestore instance"
  value       = google_filestore_instance.iq_filestore.networks[0].ip_addresses[0]
}

output "backup_bucket_name" {
  description = "Name of the backup storage bucket"
  value       = google_storage_bucket.iq_backups.name
}

output "logs_bucket_name" {
  description = "Name of the logs storage bucket"
  value       = google_storage_bucket.lb_logs.name
}

# IAM Outputs
output "service_account_email" {
  description = "Email of the Cloud Run service account"
  value       = google_service_account.iq_service_account.email
}

output "service_account_name" {
  description = "Name of the Cloud Run service account"
  value       = google_service_account.iq_service_account.name
}

output "lb_service_account_email" {
  description = "Email of the load balancer service account"
  value       = google_service_account.lb_service_account.email
}

# Secret Manager Outputs
output "db_credentials_secret_name" {
  description = "Name of the database credentials secret"
  value       = google_secret_manager_secret.db_credentials.secret_id
  sensitive   = true
}

output "db_password_secret_name" {
  description = "Name of the database password secret"
  value       = google_secret_manager_secret.db_password.secret_id
  sensitive   = true
}

# Monitoring Outputs
output "monitoring_dashboard_url" {
  description = "URL of the monitoring dashboard"
  value       = "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.iq_dashboard.id}?project=${var.gcp_project_id}"
}

output "log_explorer_url" {
  description = "URL to view logs in Cloud Logging"
  value       = "https://console.cloud.google.com/logs/query;query=resource.type%3D%22cloud_run_revision%22%0Aresource.labels.service_name%3D%22${google_cloud_run_v2_service.iq_service.name}%22?project=${var.gcp_project_id}"
}

output "uptime_check_name" {
  description = "Name of the uptime check"
  value       = google_monitoring_uptime_check_config.iq_uptime_check.display_name
}

# Security Outputs
output "security_policy_name" {
  description = "Name of the Cloud Armor security policy"
  value       = var.enable_cloud_armor ? google_compute_security_policy.iq_security_policy[0].name : null
}

output "firewall_rules" {
  description = "List of firewall rule names"
  value = [
    google_compute_firewall.allow_lb_access.name,
    google_compute_firewall.allow_health_checks.name,
    google_compute_firewall.allow_vpc_connector.name,
    google_compute_firewall.allow_cloudsql_access.name,
    google_compute_firewall.allow_filestore_access.name,
    google_compute_firewall.allow_internal.name
  ]
}

# Deployment Information
output "deployment_mode" {
  description = "Current deployment mode"
  value       = var.iq_deployment_mode
}

output "region" {
  description = "GCP region"
  value       = var.gcp_region
}

output "project_id" {
  description = "GCP project ID"
  value       = var.gcp_project_id
}

# Health Check URLs
output "health_check_urls" {
  description = "Health check URLs"
  value = {
    main_app = "http://${google_compute_global_address.iq_lb_ip.address}/"
    admin    = "http://${google_compute_global_address.iq_lb_ip.address}:8071/healthcheck"
  }
}

# Resource Names for Management
output "resource_names" {
  description = "Key resource names for management and troubleshooting"
  value = {
    vpc_network           = google_compute_network.iq_vpc.name
    cloud_run_service     = google_cloud_run_v2_service.iq_service.name
    database_instance     = google_sql_database_instance.iq_db.name
    filestore_instance    = google_filestore_instance.iq_filestore.name
    load_balancer         = google_compute_url_map.iq_url_map.name
    service_account       = google_service_account.iq_service_account.name
    backup_bucket         = google_storage_bucket.iq_backups.name
  }
}

# Access Information
output "access_information" {
  description = "Information for accessing and managing the deployment"
  value = {
    application_url     = var.ssl_certificate_name != "" ? "https://${var.domain_name != "" ? var.domain_name : google_compute_global_address.iq_lb_ip.address}" : "http://${var.domain_name != "" ? var.domain_name : google_compute_global_address.iq_lb_ip.address}"
    default_credentials = "admin / admin123"
    gcp_console_url     = "https://console.cloud.google.com/run/detail/${var.gcp_region}/${google_cloud_run_v2_service.iq_service.name}/metrics?project=${var.gcp_project_id}"
    monitoring_url      = "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.iq_dashboard.id}?project=${var.gcp_project_id}"
  }
}