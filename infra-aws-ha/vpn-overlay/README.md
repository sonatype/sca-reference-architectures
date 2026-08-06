# VPN Overlay — Sonatype CloudConnexa (Sonatype-internal only)

> **This overlay is Sonatype-internal-only.** It sources two modules from Sonatype's *private* Terraform Cloud module registry (`app.terraform.io/Sonatype-Cloud/...`) and authenticates against a real Sonatype CloudConnexa tenant. External customers copying the [`infra-aws-ha/`](../README.md) reference architecture will get a `401 Unauthorized` on `terraform init`/`plan` and have no CloudConnexa tenant to point at — there is no way to make this overlay usable outside Sonatype today. If you're a customer looking to lock this environment down, use `vpn_only = true` in `infra-aws-ha/` on its own (see its README) and bring your own VPN/bastion solution to reach the now-internal ALB.

## What this is

A second, separate root module that actually wires up Sonatype CloudConnexa VPN access on top of an `infra-aws-ha/` environment that already has `vpn_only = true` applied. It is intentionally **not** invoked from `infra-aws-ha/`'s own root module — see that folder's README for why (in short: Terraform resolves provider configuration statically, so declaring the `cloudconnexa` provider inside `infra-aws-ha/` itself, even behind a `count`-gated module, would require every user of that folder to have CloudConnexa credentials on every plan/apply, VPN or not).

This overlay stands up:
- A CloudConnexa VPN network attached to the base environment's VPC, with connector instances in its public subnets and return routes into every AZ's private route table.
- A CloudConnexa "network application" that routes VPN client traffic to the base environment's (now-internal) ALB.

## Usage

1. Apply `../infra-aws-ha` first, with `vpn_only = true`.
2. Get its outputs and feed them into this overlay's variables. Either generate a `terraform.tfvars` from them directly:

   ```bash
   cd infra-aws-ha
   terraform output -json > ../vpn-overlay/base-outputs.json
   cd ../vpn-overlay
   python3 - <<'PY'
   import json
   o = json.load(open("base-outputs.json"))
   print(f'vpc_id                  = "{o["vpc_id"]["value"]}"')
   print(f'vpc_cidr                = "{o["vpc_cidr_block"]["value"]}"')
   print(f'public_subnet_ids       = {json.dumps(o["public_subnets"]["value"])}')
   print(f'private_route_table_ids = {json.dumps(o["private_route_table_ids"]["value"])}')
   print(f'alb_dns_name            = "{o["alb_dns_name"]["value"]}"')
   PY
   ```

   ...and paste the printed lines into `terraform.tfvars`, or simply copy the values by hand from `terraform output` in `../infra-aws-ha` — see `terraform.tfvars.example` for the full variable list, including the CloudConnexa-specific ones (`cloudconnexa_owner`, etc.) that don't come from the base folder.
3. `terraform init && terraform plan && terraform apply` in this directory, as a distinct second step.

To tear down VPN access without tearing down the base environment, `terraform destroy` this overlay on its own; `infra-aws-ha/` (with `vpn_only` left at `true`) remains internal-only afterward with no VPN path until you apply this overlay again.

## Variable validation

- `cloudconnexa_base_url` is restricted by regex to real CloudConnexa API hosts (`https://<tenant>.api.openvpn.com`), since a misconfigured or malicious value here would send `CLOUDCONNEXA_CLIENT_ID`/`CLOUDCONNEXA_CLIENT_SECRET` to whatever endpoint is set.
- `cloudconnexa_connector_count` must be `>= 1` — `0` would create the CloudConnexa network with no connector instances, so VPN clients could connect with no path to the ALB.
- `cloudconnexa_owner` has no default and is required — the module needs a real, non-empty value, and failing fast here beats a confusing module-internal error at apply.
- `cloudconnexa_application_domain` is required when `ssl_enabled = true` — the ALB's raw `*.elb.amazonaws.com` DNS name never matches a real TLS certificate.

## Known unknowns: connector IAM and EBS encryption

The `cloudconnexa-network` module is sourced from Sonatype's private registry, so this repo cannot show you what IAM permissions the connector EC2 instances receive, or whether their EBS volumes are encrypted at rest — inspecting that requires registry access this reference architecture doesn't assume. Two things worth doing if that opacity matters for your security posture:

- **IAM footprint**: apply an SCP or permissions boundary to the account/OU this runs in if you want a hard ceiling on what the connector instances' role can do, rather than trusting the module's own IAM policy sight-unseen.
- **EBS encryption at rest**: verify the connector instances' EBS volumes are encrypted (or enforce it account-wide via `aws_ebs_encryption_by_default`) — those volumes may hold VPN tunnel keys/config.

This is documentation only; we're not guessing at the module's actual behavior, just flagging what isn't visible from outside it.

## Checkov

No `#checkov:skip` comments are used in `cloudconnexa.tf`. Checkov findings on the connector EC2 instances/security groups (broad egress, public IP — both needed for the connectors to establish VPN tunnels) fire on resources *inside* the child modules; an inline skip comment at the module-invocation site doesn't cross that module boundary and wouldn't actually suppress anything. Real suppression, if wanted, needs a checkov baseline/config scoped to the external module itself.

## Deferred: connector public IP output

Not implemented. Exposing the CloudConnexa connectors' public IPs (useful for firewall/IdP/SIEM allowlisting) would be a good addition to `outputs.tf`, but this repo doesn't have access to Sonatype's private Terraform Cloud registry to confirm what outputs `cloudconnexa-network` actually exposes. Adding a speculative output name that doesn't exist on the module would silently break `terraform plan`. Deferred pending someone with registry access confirming the module's real output schema.
