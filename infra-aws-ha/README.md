# Sonatype IQ Reference Architecture - AWS Cloud-Native (High Availability)

This directory contains Terraform configuration for deploying Sonatype IQ Server on AWS using ECS Fargate in a **High Availability configuration** with auto-scaling and multi-AZ deployment.

---

## Sizing Guide

This HA architecture supports sizes **M**, **L**, and **XL**. Choose your size based on application count and daily evaluation volume:

| Size | Applications | Evaluations/Day | Nodes | Compute (per node) | Java Heap | Instance Type | OpenSearch |
|------|:------------:|:---------------:|:-----:|:-------------------:|:---------:|:-------------:|:----------:|
| **M** | 2,000 - 10,000 | 5,000 - 10,000 | 2 | 8 vCPU / 60 GB | 44 GB | Fargate (8192 CPU / 61440 MEM) | Required ¹ |
| **L** | 10,000 - 20,000 | 10,000 - 20,000 | 3 | 8 vCPU / 60 GB | 44 GB | Fargate (8192 CPU / 61440 MEM) | Required ¹ |
| **XL** | 20,000 - 80,000 | 20,000+ | 4 | 16 vCPU / 120 GB | 96 GB | Fargate (16384 CPU / 122880 MEM) | Required ¹ |

> M and L were measured on Fargate at 8 vCPU, 60 GB and a 44 GB heap, and XL at 16 vCPU, 120 GB and a 96 GB heap. Evaluations an hour per task, sustained in testing, not a limit: 1,630 at M on 2 tasks, about 3,700 at L on 3 tasks and 3,830 at XL on 5 tasks.

> **Why a 44 GB heap at M and L?** Fargate caps an 8 vCPU task at 60 GB, so a 48 GB heap plus `-XX:MaxDirectMemorySize=8g` would commit 56 GB of the 60, and `-XX:+AlwaysPreTouch` claims the whole heap at startup. 44 GB leaves 8 GB for the JVM's own non-heap memory and the rest of the container. XL keeps 96 GB, which leaves 16 GB of its 120 GB task.

