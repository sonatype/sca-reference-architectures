# =============================================================================
# Inputs chained from ../infra-aws-ha (via `terraform output`)
# =============================================================================
# None of these have defaults — they should come from the base folder's own
# outputs so this overlay always targets the environment it was actually
# built for. See README.md for the exact commands.

variable "aws_region" {
  description = "AWS region the base infra-aws-ha environment was deployed in. Must match its aws_region."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID to attach the CloudConnexa VPN network to. From infra-aws-ha's vpc_id output."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block of that VPC. From infra-aws-ha's vpc_cidr_block output."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs the CloudConnexa connector instances are placed in. From infra-aws-ha's public_subnets output."
  type        = list(string)
}

variable "private_route_table_ids" {
  description = "Map of private route table IDs (one per AZ) so VPN return routes reach every AZ's private subnet, where the ALB, ECS tasks, and EFS mount targets live. From infra-aws-ha's private_route_table_ids output."
  type        = map(string)
}

variable "alb_dns_name" {
  description = "DNS name of the (now-internal) IQ Server ALB to route VPN traffic to. From infra-aws-ha's alb_dns_name output. Used as the default cloudconnexa_application_domain when that variable is left unset."
  type        = string
}

variable "ssl_enabled" {
  description = "Whether infra-aws-ha's ssl_certificate_arn is set (i.e. the ALB terminates HTTPS with a real certificate). When true, cloudconnexa_application_domain must also be set, since the ALB's raw *.elb.amazonaws.com DNS name will never match a real certificate and VPN clients browsing to it over HTTPS would hit a TLS name mismatch."
  type        = bool
  default     = false
}

# =============================================================================
# CloudConnexa configuration
# =============================================================================
# See README.md — this overlay is Sonatype-internal-only. These variables
# have no meaning outside a Sonatype CloudConnexa tenant with access to
# Sonatype's private Terraform Cloud module registry.

variable "cloudconnexa_base_url" {
  description = "CloudConnexa API base URL that the cloudconnexa provider authenticates CLOUDCONNEXA_CLIENT_ID/CLOUDCONNEXA_CLIENT_SECRET against. Restricted to real CloudConnexa API hosts so a typo'd or malicious value here can't exfiltrate those credentials to an arbitrary endpoint."
  type        = string
  default     = "https://sonatype.api.openvpn.com"

  validation {
    condition     = can(regex("^https://[a-z0-9-]+\\.api\\.openvpn\\.com$", var.cloudconnexa_base_url))
    error_message = "cloudconnexa_base_url must be an OpenVPN CloudConnexa API endpoint (https://<tenant>.api.openvpn.com)."
  }
}

variable "cloudconnexa_connector_count" {
  description = "Number of CloudConnexa VPN connector instances. Must be >= 1 (>= 2 recommended for connector redundancy, consistent with infra-aws-ha's HA design) — 0 would create the CloudConnexa network with no connector instances, so VPN clients could connect but have no path to the ALB."
  type        = number
  default     = 2

  validation {
    condition     = var.cloudconnexa_connector_count >= 1
    error_message = "cloudconnexa_connector_count must be >= 1 (>= 2 recommended for HA)."
  }
}

variable "cloudconnexa_connector_version" {
  description = "Change this value to trigger recreation of CloudConnexa connector instances (e.g., to apply user_data changes)."
  type        = string
  default     = "1"
}

variable "cloudconnexa_segment" {
  description = "CloudConnexa network segment tag (mirrors the 'segment' input on terraform-sca-cloud's cloudconnexa-network module invocation)."
  type        = string
  default     = "iq-server"
}

variable "cloudconnexa_product" {
  description = "CloudConnexa network product tag (mirrors the 'product' input on terraform-sca-cloud's cloudconnexa-network module invocation)."
  type        = string
  default     = "iq-server-ha"
}

variable "cloudconnexa_owner" {
  description = "Owner (team or email) for CloudConnexa network ownership tagging. Required with no default, since the cloudconnexa-network module needs a real, non-empty value — leaving it empty fails at apply with a confusing module-internal error rather than failing fast here."
  type        = string
}

variable "cloudconnexa_application_domain" {
  description = "Domain name CloudConnexa VPN clients use to reach the IQ Server ALB, via CloudConnexa's domain-based routing. Defaults to null, which falls back to var.alb_dns_name (the ALB's own AWS-generated DNS name). Override with a custom Route53 record aliased to the internal ALB for a friendlier URL, and to keep TLS working — see the ssl_enabled validation below."
  type        = string
  default     = null

  validation {
    condition     = !var.ssl_enabled || var.cloudconnexa_application_domain != null
    error_message = "cloudconnexa_application_domain must be set when ssl_enabled = true — the raw ALB DNS name cannot match any real TLS certificate."
  }
}

variable "cluster_name" {
  description = "Name used for CloudConnexa network naming/tagging. Should match infra-aws-ha's cluster_name for that environment."
  type        = string
  default     = "ref-arch-iq-ha-cluster"
}

variable "common_tags" {
  description = "Common tags to apply to CloudConnexa-related resources. Should match infra-aws-ha's common_tags for that environment."
  type        = map(string)
  default = {
    Project     = "nexus-iq-server-ha"
    Environment = "production"
    Terraform   = "true"
  }
}
