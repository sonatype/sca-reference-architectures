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

# Run terraform apply
echo -e "${GREEN}🚀 Starting deployment...${NC}"
echo ""

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