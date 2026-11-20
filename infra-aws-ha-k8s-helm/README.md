# Sonatype IQ Reference Architecture - AWS EKS with Helm (High Availability)

This directory contains Terraform configuration for deploying Sonatype IQ Server on AWS using EKS with Helm in a **High Availability configuration**, with Aurora PostgreSQL, Amazon EFS, pod and node auto-scaling, multi-AZ deployment and, with `search_engine = "opensearch"`, an Amazon OpenSearch Service domain.

Sizing, the JVM rules, OpenSearch planning, the Helm chart pins and the shared troubleshooting table are in the [top-level README](../README.md). This page covers what is specific to this architecture.

---

## Sizing Guide

This EKS HA architecture supports sizes **M**, **L**, and **XL**:

| Size | Applications | Evaluations per day, hour | Nodes (min / desired / max) | IQ pods, HPA min / max | Node type | Pod limit, heap / direct memory | Aurora | OpenSearch |
|------|:------------:|:---------------:|:---------------------------:|:----------------------:|:---------:|:-------------------------------:|:------:|:----------:|
| **M** | 2k - 10k | ~7.5k, 250 | 2 / 2 / 3 | 2, 2 / 3 | m8g.2xlarge (ARM) | 26 GB, 17 GB / 4 GB | 2 x db.r8g.xlarge | 3 x `m8g.large.search`, 100 GB |
| **L** | 10k - 30k | ~15k, 350 | 2 / 2 / 4 | 2, 2 / 4 | m8g.4xlarge (ARM) | 56 GB, 37 GB / 8 GB | 2 x db.r8g.2xlarge | 3 x `m8g.xlarge.search`, 150 GB |
| **XL** | 30k - 100k | ~25k, 450 | 3 / 3 / 5 | 3, 3 / 5 | r9g.4xlarge (ARM) | 112 GB, 74 GB / 8 GB | 2 x db.r8g.4xlarge | 3 x `r8g.2xlarge.search`, 250 GB |

Evaluations per day, hour are typical figures for the whole cluster on a normal day, a guide for planning,
not a limit, as in the top README's [Sizing Guide](../README.md#sizing-guide).

