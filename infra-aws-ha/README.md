# Sonatype IQ Reference Architecture - AWS Cloud-Native (High Availability)

This directory contains Terraform configuration for deploying Sonatype IQ Server on AWS using ECS Fargate in a **High Availability configuration**, with Aurora PostgreSQL, Amazon EFS, auto-scaling, multi-AZ deployment and, with `search_engine = "opensearch"`, an Amazon OpenSearch Service domain.

Sizing, the JVM rules, OpenSearch planning and the shared troubleshooting table are in the [top-level README](../README.md). This page covers what is specific to this architecture.

---

## Sizing Guide

This HA architecture supports sizes **M**, **L**, and **XL**:

| Size | Applications | Evaluations per day, hour | Tasks (min / desired / max) | Fargate task | Java heap / direct memory | Aurora | OpenSearch |
|------|:------------:|:---------------:|:---------------------------:|:------------:|:-------------------------:|:------:|:----------:|
| **M** | 2k - 10k | ~7.5k, 250 | 2 / 2 / 3 | 8 vCPU / 32 GB (`8192` / `32768`) | 20 GB / 4 GB | 2 x db.r8g.xlarge | 3 x `m8g.large.search`, 100 GB |
| **L** | 10k - 30k | ~15k, 350 | 2 / 2 / 4 | 16 vCPU / 64 GB (`16384` / `65536`) | 42 GB / 8 GB | 2 x db.r8g.2xlarge | 3 x `m8g.xlarge.search`, 150 GB |
| **XL** | 30k - 100k | ~25k, 450 | 3 / 3 / 5 | 16 vCPU / 120 GB (`16384` / `122880`) | 80 GB / 8 GB | 2 x db.r8g.4xlarge | 3 x `r8g.2xlarge.search`, 250 GB |

Evaluations per day, hour are typical figures for the whole cluster on a normal day, a guide for planning,
not a limit, as in the top README's [Sizing Guide](../README.md#sizing-guide).

