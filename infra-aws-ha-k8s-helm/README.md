# Sonatype IQ Reference Architecture - AWS EKS with Helm (High Availability)

This directory contains Terraform configuration for deploying Sonatype IQ Server on AWS using EKS (Elastic Kubernetes Service) with Helm in a **High Availability configuration** with auto-scaling and multi-AZ deployment.

---

## Sizing Guide

This EKS HA architecture supports sizes **M**, **L**, and **XL**. Choose your size based on application count and daily evaluation volume:

| Size | Applications | Evaluations/Day | Nodes | Compute (per node) | Java Heap | Instance Type | OpenSearch |
|------|:------------:|:---------------:|:-----:|:-------------------:|:---------:|:-------------:|:----------:|
| **M** | 2,000 - 10,000 | 5,000 - 10,000 | 2 | 8 vCPU / 64 GB | 48 GB | r9g.2xlarge (ARM) | Required ¹ |
| **L** | 10,000 - 20,000 | 10,000 - 20,000 | 3 | 8 vCPU / 64 GB | 48 GB | r9g.2xlarge (ARM) | Required ¹ |
| **XL** | 20,000 - 80,000 | 20,000+ | 4 | 16 vCPU / 128 GB | 96 GB | r9g.4xlarge (ARM) | Required ¹ |

> All sizes validated through performance testing, which ran on GCP ARM instances at the shapes in the table above: 8 vCPU and 64 GB with a 48 GB heap for M and L, and 16 vCPU and 128 GB with a 96 GB heap for XL. Expected evaluation throughput with continuous monitoring running: ~310 evals/hour/node (M/L) or ~405 evals/hour/node (XL).

<!-- TO BE UPDATED (CLM-55927): the ~310 and ~405 evals/hour figures above are awaiting a
     re-measurement. Leave the numbers alone until it lands. The qualifier that they are measured with
     continuous monitoring running was added so a reader does not take them as general evaluation
     throughput. -->

