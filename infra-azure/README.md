# Nexus IQ Server Azure Infrastructure

This directory contains Terraform configuration for deploying Nexus IQ Server on Azure using Container Apps as part of a **Reference Architecture for Native Cloud Deployments**.

## Architecture Overview

This infrastructure deploys a complete, production-ready Nexus IQ Server environment including:

- **Azure Container Apps** - Serverless containerized Nexus IQ Server deployment
- **Application Gateway** - HTTP load balancer with health checks and SSL termination
- **PostgreSQL Flexible Server** - Managed database with encryption and automated backups
- **Azure File Share** - Shared persistent storage for Nexus IQ data with proper access controls
- **Virtual Network & Networking** - Complete network infrastructure with public/private subnets
- **Network Security Groups** - Least-privilege network access controls
- **Managed Identity** - Service-specific permissions following Azure best practices
- **Log Analytics** - Centralized logging for monitoring and troubleshooting
- **Key Vault** - Secure database credential storage

```
Internet
    ↓
Application Gateway (Public Subnet)
    ↓
Container Apps (Private Subnet) ←→ Azure File Share (Persistent Storage)
    ↓
PostgreSQL Flexible Server (Database Subnet)
```

## Prerequisites

### Required Tools
- **Terraform** >= 1.0
- **Azure CLI** >= 2.0

### Azure Account Requirements
- Azure subscription with Contributor access
- Ability to create resource groups and resources
- Key Vault access for secrets management

## Azure Configuration Setup

### 1. Azure CLI Authentication

Ensure you're authenticated with Azure CLI:

```bash
# Login to Azure
az login

# Verify your subscription
az account show
```

### 2. Verify Access

Test your Azure access:
```bash
az account list-locations --query "[?name=='East US']"
```

This should return location information for East US region.

## Quick Start

1. **Navigate to the infrastructure directory**:
   ```bash
   cd /path/to/sca-example-terraform/infra-azure
   ```

2. **Review and customize variables**:
   ```bash
   # Copy and edit terraform.tfvars with your specific values
   cp terraform.tfvars.example terraform.tfvars
   vim terraform.tfvars
   ```

3. **Initialize Terraform**:
   ```bash
   terraform init
   ```

4. **Plan the deployment**:
   ```bash
   ./tf-plan.sh
   ```

5. **Deploy the infrastructure**:
   ```bash
   ./tf-apply.sh
   ```

6. **Access your Nexus IQ Server**:
   - Get the application URL: `terraform output`
   - Wait 5-10 minutes for service to be ready
   - Default credentials: `admin` / `admin123`

## Configuration

### 1. Review Variables in terraform.tfvars

Edit `terraform.tfvars` to customize your deployment:

```hcl
# General Configuration
azure_region = "East US"

# Network Configuration
vnet_cidr           = "10.0.0.0/16"
public_subnet_cidr  = "10.0.1.0/24"
private_subnet_cidr = "10.0.8.0/23"
db_subnet_cidr      = "10.0.30.0/24"

# Container App Configuration
container_cpu      = 2.0           # 2.0 vCPU
container_memory   = "4Gi"         # 4GB RAM
iq_docker_image    = "sonatypecommunity/nexus-iq-server:latest"

# Database Configuration
db_name                          = "nexusiq"
db_username                      = "nexusiq"
db_password                      = "YourSecurePassword123!"  # Change this!
db_sku_name                      = "B_Standard_B2s"
postgres_version                 = "15"
```

### 2. Important Settings

- **Single Instance** - Container App configured for exactly 1 replica (hardcoded for Nexus IQ requirements)
- **`db_password`** - Use a strong, unique password
- **Resource Names** - All Azure resources follow naming conventions (e.g., "rg-ref-arch-iq")
- **`environment`** - Used as suffix for all resource names

## Security Features

- **VNet Isolation**: Application runs in private subnets
- **Database Security**: PostgreSQL in isolated database subnet with private DNS
- **Secrets Management**: Database credentials stored in Azure Key Vault
- **Encryption**:
  - Azure File Share encrypted at rest
  - PostgreSQL encrypted at rest
  - Application Gateway SSL termination
- **Network Security Groups**: Least-privilege network access
- **Managed Identity**: Container Apps use system-assigned identity

## High Availability

- **Zone Redundancy**: Resources can be deployed across availability zones
- **Auto Scaling**: Container Apps can scale based on demand (single instance for IQ)
- **Database Backup**: Automated backups with configurable retention
- **Load Balancing**: Application Gateway distributes traffic with health probes

