
locals {
  # Variable defaults can't reference resources, so cloudconnexa_client_cidr_blocks
  # defaults to an empty list and falls back to the VPC's *actual* CIDR here. This
  # keeps the effective default correct even if var.vpc_cidr is overridden, instead
  # of silently drifting the way a hardcoded literal default would.
  effective_cloudconnexa_client_cidr_blocks = length(var.cloudconnexa_client_cidr_blocks) > 0 ? var.cloudconnexa_client_cidr_blocks : [aws_vpc.iq_vpc.cidr_block]

  # enable_vpc_flow_logs defaults to null so it can track vpn_only (flow logs are
  # most valuable once this environment is VPN-only, since they become the primary
  # way to reconstruct which VPN client reached which backend) while still being
  # toggleable independently of vpn_only when explicitly set.
  enable_vpc_flow_logs = var.enable_vpc_flow_logs == null ? var.vpn_only : var.enable_vpc_flow_logs
}
