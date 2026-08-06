# Sonatype IQ Reference Architecture — AWS Cloud-Native, High Availability, VPN-Only (Size XL)

This directory contains a **VPN-only variant** of the [`infra-aws-ha`](../infra-aws-ha/) reference
architecture, sized for **Size XL** (20,000 – 80,000 applications, 20,000+ evaluations/day, 4 nodes). It was
created for a Sonatype performance-testing environment that must not be reachable from the public internet.

Everything about the compute, database, and storage layers is identical to `infra-aws-ha` at Size XL. The only
differences are:

1. The Application Load Balancer is **internal** (no public IP), and lives in the **private** subnets instead
   of the public ones.
2. The ALB's security group only accepts inbound traffic from `var.cloudconnexa_client_cidr_blocks` instead of
   `0.0.0.0/0`.
3. A **Sonatype CloudConnexa VPN network** is provisioned and wired to route VPN client traffic to the ALB
   (`cloudconnexa.tf`), so the only way to reach the environment is over the CloudConnexa VPN.

See [What Makes This VPN-Only](#what-makes-this-vpn-only) below for the exact mechanics, and the parent
[repository README](../README.md) for general prerequisites, tooling, and cost/responsibility disclaimers that
apply to every reference architecture in this repo.

---

## What Makes This VPN-Only

The upstream `infra-aws-ha` architecture is internet-facing because of three things:

| # | What | Where |
|---|------|-------|
| 1 | The ALB is internet-facing (`internal = false`) and sits in public subnets | `infra-aws-ha/load_balancer.tf` |
| 2 | The ALB's security group allows inbound 80/443 from `0.0.0.0/0` | `infra-aws-ha/security_groups.tf` |
| 3 | Those public subnets have `map_public_ip_on_launch = true`, an Internet Gateway, and a public route table with a `0.0.0.0/0` route | `infra-aws-ha/main.tf` |

This variant fixes (1) and (2) directly, and repurposes what's left of (3):

- **`load_balancer.tf`**: `aws_lb.iq_alb` is now `internal = true` and placed in `aws_subnet.private_subnets[*].id`.
  It has no public IP and is not resolvable/routable from outside the VPC.
- **`security_groups.tf`**: `aws_security_group.alb`'s ingress rules on 80/443 now use
  `var.cloudconnexa_client_cidr_blocks` (default: the VPC CIDR) instead of `0.0.0.0/0`.
- **`main.tf`**: the public subnets, Internet Gateway, and NAT gateways are *kept*, but they no longer host
  anything internet-facing for application traffic. They exist solely so that (a) the CloudConnexa VPN
  connector can get the public IP it needs to establish tunnels to the CloudConnexa cloud service, and (b) NAT
  gateways can still give the private subnets outbound internet access (ECR pulls, AWS API calls, OS package
  updates, etc.) — outbound-only, which is not the same as being internet-*reachable*.
- **`cloudconnexa.tf`** (new): provisions the CloudConnexa VPN network + application routing that is the only
  way in. See below.

ECS tasks themselves were never public in the upstream architecture (`assign_public_ip = false`, private
subnets already) — the ALB was the only actual public-internet entry point, so removing its public exposure is
sufficient to make the whole environment VPN-only.

---

## CloudConnexa VPN Wiring

This replicates the pattern used internally at Sonatype in
[`terraform-sca-cloud`](https://github.com/sonatype/terraform-sca-cloud)'s
`src/infrastructure/aws/global/main.tf` (`control_plane_cloudconnexa_network` /
`control_plane_cloudconnexa_application` module invocations), via the same two private-registry modules:

- `app.terraform.io/Sonatype-Cloud/cloudconnexa-network/aws` (v2.0.0) — creates the CloudConnexa VPN network
  attached to this VPC, plus one or more connector instances in the public subnets (they need a public IP to
  reach the CloudConnexa cloud service), and injects VPN return routes into the private route tables so VPN
  clients can reach resources — in this case, the ALB — placed in the private subnets.
- `app.terraform.io/Sonatype-Cloud/cloudconnexa-network-application/cloudconnexa` (v1.0.0) — registers a
  CloudConnexa "network application" that routes VPN client traffic for a given domain to the network created
  above.

### Inputs passed, and why

| Input | Value | Why |
|-------|-------|-----|
| `vpc_id`, `vpc_cidr` | This VPC | Network to attach the VPN to |
| `public_subnet_ids` | This folder's public subnets | Where the CloudConnexa connector instances run (need a public IP) |
| `private_route_table_ids` | All of this folder's private route tables (one per AZ) | So VPN return routes reach the ALB and other resources in every private subnet/AZ |
| `connector_count` / `connector_version` | `var.cloudconnexa_connector_count` / `var.cloudconnexa_connector_version` | Connector redundancy / forced recreation trigger |
| `segment` / `product` / `owner` / `environment` / `description` / `name` / `aws_region` | Variables (see `variables.tf`) | Tagging/identification, same shape as terraform-sca-cloud's call |
| `network_id` (application module) | Output of the network module | Attaches the application routing to the network created above |
| `domains` (application module) | `var.cloudconnexa_application_domain`, defaulting to the ALB's own DNS name | The hostname VPN clients use to reach the app. terraform-sca-cloud uses a custom Route53 domain; this standalone reference architecture has no Route53 zone of its own by default, so it falls back to the ALB's AWS-generated DNS name unless you override it |

The calling root module also needs its own `cloudconnexa` provider (source `OpenVPN/cloudconnexa`, `~> 1.0`),
configured with `base_url = var.cloudconnexa_base_url` — this is declared in `cloudconnexa.tf`, matching
terraform-sca-cloud's `providers.tf` / `terraform.tf`.

### What's reachable without the VPN vs. what's VPN-gated

- **Without the VPN**: nothing application-related. There is no public IP, DNS record, or security group rule
  that allows inbound access to the ALB, ECS tasks, Aurora cluster, or EFS from the public internet. (Outbound
  internet access for the ECS tasks — pulling the `nexus-iq-server` image, reaching AWS APIs, etc. — still
  works via the NAT gateways; that's egress, not an inbound path.)
- **With the VPN**: once connected to the CloudConnexa VPN, `application_url` (the ALB's internal DNS name, or
  your custom `cloudconnexa_application_domain` if set) resolves and routes to the IQ Server ALB exactly as it
  would in the public `infra-aws-ha` variant.

### Prerequisites specific to this variant

- **`CLOUDCONNEXA_CLIENT_ID`** and **`CLOUDCONNEXA_CLIENT_SECRET`** environment variables, so the
  `OpenVPN/cloudconnexa` Terraform provider can authenticate to the CloudConnexa API.
- **Access to Sonatype's private Terraform Cloud module registry** (`app.terraform.io/Sonatype-Cloud/...`) —
  the two CloudConnexa modules referenced above are not published on the public Terraform Registry. If you are
  adapting this reference architecture outside of Sonatype, substitute your own VPN/private-connectivity
  module(s) in `cloudconnexa.tf` in place of these two module blocks; everything else in this folder (the
  internal ALB, tightened security group, VPC layout) is provider-agnostic.
- Verify `cloudconnexa_client_cidr_blocks` (in `variables.tf` / `terraform.tfvars`) actually matches the source
  CIDR your CloudConnexa network presents VPN client traffic as by the time it reaches the ALB's security
  group. It defaults to the VPC CIDR, which covers the common case where the connector NATs client traffic to
  a VPC-internal address, but this depends on your CloudConnexa network's configuration.

---

## Sizing

This folder is pre-configured for **Size XL only** (both in `variables.tf` defaults and
`terraform.tfvars.example`):

| Size | Applications | Evaluations/Day | Nodes | Compute (per node) | Java Heap | Aurora Instance Class |
|------|:------------:|:---------------:|:-----:|:-------------------:|:---------:|:----------------------|
| **XL** | 20,000 – 80,000 | 20,000+ | 4 | 16 vCPU / 128 GB (Fargate 16384 CPU / 131072 MEM) | 96 GB | db.r6g.4xlarge |

If you need a smaller VPN-only size (M or L), copy this folder again and apply the same `internal = true` /
private-subnet / security-group / CloudConnexa changes documented above on top of `infra-aws-ha`'s M/L
`terraform.tfvars` values (see [`infra-aws-ha`'s README](../infra-aws-ha/README.md#recommended-terraformtfvars-by-size)).

---

## Deployment

```bash
git clone https://github.com/sonatype/sca-reference-architectures.git
cd sca-reference-architectures/infra-aws-ha-vpn

# Copy and edit the example variables file
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values (region, passwords, CloudConnexa owner tag, etc.)

export CLOUDCONNEXA_CLIENT_ID="..."
export CLOUDCONNEXA_CLIENT_SECRET="..."

terraform init
./tf-plan.sh    # Review the execution plan
./tf-apply.sh   # Deploy infrastructure
```

After apply, connect to the Sonatype CloudConnexa VPN before browsing to the `application_url` output — there
is no public internet path to this environment.

To tear down: `./tf-destroy.sh`.
