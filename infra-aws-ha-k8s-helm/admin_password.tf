output "iq_admin_initial_password" {
  description = "The initial admin password IQ Server was given, read by iq-post-deploy.sh"
  value       = var.iq_admin_initial_password
  sensitive   = true
}