## Monitoring and Logging

- **Log Analytics**: Application logs centralized in Log Analytics workspace
- **Application Insights**: Optional APM monitoring for performance metrics
- **Container App logs**: Application and system logs with structured logging
- **Application Gateway logs**: Access logs and diagnostic information

## Persistent Storage

- **Azure File Share**: Shared storage for `/sonatype-work` directory
- **Database**: PostgreSQL Flexible Server for application data
- **Auto-scaling Storage**: PostgreSQL storage scales automatically

## Cost Optimization

- **Container Apps**: Pay-per-use serverless container compute
- **PostgreSQL**: Right-sized instance with storage auto-scaling
- **Storage Account**: LRS replication for cost efficiency
- **Resource Tagging**: All resources tagged for cost allocation

## Networking

### Subnets
- **Public Subnet**: Application Gateway
- **Private Subnet**: Container Apps (delegated)
- **Database Subnet**: PostgreSQL Flexible Server (delegated)

### Network Security Groups
- **Public NSG**: Allows HTTP (80), HTTPS (443) from internet, management traffic
- **Private NSG**: Allows HTTP/HTTPS traffic and Azure Load Balancer health probes
- **Database NSG**: Allows PostgreSQL (5432) from private subnet

## Automated Deployment Scripts

This infrastructure includes convenient scripts that handle Azure authentication automatically:

### Available Scripts

- **`./tf-plan.sh`** - Preview infrastructure changes with Azure CLI authentication
- **`./tf-apply.sh`** - Deploy infrastructure with Azure CLI authentication
- **`./tf-destroy.sh`** - Destroy infrastructure with automatic cleanup

### How the Scripts Work

1. **Use Azure CLI** for authentication
2. **Handle credentials automatically** - use current Azure CLI session
3. **Include safety features** - validation checks and confirmations
4. **Provide operational guidance** - post-deployment commands and monitoring

### Manual Terraform Commands (Alternative)

If you prefer to run Terraform commands manually:

```bash
# Initialize Terraform
terraform init

# Plan deployment
terraform plan

# Apply configuration
terraform apply

# Show outputs
terraform output

# Destroy infrastructure
terraform destroy
```

## Accessing the Application

### 1. Get Deployment Information

```bash
terraform output
```

Example output:
```
application_url = "http://ref-arch-iq-abc123.eastus.cloudapp.azure.com"
resource_group_name = "rg-ref-arch-iq"
application_gateway_fqdn = "ref-arch-iq-abc123.eastus.cloudapp.azure.com"
db_server_name = "psql-ref-arch-iq"
```

### 2. Access the Application

1. **Wait for service to be ready** (5-10 minutes after deployment)
2. **Open the application URL** from terraform output
3. **Default credentials**: `admin` / `admin123`
4. **Complete setup wizard** on first access

### 3. Monitor Deployment Status

Check Container App status:
```bash
az containerapp show \
  --name ca-ref-arch-iq \
  --resource-group rg-ref-arch-iq
```

View application logs:
```bash
az containerapp logs show \
  --name ca-ref-arch-iq \
  --resource-group rg-ref-arch-iq \
  --follow
```

## Azure Portal Access

Monitor your infrastructure in the Azure Portal:

- **Container App**: Container Apps → `ca-ref-arch-iq`
- **Database**: Azure Database for PostgreSQL → `psql-ref-arch-iq`
- **Application Gateway**: Application Gateways → `appgw-ref-arch-iq`
- **Logs**: Log Analytics workspaces → `log-ref-arch-iq`
- **Virtual Network**: Virtual networks → `vnet-ref-arch-iq`
- **Storage**: Storage accounts → Search for `strefarchiq`

## File Structure

```
infra-azure/
├── main.tf                  # VNet, networking, and core infrastructure
├── container_app.tf         # Container App Environment and Container App
├── database.tf              # PostgreSQL Flexible Server and configuration
├── application_gateway.tf   # Application Gateway and Public IP
├── storage.tf               # Storage Account and File Share
├── key_vault.tf             # Key Vault for secrets management
├── variables.tf             # Input variable definitions
├── outputs.tf               # Output value definitions
├── terraform.tfvars.example # Infrastructure configuration template
├── tf-apply.sh              # Deployment script with Azure CLI support
├── tf-plan.sh               # Planning script with Azure CLI support
├── tf-destroy.sh            # Cleanup script with Azure CLI support
└── README.md                # This file
```

## Troubleshooting

