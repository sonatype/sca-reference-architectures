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

# Function to handle terraform apply with auto-import
run_terraform_apply() {
    local apply_output
    local exit_code

    echo -e "${BLUE}🚀 Running terraform apply...${NC}"

    # Run terraform apply and capture output
    apply_output=$(terraform apply -auto-approve tfplan 2>&1)
    exit_code=$?

    # Always show the output to user
    echo "$apply_output"

    # Check if apply failed due to existing resources that need importing
    if [[ $exit_code -ne 0 ]] && echo "$apply_output" | grep -q "already exists - to be managed via Terraform this resource needs to be imported"; then
        echo ""
        echo -e "${YELLOW}⚠️  Detected existing resources that need to be imported${NC}"
        echo -e "${BLUE}🔄 Attempting automatic import...${NC}"
        echo ""

        # Try to import the most common resources that cause this issue
        local imported_any=false

        # Check for Application Gateway import needed
        if echo "$apply_output" | grep -q "azurerm_application_gateway.*already exists"; then
            local app_gw_id="/subscriptions/48a33158-a8cc-4938-84fd-e661939ed499/resourceGroups/rg-ref-arch-iq/providers/Microsoft.Network/applicationGateways/appgw-ref-arch-iq"

            echo -e "${YELLOW}📥 Importing Application Gateway...${NC}"
            if terraform import azurerm_application_gateway.iq_app_gateway "$app_gw_id" >/dev/null 2>&1; then
                echo -e "${GREEN}✅ Successfully imported Application Gateway${NC}"
                imported_any=true
            else
                echo -e "${RED}❌ Failed to import Application Gateway${NC}"
            fi
        fi

        # Check for Resource Group import needed
        if echo "$apply_output" | grep -q "azurerm_resource_group.*already exists"; then
            local rg_id="/subscriptions/48a33158-a8cc-4938-84fd-e661939ed499/resourceGroups/rg-ref-arch-iq"

            echo -e "${YELLOW}📥 Importing Resource Group...${NC}"
            if terraform import azurerm_resource_group.iq_rg "$rg_id" >/dev/null 2>&1; then
                echo -e "${GREEN}✅ Successfully imported Resource Group${NC}"
                imported_any=true
            else
                echo -e "${RED}❌ Failed to import Resource Group${NC}"
            fi
        fi

        # Check for Container App import needed
        if echo "$apply_output" | grep -q "azurerm_container_app.*already exists"; then
            local ca_id="/subscriptions/48a33158-a8cc-4938-84fd-e661939ed499/resourceGroups/rg-ref-arch-iq/providers/Microsoft.App/containerApps/ca-ref-arch-iq"

            echo -e "${YELLOW}📥 Importing Container App...${NC}"
            if terraform import azurerm_container_app.iq_app "$ca_id" >/dev/null 2>&1; then
                echo -e "${GREEN}✅ Successfully imported Container App${NC}"
                imported_any=true
            else
                echo -e "${RED}❌ Failed to import Container App${NC}"
            fi
        fi

        # If we imported anything, retry the apply
        if [[ "$imported_any" == "true" ]]; then
            echo ""
            echo -e "${BLUE}🔄 Retrying terraform apply after imports...${NC}"
            echo ""
            terraform apply -auto-approve tfplan
            return $?
        else
            echo -e "${RED}❌ No resources were imported successfully${NC}"
            echo -e "${YELLOW}💡 You may need to manually import resources${NC}"
            return 1
        fi
    else
        return $exit_code
    fi
}

# Run terraform apply with auto-import handling
echo -e "${GREEN}🚀 Starting deployment...${NC}"
echo ""

if run_terraform_apply; then
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