The Terraform values for each size are in [`examples/<size>.tfvars`](./examples/), and the pod's CPU,
memory, heap and autoscaler bounds in `examples/<size>.helm-values.yaml`, which `helm-install.sh --values`
applies after `helm-values.yaml`. The top-level `deploy.sh` uses both. Why the pod heap is lower than on a
whole VM is in [JVM Configuration](../README.md#jvm-configuration).

Aurora storage grows on its own, from about 128 GB at M, 256 GB at L and 512 GB at XL, and is expected to
grow to about 500 GB, 1 TB and 2 TB. EFS uses Elastic throughput and grows with use: plan for 200 to 500 GB
at M, 500 GB to 1.5 TB at L and 1.5 to 4 TB at XL.

> **ARM instances are the default.** The node AMI follows the instance architecture, so the x86 equivalents (m8i and r8i) deploy too.

> **Heap dumps.** The first out-of-memory error in any pod writes a heap dump to
> `/sonatype-work/clm-cluster/heap-dump.hprof`, one file on the shared storage, and the JVM exits; a later
> one skips the dump while that file exists, so delete it to allow another.

---

## OpenSearch for Advanced Search and the Nexus One Index

With `search_engine = "opensearch"`, this configuration creates an Amazon OpenSearch Service domain
running `OpenSearch_3.7` (`opensearch_engine_version`), on three data nodes in three zones at every size.
The IQ Server pods sign their requests with SigV4 through an IAM role for service accounts, which
`iq_server_irsa_role_arn` outputs, so there is no password to store. With `search_engine = "builtin"` there
is no domain: Advanced Search uses the index built into IQ Server, and Nexus One can keep its index in
IQ Server's PostgreSQL database, chosen on the Nexus One setup page.

The domain shape is set per size by `opensearch_instance_type`, `opensearch_instance_count`,
`opensearch_volume_size_gb`, `opensearch_availability_zone_count`, `opensearch_dedicated_master_type` and
`opensearch_index_replicas`, from the size's example file. The defaults are the Size M shape. The node
group runs in two private subnets; with three zones, Terraform adds a third private subnet for the domain
only, so the region needs three availability zones.

To use a domain you already run, name it instead and nothing is created:

```hcl
search_engine              = "opensearch"
opensearch_domain_endpoint = "CHANGE_ME-search-domain.us-east-1.es.amazonaws.com"
opensearch_domain_name     = "CHANGE_ME-search-domain"
opensearch_instance_count  = 3   # the domain's data node count, which sets the shard counts
```

A domain you name should run OpenSearch 3.x, and the pods' role needs the `es:ESHttpGet`,
`es:ESHttpPost`, `es:ESHttpPut`, `es:ESHttpHead` and `es:ESHttpDelete` actions on it.

### Domain shape per size

| Size | Data nodes | Instance type | Heap | Storage per node | Masters | Zones | Shards ¹ | Replicas |
|------|:----------:|:-------------:|:----:|:----------------:|:-------:|:-----:|:--------:|:--------:|
| **M** | 3 | `m8g.large.search` | 4 GB | 100 GB | 3 x `m8g.medium.search` | 3 | 3 | 1 |
| **L** | 3 | `m8g.xlarge.search` | 8 GB | 150 GB | 3 x `m8g.medium.search` | 3 | 3 | 1 |
| **XL** | 3 | `r8g.2xlarge.search` | 32 GB | 250 GB | 3 x `m8g.large.search` | 3 | 3 | 1 |

¹ Primary shards for the component, violation and vulnerability indices, set by `iq-post-deploy.sh`
from `opensearch_instance_count`. Every other index keeps 1.

Heap is half of each node's memory, capped at 32 GB. AWS sets it, and it is not a setting this
configuration can change. The rules for replicas, the Advanced Search index and disk during a rebuild are
in the [top-level OpenSearch section](../README.md#opensearch).

**Storage holds more than one copy of the index.** A replica doubles it, a rebuild holds a second copy while it runs, and AWS reserves 20% of each volume capped at 20 GB. The figures
above allow for all three.

What the created domain gets, none of which needs configuring:

- **The private subnets of this VPC**, reachable on 443 from the EKS nodes and from nowhere else.
- **Encryption at rest and node to node**, and TLS 1.2 enforced.
- **An access policy naming the pods' IRSA role and no other principal.**
- **Three dedicated master nodes**, one per zone.

**Fine-grained access control has to stay off for as long as the domain holds this index.** With it on,
SigV4 alone does not reach the domain, and IQ Server's `type: aws` configuration does not work.

### One account-level prerequisite before the first domain

A VPC domain needs the OpenSearch service-linked role, `AWSServiceRoleForAmazonOpenSearchService`. AWS
creates it on its own when a VPC domain is made through the console. Otherwise, once per account:

```bash
aws iam create-service-linked-role \
  --aws-service-name opensearchservice.amazonaws.com
```

To check first:

```bash
aws iam list-roles \
  --path-prefix /aws-service-role/opensearchservice.amazonaws.com/ \
  --query 'Roles[].RoleName' --output text
```

The calling identity needs `iam:CreateServiceLinkedRole`. An account still carrying the legacy
`AWSServiceRoleForAmazonElasticsearchService` role goes on using that one and needs nothing.

### `terraform destroy` will not delete the domain

The domain carries `prevent_destroy`, because it holds the index. A destroy fails while it is in state,
so removing it is deliberate. `./tf-destroy.sh --delete-opensearch-domain` removes the domain from state,
deletes it, waits for the delete to finish and then destroys the rest. By hand:

```bash
DOMAIN=$(terraform output -raw opensearch_domain_name)
terraform state rm aws_opensearch_domain.nexus_one
aws opensearch delete-domain --domain-name "$DOMAIN"
# wait for the domain to finish deleting, which releases its interfaces
./tf-destroy.sh
```

Read the name first, because `state rm` removes it from state along with the domain. The delete is what
lets the rest of the teardown finish: the domain's network interfaces sit in this VPC's private subnets
and hold its security group, so destroying the VPC around a live domain fails on `DependencyViolation`.

**Switching away from this domain takes the same steps.** Setting `search_engine = "builtin"`, or pointing
`opensearch_domain_endpoint` at another domain, drops this one from the plan, so the plan fails on
`prevent_destroy` in the same way. Read the name, `state rm`, delete the domain and wait, then run
`terraform apply` with the new settings in place of `./tf-destroy.sh`.

### How the configuration reaches IQ Server

Terraform does not write `config.yml` here. The Helm chart builds it from the `iq_server.config` block in
`helm-values.yaml`, and `helm-install.sh` prepares that file at install time:

1. It reads the `search_engine`, `opensearch_domain_endpoint` and `opensearch_index_replicas` outputs.
2. With `opensearch`, it fills in the values inside the `# BEGIN search backend` block and points the
   `nexus-iq-sa` service account at `iq_server_irsa_role_arn`.
3. With `builtin`, it deletes that whole block, so `config.yml` carries no `search:` key at all.
4. Either way it then fails if any of those values was left unfilled.

`helm-upgrade.sh` does the same. **Leave the values inside that block alone**; the scripts fill them in.
The result in `config.yml` is the `type: aws` form shown in the
[top-level OpenSearch section](../README.md#what-iq-servers-configuration-carries).

### Where the domain's own logs go

Three CloudWatch log groups per domain, written by OpenSearch itself, under
`/aws/opensearch/<domain>/`: `search_slow_logs`, `index_slow_logs` and `es_application_logs`. `<domain>` is
the `opensearch_domain_name` output. Retention is `opensearch_log_retention_days`, 30 days by default.

**An account at 10 CloudWatch Logs resource policies needs one written by hand**, covering every domain's
log groups, with `opensearch_create_log_resource_policy = false` in each deployment. That skips the policy
only; the log groups are still created.

**The slow logs stay empty until a threshold is set.** The domain only accepts HTTPS from the EKS node
security group, and only requests signed with the IQ Server IRSA role, so set one from an IQ Server pod,
reached with `kubectl exec`, with that role's temporary credentials. `--aws-sigv4` needs curl 7.75 or
later:

```bash
curl --aws-sigv4 "aws:amz:<aws_region>:es" \
  --user "<access key id>:<secret access key>" \
  -H "x-amz-security-token: <session token>" \
  -XPUT "https://<endpoint>/<index>/_settings" -H 'Content-Type: application/json' -d '{
  "index.search.slowlog.threshold.query.warn": "2s",
  "index.indexing.slowlog.threshold.index.warn": "2s"
}'
```

**Audit logs are not available here.** They need fine-grained access control, which this architecture
cannot turn on without breaking SigV4.

---

## Deployment Guide

The quickest route is the top-level [guided deploy script](../README.md#option-1-the-guided-deploy-script).
The steps below deploy this directory by hand.

### Step 1: Prerequisites

| Tool | Version | Installation | Purpose |
|------|---------|--------------|---------|
| **Terraform** | >= 1.2 | [Install Guide](https://developer.hashicorp.com/terraform/install) | Infrastructure as Code |
| **AWS CLI** | >= 2.0 | [Install Guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) | AWS API access, and signing in through IAM Identity Center |
| **kubectl** | Latest | [Install Guide](https://kubernetes.io/docs/tasks/tools/) | Kubernetes cluster management |
| **Helm** | >= 3.9.3 | [Install Guide](https://helm.sh/docs/intro/install/) | Application deployment |

Your IAM identity needs permissions for EC2 (VPC, subnets, security groups, network interfaces, EIPs, NAT
gateways), EKS (clusters, node groups, add-ons, OIDC providers), RDS Aurora, EFS, ELB, IAM roles, policies
and OIDC providers, Auto Scaling, KMS, CloudWatch Logs, Secrets Manager and Amazon OpenSearch Service. The
license must support clustering.

### Step 2: Configure AWS Credentials

The scripts use the standard AWS credential chain with the profile named in `AWS_PROFILE`. AWS recommends
[short-lived credentials from IAM Identity Center](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html#bp-users-federation-idp):

```bash
aws configure sso --profile nexus-iq-deployment   # once, writes the profile to ~/.aws/config
aws sso login --profile nexus-iq-deployment
export AWS_PROFILE=nexus-iq-deployment
```

### Step 3: Configure Terraform Variables

```bash
cd sca-reference-architectures/infra-aws-ha-k8s-helm
cp terraform.tfvars.example terraform.tfvars
# copy in your size's values from examples/<size>.tfvars, then replace every CHANGE_ME
```

`terraform.tfvars.example` carries the Size M values. Every `CHANGE_ME` must be replaced, including
`database_password`, `iq_admin_initial_password` (at least 12 characters, read by IQ Server on its first
start only), `iq_license_file` (the path to your IQ Server license file, which IQ Server installs on its
first start) and `search_engine`.

### Step 4: Deploy Infrastructure and Application

```bash
terraform init
./tf-plan.sh
./tf-apply.sh                     # the EKS cluster, Aurora, EFS, OpenSearch and networking
./helm-install.sh --values examples/<size>.helm-values.yaml
```

`helm-install.sh` configures kubectl for the cluster, creates the initial admin password secret from
`iq_admin_initial_password` and the license secret from `iq_license_file`, which every pod installs on
its first start, installs the chart version in `helm_chart_version` with the IQ Server release it carries, and then runs
`iq-post-deploy.sh`, which sets the shard counts and chooses the search backend, and installs the license
only if IQ Server has none yet. Run `./iq-post-deploy.sh` again at any time.

### Step 5: Access Sonatype IQ Server

Initial startup can take 10-15 minutes. Open the application URL the install printed, and log in as
`admin` with the password you set in `iq_admin_initial_password`.

### Database migration in `helm-upgrade.sh`

`./helm-upgrade.sh` takes the same `--values` files. It runs the database migration only when the IQ
Server image changes, and then only with `MIGRATE_DATABASE=yes` set. Back up the database before setting
it. The script scales IQ Server to zero for the migration, starts it again afterwards, and exits non-zero
if the migration or the rollout fails.

---

## Teardown / Cleanup

**WARNING: This will delete ALL infrastructure and data!**

```bash
./helm-uninstall.sh
./tf-destroy.sh
```

A domain this architecture created stops the destroy, see
[`terraform destroy` will not delete the domain](#terraform-destroy-will-not-delete-the-domain).

With `skip_final_snapshot = false` the destroy leaves the database's final snapshot, and the automatic EFS
backup AWS Backup keeps in `aws/efs/automatic-backup-vault` is not deleted and expires on its own.

---

## Configuration

`terraform.tfvars.example` lists every variable with its Size M value. Settings worth knowing:

- **`nexus_iq_replica_count`**: the initial number of IQ pods. `helm-install.sh` writes it into `iq_server.replicas`.
- **`hpa.minReplicas`, `hpa.maxReplicas`**: the pod autoscaler bounds, set per size in `examples/<size>.helm-values.yaml`. Every size keeps at least 2 for HA.
- **`aurora_instance_count = 2`**: a writer and a reader in different zones.
- **`helm_chart_version`**: the `nexus-iq-server-ha` chart version, set by this variable's default in `variables.tf`, the one place this architecture pins the IQ Server version. The chart sets the IQ Server image, so this also sets the IQ Server version.
- **`cluster_name`**: all AWS resources are prefixed with it, `nexus-iq-ha` by default. **Give each deployment its own value to run more than one in a single AWS account**, since the EKS cluster, load balancer, IAM roles, log groups, Secrets Manager secrets and Aurora cluster identifier all have to be unique.
- **`deletion_protection`, `skip_final_snapshot`**: set them for production.

## Security Features

- **VPC Isolation**: Application and OpenSearch run in private subnets across multiple AZs
- **Database Security**: Aurora cluster in isolated database subnets; the database password reaches the pods through a Kubernetes secret
- **Initial admin password**: a Kubernetes secret, `nexus-iq-initial-admin-password`, named in `iq_server.initialAdminPasswordSecret`
- **Encryption**: EFS encrypted at rest and in transit, Aurora and OpenSearch encrypted at rest, EBS encryption for node storage
- **IRSA**: IAM Roles for Service Accounts for pod-level AWS permissions

## Reliability and Backup

- **Multi-AZ Deployment**: EKS nodes, pods, Aurora instances and OpenSearch data nodes across availability zones
- **Horizontal Pod Autoscaler**: IQ pods scale between the minimum and maximum for your size
- **Nodes**: the node group runs `node_group_desired_size` nodes, the size minimum, one IQ pod per node. No cluster autoscaler is installed, so a pod the HPA adds above that stays Pending until `node_group_desired_size` is raised
- **Aurora Cluster**: automatic failover to the reader
- **Database Backups**: Automated Aurora backups with 7-day retention (configurable)
- **EFS Persistence**: Application data on EFS survives pod restarts

## Monitoring and Logging

- **Amazon CloudWatch Observability add-on**: collects every container's standard output, including IQ Server's server, request, audit and policy-violation logs, into the Container Insights log groups under `/aws/containerinsights/<cluster>/` (`application`, `dataplane`, `host`, `performance`). Retention is `log_retention_days`. Application Signals auto-monitoring is turned off
- **Log files**: each pod also writes its logs to `/sonatype-work/clm-cluster/log/` on EFS
- **Audit events**: IQ Server writes them to the database by default, see [Logging](../README.md#logging)
- **OpenSearch Metrics**: published to CloudWatch by the service, plus the domain's two slow logs and its application log. No alarms are created

## Networking

- **Public Subnets**: Load balancer and NAT gateways
- **Private Subnets**: EKS nodes in two zones, plus a third private subnet for the OpenSearch domain
- **Database Subnets**: Aurora cluster instances (no internet access)
- **Load balancer**: an Application Load Balancer created by the AWS Load Balancer Controller