### Common Issues

1. **Azure CLI Authentication Fails**
   ```bash
   # Re-authenticate with Azure
   az login

   # Verify your subscription
   az account show
   ```

2. **Container App Not Starting**
   ```bash
   # Check container logs
   az containerapp logs show \
     --name ca-ref-arch-iq \
     --resource-group rg-ref-arch-iq \
     --follow
   ```
   - **Database connection errors**: Check Key Vault secrets and network connectivity
   - **File share mount errors**: Verify storage account access and file share permissions

3. **Application Not Accessible**
   - Wait 5-10 minutes for Container App to fully start
   - Check Application Gateway backend health in Azure Portal
   - Verify Network Security Group rules allow HTTP traffic

4. **Database Connection Issues**
   - Verify database credentials in Key Vault
   - Check PostgreSQL server status in Azure Portal
   - Ensure Container App can reach database subnet

5. **Resource Naming Conflicts**
   ```bash
   # If you get "name already exists" errors:
   # Key Vault and Storage Account names must be globally unique
   # Adjust the random suffixes or change environment name
   ```

### Resource Limits

- **Container App**: Limited to 1 replica (Nexus IQ requirement)
- **Database**: Uses B_Standard_B2s SKU for cost efficiency
- **Storage**: Azure File Share provides scalable storage

## Cleanup

### Complete Infrastructure Removal

Remove all Azure resources:
```bash
./tf-destroy.sh
```

This will:
- Prompt for confirmation with safety checks
- Automatically clean up Key Vault secrets
- Destroy all Terraform-managed resources
- Provide manual cleanup commands if needed

### Partial Cleanup

Stop only the Container App (keeps data):
```bash
terraform destroy -target=azurerm_container_app.iq_app
```

**Warning**: Complete cleanup will permanently delete all data including the database. Ensure you have backups if needed.

## Azure Container Apps Port Limitation

### **Important: Admin Port 8071 Limitation**

**Azure Container Apps ingress has specific port exposure limitations:**

- **Primary Port**: Container Apps ingress exposes one primary external port (currently port 8070 via port 80)
- **Additional Ports**: While Azure supports up to 5 additional TCP ports, these have significant restrictions:
  - Only work with VNET-integrated environments
  - Must be unique across the entire Container Apps environment
  - Limited to basic TCP (no HTTP features like health probes)
  - Require CLI extension and special configuration

**Current Configuration Impact:**
- ✅ **Main application access**: Works perfectly via Application Gateway port 80 with full HTTP support
- ❌ **Admin port 8071 health checks**: **NOT possible** - additional ports don't support Application Gateway HTTP health probes
- ❌ **Admin port external access**: Would require complex additional port configuration with limited functionality

**Admin port 8071 is accessible:**
- Within the container itself (internal communication)
- Via Container App exec/debug sessions
- **NOT recommended for external access** due to Azure Container Apps additional port limitations

**Reference**: [Azure Container Apps Ingress Documentation](https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview)

## Production Considerations

For production deployments, consider:

1. **SSL/TLS Certificate**: Add SSL certificate for HTTPS
2. **Custom Domain**: Configure DNS for custom domain name
3. **Backup Strategy**: Review PostgreSQL backup settings
4. **Monitoring**: Add Azure Monitor alerts and dashboards
5. **High Availability**: Consider zone redundancy for database
6. **Resource Sizing**: Adjust CPU/memory based on usage patterns
7. **Network Security**: Restrict Application Gateway access to specific IP ranges
8. **Database Protection**: Enable high availability and geo-redundant backups
9. **Admin Access**: Plan alternative admin access methods (Container App exec, logs analysis)

## Reference Architecture

This infrastructure serves as a **Reference Architecture for Native Cloud Deployments** demonstrating:

- **Cloud-native patterns**: Serverless containers, managed services
- **Security best practices**: Network isolation, encryption, secrets management
- **Operational excellence**: Centralized logging, monitoring, automation
- **Cost optimization**: Right-sized resources, efficient scaling
- **Reliability**: Health probes, automated backups, zone redundancy

## Support

For issues with this infrastructure:
1. Check the troubleshooting section above
2. Review Azure Monitor logs and metrics
3. Verify Azure CLI authentication and permissions
4. Consult the [Nexus IQ Server documentation](https://help.sonatype.com/iqserver)

For Terraform-specific issues:
- Review the [Terraform AzureRM Provider documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- Check [Azure service documentation](https://docs.microsoft.com/en-us/azure/) for specific services