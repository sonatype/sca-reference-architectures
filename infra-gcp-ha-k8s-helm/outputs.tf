output "gke_cluster_name" {
  description = "GKE cluster name"
  value       = google_container_cluster.iq_gke.name
}

output "gke_cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = google_container_cluster.iq_gke.endpoint
  sensitive   = true
}

output "gke_cluster_ca_certificate" {
  description = "GKE cluster CA certificate"
  value       = google_container_cluster.iq_gke.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "gke_cluster_location" {
  description = "GKE cluster location"
  value       = google_container_cluster.iq_gke.location
}

output "database_connection_name" {
  description = "Cloud SQL database connection name"
  value       = google_sql_database_instance.iq_ha_db.connection_name
}

output "database_private_ip" {
  description = "Cloud SQL database private IP address"
  value       = google_sql_database_instance.iq_ha_db.private_ip_address
}

output "database_name" {
  description = "Database name"
  value       = google_sql_database.iq_ha_database.name
}

output "database_username" {
  description = "Database username"
  value       = var.db_username
}

output "database_password" {
  description = "Database password"
  value       = var.db_password
  sensitive   = true
}

output "filestore_ip" {
  description = "Filestore IP address"
  value       = google_filestore_instance.iq_ha_filestore.networks[0].ip_addresses[0]
}

output "filestore_share_name" {
  description = "Filestore share name"
  value       = google_filestore_instance.iq_ha_filestore.file_shares[0].name
}

output "ingress_ip" {
  description = "Global ingress IP address"
  value       = google_compute_global_address.ingress_ip.address
}

output "ingress_ip_name" {
  description = "Global ingress IP address name"
  value       = google_compute_global_address.ingress_ip.name
}

output "workload_identity_email" {
  description = "Workload Identity service account email"
  value       = google_service_account.gke_workload_identity.email
}

output "fluentd_workload_identity_email" {
  description = "Fluentd Workload Identity service account email"
  value       = google_service_account.fluentd_workload_identity.email
}

output "log_bucket_id" {
  description = "Cloud Logging bucket ID"
  value       = google_logging_project_bucket_config.nexus_iq_logs.bucket_id
}

output "kubectl_config_command" {
  description = "Command to configure kubectl"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.iq_gke.name} --region ${var.gcp_region} --project ${var.gcp_project_id}"
}

output "helm_install_command" {
  description = "Command to install Nexus IQ Server with Helm"
  value       = "./helm-install.sh"
}

output "vpc_name" {
  description = "VPC network name"
  value       = google_compute_network.iq_vpc.name
}

output "vpc_id" {
  description = "VPC network ID"
  value       = google_compute_network.iq_vpc.id
}

output "region" {
  description = "GCP region"
  value       = var.gcp_region
}

output "project_id" {
  description = "GCP project ID"
  value       = var.gcp_project_id
}
