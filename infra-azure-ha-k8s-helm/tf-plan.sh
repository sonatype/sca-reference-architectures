#!/bin/bash

# Terraform plan script for Nexus IQ Server HA on AKS deployment
# Usage: ./tf-plan.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

TERRAFORM_DIR="$(dirname "$0")"

echo -e "${BLUE}📋 Nexus IQ Server HA on AKS - Terraform Plan${NC}"
echo "===================================================="
echo ""

# Check if we're in the right directory
if [[ ! -f "main.tf" ]]; then
    echo -e "${RED}❌ Error: main.tf not found in current directory${NC}"
    echo "Please run this script from the infra-azure-ha-k8s-helm directory"
    exit 1
fi

# Check if terraform.tfvars exists
if [[ ! -f "terraform.tfvars" ]]; then
    echo -e "${YELLOW}⚠️  Warning: terraform.tfvars not found${NC}"
    echo "Creating terraform.tfvars from terraform.tfvars.example..."
    if [[ -f "terraform.tfvars.example" ]]; then
        cp terraform.tfvars.example terraform.tfvars
        echo -e "${GREEN}✅ Created terraform.tfvars from example${NC}"
        echo -e "${YELLOW}📝 Please edit terraform.tfvars and update the following:${NC}"
        echo "   - database_password (set a strong password)"
        echo "   - nexus_iq_license (base64 encoded license)"
        echo "   - nexus_iq_admin_password (initial admin password)"
        echo ""
        exit 1
    else
        echo -e "${RED}❌ Error: terraform.tfvars.example not found${NC}"
        exit 1
    fi
fi

# Check for required tools
command -v az >/dev/null 2>&1 || {
    echo -e "${RED}❌ Error: Azure CLI is required but not installed${NC}"
    exit 1
}

command -v terraform >/dev/null 2>&1 || {
    echo -e "${RED}❌ Error: terraform is required but not installed${NC}"
    exit 1
}

echo -e "${BLUE}📋 Pre-flight checks${NC}"
echo "• Azure CLI: $(az --version | head -1)"
echo "• Terraform Directory: $TERRAFORM_DIR"
echo "• Configuration file: terraform.tfvars ✓"
echo ""

# Check Azure login
echo -e "${BLUE}🔐 Checking Azure authentication...${NC}"
if ! az account show >/dev/null 2>&1; then
    echo -e "${RED}❌ Not logged in to Azure${NC}"
    echo "Please run: az login"
    exit 1
fi

ACCOUNT_NAME=$(az account show --query 'name' -o tsv)
echo -e "${GREEN}✅ Logged in to Azure: $ACCOUNT_NAME${NC}"
echo ""

# Check for sensitive variables
echo -e "${BLUE}🔍 Validating configuration...${NC}"
if grep -q "CHANGE_ME" terraform.tfvars; then
    echo -e "${RED}❌ Error: Found placeholder values in terraform.tfvars${NC}"
    echo "Please update the following values in terraform.tfvars:"
    grep "CHANGE_ME" terraform.tfvars || true
    echo ""
    exit 1
fi

if grep -q "YOUR_BASE64_LICENSE_HERE" terraform.tfvars; then
    echo -e "${YELLOW}⚠️  Warning: Nexus IQ license placeholder found${NC}"
    echo "Please update nexus_iq_license in terraform.tfvars with your base64 encoded license"
    echo ""
fi

echo -e "${GREEN}✅ Configuration validation passed${NC}"
echo ""

# Initialize Terraform
echo -e "${BLUE}🔧 Initializing Terraform...${NC}"
terraform init

echo ""
echo -e "${BLUE}🔍 Validating Terraform configuration...${NC}"
terraform validate

if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}✅ Validation successful${NC}"
else
    echo -e "${RED}❌ Validation failed${NC}"
    exit 1
fi

# Show what will be planned
echo -e "${BLUE}📋 Planning infrastructure changes...${NC}"
echo ""
echo -e "${YELLOW}This plan will create the following Azure resources:${NC}"
echo "   - Virtual Network with public, private, and database subnets"
echo "   - AKS Cluster with auto-scaling node pools (2-6 nodes)"
echo "   - PostgreSQL Flexible Server (Zone-Redundant HA)"
echo "   - Azure Files Premium (Zone-Redundant Storage)"
echo "   - Application Gateway v2 (Zone-Redundant)"
echo "   - Network Security Groups and rules"
echo "   - Managed Identities and role assignments"
echo "   - Log Analytics and Application Insights"
echo "   - Application Gateway Ingress Controller (AGIC)"
echo ""

# Run terraform plan
echo -e "${BLUE}📊 Planning Terraform deployment...${NC}"
echo "This will show you what resources will be created/modified/destroyed."
echo ""

if terraform plan -out=tfplan; then
    echo ""
    echo -e "${GREEN}✅ Terraform plan completed successfully!${NC}"
    echo ""
    echo -e "${BLUE}📊 Plan Summary:${NC}"
    echo "   Plan file saved as: tfplan"
    echo ""

    echo ""
    echo -e "${BLUE}🚀 Next steps:${NC}"
    echo "1. Review the plan output above carefully"
    echo "2. Ensure all configurations are correct"
    echo "3. Run terraform apply:"
    echo "   ./tf-apply.sh"
    echo ""
    echo -e "${YELLOW}💡 Estimated deployment time: 15-25 minutes${NC}"
    echo "   - AKS cluster: ~10-15 minutes"
    echo "   - PostgreSQL cluster: ~5-10 minutes"
    echo "   - Other resources: ~5 minutes"
    echo ""

else
    echo ""
    echo -e "${RED}❌ Terraform plan failed!${NC}"
    echo ""
    echo "Common issues and solutions:"
    echo "1. Check terraform.tfvars for syntax errors"
    echo "2. Verify Azure credentials and permissions"
    echo "3. Check for resource naming conflicts"
    echo "4. Ensure all required variables are set"
    echo ""

    # Clean up failed plan file
    if [[ -f "tfplan" ]]; then
        rm tfplan
    fi

    exit 1
fi