The values for each size are in [`examples/<size>.tfvars`](./examples/), which the top-level `deploy.sh`
applies for you, and in the top README's [Detailed Specifications](../README.md#detailed-specifications).
`ecs_memory_reservation`, the task's soft memory limit, is the heap plus direct memory: 24 GB (`24576`) at
M, 50 GB (`51200`) at L and 88 GB (`90112`) at XL. Why the Fargate heap is lower than on a whole VM is in
[JVM Configuration](../README.md#jvm-configuration).

Aurora storage grows on its own, from about 128 GB at M, 256 GB at L and 512 GB at XL, and is expected to
grow to about 500 GB, 1 TB and 2 TB. EFS uses Elastic throughput and grows with use: plan for 200 to 500 GB
at M, 500 GB to 1.5 TB at L and 1.5 to 4 TB at XL.

> **Smaller deployments?** For < 2k applications with a single instance, use the [Single Instance](../infra-aws/) architecture.

> **Heap dumps.** The first out-of-memory error on any task writes a heap dump to
> `/sonatype-work/heap-dump.hprof`, one file on the shared storage, and the JVM exits; a later one skips
> the dump while that file exists, so delete it to allow another.

---

## Search: Nexus One Index and Advanced Search

`search_engine` sets where both of IQ Server's search features keep their indices:

| `search_engine` | Nexus One index | Advanced Search |
|---|---|---|
| `builtin` | This configuration's Aurora PostgreSQL database, chosen on the Nexus One setup page | The index built into IQ Server |
| `opensearch` | The OpenSearch domain this configuration creates | The same OpenSearch domain |

PostgreSQL supports estates of up to 10,000 applications, so of this architecture's sizes only M can use
`builtin`: L and XL need `opensearch`. With `builtin`, no domain is created. See
[Choosing the search backend](../README.md#choosing-the-search-backend).

With `search_engine = "opensearch"`, this configuration creates an Amazon OpenSearch Service domain
running `OpenSearch_3.7` (`opensearch_engine_version`). IQ Server authenticates with AWS SigV4 signed by
the ECS task role, so there is no password to store.

The domain shape is set per size by `opensearch_instance_type`, `opensearch_instance_count`,
`opensearch_volume_size_gb`, `opensearch_availability_zone_count`, `opensearch_dedicated_master_type` and
`opensearch_index_replicas`, from the size's example file. The defaults are the Size M shape.

To use a domain you already run, name it instead and nothing is created:

```hcl
search_engine              = "opensearch"
opensearch_domain_endpoint = "CHANGE_ME-search-domain.us-east-1.es.amazonaws.com"
opensearch_domain_name     = "CHANGE_ME-search-domain"
opensearch_instance_count  = 3   # the domain's data node count, which sets the shard counts
```

A domain you name should run OpenSearch 3.x, and the task role needs the `es:ESHttpGet`,
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
configuration can change. Three data nodes at every size, because three is the smallest count that both
places a replica and spreads across three Availability Zones. The rules for replicas, the Advanced Search
index and disk during a rebuild are in the [top-level OpenSearch section](../README.md#opensearch).

**Storage holds more than one copy of the index.** A replica doubles it, a rebuild holds a second copy while it runs, and AWS reserves 20% of each volume capped at 20 GB. The figures
above allow for all three.

What the created domain gets, none of which needs configuring:

- **The private subnets of this VPC**, reachable on 443 from the ECS task and from nowhere else.
- **Encryption at rest and node to node**, and TLS 1.2 enforced.
- **An access policy naming the ECS task role and no other principal.**
- **Three dedicated master nodes at three data nodes**, and none at one data node.

**Fine-grained access control has to stay off for as long as the domain holds this index.** With it on,
SigV4 alone does not reach the domain, and IQ Server's `type: aws` configuration does not work.

### One account-level prerequisite before the first domain

A VPC domain needs the OpenSearch service-linked role, `AWSServiceRoleForAmazonOpenSearchService`, which
OpenSearch assumes to put the domain's network interfaces in the private subnets. AWS creates it on its
own when a VPC domain is made through the console. Otherwise, once per account:

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
`AWSServiceRoleForAmazonElasticsearchService` role goes on using that one and needs nothing. This
configuration does not create the role, because AWS allows one per account and every deployment's domain
depends on it.

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

Read the name first, because `state rm` removes it from state along with the domain. `./tf-destroy.sh`
rather than a bare `terraform destroy`, because the script also force-deletes the database, admin
password and license secrets. They are created with no recovery window, and the forced delete covers any
secret still in one, which would otherwise keep its name for 7 days and block a re-apply under the
same name.

The `state rm` is what gets past `prevent_destroy`. The delete is what lets the rest of the teardown
finish: the domain's network interfaces sit in this VPC's private subnets and hold its security group, so
destroying the VPC around a live domain fails on `DependencyViolation`.

**Switching away from this domain takes the same steps.** Setting `search_engine = "builtin"`, or pointing
`opensearch_domain_endpoint` at another domain, drops this one from the plan, so the plan fails on
`prevent_destroy` in the same way. Read the name, `state rm`, delete the domain and wait, then run
`terraform apply` with the new settings in place of `./tf-destroy.sh`. Setting `"builtin"` does not move
Nexus One to PostgreSQL: the deploy already chose OpenSearch as IQ Server's Nexus One backend, and IQ
Server keeps that choice, so with the domain gone Nexus One has no index.

### Where the domain's own logs go

Three CloudWatch log groups per domain, written by OpenSearch itself. `<domain>` is the
`opensearch_domain_name` output, which is `cluster_name` cut to 18 characters plus `-nexus-one`:

| Log group | Holds |
|---|---|
| `/aws/opensearch/<domain>/search_slow_logs` | Searches past the index's slow threshold |
| `/aws/opensearch/<domain>/index_slow_logs` | Writes past the index's slow threshold |
| `/aws/opensearch/<domain>/es_application_logs` | What the cluster itself saw: rejected writes, cluster state changes, errors behind a 5xx |

Retention is `opensearch_log_retention_days`, 30 days by default.

**An account at 10 CloudWatch Logs resource policies needs one written by hand.** OpenSearch needs a
resource policy granting it `logs:PutLogEvents` and `logs:CreateLogStream` on the groups, and AWS allows
10 per region, so a deployment into an account at that limit fails with `LimitExceededException`. Write
one policy covering every domain's log groups outside Terraform, and set
`opensearch_create_log_resource_policy = false` in each deployment. That skips the policy only; the log
groups and `log_publishing_options` are still created.

**The slow logs stay empty until a threshold is set.** OpenSearch ships with slow logging off per index.
The domain only accepts HTTPS from the IQ Server task security group, and only requests signed with the
IQ Server task role, so a request to set one has to run from a one-off ECS task started from the IQ Server
task definition, in the private subnets with that security group, carrying that role's temporary
credentials. `--aws-sigv4` needs curl 7.75 or later:

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

### What Terraform writes into `config.yml`

```yaml
search:
  type: aws
  mode: OPENSEARCH
  domain: https://<the created domain's endpoint, or opensearch_domain_endpoint>
  region: <aws_region>
  nexusOneIndexReplicas: <opensearch_index_replicas>

nexusOne:
  connection:
    type: aws
    mode: OPENSEARCH
    domain: https://<the same endpoint>
    region: <aws_region>
    nexusOneIndexReplicas: <opensearch_index_replicas>
```

- **`type: aws`** signs every request with SigV4 through the task role.
- **`nexusOne.connection` repeats the same fields**, because the Nexus One index needs its own connection
  block naming the same domain.

Shard counts are not set in `config.yml`. `iq-post-deploy.sh` sets them through IQ Server's configuration
API once IQ Server is healthy and before the first build.

---

## Deployment Guide

The quickest route is the top-level [guided deploy script](../README.md#option-1-the-guided-deploy-script).
The steps below deploy this directory by hand.

### Step 1: Prerequisites

| Tool | Version | Installation | Purpose |
|------|---------|--------------|---------|
| **Terraform** | >= 1.2 | [Install Guide](https://developer.hashicorp.com/terraform/install) | Infrastructure as Code |
| **AWS CLI** | >= 2.0 | [Install Guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) | AWS API access, and signing in through IAM Identity Center |
| **jq** | >= 1.6 | [Install Guide](https://jqlang.org/download/) | Read the plan in `tf-apply.sh` |

Your IAM identity needs permissions for EC2 (VPC, subnets, security groups, network interfaces), ECS,
Application Auto Scaling, RDS, EFS, AWS Backup, ELB, IAM roles and policies, CloudWatch Logs, Secrets
Manager, SSM parameters and Amazon OpenSearch Service, plus S3 if you keep Terraform state there. The
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
cd sca-reference-architectures/infra-aws-ha
cp terraform.tfvars.example terraform.tfvars
# copy in your size's values from examples/<size>.tfvars, then replace every CHANGE_ME
```

`terraform.tfvars.example` carries the Size M values. Every `CHANGE_ME` must be replaced, including
`db_password`, `iq_admin_initial_password` (at least 12 characters, read by IQ Server on its first start
only), `iq_license_file` (the path to your IQ Server license file, which IQ Server installs on its first
start) and `search_engine`.

### Step 4: Deploy Infrastructure

```bash
terraform init
./tf-plan.sh
./tf-apply.sh
```

The apply script prints the application URL, then runs `iq-post-deploy.sh`, which sets the shard counts
and chooses the search backend, and installs the license only if IQ Server has none yet. Run
`./iq-post-deploy.sh` again at any time.

### Step 5: Access Sonatype IQ Server

Initial startup can take 5-15 minutes. Open the application URL, and log in as `admin` with the password
you set in `iq_admin_initial_password`.

---

## Teardown / Cleanup

**WARNING: This will delete ALL infrastructure and data!**

```bash
./tf-destroy.sh
```

Keep the terminal open until it finishes. A domain this architecture created stops the destroy, see
[`terraform destroy` will not delete the domain](#terraform-destroy-will-not-delete-the-domain). A domain
named through `opensearch_domain_endpoint` was never created here and is not deleted here.

With `db_skip_final_snapshot = false` the destroy leaves the database's final snapshot, and the automatic
EFS backup AWS Backup keeps in `aws/efs/automatic-backup-vault` is not deleted and expires on its own.

---

## Configuration

`terraform.tfvars.example` lists every variable with its Size M value. Settings worth knowing:

- **`iq_desired_count`, `iq_min_count`, `iq_max_count`**: the task counts per size in the Sizing Guide. Every size keeps at least 2 for HA.
- **`iq_cpu_target_value = 70`, `iq_memory_target_value = 80`**: the auto scaling targets, in percent.
- **`aurora_instances = 2`**: a writer and a reader in different zones.
- **`iq_docker_image`**: the IQ Server image and its version tag, set by this variable's default in `variables.tf`, the one place this architecture pins the IQ Server version. Set it in `terraform.tfvars` only to run a different image.
- **`cluster_name`**: the base name for every resource, `ref-arch-iq-ha-cluster` by default. **Give each deployment its own value to run more than one in a single AWS account**, since the load balancer, target groups, IAM roles, log group, SSM parameters, Secrets Manager secrets and Aurora cluster identifier all have to be unique.
- **`db_deletion_protection`, `db_skip_final_snapshot`, `alb_deletion_protection`**: set them for production.
- **`aurora_engine_version`**: `18.6` by default. An instance class change applies in the next maintenance window, because this configuration does not set `apply_immediately`.

### Clustering

- **Work directories**: each task gets its own `/sonatype-work/clm-server-${HOSTNAME}` directory, and shares `/sonatype-work/clm-cluster` with the others
- **Configuration**: `config.yml` is generated per task, pointing every task at the shared Aurora cluster
- **Logs**: each task writes its logs under its own host name. A task that has gone leaves its directory behind, and the next task to start deletes any other task's directory unchanged for 7 days

## Security Features

- **VPC Isolation**: Application and OpenSearch run in private subnets across multiple AZs
- **Database Security**: Aurora cluster in isolated database subnets
- **Secrets Management**: The database password and the initial admin password are stored in AWS Secrets Manager
- **Encryption**: EFS encrypted at rest and in transit, Aurora and OpenSearch encrypted at rest, S3 ALB logs encrypted
- **Security Groups**: Least-privilege network access

## Reliability and Backup

- **Multi-AZ Deployment**: ECS tasks, Aurora instances and OpenSearch data nodes across three availability zones
- **Auto Scaling**: the ECS service scales between the minimum and maximum task counts for your size on CPU and memory
- **Aurora Cluster**: automatic failover to the reader
- **Rolling Deployments**: zero-downtime updates with 50% minimum healthy capacity
- **Database Backups**: Automated Aurora backups with 7-day retention (configurable)
- **EFS Backups**: daily and weekly backups through AWS Backup

## Monitoring and Logging

- **Fluent Bit sidecar**: collects the application, request, audit, policy-violation and stderr logs, and sends them to one CloudWatch log group, `/ecs/${cluster_name}/nexus-iq-server`, one stream prefix per log type. It also writes them as JSON to EFS under `/var/log/nexus-iq-server/aggregated/`
- **Audit events**: IQ Server writes them to the database by default, see [Logging](../README.md#logging)
- **Container Insights**: ECS cluster monitoring enabled
- **Aurora Monitoring**: Performance Insights and Enhanced Monitoring enabled
- **ALB Access Logs**: Load balancer access logs stored in S3
- **OpenSearch Metrics**: published to CloudWatch by the service, plus the domain's two slow logs and its application log. No alarms are created

## Networking

- **Public Subnets**: Load balancer and NAT gateways across multiple AZs
- **Private Subnets**: ECS Fargate tasks and the OpenSearch domain across multiple AZs
- **Database Subnets**: Aurora cluster instances (no internet access)
- **Security groups**: the ALB allows 80 and 443 from the internet; ECS allows 8070 from the ALB and traffic between tasks; Aurora allows 5432 and EFS 2049 from the ECS tasks only; the domain allows 443 from the ECS tasks only
