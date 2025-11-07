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
  value       = google_compute_subnetwork.iq_private_subnet.id
}

output "db_subnet_id" {
  description = "ID of the database subnet"
  value       = google_compute_subnetwork.db_subnet.id
}

# GCE Outputs
output "instance_name" {
  description = "Name of the Nexus IQ Server instance"
  value       = google_compute_instance.iq_server.name
}

output "instance_group_name" {
  description = "Name of the instance group"
  value       = google_compute_instance_group.iq_group.name
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

output "nexus_iq_url" {
  description = "Public URL to access Nexus IQ Server"
  value       = var.domain_name != "" ? (var.enable_ssl ? "https://${var.domain_name}" : "http://${var.domain_name}") : (var.enable_ssl ? "https://${google_compute_global_address.iq_lb_ip.address}" : "http://${google_compute_global_address.iq_lb_ip.address}")
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

# Storage Outputs
output "filestore_instance_name" {
  description = "Name of the Filestore instance"
  value       = google_filestore_instance.iq_filestore.name
}

output "filestore_ip_address" {
  description = "IP address of the Filestore instance"
  value       = google_filestore_instance.iq_filestore.networks[0].ip_addresses[0]
}

# IAM Outputs
output "iq_service_account_email" {
  description = "Email of the Nexus IQ service account"
  value       = google_service_account.iq_service.email
}

# Secret Manager Outputs
output "db_credentials_secret_name" {
  description = "Name of the database credentials secret"
  value       = google_secret_manager_secret.db_credentials.secret_id
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

# SSL Certificate Outputs
output "ssl_certificate_name" {
  description = "Name of the SSL certificate"
  value       = var.enable_ssl && var.domain_name != "" ? google_compute_managed_ssl_certificate.iq_ssl_cert[0].name : null
}

