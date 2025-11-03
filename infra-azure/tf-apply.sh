#!/bin/bash

# Terraform apply script for Azure IQ Server Single Instance deployment
# Usage: ./tf-apply.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
TERRAFORM_DIR="$(dirname "$0")"

echo -e "${BLUE}🚀 Nexus IQ Server Single Instance - Azure Terraform Apply${NC}"
echo "========================================================"
echo ""

# Check if we're in the right directory
if [[ ! -f "main.tf" ]]; then
    echo -e "${RED}❌ Error: main.tf not found in current directory${NC}"
    echo "Please run this script from the infra-azure directory"
    exit 1
fi

# Check if plan file exists
if [[ ! -f "tfplan" ]]; then
    echo -e "${YELLOW}⚠️  Warning: tfplan file not found${NC}"
    echo "Running plan first..."
    ./tf-plan.sh
    echo ""
fi

# Pre-flight checks
echo -e "${GREEN}🔍 Pre-flight Checks:${NC}"

# Check Azure authentication
if ! az account show &> /dev/null; then
    echo -e "${RED}❌ Error: Not authenticated with Azure${NC}"
    echo "Please run: az login"
    exit 1
fi

# Display current Azure context
CURRENT_SUBSCRIPTION=$(az account show --query name -o tsv 2>/dev/null)
CURRENT_TENANT=$(az account show --query tenantId -o tsv 2>/dev/null)

echo "   ✅ Azure authentication active"
echo "   📍 Subscription: $CURRENT_SUBSCRIPTION"
echo "   🏢 Tenant: $CURRENT_TENANT"

# Check Terraform
if ! command -v terraform &> /dev/null; then
    echo -e "${RED}❌ Error: Terraform is not installed${NC}"
    exit 1
fi
echo "   ✅ Terraform available"

# Check terraform.tfvars
if [[ ! -f "terraform.tfvars" ]]; then
    echo -e "${RED}❌ Error: terraform.tfvars not found${NC}"
    echo "Please create terraform.tfvars or run tf-plan.sh first"
    exit 1
fi
echo "   ✅ Configuration file present"

echo ""

# Display deployment summary
echo -e "${BLUE}📋 Deployment Summary:${NC}"
echo "   🏗️  Infrastructure: Azure Single Instance Nexus IQ Server"
echo "   🌐 Region: $(grep '^azure_region' terraform.tfvars | cut -d'=' -f2 | tr -d ' \"' || echo 'East US')"
echo "   🗄️  Database: PostgreSQL Flexible Server"
echo "   📦 Compute: Azure Container Apps"
echo "   🔄 Load Balancer: Application Gateway"
echo "   💾 Storage: Azure File Share"
echo ""

# Auto-deployment (no confirmation required)
echo -e "${YELLOW}ℹ️  Deploying Azure resources automatically...${NC}"
echo ""

# Function to import existing resources automatically
import_existing_resource() {
    local resource_address="$1"
    local resource_id="$2"

    echo -e "${YELLOW}📥 Auto-importing existing resource: $resource_address${NC}"
    if terraform import "$resource_address" "$resource_id"; then
        echo -e "${GREEN}✅ Successfully imported: $resource_address${NC}"
        return 0
    else
        echo -e "${RED}❌ Failed to import: $resource_address${NC}"
        return 1
    fi
}


# Function to check if resource is already in terraform state
is_in_state() {
    local terraform_address="$1"
    terraform state show "$terraform_address" >/dev/null 2>&1
}

# Function to import a single resource synchronously (with visible output)
import_resource_sync() {
    local terraform_address="$1"
    local azure_id="$2"

    if is_in_state "$terraform_address"; then
        echo -e "${BLUE}ℹ️  Skipped: $terraform_address (already in state)${NC}"
        return 0
    else
        echo -e "${YELLOW}📥 Importing: $terraform_address${NC}"
        if terraform import "$terraform_address" "$azure_id" 2>&1 | grep -q "Import successful\|Resource already managed"; then
            echo -e "${GREEN}✅ Imported: $terraform_address${NC}"
            return 0
        else
            echo -e "${BLUE}ℹ️  Skipped: $terraform_address (doesn't exist in Azure)${NC}"
            return 1
        fi
    fi
}

