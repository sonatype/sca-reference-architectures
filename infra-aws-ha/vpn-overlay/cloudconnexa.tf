# =============================================================================
# CloudConnexa VPN wiring
# =============================================================================
# Stands up a Sonatype CloudConnexa VPN network attached to the VPC named by
# var.vpc_id, and a CloudConnexa "network application" that routes VPN client
# traffic to the (already-internal, per ../infra-aws-ha's vpn_only = true)
# IQ Server ALB.
#
# Sonatype-internal-only — see README.md. This mirrors the pattern used by
# sonatype/terraform-sca-cloud's control_plane_cloudconnexa_network /
# control_plane_cloudconnexa_application module invocations, adapted to take
# its VPC/subnet/route-table/ALB inputs from ../infra-aws-ha's outputs instead
# of a shared VPC module.
#
# Prerequisites:
#   - CLOUDCONNEXA_CLIENT_ID and CLOUDCONNEXA_CLIENT_SECRET environment
#     variables set, so the OpenVPN/cloudconnexa provider can authenticate to
#     the CloudConnexa API.
#   - Access to Sonatype's private Terraform Cloud module registry
#     (app.terraform.io/Sonatype-Cloud/...) — these two modules are not on
#     the public Terraform Registry.
#
# No #checkov:skip comments are used here: checkov findings on the connector
# EC2 instances/security groups fire on resources *inside* these child
# modules, and inline skip comments at the module-invocation site don't cross
# that module boundary. Real suppression (if needed) requires a checkov
# baseline/config scoped to the external module itself, not a code comment
# here.
# =============================================================================

module "cloudconnexa_network" {
  source  = "app.terraform.io/Sonatype-Cloud/cloudconnexa-network/aws"
  version = "2.0.0"

  segment     = var.cloudconnexa_segment
  product     = var.cloudconnexa_product
  owner       = var.cloudconnexa_owner
  environment = lookup(var.common_tags, "Environment", "production")
  description = "CloudConnexa VPN network for ${var.cluster_name} (VPN-only access, no public internet path)"
  name        = var.cluster_name
  aws_region  = var.aws_region

  vpc_id   = var.vpc_id
  vpc_cidr = var.vpc_cidr

  public_subnet_ids = var.public_subnet_ids

  private_route_table_ids = var.private_route_table_ids

  connector_count   = var.cloudconnexa_connector_count
  connector_version = var.cloudconnexa_connector_version
}

module "cloudconnexa_application" {
  source  = "app.terraform.io/Sonatype-Cloud/cloudconnexa-network-application/cloudconnexa"
  version = "1.0.0"

  name        = "${var.cluster_name}-iq"
  description = "Route VPN traffic to the Nexus IQ Server ALB (VPN-only access)"
  network_id  = module.cloudconnexa_network.network_id
  domains     = [coalesce(var.cloudconnexa_application_domain, var.alb_dns_name)]
}
