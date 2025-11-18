# Sonatype IQ Reference Architecture - Azure Container Apps (Single Instance)

This directory contains Terraform configuration for deploying a **single-instance** Sonatype IQ Server on Azure using Container Apps with Workload Profiles.

## Deployment Guide

### Step 1: Prerequisites

#### Required Tools
Install these tools on your local machine:

| Tool | Version | Installation | Purpose |
|------|---------|--------------|---------|
| **Terraform** | >= 1.0 | [Install Guide](https://developer.hashicorp.com/terraform/install) | Infrastructure as Code |
| **Azure CLI** | >= 2.0 | [Install Guide](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) | Azure API access |

#### Azure Account Requirements
- Azure subscription with Contributor access
- Ability to create: Resource Groups, Virtual Networks, Container Apps, PostgreSQL, Application Gateway
- Key Vault access for secrets management

#### Required Azure Permissions
Your Azure account needs permissions for these services:
- **Resource Groups**: Create and manage resource groups
- **Compute**: Container Apps, Container App Environments, Container App Environment Storage
- **Networking**: Virtual Networks, subnets, Network Security Groups, Application Gateways, Public IPs, Private DNS Zones
- **Database**: Azure Database for PostgreSQL Flexible Server, databases, firewall rules
- **Storage**: Storage Accounts, File Shares
- **Security**: Key Vault, Key Vault access policies, Managed Identities (system-assigned)
- **Monitoring**: Log Analytics workspaces, Application Insights

### Step 2: Configure Azure Credentials

**The provided scripts use Azure CLI for authentication.**

1. **Login to Azure:**
   ```bash
   az login
   ```

2. **Verify your subscription:**
   ```bash
   az account show
   ```

3. **Set subscription (if you have multiple):**
   ```bash
   az account set --subscription "<subscription-id-or-name>"
   ```

### Step 3: Configure Terraform Variables

1. **Copy the example configuration:**
   ```bash
   cd /path/to/sca-example-terraform/infra-azure
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

   This downloads required providers (Azure, etc.)

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

   Example: `http://ref-arch-iq-abc123.westus2.cloudapp.azure.com`

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

---

## Configuration

### Configuration Variables

Edit `terraform.tfvars` to customize your deployment:

```hcl
# General Configuration
azure_region = "West US 2"  # Use West US 2 to avoid GP tier quota restrictions in East US

# Network Configuration
vnet_cidr           = "10.0.0.0/16"
public_subnet_cidr  = "10.0.1.0/24"
private_subnet_cidr = "10.0.8.0/23"
db_subnet_cidr      = "10.0.30.0/24"

# Container App Configuration
container_cpu    = 4.0           # 4.0 vCPU
container_memory = "8Gi"         # 8GB RAM
iq_docker_image  = "sonatype/nexus-iq-server:latest"
java_opts        = "-Xms6g -Xmx6g -Djava.util.prefs.userRoot=/sonatype-work/javaprefs"

# Database Configuration
db_name                          = "nexusiq"
db_username                      = "nexusiq"
db_password                      = "YourSecurePassword123!"  # Change this!
postgres_version                 = "15"
db_sku_name                      = "MO_Standard_E16s_v3"  # Memory Optimized (16 vCores, 128GB RAM)
db_storage_mb                    = 524288                 # 512GB storage
db_auto_grow_enabled             = true
db_backup_retention_days         = 7
db_geo_redundant_backup_enabled  = false
db_high_availability_enabled     = false

# Application Gateway Configuration
app_gateway_sku_name = "Standard_v2"
app_gateway_sku_tier = "Standard_v2"
app_gateway_capacity = 2

# Storage Configuration
storage_account_tier             = "Standard"
storage_account_replication_type = "LRS"
file_share_quota                 = 500

# Monitoring Configuration
log_retention_days = 30
enable_monitoring  = true
```

**Important Settings:**
- **Single Instance** - Container App configured for exactly 1 replica (Sonatype IQ single instance requirement)
- **`db_password`** - Use a strong, unique password (required change)
- **`db_high_availability_enabled = false`** - Set to `true` for production to enable zone-redundant database
- **`db_geo_redundant_backup_enabled = false`** - Set to `true` for production for geo-redundant backups
- **Resource Names** - All Azure resources follow naming conventions (e.g., "rg-ref-arch-iq")

## Security Features

- **VNet Isolation**: Application runs in private subnets
- **Database Security**: PostgreSQL in isolated database subnet with private DNS
- **Secrets Management**: Database credentials stored in Azure Key Vault
- **Encryption**:
  - Azure File Share encrypted at rest
  - PostgreSQL encrypted at rest
  - Application Gateway SSL termination support
- **Network Security Groups**: Least-privilege network access
- **Managed Identity**: Container Apps use system-assigned identity for secure access

## Reliability and Backup

This is a **single instance** deployment.
- **Single Instance**: One Container App replica running Sonatype IQ Server (runs in one zone at a time)
- **Single Zone Database**: PostgreSQL Flexible Server runs in one availability zone (unless HA enabled)
- **Zone Redundancy Available**: Infrastructure can be made zone-redundant (Application Gateway, database HA)
- **Automatic Restart**: Container Apps automatically restarts the container if it fails (may restart in different zone, causing brief downtime)
- **Database Backups**: Automated PostgreSQL backups with 7-day retention (configurable)
- **File Share Persistence**: Application data stored on Azure File Share survives container restarts

## Monitoring and Logging

- **Log Analytics**: Application logs centralized in Log Analytics workspace
- **Container App Logs**: Application and system logs with structured logging
- **Application Gateway Logs**: Access logs and diagnostic information
- **Azure Monitor**: Optional monitoring and alerting

## Persistent Storage

- **Azure File Share**: Shared storage for `/sonatype-work` directory using SMB protocol
- **Database**: PostgreSQL Flexible Server for application data
- **Auto-scaling Storage**: PostgreSQL storage scales automatically

## Networking

### Subnets
- **Public Subnet**: Application Gateway
- **Private Subnet**: Container Apps (delegated to Container Apps infrastructure)
- **Database Subnet**: PostgreSQL Flexible Server (delegated to PostgreSQL)

### Security Groups
- **Public NSG**: Allows HTTP (80), HTTPS (443) from internet
- **Private NSG**: Allows HTTP/HTTPS traffic and Azure Load Balancer health probes
- **Database NSG**: Allows PostgreSQL (5432) from private subnet only

## Important: Admin Port 8071 Not Exposed

The admin port 8071 is configured within the IQ Server container but **not exposed externally** through the Application Gateway. Only the main application port 8070 is accessible via port 80.

**Admin port access** is available through Container App console/exec sessions if needed for troubleshooting.

