# Sonatype IQ Reference Architecture - AWS Cloud-Native (Single Instance)

This directory contains Terraform configuration for deploying a **single-instance** Sonatype IQ Server on AWS using ECS Fargate.

---

## Sizing Guide

This single-instance architecture supports sizes **XS**, **S**, and **M**. Choose your size based on application count and daily evaluation volume:

| Size | Applications | Evaluations/Day | Compute | Java Heap | Instance Type | OpenSearch |
|------|:------------:|:---------------:|:-------:|:---------:|:-------------:|:----------:|
| **XS** ¹ | < 500 | < 1,000 | 2 vCPU / 16 GB | 12 GB | Fargate (2048 CPU / 16384 MEM) | Required ² |
| **S** ¹ | 500 - 2,000 | 1,000 - 5,000 | 4 vCPU / 30 GB | 22 GB | Fargate (4096 CPU / 30720 MEM) | Required ² |
| **M** | 2,000 - 10,000 | 5,000 - 10,000 | 8 vCPU / 60 GB | 44 GB | Fargate (8192 CPU / 61440 MEM) | Required ² |

> ¹ XS and S are projected sizing estimates. M has been validated through performance testing, which ran on a GCP ARM instance at 8 vCPU and 64 GB with a 48 GB heap rather than on a Fargate task. The 60 GB task and 44 GB heap above are the nearest shape Fargate allows, so treat the figures as indicative rather than measured at those values.

> **Why a 44 GB heap on a 60 GB task?** Fargate caps an 8 vCPU task at 60 GB, so a 48 GB heap plus `-XX:MaxDirectMemorySize=8g` would commit 56 GB of the 60, and `-XX:+AlwaysPreTouch` claims the whole heap at startup. 44 GB leaves 8 GB for the JVM's own non-heap memory and the rest of the container. Raising it back to 48 GB removes most of that margin. Size S is the same case: Fargate caps a 4 vCPU task at 30 GB, so S runs a 22 GB heap, which with `-XX:MaxDirectMemorySize=6g` commits 28 GB of the 30.