# Function to proactively import all possible resources (optimized for speed)
import_all_resources() {
    echo -e "${BLUE}📥 Fast parallel resource import...${NC}"
    echo ""

    # Get current subscription ID dynamically
    local SUBSCRIPTION_ID=$(az account show --query id -o tsv 2>/dev/null)

    # Dynamically discover resource names from Azure if the resource group exists
    local STORAGE_ACCOUNT=""
    local KEY_VAULT=""

    if az group show --name rg-ref-arch-iq &>/dev/null; then
        STORAGE_ACCOUNT=$(az storage account list --resource-group rg-ref-arch-iq --query "[?starts_with(name, 'strefarchiq')].name" -o tsv 2>/dev/null | head -1)
        KEY_VAULT=$(az keyvault list --resource-group rg-ref-arch-iq --query "[?starts_with(name, 'kv-ref-arch-iq')].name" -o tsv 2>/dev/null | head -1)
    fi

    # Comprehensive resource list - ALL resources that may exist
    local critical_resources=(
        # Core infrastructure
        "azurerm_resource_group.iq_rg:/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/rg-ref-arch-iq"

        # Logging & Monitoring
        "azurerm_log_analytics_workspace.iq_logs:/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/rg-ref-arch-iq/providers/Microsoft.OperationalInsights/workspaces/log-ref-arch-iq"
        "azurerm_application_insights.iq_insights[0]:/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/rg-ref-arch-iq/providers/Microsoft.Insights/components/appi-ref-arch-iq"

        # Networking - VNet and Subnets
        "azurerm_virtual_network.iq_vnet:/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/rg-ref-arch-iq/providers/Microsoft.Network/virtualNetworks/vnet-ref-arch-iq"
        "azurerm_subnet.public_subnet:/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/rg-ref-arch-iq/providers/Microsoft.Network/virtualNetworks/vnet-ref-arch-iq/subnets/snet-public"
        "azurerm_subnet.private_subnet:/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/rg-ref-arch-iq/providers/Microsoft.Network/virtualNetworks/vnet-ref-arch-iq/subnets/snet-private"
        "azurerm_subnet.db_subnet:/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/rg-ref-arch-iq/providers/Microsoft.Network/virtualNetworks/vnet-ref-arch-iq/subnets/snet-database"

        # Network Security Groups
        "azurerm_network_security_group.public_nsg:/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/rg-ref-arch-iq/providers/Microsoft.Network/networkSecurityGroups/nsg-public"
        "azurerm_network_security_group.private_nsg:/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/rg-ref-arch-iq/providers/Microsoft.Network/networkSecurityGroups/nsg-private"
        "azurerm_network_security_group.db_nsg:/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/rg-ref-arch-iq/providers/Microsoft.Network/networkSecurityGroups/nsg-database"

        # NSG Associations (use subnet ID as the import ID)
        "azurerm_subnet_network_security_group_association.public_nsg_association:/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/rg-ref-arch-iq/providers/Microsoft.Network/virtualNetworks/vnet-ref-arch-iq/subnets/snet-public"
        "azurerm_subnet_network_security_group_association.private_nsg_association:/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/rg-ref-arch-iq/providers/Microsoft.Network/virtualNetworks/vnet-ref-arch-iq/subnets/snet-private"
        "azurerm_subnet_network_security_group_association.db_nsg_association:/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/rg-ref-arch-iq/providers/Microsoft.Network/virtualNetworks/vnet-ref-arch-iq/subnets/snet-database"

        # Public IP
        "azurerm_public_ip.app_gateway_pip:/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/rg-ref-arch-iq/providers/Microsoft.Network/publicIPAddresses/pip-ref-arch-iq-appgw"

        # Private DNS
        "azurerm_private_dns_zone.iq_db_dns:/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/rg-ref-arch-iq/providers/Microsoft.Network/privateDnsZones/privatelink.postgres.database.azure.com"
        "azurerm_private_dns_zone_virtual_network_link.iq_db_dns_link:/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/rg-ref-arch-iq/providers/Microsoft.Network/privateDnsZones/privatelink.postgres.database.azure.com/virtualNetworkLinks/vnetlink-ref-arch-iq-db"

        # Application Gateway
        "azurerm_application_gateway.iq_app_gateway:/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/rg-ref-arch-iq/providers/Microsoft.Network/applicationGateways/appgw-ref-arch-iq"

        # Container Apps
        "azurerm_container_app_environment.iq_env:/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/rg-ref-arch-iq/providers/Microsoft.App/managedEnvironments/cae-ref-arch-iq"
        "azurerm_container_app.iq_app:/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/rg-ref-arch-iq/providers/Microsoft.App/containerApps/ca-ref-arch-iq"

        # Database
        "azurerm_postgresql_flexible_server.iq_db:/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/rg-ref-arch-iq/providers/Microsoft.DBforPostgreSQL/flexibleServers/psql-ref-arch-iq"
        "azurerm_postgresql_flexible_server_database.iq_database:/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/rg-ref-arch-iq/providers/Microsoft.DBforPostgreSQL/flexibleServers/psql-ref-arch-iq/databases/nexusiq"
    )

    # Add storage account if found
    if [[ -n "$STORAGE_ACCOUNT" ]]; then
        critical_resources+=("azurerm_storage_account.iq_storage:/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/rg-ref-arch-iq/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT}")
    fi

    # Add key vault if found
    if [[ -n "$KEY_VAULT" ]]; then
        critical_resources+=("azurerm_key_vault.iq_kv:/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/rg-ref-arch-iq/providers/Microsoft.KeyVault/vaults/${KEY_VAULT}")
    fi

    echo -e "${YELLOW}🚀 Starting sequential imports...${NC}"
    echo ""

    local imported_count=0
    local skipped_count=0

    # Import resources sequentially with visible output
    for resource in "${critical_resources[@]}"; do
        local terraform_address="${resource%%:*}"
        local azure_id="${resource#*:}"

        if import_resource_sync "$terraform_address" "$azure_id"; then
            if is_in_state "$terraform_address"; then
                imported_count=$((imported_count + 1))
            else
                skipped_count=$((skipped_count + 1))
            fi
        else
            skipped_count=$((skipped_count + 1))
        fi
    done

    echo ""
    echo -e "${GREEN}📊 Import Summary: $imported_count imported, $skipped_count skipped${NC}"
    echo ""
}

