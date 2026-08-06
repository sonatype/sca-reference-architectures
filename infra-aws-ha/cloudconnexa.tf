# =============================================================================
# CloudConnexa VPN wiring (only created when var.vpn_only = true)
#
# This is the mechanism that makes the environment VPN-only: it stands up a
# Sonatype CloudConnexa VPN network attached to this VPC, and a CloudConnexa
# "network application" that routes VPN client traffic to the (now-internal)
# IQ Server ALB. When var.vpn_only = true there is no other network path into
# this environment — the ALB has no public IP (see load_balancer.tf) and its
# security group only accepts traffic from var.cloudconnexa_client_cidr_blocks
# (see security_groups.tf).
#
# This mirrors the exact pattern used by sonatype/terraform-sca-cloud in
# src/infrastructure/aws/global/main.tf (control_plane_cloudconnexa_network /
# control_plane_cloudconnexa_application module invocations, ~lines 139-177):
#   - terraform-sca-cloud passes public_subnet_ids from its shared VPC module
#     and a single private_route_table_id; here we pass this folder's own
#     public subnets and the full set of per-AZ private route tables from
#     main.tf.
#   - terraform-sca-cloud routes VPN traffic to its control plane ALB via a
#     custom Route53 domain (local.control_plane_domain_name). This folder
#     has no Route53 zone of its own, so it defaults to routing via the ALB's
#     own AWS-generated DNS name instead (override with
#     var.cloudconnexa_application_domain if you wire up a custom domain).
#
# Prerequisites when var.vpn_only = true (same as terraform-sca-cloud):
#   - CLOUDCONNEXA_CLIENT_ID and CLOUDCONNEXA_CLIENT_SECRET environment
#     variables set, so the OpenVPN/cloudconnexa provider can authenticate to
#     the CloudConnexa API.
#   - Access to Sonatype's private Terraform Cloud module registry
#     (app.terraform.io/Sonatype-Cloud/...) — these two modules are not on
#     the public Terraform Registry.
# =============================================================================

# required_providers for "cloudconnexa" (source = OpenVPN/cloudconnexa) is
# declared in main.tf's terraform block, since a module may only have one.
provider "cloudconnexa" {
  base_url = var.cloudconnexa_base_url
}

#checkov:skip=CKV_AWS_382:VPN connector requires broad egress to reach CloudConnexa service and AWS endpoints
#checkov:skip=CKV_AWS_126:CloudConnexa connector requires public IP to establish VPN tunnels with cloud service
#checkov:skip=CKV_AWS_88:CloudConnexa connector requires public IP to establish VPN tunnels with cloud service
module "cloudconnexa_network" {
  count   = var.vpn_only ? 1 : 0
  source  = "app.terraform.io/Sonatype-Cloud/cloudconnexa-network/aws"
  version = "2.0.0"

  segment     = var.cloudconnexa_segment
  product     = var.cloudconnexa_product
  owner       = var.cloudconnexa_owner
  environment = lookup(var.common_tags, "Environment", "production")
  description = "CloudConnexa VPN network for ${var.cluster_name} (VPN-only access, no public internet path)"
  name        = var.cluster_name
  aws_region  = var.aws_region

  vpc_id   = aws_vpc.iq_vpc.id
  vpc_cidr = aws_vpc.iq_vpc.cidr_block

  public_subnet_ids = aws_subnet.public_subnets[*].id

  # One entry per private route table so VPN return routes reach every AZ's
  # private subnet (where the ALB, ECS tasks, and EFS mount targets live).
  private_route_table_ids = {
    for idx, rt in aws_route_table.private_rt : "private-${idx}" => rt.id
  }

  connector_count   = var.cloudconnexa_connector_count
  connector_version = var.cloudconnexa_connector_version
}

module "cloudconnexa_application" {
  count   = var.vpn_only ? 1 : 0
  source  = "app.terraform.io/Sonatype-Cloud/cloudconnexa-network-application/cloudconnexa"
  version = "1.0.0"

  name        = "${var.cluster_name}-iq"
  description = "Route VPN traffic to the Nexus IQ Server ALB (VPN-only access)"
  network_id  = module.cloudconnexa_network[0].network_id
  domains     = [coalesce(var.cloudconnexa_application_domain, aws_lb.iq_alb.dns_name)]
}