> ¹ OpenSearch is part of this architecture at every size, not an optional extra. See [OpenSearch](#opensearch) for what it serves, what this architecture does and does not do about it, and the per-size cluster specification.

> **ARM instances recommended.** r9g (Graviton5) costs 8% less than the x86 equivalent (r8i) on demand in us-east-1, at list prices in November 2026. The node AMI follows the instance architecture, so both ARM and x86 types deploy.

> **Smaller deployments?** For < 2,000 applications with a single instance, use the [Single Instance](../infra-aws/) architecture.

### Recommended `terraform.tfvars` by Size

<details>
<summary><strong>Size M</strong> — Medium (2,000 – 10,000 applications, 2 nodes)</summary>

```hcl
node_instance_type      = "r9g.2xlarge"    # 8 vCPU, 64 GB (ARM)
node_group_desired_size = 2
node_group_min_size     = 2
node_group_max_size     = 3
nexus_iq_replica_count  = 2                # 2 IQ pods
nexus_iq_memory_request = "48Gi"
nexus_iq_memory_limit   = "56Gi"
nexus_iq_cpu_request    = "6"
nexus_iq_cpu_limit      = "8"
aurora_instance_class   = "db.r8g.2xlarge" # 8 vCPU, 64 GB
aurora_instance_count   = 2
```
</details>

<details>
<summary><strong>Size L</strong> — Large (10,000 – 20,000 applications, 3 nodes)</summary>

```hcl
node_instance_type      = "r9g.2xlarge"    # 8 vCPU, 64 GB (ARM)
node_group_desired_size = 3
node_group_min_size     = 2
node_group_max_size     = 5
nexus_iq_replica_count  = 3                # 3 IQ pods
nexus_iq_memory_request = "48Gi"
nexus_iq_memory_limit   = "56Gi"
nexus_iq_cpu_request    = "6"
nexus_iq_cpu_limit      = "8"
aurora_instance_class   = "db.r8g.2xlarge" # 8 vCPU, 64 GB
aurora_instance_count   = 2
```
</details>

<details>
<summary><strong>Size XL</strong> — Extra Large (20,000 – 80,000 applications, 4 nodes)</summary>

```hcl
node_instance_type      = "r9g.4xlarge"    # 16 vCPU, 128 GB (ARM)
node_group_desired_size = 4
node_group_min_size     = 3
node_group_max_size     = 6
nexus_iq_replica_count  = 4                # 4 IQ pods
nexus_iq_memory_request = "96Gi"
nexus_iq_memory_limit   = "112Gi"
nexus_iq_cpu_request    = "12"
nexus_iq_cpu_limit      = "16"
aurora_instance_class   = "db.r8g.4xlarge" # 16 vCPU, 128 GB
aurora_instance_count   = 2
```
</details>

### Database Sizing (Aurora PostgreSQL)

| Size | Aurora Instance Class | vCPU | Memory | Storage |
|------|:--------------------|:----:|:------:|:-------:|
| **M** | db.r8g.2xlarge | 8 | 64 GB | 100 GB (auto-scales to 500 GB) |
| **L** | db.r8g.2xlarge | 8 | 64 GB | 200 GB – 1 TB auto-scaling |
| **XL** | db.r8g.4xlarge | 16 | 128 GB | 500 GB – 2 TB auto-scaling |

### Shared Storage (EFS)

All sizes use Amazon EFS with Elastic throughput mode. Enable lifecycle policies to move files older than 30 days to Infrequent Access (IA) for ~92% storage savings.

| Size | Estimated Capacity |
|------|:------------------:|
| **M** | 200 GB – 500 GB |
| **L** | 500 GB – 1.5 TB |
| **XL** | 1.5 TB – 4 TB |

### OpenSearch

IQ Server uses an OpenSearch cluster for Advanced Search and for the Nexus One index behind the Nexus
One list pages, typeahead, and dashboard, and **it is required at every size this architecture
supports.** One cluster serves both features, through a single `search:` block in IQ Server's
`config.yml`: one endpoint, one set of credentials, and nothing extra to switch on per feature.

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
survivable. **IQ Server's own default depends on the release.** Releases that include
CLM-55924 use 1 replica, or 0 on a cluster with exactly one data node. Earlier releases use 0.
So this architecture sets `nexusOneIndexReplicas` itself rather than inheriting that
default:

| Size | OpenSearch data nodes | Replica count |
|------|:---------------------:|:-------------:|
| **M** | 2 | `1` |
| **L** | 2 | `1` |
| **XL** | 2 | `1` |

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
created with 3 primary shards and every other index with 1; at XS and S every index has 1. The
shard counts are set through the configuration API before the first build, as shown there.

See the [top-level OpenSearch section](../README.md#opensearch) for the full planning rules.

---

## OpenSearch for the Nexus One Index

Sonatype IQ Server can keep its Nexus One index in an AWS-managed OpenSearch
domain instead of the index built into the server. Set `search_engine` to
`opensearch` and this configuration creates the domain:

```hcl
search_engine                      = "opensearch"
opensearch_instance_type           = "m8g.large.search"
opensearch_instance_count          = 2
opensearch_volume_size_gb          = 100
opensearch_availability_zone_count = 2
opensearch_index_replicas          = 1
```

`search_engine = "lucene"` is the default and needs none of the others.

To use a domain you already run, name it instead and nothing is created:

```hcl
search_engine              = "opensearch"
opensearch_domain_endpoint = "search-my-domain-abc123.us-east-1.es.amazonaws.com"
opensearch_domain_name     = "my-domain"
```

**On this architecture OpenSearch is the index that every pod shares.** The
built-in index lives on each pod's own storage, so a set of replicas keeps a
copy each and each copy is rebuilt separately. An OpenSearch domain is one
index all the pods read and write.

### `terraform destroy` will not delete the domain

The domain carries `prevent_destroy`, because it holds the index and rebuilding
one takes an hour or more on a large estate. A destroy fails while it is in
state, so removing it is deliberate:

```bash
terraform state rm aws_opensearch_domain.nexus_one
aws opensearch delete-domain --domain-name <the domain>
# wait for the domain to finish deleting, which releases its interfaces
terraform destroy
```

The `state rm` is what gets past `prevent_destroy`. The delete is what lets the
rest of the teardown finish: the domain's network interfaces sit in this VPC's
private subnets and hold its security group, so destroying the VPC around a live
domain fails on `DependencyViolation`.

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

- **The private subnets of this VPC**, one per Availability Zone it spreads
  across, reachable on 443 from the EKS node security groups alone.
- **Encryption at rest and node to node**, and TLS 1.2 enforced.
- **An access policy naming the pods' IRSA role and no other principal**, so
  nothing has to be wired up by hand after the apply. The pods sign with SigV4
  through that role, and `iq_server_irsa_role_arn` outputs it.
- **Three dedicated master nodes** whenever there is more than one data node,
  which keeps cluster state off the nodes serving queries.

**Fine-grained access control has to stay off for as long as the domain holds this
index.** Turning it on gives the domain an internal user database and changes how
every request is authenticated, so SigV4 alone no longer reaches it and IQ Server's
`type: aws` configuration stops working. There is no credential to supply instead:
this architecture authenticates with the pods' IAM role and nothing else.

### How the configuration reaches IQ Server

Terraform does not write `config.yml` here. The Helm chart builds it from the
`iq_server.config` block in `helm-values.yaml`, and `helm-install.sh` prepares
that file at install time:

1. It reads the `search_engine`, `opensearch_domain_endpoint` and
   `opensearch_index_replicas` outputs.
2. With `opensearch`, it fills in the three placeholders inside the
   `# BEGIN search backend` block and points the `nexus-iq-sa` service account
   at `iq_server_irsa_role_arn`.
3. With `lucene`, it deletes that whole block, so `config.yml` carries no
   `search:` key at all.
4. Either way it then fails if any placeholder survived, rather than installing
   a chart with a literal placeholder in it.

`helm-upgrade.sh` does the same. **Do not rename the keys inside that block.**
Both scripts substitute `hostname`, `port`, `name`, `username`, `password` and
`region` across the whole file with no line anchor, for the database and for
CloudWatch, so a search key called `hostname` would be handed the database
endpoint.

### Domain shape per size

| Size | Applications | Data nodes | Instance type | Heap | Storage per node | Masters | Zones | Shards ¹ | Replicas |
|------|:------------:|:----------:|:-------------:|:----:|:----------------:|:-------:|:-----:|:--------:|:--------:|
| **M** | 2,000 - 10,000 | 2 | `m8g.large.search` | 4 GiB | 100 GB | 3 x `m8g.medium.search` | 2 | 3 | 1 |
| **L** | 10,000 - 20,000 | 2 | `m8g.xlarge.search` | 8 GiB | 150 GB | 3 x `m8g.medium.search` | 2 | 3 | 1 |
| **XL** | 20,000 - 80,000 | 2 | `r8g.2xlarge.search` | 32 GiB | 250 GB | 3 x `m8g.large.search` | 2 | 3 | 1 |

¹ Primary shards for the component, violation and vulnerability indices. Every
other index keeps 1. See [What Terraform writes into `config.yml`](#what-terraform-writes-into-configyml)
for how to set them.

Heap is half of each node's memory, capped at 32 GiB. AWS sets it, and it is
not a setting this configuration can change.

**These are starting points, not measured results.** Sizing per size is being
measured under
[CLM-55930](https://sonatype.atlassian.net/browse/CLM-55930). Measure your own
estate until it reports.

**Two zones, because that is what this architecture builds.** `main.tf` creates
two private subnets, and the domain needs one subnet per zone, so two is the
most it can spread across. Two nodes with one replica keeps a complete copy of
the index in each zone, and a node count has to divide evenly by the zone count
or AWS refuses the domain. Three zones needs a third private subnet in `main.tf`
first; `opensearch.tf` refuses the plan rather than failing inside `slice()`.

**Storage holds more than one copy of the index.** A replica doubles it, a
rebuild holds a second generation for the whole run and for 30 minutes after
cutover, and AWS reserves 20% of each volume capped at 20 GiB. The figures
above allow for all three.

### Where the domain's own logs go

Three CloudWatch log groups per domain, written by OpenSearch itself:

| Log group | Holds |
|---|---|
| `/aws/opensearch/<cluster_name>-nexus-one/search_slow_logs` | Searches past the index's slow threshold |
| `/aws/opensearch/<cluster_name>-nexus-one/index_slow_logs` | Writes past the index's slow threshold |
| `/aws/opensearch/<cluster_name>-nexus-one/es_application_logs` | What the cluster itself saw: rejected writes, cluster state changes, errors behind a 5xx |

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
slow logging off per index, so set a threshold on the index to get any rows:

```bash
curl -XPUT "https://<endpoint>/<index>/_settings" -H 'Content-Type: application/json' -d '{
  "index.search.slowlog.threshold.query.warn": "2s",
  "index.indexing.slowlog.threshold.index.warn": "2s"
}'
```

The application log needs nothing and fills on its own.

**Audit logs are not available here.** They need fine-grained access control,
which this architecture cannot turn on without breaking SigV4.

### What ends up in `config.yml`

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

- **`type: aws`** signs every request with SigV4 through the pod's role.
  `type: http` always sends a user name and password, which a domain with
  fine-grained access control off has no way to check.
- **`mode: OPENSEARCH`** is written out rather than left to default. The
  default is `HYBRID`, which also writes every batch to the built-in index.
- **`nexusOneIndexReplicas`** is always written, because IQ Server's own
  default depends on the release. Releases that include CLM-55924 use 1
  replica, or 0 on a domain with exactly one data node. Earlier releases use
  0. Writing the value gives the same count on every release.
- **`nexusOne.connection` repeats the same fields** because it is the only
  block the Nexus One index reads. With `search:` set and this one absent, the
  index store has no transport and turning the feature on is refused. Both name
  the same domain.

Shard counts are held in IQ Server's database, not in `config.yml`, and a
shard count only takes effect when an index is created. **At M, L and XL, set
the component, violation and vulnerability indices to 3 shards before the
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
| **Terraform** | >= 1.0 | [Install Guide](https://developer.hashicorp.com/terraform/install) | Infrastructure as Code |
| **AWS CLI** | >= 2.0 | [Install Guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) | AWS API access |
| **aws-vault** | Latest | [Install Guide](https://github.com/99designs/aws-vault#installing) | Secure credential management |
| **kubectl** | Latest | [Install Guide](https://kubernetes.io/docs/tasks/tools/) | Kubernetes cluster management |
| **Helm** | >= 3.9.3 | [Install Guide](https://helm.sh/docs/intro/install/) | Application deployment |

#### AWS Account Requirements
- AWS account with administrative access (or sufficient permissions listed below)
- IAM user with MFA enabled
- Ability to create: VPC, EKS, RDS Aurora, EFS, ALB, IAM roles

#### Required AWS Permissions
Your IAM user/role needs these AWS service permissions:
- **EC2**: VPC, subnets, security groups, network interfaces, EIPs, NAT gateways
- **EKS**: Clusters, node groups, add-ons (CoreDNS, kube-proxy, VPC CNI, EBS CSI, EFS CSI), OIDC providers
- **RDS**: Aurora clusters, instances, subnet groups, parameter groups
- **EFS**: File systems, mount targets, access points, backup policies
- **ELB**: Application Load Balancers, target groups, listeners
- **IAM**: Roles, policies, OIDC providers
- **Auto Scaling**: Launch configurations, auto scaling groups (for EKS node groups)
- **KMS**: Keys and aliases for encryption (RDS, EFS)
- **Logs**: CloudWatch log groups and streams
- **Secrets Manager**: Secrets creation and management
- **SSM Parameter Store**: Parameters for storing database credentials and EFS IDs
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
   cd /path/to/sca-example-terraform/infra-aws-ha-k8s-helm
   cp terraform.tfvars.example terraform.tfvars
   ```

2. **Edit `terraform.tfvars` with your values (or leave to get started quickly):**
   ```bash
   vi terraform.tfvars
   ```

### Step 4: Deploy Infrastructure and Application

1. **Initialize Terraform:**
   ```bash
   terraform init
   ```

   This downloads required providers (AWS, Kubernetes, Helm, etc.)

2. **Review the deployment plan:**
   ```bash
   ./tf-plan.sh
   ```

   This shows what resources will be created without actually deploying them.

3. **Deploy the infrastructure:**
   ```bash
   ./tf-apply.sh
   ```

   This creates the EKS cluster, Aurora database, EFS, and networking.

4. **Install IQ Server using Helm:**
   ```bash
   ./helm-install.sh
   ```

   This script:
   - Configures kubectl to access the EKS cluster
   - Retrieves database credentials from AWS Secrets Manager
   - Installs the official Sonatype Helm chart
   - Configures ingress and load balancer

### Step 5: Access Sonatype IQ Server

1. **Wait for service to be ready:**
   - Initial startup can take 10-15 minutes
   - All pods must complete database migrations and clustering setup

2. **Access the web UI:**

   Use the application URL displayed at the end of the Helm deployment.

   Example: `http://k8s-nexusiq-12345-67890.us-east-1.elb.amazonaws.com`

3. **Login credentials:**
   - **Username:** `admin`
   - **Password:** `admin123` (change immediately!)

---

## Teardown / Cleanup

> **Your OpenSearch domain is not deleted by this.** A domain this architecture created carries `prevent_destroy`, so `./tf-destroy.sh` stops rather than deleting it; the steps that remove it deliberately are in [`terraform destroy` will not delete the domain](#terraform-destroy-will-not-delete-the-domain). A domain named through `opensearch_domain_endpoint` was never created here and is not deleted here.

**WARNING: This will delete ALL infrastructure and data!**

1. **Uninstall the Helm deployment:**
   ```bash
   ./helm-uninstall.sh
   ```

2. **Destroy all infrastructure:**
   ```bash
   ./tf-destroy.sh
   ```

   > **Keep the terminal open** - If you close it mid-destroy, the process will potentially stop and leave resources partially deleted.

---

## Configuration

> **Upgrading an existing deployment.** These variable defaults changed with the
> published sizing. A deployment whose `terraform.tfvars` does not set a variable
> picks up the new default on its next apply. Set the values your deployment is
> running at in `terraform.tfvars` before applying.
>
> | Variable | Previous default | New default |
> |---|:---:|:---:|
> | `aurora_engine_version` | 15.8 | 15.19 |
> | `iq_server.resources` in `helm-values.yaml` | 4 to 6 CPU, 16 to 24 GB | 6 to 8 CPU, 48 to 56 GB |
> | `iq_server.javaOpts` in `helm-values.yaml` | 24 GB heap | 48 GB heap |

### Configuration Variables

Edit `terraform.tfvars` to customize your deployment:

```hcl
# AWS Configuration
aws_region  = "us-east-1"
environment = "prod"

# Cluster Configuration
cluster_name = "nexus-iq-ha"
vpc_cidr     = "10.0.0.0/16"

# EKS Configuration
kubernetes_version       = "1.30"
node_instance_type      = "m9gd.2xlarge"
node_group_min_size     = 2
node_group_max_size     = 5
node_group_desired_size = 3
node_disk_size          = 50

# RDS Aurora Configuration
aurora_engine_version   = "15.19"
aurora_instance_class   = "db.r8g.4xlarge"
aurora_instance_count   = 2
database_name           = "nexusiq"
database_username       = "nexusiq"
database_password       = "CHANGE_ME_STRONG_PASSWORD"  # Change this!
backup_retention_period = 7
skip_final_snapshot     = true
deletion_protection     = false

# EFS Configuration
efs_provisioned_throughput = 100

# Nexus IQ Server Configuration
nexus_iq_version       = "1.195.0"
nexus_iq_license       = ""
nexus_iq_admin_password = "admin123"
nexus_iq_replica_count = 3

# Resource Limits
nexus_iq_memory_request = "48Gi"
nexus_iq_memory_limit   = "56Gi"
nexus_iq_cpu_request    = "6"
nexus_iq_cpu_limit      = "8"

# Helm Configuration
helm_chart_version = "195.0.0"
helm_namespace     = "nexus-iq"

# Logging Configuration
enable_fluentd        = true
enable_cloudwatch_logs = true

# Ingress Configuration
enable_ingress_nginx = true
ingress_hostname     = "nexus-iq.yourdomain.com"
ingress_tls_enabled  = false
acm_certificate_arn  = ""

# Search Backend (optional)
# "lucene" (default) uses the index built into IQ Server. "opensearch" creates
# a domain here, or uses one you already run if you set
# opensearch_domain_endpoint. See the OpenSearch section above.
search_engine = "lucene"
# opensearch_domain_endpoint = "search-my-domain-abc123.us-east-1.es.amazonaws.com"
# opensearch_domain_name     = "my-domain"
# opensearch_index_replicas  = 1

# Extra tags merged onto the resources the search backend creates. Keep the
# keys lowercase, and keep the values in terraform.tfvars rather than in
# terraform.tfvars.example.
# common_tags = {
#   owner      = "REPLACE-ME@example.com"
#   project    = "REPLACE-ME"
#   subproject = "REPLACE-ME"
#   department = "REPLACE-ME"
#   team       = "REPLACE-ME"
# }
```

Pod count and pod autoscaling are Helm chart values, set in `helm-values.yaml`:

```yaml
iq_server:
  replicas: 3          # Set from nexus_iq_replica_count in terraform.tfvars. Size L. Size M uses 2 and Size XL uses 4
hpa:
  enabled: true
  minReplicas: 2       # Size L. Size M uses 2 and Size XL uses 3
  maxReplicas: 4       # Size L. Size M uses 3 and Size XL uses 5
```

> **Upgrading an existing deployment.** Earlier installs ran 2 pods with no autoscaler. The next
> `helm-upgrade.sh` moves them to the values above, so before upgrading, set `nexus_iq_replica_count`
> in `terraform.tfvars` and the `hpa` block in `helm-values.yaml` to what the deployment runs.

**Important Settings:**
- **`nexus_iq_replica_count = 3`** - Initial number of IQ pods, the Size L value. Size M uses 2 and Size XL uses 4
- **`hpa.minReplicas` in `helm-values.yaml`** - Minimum auto scaling capacity, 2 for Size M and L. Size XL uses 3, and every size must be at least 2 for HA
- **`hpa.maxReplicas` in `helm-values.yaml`** - Maximum auto scaling capacity, 4 for Size L. Size M uses 3 and Size XL uses 5
- **`aurora_instance_count = 2`** - Number of Aurora instances (minimum 2 for HA)
- **`database_password`** - Use a strong, unique password (required change)
- **`nexus_iq_license`** - Base64 encoded HA-capable license
- **`deletion_protection = false`** - Set to `true` for production to prevent accidental database deletion
- **`skip_final_snapshot = true`** - Set to `false` for production to create a final backup snapshot before database deletion
- **Resource Names** - All AWS resources are prefixed with the `cluster_name` variable, which defaults to `nexus-iq-ha`. **Give each deployment its own value to run more than one in a single AWS account**, since the EKS cluster, load balancer, IAM roles, log group, SSM parameters, Secrets Manager secret and Aurora cluster identifier all have to be unique. One value per size, for example `nexus-iq-m` through `nexus-iq-xl`, is the intended use.

### Clustering Solution

This deployment leverages Kubernetes and Helm for IQ Server clustering:

- **Pod Distribution**: Kubernetes pod anti-affinity ensures replicas run on different nodes across AZs
- **Shared Storage**: EFS provides consistent storage across all replicas with proper locking
- **Database Sharing**: All replicas connect to the shared Aurora cluster via Kubernetes secrets
- **Service Discovery**: Kubernetes service provides stable DNS and load balancing

**Important**: Ensure your Sonatype IQ Server license supports clustering for HA deployments.

## Security Features

- **VPC Isolation**: Application runs in private subnets across multiple AZs
- **Database Security**: Aurora cluster in isolated database subnets with Multi-AZ deployment
- **Secrets Management**: Database credentials stored in Kubernetes secrets (sourced from AWS Secrets Manager)
- **Encryption**:
  - EFS encrypted at rest and in transit
  - Aurora encrypted at rest
  - EBS encryption for EKS node storage
- **Security Groups**: Least-privilege network access
- **RBAC**: Kubernetes role-based access control
- **IRSA**: IAM Roles for Service Accounts for pod-level AWS permissions

## Reliability and Backup

This is a **High Availability** deployment with comprehensive reliability features:

- **Multi-AZ Deployment**: EKS nodes, pods, and Aurora instances distributed across multiple availability zones
- **Horizontal Pod Autoscaler (HPA)**: IQ pods scale between the minimum and maximum for your size. Size M is 2 to 3, Size L is 2 to 4, Size XL is 3 to 5
- **Node Auto Scaling**: EKS node groups scale from 2-5 nodes based on pod resource requests
- **Aurora Cluster**: Multi-AZ database deployment with automatic failover (~30 seconds)
- **Automatic Restart**: Kubernetes automatically restarts failed pods
- **Pod Disruption Budgets**: Maintains availability during updates and node maintenance
- **Rolling Updates**: Zero-downtime updates with controlled rollout
- **Database Backups**: Automated Aurora backups with 7-day retention (configurable)
- **EFS Persistence**: Application data stored on EFS survives pod restarts

## Monitoring and Logging

This deployment includes **production-grade logging** with a unified CloudWatch approach:

### Structured Logging with Fluentd
- **Fluentd Sidecars**: Lightweight log forwarders in each IQ Server pod
- **Fluentd Aggregator**: Central aggregator pod (DaemonSet) receives logs from sidecars
- **5 Log Types Collected**: Application, request, audit, policy-violation, stderr
- **Aggregated to One CloudWatch Log Group**: All logs sent to `/eks/${cluster_name}/nexus-iq-server`
- **Separated by Stream Prefix**: Each log type has its own stream prefix for easy filtering
- **IRSA Authentication**: Fluentd uses IAM Roles for Service Accounts to write to CloudWatch

### CloudWatch Unified Log Group
- **Log Group**: `/eks/${cluster_name}/nexus-iq-server`
- **Log Streams** (organized by prefix):
  - `application/` - Main IQ Server logs
  - `request/` - HTTP request logs
  - `audit/` - Audit events (JSON format)
  - `policy-violation/` - Policy violations (JSON format)
  - `stderr/` - System.err output for debugging
  - `fluentd/` - Fluentd internal logs

### Additional Monitoring
- **Kubernetes Metrics**: Pod CPU/memory usage via `kubectl top`
- **HPA Metrics**: Horizontal Pod Autoscaler metrics
- **Aurora Monitoring**: Performance Insights and Enhanced Monitoring enabled
- **EKS Control Plane Logs**: Audit, authenticator, controller logs
- **OpenSearch Metrics**: `ClusterStatus`, `FreeStorageSpace`, `ClusterIndexWritesBlocked` and
  the rest published to CloudWatch by the service, plus the domain's two slow logs and its
  application log. No alarms are created; see the OpenSearch section above

## Persistent Storage

- **EFS File System**: Shared storage for clustering with Kubernetes CSI driver
- **Aurora Database**: PostgreSQL cluster for application data with continuous backups
- **Auto-scaling Storage**: Aurora storage scales automatically
- **EBS Volumes**: Node storage encrypted at rest

## Networking

### Subnets
- **Public Subnets**: Load balancer and NAT gateways across multiple AZs
- **Private Subnets**: EKS worker nodes across multiple AZs
- **Database Subnets**: Aurora cluster instances (no internet access)

### Security Groups
- **ALB**: Allows HTTP (80) and HTTPS (443) from internet
- **EKS Nodes**: Allows traffic from ALB, inter-node communication
- **Aurora**: Allows PostgreSQL (5432) from EKS nodes only
- **EFS**: Allows NFS (2049) from EKS nodes only

