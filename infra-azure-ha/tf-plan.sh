#!/bin/bash

# Terraform plan script for Nexus IQ Server High Availability deployment on Azure
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

echo -e "${BLUE}🏗️  Nexus IQ Server HA - Azure Terraform Plan${NC}"
echo "======================================================="
echo ""

# Check if we're in the right directory
if [[ ! -f "main.tf" ]]; then
    echo -e "${RED}❌ Error: main.tf not found in current directory${NC}"
    echo "Please run this script from the infra-azure-ha directory"
    exit 1
fi

# Check if terraform.tfvars exists
if [[ ! -f "terraform.tfvars" ]]; then
    echo -e "${YELLOW}⚠️  Warning: terraform.tfvars not found${NC}"
    echo "Creating from terraform.tfvars.example..."
    if [[ -f "terraform.tfvars.example" ]]; then
        cp terraform.tfvars.example terraform.tfvars
        echo -e "${YELLOW}📝 Please edit terraform.tfvars with your HA values before continuing${NC}"
        exit 1
    else
        echo -e "${RED}❌ Error: terraform.tfvars.example not found${NC}"
        echo "Please create terraform.tfvars with required HA variables"
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

echo -e "${GREEN}🚀 Starting HA Terraform Plan...${NC}"
echo ""

# Validate HA configuration
echo -e "${BLUE}🔍 Validating HA configuration...${NC}"

# Check for minimum replicas
MIN_REPLICAS=$(grep "iq_min_replicas" terraform.tfvars | cut -d'=' -f2 | tr -d ' "')
MAX_REPLICAS=$(grep "iq_max_replicas" terraform.tfvars | cut -d'=' -f2 | tr -d ' "')

if [ "$MIN_REPLICAS" -lt 2 ]; then
    echo -e "${RED}❌ ERROR: HA deployment requires minimum 2 replicas (current: $MIN_REPLICAS)${NC}"
    echo "   Please set iq_min_replicas = 2 or higher in terraform.tfvars"
    exit 1
fi

# Check for zone-redundant database
DB_HA_MODE=$(grep "db_high_availability_mode" terraform.tfvars | cut -d'=' -f2 | tr -d ' "')
if [ "$DB_HA_MODE" != "ZoneRedundant" ]; then
    echo -e "${YELLOW}⚠️  WARNING: Database HA mode is not ZoneRedundant (current: $DB_HA_MODE)${NC}"
    echo "   For true HA, set db_high_availability_mode = \"ZoneRedundant\""
fi

# Check for zone-redundant storage
STORAGE_REPLICATION=$(grep "storage_account_replication_type" terraform.tfvars | cut -d'=' -f2 | tr -d ' "')
if [ "$STORAGE_REPLICATION" != "ZRS" ]; then
    echo -e "${YELLOW}⚠️  WARNING: Storage is not zone-redundant (current: $STORAGE_REPLICATION)${NC}"
    echo "   For true HA, set storage_account_replication_type = \"ZRS\""
fi

echo -e "${GREEN}✅ HA Configuration Valid:${NC}"
echo "   📊 Container Replicas: $MIN_REPLICAS-$MAX_REPLICAS"
echo "   🗄️  Database HA: $DB_HA_MODE"
echo "   💾 Storage Redundancy: $STORAGE_REPLICATION"
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
echo -e "${BLUE}🔍 Running Terraform Plan for HA infrastructure...${NC}"
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
    echo -e "${GREEN}✅ Terraform HA Plan completed successfully!${NC}"
    echo ""
    echo -e "${BLUE}📊 HA Resources to be created:${NC}"
    echo "   • Resource Group with multi-zone networking (VNet, Subnets, NSGs)"
    echo "   • Zone-redundant PostgreSQL Flexible Server with automatic failover"
    echo "   • Container App Environment with 2-10 auto-scaling replicas"
    echo "   • Premium Azure Storage Account with Zone-Redundant Storage (ZRS)"
    echo "   • Zone-redundant Application Gateway across 3 availability zones"
    echo "   • Key Vault for secrets management with network isolation"
    echo "   • Log Analytics Workspace and Application Insights for monitoring"
    echo "   • KEDA-based auto-scaling rules (CPU, Memory, HTTP requests)"
    echo ""
    echo -e "${YELLOW}📝 Plan saved to: tfplan${NC}"
    echo ""
    echo -e "${GREEN}🎯 Next Steps:${NC}"
    echo "   1. Review the HA plan output above"
    echo "   2. If everything looks correct, run: ./tf-apply.sh"
    echo "   3. Monitor HA deployment progress and replica status"
    echo ""
    echo -e "${BLUE}💡 Useful HA Commands:${NC}"
    echo "   • View plan details: terraform show tfplan"
    echo "   • Estimate costs: az consumption budget list (if configured)"
    echo "   • Check resource limits: az vm list-usage --location 'East US'"
    echo "   • Monitor replicas: az containerapp replica list --resource-group <rg> --name <app>"
    echo ""
else
    # Check if the error is about existing resources
    if grep -q "already exists - to be managed via Terraform this resource needs to be imported" plan_output.log; then
        echo ""
        echo -e "${YELLOW}⚠️  Detected existing HA resources conflict${NC}"
        echo ""

        echo -e "${BLUE}🔍 Checking if resource actually exists in Azure...${NC}"

        if check_resource_exists "rg-ref-arch-iq-ha"; then
            echo -e "${YELLOW}📦 HA Resource exists in Azure but not in Terraform state${NC}"
            echo ""
            echo -e "${BLUE}💡 Options:${NC}"
            echo "   1. Import existing: terraform import azurerm_resource_group.iq_rg /subscriptions/{subscription-id}/resourceGroups/rg-ref-arch-iq-ha"
            echo "   2. Or delete and recreate: az group delete --name rg-ref-arch-iq-ha --yes"
            echo "   3. Or start fresh: rm terraform.tfstate*"
        else
            echo -e "${RED}🚫 HA Resource doesn't exist in Azure - clearing stale state${NC}"
            echo ""
            echo -e "${BLUE}🔧 Auto-fixing stale state...${NC}"
            rm -f terraform.tfstate terraform.tfstate.backup
            echo -e "${GREEN}✅ Cleared stale state files${NC}"
            echo ""
            echo -e "${BLUE}🔄 Re-running HA plan...${NC}"
            terraform plan -out=tfplan
        fi
    else
        echo ""
        echo -e "${RED}❌ Terraform HA Plan failed!${NC}"
        echo ""
        echo -e "${YELLOW}🔧 Common HA Issues:${NC}"
        echo "   • Check terraform.tfvars for missing or invalid HA values"
        echo "   • Verify Azure subscription has sufficient permissions for zone-redundant resources"
        echo "   • Ensure HA resource names are unique (Key Vault, Storage Account)"
        echo "   • Check Azure resource limits and quotas for multi-zone deployment"
        echo "   • Verify iq_min_replicas >= 2 and db_high_availability_mode = \"ZoneRedundant\""
        echo ""
        exit 1
    fi
fi

# Clean up
rm -f plan_output.log