> ¹ Required for Advanced Search and the Nexus One index at every size, and not switched on for you: `search_engine` defaults to `lucene` in `variables.tf`, so a deployment that wants either feature sets it to `opensearch`, and this configuration then creates the domain. See [OpenSearch](#opensearch) for what it serves, what this architecture does and does not do about it, and the per-size cluster specification.

> **Smaller deployments?** For < 2,000 applications with a single instance, use the [Single Instance](../infra-aws/) architecture.

### Recommended `terraform.tfvars` by Size

> **Heap dumps.** At M, L and XL the first out-of-memory error on any node writes a heap dump to
> `/sonatype-work/heap-dump.hprof`, one file on the shared storage, and the JVM exits; a later one
> skips the dump while that file exists, so delete it to allow another.

<details>
<summary><strong>Size M</strong> — Medium (2,000 – 10,000 applications, 2 nodes)</summary>

```hcl
ecs_cpu              = 8192                # 8 vCPU
ecs_memory           = 61440               # 60 GB, the maximum at 8 vCPU
iq_desired_count     = 2                   # 2 nodes for HA
iq_min_count         = 2
iq_max_count         = 3
iq_docker_image      = "sonatype/nexus-iq-server:latest"
java_opts            = "-Xms44g -Xmx44g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/heap-dump.hprof -XX:+ExitOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
aurora_instance_class = "db.r8g.2xlarge"   # 8 vCPU, 64 GB
aurora_instances      = 2                  # Multi-AZ

search_engine                      = "opensearch"
opensearch_instance_type           = "m8g.large.search"
opensearch_instance_count          = 3
opensearch_volume_size_gb          = 100
opensearch_availability_zone_count = 3
opensearch_index_replicas          = 1
```
</details>

<details>
<summary><strong>Size L</strong> — Large (10,000 – 20,000 applications, 3 nodes)</summary>

```hcl
ecs_cpu              = 8192                # 8 vCPU
ecs_memory           = 61440               # 60 GB, the maximum at 8 vCPU
iq_desired_count     = 3                   # 3 nodes recommended
iq_min_count         = 2
iq_max_count         = 4
iq_docker_image      = "sonatype/nexus-iq-server:latest"
java_opts            = "-Xms44g -Xmx44g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/heap-dump.hprof -XX:+ExitOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
aurora_instance_class = "db.r8g.2xlarge"   # 8 vCPU, 64 GB
aurora_instances      = 2                  # Multi-AZ with failover

search_engine                      = "opensearch"
opensearch_instance_type           = "m8g.xlarge.search"
opensearch_instance_count          = 3
opensearch_volume_size_gb          = 150
opensearch_availability_zone_count = 3
opensearch_index_replicas          = 1
```
</details>

<details>
<summary><strong>Size XL</strong> — Extra Large (20,000 – 80,000 applications, 4 nodes)</summary>

```hcl
ecs_cpu              = 16384               # 16 vCPU
ecs_memory           = 122880              # 120 GB, the maximum at 16 vCPU
iq_desired_count     = 4                   # 4 nodes for XL
iq_min_count         = 3
iq_max_count         = 5
iq_docker_image      = "sonatype/nexus-iq-server:latest"
java_opts            = "-Xms96g -Xmx96g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/heap-dump.hprof -XX:+ExitOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
aurora_instance_class = "db.r8g.4xlarge"   # 16 vCPU, 128 GB
aurora_instances      = 2                  # Multi-AZ with automatic failover

search_engine                      = "opensearch"
opensearch_instance_type           = "r8g.2xlarge.search"
opensearch_instance_count          = 3
opensearch_volume_size_gb          = 250
opensearch_availability_zone_count = 3
opensearch_dedicated_master_type   = "m8g.large.search"
opensearch_index_replicas          = 1
```
</details>

### Database Sizing

| Size | Aurora Instance Class | vCPU | Memory | Storage |
|------|:--------------------|:----:|:------:|:-------:|
| **M** | db.r8g.2xlarge | 8 | 64 GB | Grows automatically, about 128 GB, up to 500 GB |
| **L** | db.r8g.2xlarge | 8 | 64 GB | Grows automatically, about 256 GB, up to 1 TB |
| **XL** | db.r8g.4xlarge | 16 | 128 GB | Grows automatically, about 512 GB, up to 2 TB |

### Shared Storage (EFS)

| Size | Throughput Mode | Estimated Capacity | Cost Optimization |
|------|:---------------|:------------------:|:-----------------|
| **M** | Elastic | 200 GB – 500 GB | Lifecycle policies: 30-day move to IA |
| **L** | Elastic | 500 GB – 1.5 TB | Lifecycle policies: 30-day move to IA |
| **XL** | Elastic | 1.5 TB – 4 TB | Lifecycle policies: 30-day move to IA |

### OpenSearch

IQ Server uses an OpenSearch cluster for Advanced Search and for the Nexus One index behind the Nexus
One list pages, typeahead, and dashboard, and **it is required at every size this architecture
supports.** One cluster serves both features, through a `search:` block and a `nexusOne.connection` block in IQ Server's
`config.yml` that name the same endpoint and credentials, with nothing extra to switch on per
feature.

On AWS the cluster is an **Amazon OpenSearch Service domain**, and IQ Server authenticates with AWS
SigV4 signed by the deployment's own role, so there is no password to store. That role needs the
`es:ESHttpGet`, `es:ESHttpPost`, `es:ESHttpPut`, `es:ESHttpHead` and `es:ESHttpDelete` actions on the
domain.

**The templates do not turn it on for you.** `search_engine` defaults to `lucene` in `variables.tf`, so
a deployment that wants either feature sets `search_engine = "opensearch"`. Every variable and its
default is in [OpenSearch for the Nexus One Index](#opensearch-for-the-nexus-one-index) below.

**This architecture creates the domain unless you name one.** With `search_engine = "opensearch"` and
`opensearch_domain_endpoint` left empty, the domain is created here. Set that endpoint and
`opensearch_domain_name` to point at a domain you already run, and nothing is created. A domain created
here carries `prevent_destroy`, so `terraform destroy` stops rather than deleting your index; a domain
you named stays independent of this deployment entirely.

#### Seven indices in one shared cluster

A deployment running both features holds **seven indices on one domain**: six for the Nexus One index
and one for Advanced Search. The index list, what each one holds, the one-primary-shard default, and
why a shard count can only be set when an index is created are the same on every cloud, so they are
stated once in the [top-level OpenSearch section](../README.md#opensearch) rather than repeated here.

#### Replicas

A replica is a full second copy of every shard, and it is what makes losing a data node
survivable. This architecture writes `nexusOneIndexReplicas` itself. When IQ Server is not
given a count, it uses 1:

| Size | OpenSearch data nodes | Replica count |
|------|:---------------------:|:-------------:|
| **M** | 3 | `1` |
| **L** | 3 | `1` |
| **XL** | 3 | `1` |

The rules behind this, including what a yellow index does and does not mean and how to give the
Advanced Search index a matching replica count, are in the
[top-level OpenSearch section](../README.md#replicas-each-architecture-sets-the-count).

#### Plan for twice the index during a rebuild

A Nexus One index rebuild builds a complete new set of indices and keeps the old set for 30 minutes
after the cutover, so the domain holds twice the Nexus One shards and twice the Nexus One disk for the
whole run and for half an hour afterwards. **Judge free storage against the doubled figure, not the
steady state.** A replica is a separate doubling that applies at the same time. The full rules, and why
a rebuild is not a backup, are in the
[top-level OpenSearch section](../README.md#plan-for-twice-the-index-during-a-rebuild).

#### Per-size cluster specification

The data node type and count, storage per node, shards and replicas for each size are in the
[domain shape table](#domain-shape-per-size) below. At M, L and XL the component, violation and vulnerability indices are
created with 3 primary shards and every other index with 1. The
shard counts are set through the configuration API before the first build, as shown there.

See the [top-level OpenSearch section](../README.md#opensearch) for the full planning rules.

---

## OpenSearch for the Nexus One Index

Sonatype IQ Server keeps its Nexus One index in an AWS-managed OpenSearch
domain. With `search_engine = "lucene"` there is no Nexus One index, and
Advanced Search uses the index built into the server. Set `search_engine` to
`opensearch` and this configuration creates the domain:

```hcl
search_engine                      = "opensearch"
opensearch_instance_type           = "m8g.large.search"
opensearch_instance_count          = 3
opensearch_volume_size_gb          = 100
opensearch_availability_zone_count = 3
opensearch_index_replicas          = 1
```

`search_engine = "lucene"` is the default and needs none of the others.

To use a domain you already run, name it instead and nothing is created:

```hcl
search_engine              = "opensearch"
opensearch_domain_endpoint = "CHANGE_ME-search-domain.us-east-1.es.amazonaws.com"
opensearch_domain_name     = "CHANGE_ME-search-domain"
```

**On this architecture OpenSearch is the index that every task shares.** The
built-in index lives on each task's own storage, so a cluster of tasks keeps a
copy each and each copy is rebuilt separately. An OpenSearch domain is one
index all the tasks read and write, which is why it matters more here than on
the single-instance architecture.

### `terraform destroy` will not delete the domain

The domain carries `prevent_destroy`, because it holds the index and rebuilding
one takes over an hour on a large estate. A destroy fails while it is in state,
so removing it is deliberate:

```bash
DOMAIN=$(terraform output -raw opensearch_domain_name)
terraform state rm aws_opensearch_domain.nexus_one
aws opensearch delete-domain --domain-name "$DOMAIN"
# wait for the domain to finish deleting, which releases its interfaces
./tf-destroy.sh
```

Read the name first, because `state rm` removes it from state along with the
domain. `./tf-destroy.sh` rather than a bare `terraform destroy`, because the
script also empties the EFS backup vault, which cannot be deleted while it holds
a recovery point, and force-deletes the database secret, which a plain destroy
leaves in its 7-day recovery window, blocking a re-apply under the same name.

The `state rm` is what gets past `prevent_destroy`. The delete is what lets the
rest of the teardown finish: the domain's network interfaces sit in this VPC's
private subnets and hold its security group, so destroying the VPC around a live
domain fails on `DependencyViolation`.

**Switching away from this domain takes the same steps.** Setting
`search_engine = "lucene"`, or pointing `opensearch_domain_endpoint` at another
domain, drops this one from the plan, so the plan fails on `prevent_destroy` in
the same way. Read the name, `state rm`, delete the domain and wait, then run
`terraform apply` with the new settings in place of `./tf-destroy.sh`.

**To keep the index, keep this deployment standing.** A domain cannot outlive the
VPC it was built in. A deployment that builds its own network can then name this
domain through `opensearch_domain_endpoint` and share the index with it.

### One account-level prerequisite before the first domain

A VPC domain needs the OpenSearch service-linked role,
`AWSServiceRoleForAmazonOpenSearchService`, which is what OpenSearch assumes to
put the domain's network interfaces in the private subnets. AWS creates it on its
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

The calling identity needs `iam:CreateServiceLinkedRole`. An account still
carrying the legacy `AWSServiceRoleForAmazonElasticsearchService` role goes on
using that one and needs nothing. This configuration does not create the role,
because AWS allows one per account and every deployment's domain depends on it.

What the created domain gets, none of which needs configuring:

- **The private subnets of this VPC**, one per Availability Zone it spreads
  across, reachable on 443 from the ECS tasks alone and from nowhere else.
- **Encryption at rest and node to node**, and TLS 1.2 enforced.
- **An access policy naming the ECS task role and no other principal.** IQ
  Server signs its requests with SigV4 through that role.
- **Three dedicated master nodes** whenever there is more than one data node,
  which keeps cluster state off the nodes serving queries.

**Fine-grained access control has to stay off for as long as the domain holds this
index.** With it on, SigV4 alone no longer reaches the domain, and IQ Server's
`type: aws` configuration stops working.

### Domain shape per size

| Size | Applications | Data nodes | Instance type | Heap | Storage per node | Masters | Zones | Shards ¹ | Replicas |
|------|:------------:|:----------:|:-------------:|:----:|:----------------:|:-------:|:-----:|:--------:|:--------:|
| **M** | 2,000 - 10,000 | 3 | `m8g.large.search` | 4 GiB | 100 GB | 3 x `m8g.medium.search` | 3 | 3 | 1 |
| **L** | 10,000 - 20,000 | 3 | `m8g.xlarge.search` | 8 GiB | 150 GB | 3 x `m8g.medium.search` | 3 | 3 | 1 |
| **XL** | 20,000 - 80,000 | 3 | `r8g.2xlarge.search` | 32 GiB | 250 GB | 3 x `m8g.large.search` | 3 | 3 | 1 |

¹ Primary shards for the component, violation and vulnerability indices. Every
other index keeps 1. See [What Terraform writes into `config.yml`](#what-terraform-writes-into-configyml)
for how to set them.

Heap is half of each node's memory, capped at 32 GiB. AWS sets it, and it is
not a setting this configuration can change.

Three data nodes at every size, because three is the smallest count that both
places a replica and spreads across three Availability Zones. At 0 replicas a
lost node means the index is rebuilt rather than recovered.

The data node types, masters, shards and replicas above are measured at every size.

**Storage holds more than one copy of the index.** A replica doubles it, a
rebuild holds a second generation for the whole run and for 30 minutes after
cutover, and AWS reserves 20% of each volume capped at 20 GiB. The figures
above allow for all three.

### Where the domain's own logs go

Three CloudWatch log groups per domain, written by OpenSearch itself. `<domain>`
is the `opensearch_domain_name` output, which is `cluster_name` cut to 18
characters plus `-nexus-one`:

| Log group | Holds |
|---|---|
| `/aws/opensearch/<domain>/search_slow_logs` | Searches past the index's slow threshold |
| `/aws/opensearch/<domain>/index_slow_logs` | Writes past the index's slow threshold |
| `/aws/opensearch/<domain>/es_application_logs` | What the cluster itself saw: rejected writes, cluster state changes, errors behind a 5xx |

Retention is `opensearch_log_retention_days`, 30 days by default.

**An account at 10 CloudWatch Logs resource policies needs one written by
hand.** OpenSearch needs a resource policy granting it `logs:PutLogEvents` and
`logs:CreateLogStream` on the groups, and AWS allows 10 per region, so a
deployment into an account at that limit fails with `LimitExceededException`.
Write one policy covering every domain's log groups outside Terraform, and set
`opensearch_create_log_resource_policy = false` in each deployment. That skips
the policy only; the log groups and `log_publishing_options` are still created.
With no such policy in the account, the domain create fails.

**The slow logs stay empty until a threshold is set.** OpenSearch ships with
slow logging off per index, so set a threshold on the index to get any rows.

The domain only accepts HTTPS from the IQ Server task security group, and only requests signed with
the IQ Server task role. A one-off ECS task started from the IQ Server
task definition, in the private subnets with that security group, has both, so the request has to run from there and carry that role's temporary
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

The application log needs nothing and fills on its own.

**Audit logs are not available here.** They need fine-grained access control,
which this architecture cannot turn on without breaking SigV4.

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
  `type: http` always sends a user name and password, which a domain with
  fine-grained access control off has no way to check.
- **`mode: OPENSEARCH`** is written out rather than left to default. The
  default is `HYBRID`, which also writes every batch to the built-in index.
- **`nexusOneIndexReplicas`** is always written. When IQ Server is not given a
  count, it uses 1.
- **`nexusOne.connection` repeats the same fields** because it is the only
  block the Nexus One index reads. Without it, turning the feature on is refused.

Shard counts are held in IQ Server's database, not in `config.yml`, and a
shard count only takes effect when an index is created. **At M, L and XL, set
the component, violation and vulnerability indices to 3 shards before the
Nexus One index is first built**, with the request in
[Shards](../README.md#shards-3-for-three-indices-at-m-and-above).

The other Nexus One indices and the Advanced Search index keep 1 shard. An
index built before the change keeps its count until it is rebuilt.

---

## Deployment Guide

### Step 1: Prerequisites

#### Required Tools
Install these tools on your local machine:

| Tool | Version | Installation | Purpose |
|------|---------|--------------|---------|
| **Terraform** | >= 1.2 | [Install Guide](https://developer.hashicorp.com/terraform/install) | Infrastructure as Code |
| **AWS CLI** | >= 2.0 | [Install Guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) | AWS API access |
| **aws-vault** | Latest | [Install Guide](https://github.com/99designs/aws-vault#installing) | Secure credential management |
| **jq** | >= 1.6 | [Install Guide](https://jqlang.org/download/) | Read the plan in `tf-apply.sh` |

#### AWS Account Requirements
- AWS account with administrative access (or sufficient permissions listed below)
- IAM user with MFA enabled
- Ability to create: VPC, ECS, RDS Aurora, EFS, ALB, IAM roles

#### Required AWS Permissions
Your IAM user/role needs these AWS service permissions:
- **EC2**: VPC, subnets, security groups, network interfaces, EIPs, NAT gateways, route tables
- **ECS**: Clusters, task definitions, services, container insights
- **RDS**: Aurora clusters, instances, subnet groups, parameter groups
- **EFS**: File systems, mount targets, access points, backup policies
- **ELB**: Application Load Balancers, target groups, listeners
- **IAM**: Roles, policies, instance profiles
- **Application Auto Scaling**: Scaling policies and targets for ECS services
- **Cloud Map**: Service discovery private DNS namespaces and services
- **Backup**: Backup vaults, plans, selections for EFS
- **KMS**: Keys and aliases for encryption (Aurora, EFS, Backup)
- **Logs**: CloudWatch log groups and streams
- **Secrets Manager**: Secrets creation and management
- **SSM Parameter Store**: Parameters for storing Fluent Bit configuration
- **S3**: ALB logs storage, log archival (optional), Terraform state storage (if using remote state)

### Step 2: Configure AWS Credentials

**The provided scripts use aws-vault for secure credential management.**

1. **Choose a profile name** (e.g., `nexus-iq-deployment`)

2. **Configure your AWS profile in `~/.aws/config`:**
   ```ini
   [profile nexus-iq-deployment]
   region = us-east-1
   output = json
   mfa_serial = arn:aws:iam::<YOUR_ACCOUNT_ID>:mfa/<YOUR-USERNAME>
   ```

3. **Add credentials to aws-vault and test:**
   ```bash
   aws-vault add nexus-iq-deployment
   ```
   Enter your AWS Access Key ID and Secret Access Key when prompted

   ```bash
   aws-vault exec nexus-iq-deployment -- aws sts get-caller-identity
   ```
   You should see your AWS account details.

4. **Set the AWS_PROFILE environment variable:**

   The scripts require the `AWS_PROFILE` environment variable to be set:

   Option 1: Export for your entire session
   ```bash
   export AWS_PROFILE=nexus-iq-deployment
   export AWS_REGION=us-east-1  # Optional: override default region
   ```

   Option 2: Set inline for a single command
   ```bash
   AWS_PROFILE=nexus-iq-deployment <script>
   ```

### Step 3: Configure Terraform Variables

1. **Copy the example configuration:**
   ```bash
   cd /path/to/sca-example-terraform/infra-aws-ha
   cp terraform.tfvars.example terraform.tfvars
   ```

2. **Edit `terraform.tfvars` with your values (set `search_engine = "opensearch"`, see [OpenSearch](#opensearch-for-the-nexus-one-index)):**
   ```bash
   vi terraform.tfvars
   ```

### Step 4: Deploy Infrastructure

1. **Initialize Terraform:**
   ```bash
   terraform init
   ```

   This downloads required providers (AWS, etc.)

2. **Review the deployment plan:**
   ```bash
   ./tf-plan.sh
   ```

   This shows what resources will be created without actually deploying them. The plan script
   stops before Terraform runs if an uncommented line in `terraform.tfvars` still holds
   `CHANGE_ME`, and Terraform rejects a `CHANGE_ME` value too, so deploy through the scripts
   rather than plain `terraform apply`.

3. **Deploy the infrastructure:**
   ```bash
   ./tf-apply.sh
   ```

   The script will display the application URL when complete.

### Step 5: Access Sonatype IQ Server

1. **Wait for service to be ready:**
   - Initial startup can take 10-15 minutes
   - All instances must complete database migrations and clustering setup

2. **Access the web UI:**

   Use the application URL displayed at the end of the deployment.

   Example: `http://ref-arch-iq-ha-cluster-alb-123456789.us-east-1.elb.amazonaws.com`

3. **Login credentials:**
   - **Username:** `admin`
   - **Password:** `admin123` (change immediately!)

---

## Teardown / Cleanup

> **Your OpenSearch domain is not deleted by this.** A domain this architecture created carries `prevent_destroy`, so `./tf-destroy.sh` stops rather than deleting it; the steps that remove it deliberately are in [`terraform destroy` will not delete the domain](#terraform-destroy-will-not-delete-the-domain). A domain named through `opensearch_domain_endpoint` was never created here and is not deleted here.

**WARNING: This will delete ALL infrastructure and data!**

1. **Destroy all resources:**
   ```bash
   ./tf-destroy.sh
   ```

   > **Keep the terminal open** - If you close it mid-destroy, the process will potentially stop and leave resources partially deleted.

---

## Configuration

> **PostgreSQL version.** Minimum PostgreSQL 16. Recommended, and the default for new
> deployments, PostgreSQL 18. An existing deployment sets `aurora_engine_version` in
> `terraform.tfvars` to the version it runs today, and one still on PostgreSQL 15 is below
> the minimum. Upgrading is the deployer's decision.

> **Upgrading an existing deployment.** These variable defaults changed with the
> published sizing. A deployment whose `terraform.tfvars` does not set a variable
> picks up the new default on its next apply. Set the values your deployment is
> running at in `terraform.tfvars` before applying.
>
> | Variable | Previous default | New default |
> |---|:---:|:---:|
> | `iq_max_count` | 5 | 4 |
> | `aurora_engine_version` | 15.10 | 18.6 |
> | `ecs_memory` | 32768 | 61440 |
> | `ecs_memory_reservation` | 24576 | 53248 |
> | `java_opts` | 24 GB heap | 44 GB heap |
> | `aurora_instance_class` | db.r6g.2xlarge | db.r8g.2xlarge |
>
> An instance class change applies in the next maintenance window, because this
> configuration does not set `apply_immediately`.
>
> The `Name` tags on the VPC, internet gateway, subnets, NAT gateways and their
> addresses, and route tables follow `cluster_name`. A deployment that sets its
> own `cluster_name` sees those tags renamed on the next apply. Only the tags change.
>
> Each task writes its logs under its own host name, so files an earlier version
> wrote stay at the top of the log directory: `clm-server.log`, `request.log`,
> `audit.log`, and their `clm-server-*`, `request-*` and `audit-*` archives. Delete
> them once, from anything that mounts the logs EFS access point, keeping the
> `audit-*` archives for as long as your retention needs:
> `cd /var/log/nexus-iq-server && rm -f clm-server.log request.log audit.log clm-server-*.log.gz request-*.log.gz`.
>
> A task that has gone leaves its directory behind, and the next task to start
> deletes any other task's directory unchanged for 7 days.

### Configuration Variables

Edit `terraform.tfvars` to customize your deployment. The task counts below are the Size L values from
the [Sizing Guide](#sizing-guide); use the per-size block for your own size instead of copying these.

```hcl
# General Configuration
aws_region   = "us-east-1"
cluster_name = "ref-arch-iq-ha-cluster"

# Network Configuration
vpc_cidr               = "10.0.0.0/16"
public_subnet_cidrs    = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
private_subnet_cidrs   = ["10.0.10.0/24", "10.0.20.0/24", "10.0.30.0/24"]
db_subnet_cidrs        = ["10.0.40.0/24", "10.0.50.0/24", "10.0.60.0/24"]
enable_nat_gateway     = true

# ECS Configuration
ecs_cpu                 = 8192   # 8 vCPU
ecs_memory              = 61440  # 60 GB, the Size M and L value
ecs_memory_reservation  = 53248  # 52 GB soft limit, the heap plus direct memory

# IQ Server Configuration
iq_desired_count        = 3
iq_min_count           = 2
iq_max_count           = 4
iq_cpu_target_value    = 70  # CPU target for auto scaling (%)
iq_memory_target_value = 80  # Memory target for auto scaling (%)
iq_docker_image        = "sonatype/nexus-iq-server:latest"
java_opts              = "-Xms44g -Xmx44g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/heap-dump.hprof -XX:+ExitOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"

# Database Configuration (Aurora PostgreSQL)
db_name                     = "nexusiq"
db_username                 = "nexusiq"
db_password                 = "CHANGE_ME_STRONG_PASSWORD"  # Change this!
aurora_engine_version       = "18.6"
aurora_instance_class       = "db.r8g.2xlarge"
aurora_instances            = 2
db_backup_retention_period  = 7
db_backup_window           = "03:00-04:00"
db_maintenance_window      = "sun:04:00-sun:05:00"
db_skip_final_snapshot     = true
db_deletion_protection     = false

# Load Balancer Configuration
# ssl_certificate_arn = "arn:aws:acm:us-east-1:CHANGE_ME:certificate/CHANGE_ME"
alb_deletion_protection = false

# Monitoring Configuration
enable_container_insights = true
enable_prometheus        = true
log_retention_days       = 30

# Search Backend, needed for Advanced Search and the Nexus One index at every size
# "lucene" (default) uses the index built into IQ Server. "opensearch" creates
# a domain here, or uses one you already run if you set
# opensearch_domain_endpoint. See the OpenSearch section above.
search_engine = "lucene"
# opensearch_domain_endpoint = "CHANGE_ME-search-domain.us-east-1.es.amazonaws.com"
# opensearch_domain_name     = "CHANGE_ME-search-domain"
# opensearch_index_replicas  = 1
```

**Important Settings:**
- **`iq_desired_count = 3`** - Initial number of tasks, the Size L value. Size M uses 2 and Size XL uses 4
- **`iq_min_count = 2`** - Minimum auto scaling capacity, the Size M and L value. Size XL uses 3, and every size must be at least 2 for HA
- **`iq_max_count = 4`** - Maximum auto scaling capacity, the Size L value. Size M uses 3 and Size XL uses 5
- **`aurora_instances = 2`** - Number of Aurora instances (minimum 2 for HA)
- **`db_password`** - Use a strong, unique password (required change)
- **`db_deletion_protection = false`** - Set to `true` for production to prevent accidental database deletion
- **`db_skip_final_snapshot = true`** - Set to `false` for production to create a final backup snapshot before database deletion
- **`alb_deletion_protection = false`** - Set to `true` for production use
- **Resource Names** - Controlled by `cluster_name` variable, which defaults to `ref-arch-iq-ha-cluster`. **Give each deployment its own value to run more than one in a single AWS account**, since the load balancer, target groups, IAM roles, log group, SSM parameters, Secrets Manager secret and Aurora cluster identifier all have to be unique. One value per size, for example `ref-arch-m-cluster` through `ref-arch-xl-cluster`, is the intended use.

### Custom Clustering Solution

This deployment solves critical IQ Server clustering challenges:

- **Work Directory Conflicts**: Each task gets unique `/sonatype-work/clm-server-${HOSTNAME}` directory
- **Database Sharing**: Custom config.yml generation ensures all instances connect to shared Aurora cluster
- **Cluster Coordination**: Shared `/sonatype-work/clm-cluster` directory for coordination
- **Dynamic Configuration**: config.yml generated per task with proper database configuration

**Important**: Ensure your Sonatype IQ Server license supports clustering for HA deployments.

## Security Features

- **VPC Isolation**: Application runs in private subnets across multiple AZs
- **Database Security**: Aurora cluster in isolated database subnets with Multi-AZ deployment
- **Secrets Management**: Database credentials stored in AWS Secrets Manager
- **Encryption**:
  - EFS encrypted at rest and in transit
  - Aurora encrypted at rest
  - S3 ALB logs encrypted
- **Security Groups**: Least-privilege network access
- **Work Directory Isolation**: Unique work directories per task prevent clustering conflicts

## Reliability and Backup

This is a **High Availability** deployment with comprehensive reliability features:

- **Multi-AZ Deployment**: ECS tasks and Aurora instances distributed across multiple availability zones
- **Auto Scaling**: ECS service scales between the minimum and maximum task counts for your size based on CPU/memory utilization. Size M is 2 to 3, Size L is 2 to 4, Size XL is 3 to 5
- **Aurora Cluster**: Multi-AZ database deployment with automatic failover (~30 seconds)
- **Automatic Restart**: ECS automatically restarts failed containers
- **Load Balancing**: ALB distributes traffic across healthy containers
- **Rolling Deployments**: Zero-downtime updates with 50% minimum healthy capacity
- **Database Backups**: Automated Aurora backups with 7-day retention (configurable)
- **EFS Backups**: Automated EFS backup with daily and weekly policies via AWS Backup
- **EFS Persistence**: Application data stored on EFS survives container restarts
- **Service Discovery**: Internal DNS for efficient inter-service communication

## Monitoring and Logging

This deployment includes **production-grade logging** with a unified CloudWatch approach:

### Structured Logging with Fluent Bit
- **Fluent Bit Sidecar**: Lightweight log processor running alongside each IQ Server task
- **5 Log Types Collected**: Application, request, audit, policy-violation, stderr
- **Aggregated to One CloudWatch Log Group**: All logs sent to `/ecs/${cluster_name}/nexus-iq-server`
- **Separated by Stream Prefix**: Each log type has its own stream prefix for easy filtering
- **Dual Output**: Logs written to both CloudWatch AND EFS for persistence

### CloudWatch Unified Log Group
- **Log Group**: `/ecs/${cluster_name}/nexus-iq-server`
- **Log Streams** (organized by prefix):
  - `application/` - Main IQ Server logs with multiline parsing
  - `request/` - HTTP request logs with field extraction
  - `audit/` - Audit events (JSON format)
  - `policy-violation/` - Policy violations (JSON format)
  - `stderr/` - System.err output for debugging
  - `fluent-bit/` - Fluent Bit internal logs

### EFS Aggregated Logs
- **Location**: `/var/log/nexus-iq-server/aggregated/`
- **Format**: JSON with ECS metadata enrichment

### Additional Monitoring
- **Container Insights**: ECS cluster monitoring enabled
- **Aurora Monitoring**: Performance Insights and Enhanced Monitoring enabled
- **Auto Scaling Metrics**: CPU and memory utilization tracking
- **ALB Access Logs**: Load balancer access logs stored in S3
- **OpenSearch Metrics**: `ClusterStatus`, `FreeStorageSpace`, `ClusterIndexWritesBlocked` and
  the rest published to CloudWatch by the service, plus the domain's two slow logs and its
  application log. No alarms are created; see the OpenSearch section above

## Persistent Storage

- **EFS File System**: Shared storage for clustering with unique work directories
- **Aurora Database**: PostgreSQL cluster for application data with continuous backups. Minimum PostgreSQL 16. Recommended, and the default for new deployments, PostgreSQL 18
- **Auto-scaling Storage**: Aurora storage scales automatically
- **AWS Backup**: Automated EFS backup with daily/weekly retention policies

## Networking

### Subnets
- **Public Subnets**: Load balancer and NAT gateways across multiple AZs
- **Private Subnets**: ECS Fargate tasks across multiple AZs
- **Database Subnets**: Aurora cluster instances (no internet access)

### Security Groups
- **ALB**: Allows HTTP (80) and HTTPS (443) from internet
- **ECS**: Allows traffic from ALB on port 8070, inter-task communication
- **Aurora**: Allows PostgreSQL (5432) from ECS tasks only
- **EFS**: Allows NFS (2049) from ECS tasks only

