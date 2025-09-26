#!/bin/bash

# Terraform plan script for Azure IQ Server Single Instance deployment
# Usage: ./tf-plan.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
TERRAFORM_DIR="$(dirname "$0")"

echo -e "${BLUE}🏗️  Nexus IQ Server Single Instance - Azure Terraform Plan${NC}"
echo "========================================================="
echo ""

# Check if we're in the right directory
if [[ ! -f "main.tf" ]]; then
    echo -e "${RED}❌ Error: main.tf not found in current directory${NC}"
    echo "Please run this script from the infra-azure directory"
    exit 1
fi

# Check if terraform.tfvars exists
if [[ ! -f "terraform.tfvars" ]]; then
    echo -e "${YELLOW}⚠️  Warning: terraform.tfvars not found${NC}"
    echo "Creating from terraform.tfvars.example..."
    if [[ -f "terraform.tfvars.example" ]]; then
        cp terraform.tfvars.example terraform.tfvars
        echo -e "${YELLOW}📝 Please edit terraform.tfvars with your values before continuing${NC}"
        exit 1
    else
        echo -e "${RED}❌ Error: terraform.tfvars.example not found${NC}"
        echo "Please create terraform.tfvars with required variables"
        exit 1
    fi
fi

# Check if Azure CLI is installed and authenticated
if ! command -v az &> /dev/null; then
    echo -e "${RED}❌ Error: Azure CLI is not installed${NC}"
    echo "Please install Azure CLI: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

# Check Azure authentication
if ! az account show &> /dev/null; then
    echo -e "${RED}❌ Error: Not authenticated with Azure${NC}"
    echo "Please run: az login"
    exit 1
fi

# Display current Azure context
CURRENT_SUBSCRIPTION=$(az account show --query name -o tsv 2>/dev/null)
CURRENT_TENANT=$(az account show --query tenantId -o tsv 2>/dev/null)

echo -e "${GREEN}🔐 Azure Context:${NC}"
echo "   Subscription: $CURRENT_SUBSCRIPTION"
echo "   Tenant ID: $CURRENT_TENANT"
echo ""

# Check if Terraform is installed
if ! command -v terraform &> /dev/null; then
    echo -e "${RED}❌ Error: Terraform is not installed${NC}"
    echo "Please install Terraform: https://www.terraform.io/downloads.html"
    exit 1
fi

echo -e "${GREEN}🚀 Starting Terraform Plan...${NC}"
echo ""

# Initialize Terraform
echo -e "${BLUE}📦 Initializing Terraform...${NC}"
terraform init

echo ""
echo -e "${BLUE}✅ Validating Terraform configuration...${NC}"
terraform validate

echo ""
echo -e "${BLUE}📋 Formatting Terraform files...${NC}"
terraform fmt

echo ""
echo -e "${BLUE}🔍 Running Terraform Plan...${NC}"
echo ""

# Function to check if resource exists in Azure
check_resource_exists() {
    local resource_name="$1"
    az group show --name "$resource_name" >/dev/null 2>&1
}

# Run terraform plan with smart error handling
echo "Running terraform plan..."
if terraform plan -out=tfplan 2>&1 | tee plan_output.log; then
    echo ""
    echo -e "${GREEN}✅ Terraform Plan completed successfully!${NC}"
    echo ""
    echo -e "${BLUE}📊 Resources to be created:${NC}"
    echo "   • Resource Group with networking (VNet, Subnets, NSGs)"
    echo "   • PostgreSQL Flexible Server with private endpoint"
    echo "   • Container App Environment and Container App"
    echo "   • Azure Storage Account with File Share"
    echo "   • Application Gateway with public IP"
    echo "   • Key Vault for secrets management"
    echo "   • Log Analytics Workspace and Application Insights"
    echo ""
    echo -e "${YELLOW}📝 Plan saved to: tfplan${NC}"
    echo ""
    echo -e "${GREEN}🎯 Next Steps:${NC}"
    echo "   1. Review the plan output above"
    echo "   2. If everything looks correct, run: ./tf-apply.sh"
    echo "   3. Monitor deployment progress and logs"
    echo ""
    echo -e "${BLUE}💡 Useful Commands:${NC}"
    echo "   • View plan details: terraform show tfplan"
    echo "   • Estimate costs: az consumption budget list (if configured)"
    echo "   • Check resource limits: az vm list-usage --location 'East US'"
    echo ""
else
    # Check if the error is about existing resources
    if grep -q "already exists - to be managed via Terraform this resource needs to be imported" plan_output.log; then
        echo ""
        echo -e "${YELLOW}⚠️  Detected existing resources conflict${NC}"
        echo ""

        echo -e "${BLUE}🔍 Checking if resource actually exists in Azure...${NC}"

        if check_resource_exists "rg-ref-arch-iq"; then
            echo -e "${YELLOW}📦 Resource exists in Azure but not in Terraform state${NC}"
            echo ""
            echo -e "${BLUE}💡 Options:${NC}"
            echo "   1. Import existing: terraform import azurerm_resource_group.iq_rg /subscriptions/48a33158-a8cc-4938-84fd-e661939ed499/resourceGroups/rg-ref-arch-iq"
            echo "   2. Or delete and recreate: az group delete --name rg-ref-arch-iq --yes"
            echo "   3. Or start fresh: rm terraform.tfstate*"
        else
            echo -e "${RED}🚫 Resource doesn't exist in Azure - clearing stale state${NC}"
            echo ""
            echo -e "${BLUE}🔧 Auto-fixing stale state...${NC}"
            rm -f terraform.tfstate terraform.tfstate.backup
            echo -e "${GREEN}✅ Cleared stale state files${NC}"
            echo ""
            echo -e "${BLUE}🔄 Re-running plan...${NC}"
            terraform plan -out=tfplan
        fi
    else
        echo ""
        echo -e "${RED}❌ Terraform Plan failed!${NC}"
        echo ""
        echo -e "${YELLOW}🔧 Common Issues:${NC}"
        echo "   • Check terraform.tfvars for missing or invalid values"
        echo "   • Verify Azure subscription has sufficient permissions"
        echo "   • Ensure resource names are unique (Key Vault, Storage Account)"
        echo "   • Check Azure resource limits and quotas"
        echo ""
        exit 1
    fi
fi

# Clean up
rm -f plan_output.log