> ² Required for Advanced Search and the Nexus One index at every size, and not switched on for you: `search_engine` defaults to `lucene` in `variables.tf`, so a deployment that wants either feature sets it to `opensearch`, and this configuration then creates the domain. See [OpenSearch](#opensearch) for what it serves, what this architecture does and does not do about it, and the per-size cluster specification.

> **Need more capacity?** For 10,000+ applications or multi-node deployments, use the [High Availability](../infra-aws-ha/) or [Kubernetes](../infra-aws-ha-k8s-helm/) architectures.

### Recommended `terraform.tfvars` by Size

<details>
<summary><strong>Size XS</strong> — Extra Small (< 500 applications)</summary>

```hcl
ecs_cpu              = 2048                # 2 vCPU
ecs_memory           = 16384               # 16 GB
iq_desired_count     = 1
iq_docker_image      = "sonatype/nexus-iq-server:latest"
java_opts            = "-Xms12g -Xmx12g -XX:MaxDirectMemorySize=4g -XX:+UseG1GC -XX:+AlwaysPreTouch -Dinsight.threads.monitor=3 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_instance_class    = "db.m8g.large"      # 2 vCPU, 8 GB
db_allocated_storage = 64
```
</details>

<details>
<summary><strong>Size S</strong> — Small (500 – 2,000 applications)</summary>

```hcl
ecs_cpu              = 4096                # 4 vCPU
ecs_memory           = 30720               # 30 GB, the maximum at 4 vCPU
iq_desired_count     = 1
iq_docker_image      = "sonatype/nexus-iq-server:latest"
java_opts            = "-Xms22g -Xmx22g -XX:MaxDirectMemorySize=6g -XX:+UseG1GC -XX:+AlwaysPreTouch -Dinsight.threads.monitor=5 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_instance_class    = "db.r8g.large"      # 2 vCPU, 16 GB
db_allocated_storage = 128
```
</details>

<details>
<summary><strong>Size M</strong> — Medium (2,000 – 10,000 applications)</summary>

```hcl
ecs_cpu              = 8192                # 8 vCPU
ecs_memory           = 61440               # 60 GB, the maximum at 8 vCPU
iq_desired_count     = 1
iq_docker_image      = "sonatype/nexus-iq-server:latest"
java_opts            = "-Xms44g -Xmx44g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/Java_Heap_logs -XX:+CrashOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"
db_instance_class    = "db.r8g.2xlarge"    # 8 vCPU, 64 GB
db_allocated_storage = 128                 # auto-scales to 500 GB

# The M domain: three data nodes across three zones, which needs a third
# private subnet, and a third public one so the load balancer reaches a task in
# that zone. 10.0.30.0/24 is already db_subnet_cidrs[0].
public_subnet_cidrs                = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
private_subnet_cidrs               = ["10.0.10.0/24", "10.0.20.0/24", "10.0.50.0/24"]
search_engine                      = "opensearch"
opensearch_instance_type           = "m8g.large.search"
opensearch_instance_count          = 3
opensearch_volume_size_gb          = 100
opensearch_availability_zone_count = 3
opensearch_index_replicas          = 1
```
</details>

### Database Sizing

| Size | DB Instance Class | vCPU | Memory | Storage |
|------|:-----------------|:----:|:------:|:-------:|
| **XS** | db.m8g.large | 2 | 8 GB | 64 GB |
| **S** | db.r8g.large | 2 | 16 GB | 128 GB |
| **M** | db.r8g.2xlarge | 8 | 64 GB | 128 GB (auto-scales to 500 GB) |

### OpenSearch

IQ Server uses an OpenSearch cluster for Advanced Search and for the Nexus One index behind the Nexus
One list pages, typeahead, and dashboard, and **it is required at every size this architecture
supports.** One cluster serves both features, through a `search:` block and a `nexusOne.connection` block in IQ Server's
`config.yml` that name the same endpoint and credentials, with nothing extra to switch on per
feature.

On AWS the cluster is an **Amazon OpenSearch Service domain**, and IQ Server authenticates with AWS
SigV4 signed by the ECS task role, so there is no password to store. The task role needs the
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
| **XS** | 1 | `0` |
| **S** | 1 | `0` |
| **M** | 3 | `1` |

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
[domain shape table](#domain-shape-per-size) below. At M the component, violation and vulnerability indices are
created with 3 primary shards and every other index with 1; at XS and S every index has 1. The
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
opensearch_instance_count          = 1
opensearch_volume_size_gb          = 50
opensearch_availability_zone_count = 1
opensearch_index_replicas          = 0
```

`search_engine = "lucene"` is the default and needs none of the others.

To use a domain you already run, name it instead and nothing is created:

```hcl
search_engine              = "opensearch"
opensearch_domain_endpoint = "search-my-domain-abc123.us-east-1.es.amazonaws.com"
opensearch_domain_name     = "my-domain"
```

### `terraform destroy` will not delete the domain

The domain carries `prevent_destroy`, because it holds the index and rebuilding
one takes an hour or more on a large estate. A destroy fails while it is in
state, so removing it is deliberate:

```bash
DOMAIN=$(terraform output -raw opensearch_domain_name)
terraform state rm aws_opensearch_domain.nexus_one
aws opensearch delete-domain --domain-name "$DOMAIN"
# wait for the domain to finish deleting, which releases its interfaces
./tf-destroy.sh
```

Read the name first, because `state rm` removes it from state along with the
domain. `./tf-destroy.sh` rather than a bare `terraform destroy`, because the
script also force-deletes the database secret, which a plain destroy leaves in
its 7-day recovery window, blocking a re-apply under the same name.

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
own when a VPC domain is made through the console, so an account that has ever
held one already has it. Otherwise, once per account:

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
using that one and needs nothing. This configuration deliberately does not create
the role: AWS allows one per account while each deployment of this root is
separate, so whichever deployment owned it would delete it out from under the
others at teardown.

What the created domain gets, none of which needs configuring:

- **The private subnets of this VPC**, reachable on 443 from the ECS task and
  from nowhere else.
- **Encryption at rest and node to node**, and TLS 1.2 enforced.
- **An access policy naming the ECS task role and no other principal.** IQ
  Server signs its requests with SigV4 through that role.
- **No dedicated master nodes at one data node**, since there is no cluster
  state worth separating. Raising `opensearch_instance_count` above 1 adds
  three.

**Fine-grained access control has to stay off for as long as the domain holds this
index.** Turning it on gives the domain an internal user database and changes how
every request is authenticated, so SigV4 alone no longer reaches it and IQ Server's
`type: aws` configuration stops working. There is no credential to supply instead:
this architecture authenticates with the ECS task role and nothing else.

### Domain shape per size

| Size | Applications | Data nodes | Instance type | Heap | Storage per node | Masters | Zones | Shards ¹ | Replicas |
|------|:------------:|:----------:|:-------------:|:----:|:----------------:|:-------:|:-----:|:--------:|:--------:|
| **XS** | < 500 | 1 | `m8g.medium.search` | 2 GiB | 25 GB | none | 1 | 1 | 0 |
| **S** | 500 - 2,000 | 1 | `m8g.large.search` | 4 GiB | 50 GB | none | 1 | 1 | 0 |
| **M** | 2,000 - 10,000 | 3 | `m8g.large.search` | 4 GiB | 100 GB | 3 x `m8g.medium.search` | 3 | 3 | 1 |

¹ Primary shards for the component, violation and vulnerability indices. Every
other index keeps 1. See [What Terraform writes into `config.yml`](#what-terraform-writes-into-configyml)
for how to set them.

Heap is half of each node's memory, capped at 32 GiB. AWS sets it, and it is
not a setting this configuration can change.

**The data node type and count, masters, shards and replicas above are the
measured values at every size.** Storage per node is the published size, chosen
at or above the measured use. The measurements are on
[the OpenSearch sizing pages](https://sonatype.atlassian.net/wiki/spaces/INSIGHT/pages/2866971307)
and [CLM-55930](https://sonatype.atlassian.net/browse/CLM-55930).

At 0 replicas a lost node means the index is rebuilt rather than recovered.
That is the trade a one-node domain makes, and it is part of why XS and S are
marked projected in the sizing guide above. **A one-node domain reports yellow
and that is correct**: the index still takes writes and returns correct reads,
because yellow means a replica is unassigned rather than that data is missing.

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
hand.** OpenSearch writes these streams itself, so the service principal needs a
resource policy granting it `logs:PutLogEvents` and `logs:CreateLogStream` on the
groups. A resource policy is account-wide and AWS allows 10 per region, so a
deployment into an account already at that quota fails with
`LimitExceededException`. The answer is one policy covering every domain's log
groups, written once outside Terraform, and `opensearch_create_log_resource_policy
= false` in each deployment. That toggle skips the policy and nothing else: the
log groups and the domain's `log_publishing_options` are still created, so the
shared policy has groups to name. Setting it false with no such policy in the
account is not a working configuration, the domain create then fails on the
`log_publishing_options`.

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
  block the Nexus One index reads. With `search:` set and this one absent, the
  index store has no transport and turning the feature on is refused. Both name
  the same domain.

Shard counts are held in IQ Server's database, not in `config.yml`, and a
shard count only takes effect when an index is created. **At M, set the
component, violation and vulnerability indices to 3 shards before the
Nexus One index is first built**, with one request to the configuration API as
an administrator:

```bash
curl -u admin -X PUT -H 'Content-Type: application/json' \
  -d '{"nexusOneIndexComponentShards": 3, "nexusOneIndexViolationShards": 3, "nexusOneIndexVulnerabilityShards": 3}' \
  https://<your IQ Server URL>/api/v2/config
```

The other Nexus One indices and the Advanced Search index keep 1 shard, and XS
and S keep 1 for every index. An index built before the change keeps its count
until it is rebuilt.

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
- Ability to create: VPC, ECS, RDS, EFS, ALB, IAM roles

#### Required AWS Permissions
Your IAM user/role needs these AWS service permissions:
- **EC2**: VPC, subnets, security groups, network interfaces
- **ECS**: Clusters, task definitions, services
- **RDS**: Database instances, subnet groups, parameter groups
- **EFS**: File systems, mount targets, access points
- **ELB**: Application Load Balancers, target groups, listeners
- **IAM**: Roles, policies, instance profiles
- **Logs**: CloudWatch log groups
- **Secrets Manager**: Secrets creation and management
- **S3**: Terraform state storage (if using remote state)

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
   cd /path/to/sca-example-terraform/infra-aws
   cp terraform.tfvars.example terraform.tfvars
   ```

2. **Edit `terraform.tfvars` with your values (or leave to get started quickly):**
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

   This shows what resources will be created without actually deploying them.

3. **Deploy the infrastructure:**
   ```bash
   ./tf-apply.sh
   ```

   The script will display the application URL when complete.

### Step 5: Access Sonatype IQ Server

1. **Wait for service to be ready:**
   - Initial startup can take 5-10 minutes
   - Database migrations, if needed, run on first boot

2. **Access the web UI:**

   Use the application URL displayed at the end of the deployment.

   Example: `http://ref-arch-iq-alb-123456789.us-east-1.elb.amazonaws.com`

3. **Login credentials:**
   - **Username:** `admin`
   - **Password:** `admin123` (change immediately!)

---

## Teardown / Cleanup

**WARNING: This will delete ALL infrastructure and data!**

1. **Destroy all resources:**
   ```bash
   ./tf-destroy.sh
   ```

   > **Keep the terminal open** - If you close it mid-destroy, the process will potentially stop and leave resources partially deleted.

   > **Your OpenSearch domain is not deleted by this.** A domain this architecture created carries `prevent_destroy`, so `./tf-destroy.sh` stops rather than deleting it; the steps that remove it deliberately are in [`terraform destroy` will not delete the domain](#terraform-destroy-will-not-delete-the-domain). A domain named through `opensearch_domain_endpoint` was never created here and is not deleted here.

---

## Configuration

> **PostgreSQL version.** Minimum PostgreSQL 16. Recommended, and the default for new
> deployments, PostgreSQL 18. An existing deployment sets `postgres_version` in
> `terraform.tfvars` to the version it runs today, and one still on PostgreSQL 15 is below
> the minimum. Upgrading is the deployer's decision.

> **Upgrading an existing deployment.** These variable defaults changed with the
> published sizing. A deployment whose `terraform.tfvars` does not set a variable
> picks up the new default on its next apply. Set the values your deployment is
> running at in `terraform.tfvars` before applying.
>
> | Variable | Previous default | New default |
> |---|:---:|:---:|
> | `postgres_version` | 15.10 | 18.6 |
> | `ecs_memory` | 32768 | 61440 |
> | `java_opts` | 24 GB heap | 44 GB heap |
> | `db_instance_class` | db.r6g.2xlarge | db.r8g.2xlarge |
> | `db_allocated_storage` | 500 | 128. RDS cannot shrink storage, so an existing instance keeps its size here |
> | `db_max_allocated_storage` | 1000 | 500 |
>
> An instance class change applies in the next maintenance window, because this
> configuration does not set `apply_immediately`.

### Configuration Variables

Edit `terraform.tfvars` to customize your deployment:

```hcl
# General Configuration
aws_region  = "us-east-1"

# Base name for every resource this creates. Give each deployment its own value
# to run more than one in a single AWS account, one per size for example.
cluster_name = "ref-arch"

# Network Configuration
vpc_cidr               = "10.0.0.0/16"
public_subnet_cidrs    = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs   = ["10.0.10.0/24", "10.0.20.0/24"]
db_subnet_cidrs        = ["10.0.30.0/24", "10.0.40.0/24"]

# ECS Configuration
ecs_cpu           = 8192  # 8 vCPU
ecs_memory        = 61440 # 60 GB, the Size M value
iq_desired_count  = 1 # Single instance
iq_docker_image   = "sonatype/nexus-iq-server:latest"
java_opts         = "-Xms44g -Xmx44g -XX:MaxDirectMemorySize=8g -XX:+UseG1GC -XX:+AlwaysPreTouch -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/sonatype-work/Java_Heap_logs -XX:+CrashOnOutOfMemoryError -Dinsight.threads.monitor=10 -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"

# Database Configuration
db_name                     = "nexusiq"
db_username                 = "nexusiq"
db_password                 = "CHANGE_ME_STRONG_PASSWORD"  # Change this!
db_instance_class           = "db.r8g.2xlarge"
db_allocated_storage        = 128
db_max_allocated_storage    = 500
postgres_version            = "18.6"
db_backup_retention_period  = 7
db_backup_window           = "03:00-04:00"
db_maintenance_window      = "sun:04:00-sun:05:00"
db_skip_final_snapshot     = true
db_deletion_protection     = false

# Load Balancer Configuration
# ssl_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
alb_deletion_protection = false

# Logging Configuration
log_retention_days = 30

# Search Backend (optional)
# "lucene" (default) uses the index built into IQ Server. "opensearch" creates
# a domain here, or uses one you already run if you set
# opensearch_domain_endpoint. See the OpenSearch section above.
search_engine = "lucene"
# opensearch_domain_endpoint = "search-my-domain-abc123.us-east-1.es.amazonaws.com"
# opensearch_domain_name     = "my-domain"
# opensearch_index_replicas  = 0
```

**Important Settings:**
- **`iq_desired_count = 1`** - Keep this at 1. Only use a single Sonatype IQ Server instance
- **`db_password`** - Use a strong, unique password (required change)
- **`db_deletion_protection = false`** - Set to `true` for production to prevent accidental database deletion
- **`db_skip_final_snapshot = true`** - Set to `false` for production to create a final backup snapshot before database deletion
- **`alb_deletion_protection = false`** - Set to `true` for production use
- **Resource Names** - Controlled by the `cluster_name` variable, which defaults to `ref-arch`, so the ECS cluster is `ref-arch-iq-cluster` and the log group `/ecs/ref-arch-nexus-iq-server`. **Give each deployment its own value to run more than one in a single AWS account**, since the load balancer, target groups, IAM roles, log group, SSM parameters, Secrets Manager secret and RDS identifier all have to be unique. One value per size, for example `ref-arch-xs` through `ref-arch-m`, is the intended use.

## Security Features

- **VPC Isolation**: Application runs in private subnets
- **Database Security**: RDS in isolated database subnets
- **Secrets Management**: Database credentials stored in AWS Secrets Manager
- **Encryption**:
  - EFS encrypted at rest and in transit
  - RDS encrypted at rest
  - S3 ALB logs encrypted
- **Security Groups**: Least-privilege network access

## Reliability and Backup

This is a **single instance** deployment.
- **Single Instance**: One ECS Fargate task running Sonatype IQ Server (runs in one AZ at a time)
- **Single AZ Database**: RDS instance runs in one availability zone (no multi-AZ failover)
- **Multi-AZ Infrastructure**: Supporting resources (ALB, subnets, NAT gateways) span 2 availability zones for infrastructure resilience
- **Automatic Restart**: ECS automatically restarts the container if it fails (may restart in different AZ, causing brief downtime)
- **Database Backups**: Automated RDS backups with 7-day retention (configurable)
- **EFS Persistence**: Application data stored on EFS survives container restarts

## Monitoring and Logging

This deployment includes **production-grade logging** with a unified CloudWatch approach:

### Structured Logging with Fluent Bit
- **Fluent Bit Sidecar**: Lightweight log processor running alongside IQ Server
- **5 Log Types Collected**: Application, request, audit, policy-violation, stderr
- **Aggregated to One CloudWatch Log Group**: All logs sent to `/ecs/ref-arch-nexus-iq-server`
- **Separated by Stream Prefix**: Each log type has its own stream prefix for easy filtering
- **Dual Output**: Logs written to both CloudWatch AND EFS for persistence

### CloudWatch Unified Log Group
- **Log Group**: `/ecs/ref-arch-nexus-iq-server`
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
- **RDS Enhanced Monitoring**: Database performance metrics
- **ALB Access Logs**: Load balancer access logs stored in S3
- **OpenSearch Metrics**: `ClusterStatus`, `FreeStorageSpace`, `ClusterIndexWritesBlocked` and
  the rest published to CloudWatch by the service, plus the domain's two slow logs and its
  application log. No alarms are created; see the OpenSearch section above

## Persistent Storage

- **EFS File System**: Shared storage for `/sonatype-work` directory
- **Database**: PostgreSQL RDS for application data. Minimum PostgreSQL 16. Recommended, and the default for new deployments, PostgreSQL 18
- **Auto-scaling Storage**: RDS storage scales automatically up to configured limit

## Networking

### Subnets
- **Public Subnets**: Load balancer and NAT gateway
- **Private Subnets**: ECS Fargate tasks
- **Database Subnets**: RDS instance (no internet access)

### Security Groups
- **ALB**: Allows HTTP (80) and HTTPS (443) from internet
- **ECS**: Allows traffic from ALB on port 8070
- **RDS**: Allows PostgreSQL (5432) from ECS tasks only
- **EFS**: Allows NFS (2049) from ECS tasks only