# Run comprehensive import then apply
echo -e "${GREEN}🚀 Starting deployment...${NC}"
echo ""

# First, import everything that might exist
import_all_resources

# After imports, regenerate the plan since state may have changed
echo -e "${BLUE}📋 Regenerating plan after imports...${NC}"
if terraform plan -out=tfplan; then
    echo -e "${GREEN}✅ Plan regenerated${NC}"
    echo ""
else
    echo -e "${RED}❌ Failed to regenerate plan${NC}"
    exit 1
fi

# Then run terraform apply (simplified, no import error handling needed)
if terraform apply -auto-approve tfplan; then
    echo ""
    echo -e "${GREEN}🎉 Deployment completed successfully!${NC}"
    echo ""

    # Extract outputs
    APPLICATION_URL=$(terraform output -raw application_url 2>/dev/null || echo "Not available")
    RESOURCE_GROUP=$(terraform output -raw resource_group_name 2>/dev/null || echo "Not available")
    DATABASE_NAME=$(terraform output -raw db_server_name 2>/dev/null || echo "Not available")

    echo -e "${BLUE}📊 Deployment Results:${NC}"
    echo "   🌐 Application URL: $APPLICATION_URL"
    echo "   📦 Resource Group: $RESOURCE_GROUP"
    echo "   🗄️  Database Server: $DATABASE_NAME"
    echo ""

    echo -e "${GREEN}🎯 Next Steps:${NC}"
    echo "   1. Wait 5-10 minutes for full application startup"
    echo "   2. Access Nexus IQ Server at: $APPLICATION_URL"
    echo "   3. Login with default credentials (admin/admin123)"
    echo "   4. Configure your IQ Server settings"
    echo ""

    echo -e "${BLUE}📊 Monitoring Commands:${NC}"
    echo "   # Check Container App status"
    echo "   az containerapp show --name \$(terraform output -raw container_app_id | cut -d'/' -f9) --resource-group $RESOURCE_GROUP"
    echo ""
    echo "   # View Container App logs"
    echo "   az containerapp logs show --name \$(terraform output -raw container_app_id | cut -d'/' -f9) --resource-group $RESOURCE_GROUP --follow"
    echo ""
    echo "   # Check Application Gateway health"
    echo "   az network application-gateway show --name \$(terraform output -raw application_gateway_id | cut -d'/' -f9) --resource-group $RESOURCE_GROUP"
    echo ""
    echo "   # View Log Analytics workspace"
    echo "   az monitor log-analytics workspace show --workspace-name \$(terraform output -raw log_analytics_workspace_name) --resource-group $RESOURCE_GROUP"
    echo ""

    echo -e "${YELLOW}🔐 Security Notes:${NC}"
    echo "   • Database credentials are stored in Azure Key Vault"
    echo "   • Container App uses system-assigned managed identity"
    echo "   • All traffic between components uses private networking"
    echo "   • Enable HTTPS by providing SSL certificate in variables"
    echo ""

    echo -e "${BLUE}🏗️  For High Availability setup:${NC}"
    echo "   Consider the infra-azure-ha version for production workloads"
    echo "   (Multi-region, auto-scaling, enhanced monitoring)"
    echo ""

else
    echo ""
    echo -e "${RED}❌ Deployment failed!${NC}"
    echo ""
    echo -e "${YELLOW}🔧 Troubleshooting:${NC}"
    echo "   • Check the error messages above"
    echo "   • Verify Azure subscription limits and quotas"
    echo "   • Ensure resource names are globally unique"
    echo "   • Check terraform.tfvars for correct values"
    echo ""
    echo -e "${BLUE}📊 Diagnostic Commands:${NC}"
    echo "   • View current state: terraform state list"
    echo "   • Check resource status: az resource list --resource-group $RESOURCE_GROUP"
    echo "   • View activity log: az monitor activity-log list --resource-group $RESOURCE_GROUP"
    echo ""
    exit 1
fi