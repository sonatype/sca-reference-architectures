output "cloudconnexa_network_id" {
  description = "CloudConnexa VPN network ID."
  value       = module.cloudconnexa_network.network_id
}

output "cloudconnexa_network_name" {
  description = "CloudConnexa VPN network name."
  value       = module.cloudconnexa_network.network_name
}

output "cloudconnexa_connector_security_group_id" {
  description = "Security group ID of the CloudConnexa connector instances."
  value       = module.cloudconnexa_network.connector_security_group_id
}

output "cloudconnexa_application_domain" {
  description = "Domain name routed to the IQ Server ALB via CloudConnexa's domain-based VPN routing."
  value       = coalesce(var.cloudconnexa_application_domain, var.alb_dns_name)
}

# Connector public IPs (needed for firewall/IdP/SIEM allowlisting) are
# deliberately NOT exposed here. Whether module.cloudconnexa_network exposes
# them at all is unconfirmed without access to the private Terraform Cloud
# registry this module is sourced from — adding a speculative output name
# that doesn't actually exist on the module would silently break
# `terraform plan`. Add this once someone with registry access has confirmed
# the module's actual output schema.
