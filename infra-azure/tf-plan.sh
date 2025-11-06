#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DEPLOYMENT_NAME="Nexus IQ Server"
DEPLOYMENT_TYPE="Single Instance"
CLOUD_PROVIDER="Azure"
TERRAFORM_DIR="$(dirname "$0")"

echo -e "${BLUE}📋 ${DEPLOYMENT_NAME} ${DEPLOYMENT_TYPE} - Terraform Plan${NC}"
echo "========================================================"
echo ""

echo -e "${BLUE}📋 Pre-flight Checks${NC}"
echo "━━━━━━━━━━━━━━━━━━━━"

if [[ ! -f "main.tf" ]]; then
    echo -e "${RED}❌ Error: main.tf not found in current directory${NC}"
    echo "Please run this script from the infra-azure directory"
    exit 1
fi

if [[ ! -f "terraform.tfvars" ]]; then
    echo -e "${YELLOW}⚠️  Warning: terraform.tfvars not found${NC}"
    if [[ -f "terraform.tfvars.example" ]]; then
        echo "Creating terraform.tfvars from example..."
        cp terraform.tfvars.example terraform.tfvars
        echo -e "${GREEN}✅ Created terraform.tfvars${NC}"
        echo -e "${YELLOW}📝 Please edit terraform.tfvars before continuing${NC}"
        exit 1
    else
        echo -e "${RED}❌ Error: terraform.tfvars.example not found${NC}"
        exit 1
    fi
fi

command -v terraform >/dev/null 2>&1 || {
    echo -e "${RED}❌ Error: terraform is required but not installed${NC}"
    exit 1
}

command -v az >/dev/null 2>&1 || {
    echo -e "${RED}❌ Error: Azure CLI is required but not installed${NC}"
    echo "Install from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
}

if ! az account show &> /dev/null; then
    echo -e "${RED}❌ Error: Not authenticated with Azure${NC}"
    echo "Please run: az login"
    exit 1
fi

SUBSCRIPTION=$(az account show --query name -o tsv 2>/dev/null)
TENANT=$(az account show --query tenantId -o tsv 2>/dev/null)

echo "• Cloud Provider: Azure"
echo "• Subscription: $SUBSCRIPTION"
echo "• Tenant ID: $TENANT"
echo "• Deployment: $DEPLOYMENT_NAME $DEPLOYMENT_TYPE"
echo "• Configuration: terraform.tfvars ✓"
echo ""

echo -e "${BLUE}🔍 Configuration Validation${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if grep -q "CHANGE_ME" terraform.tfvars 2>/dev/null; then
    echo -e "${RED}❌ Error: Found placeholder values${NC}"
    grep "CHANGE_ME" terraform.tfvars || true
    exit 1
fi

echo -e "${GREEN}✅ Configuration validated${NC}"

RESOURCE_GROUP=$(grep '^resource_group_name' terraform.tfvars | cut -d'"' -f2)

if [[ -n "$RESOURCE_GROUP" ]]; then
  RG_EXISTS=$(az group show --name "$RESOURCE_GROUP" --query name -o tsv 2>/dev/null || echo "")

  if [[ -n "$RG_EXISTS" ]]; then
    if [[ -f "terraform.tfstate" ]]; then
      STATE_HAS_RG=$(grep -q "\"name\": \"$RESOURCE_GROUP\"" terraform.tfstate 2>/dev/null && echo "yes" || echo "no")

      if [[ "$STATE_HAS_RG" == "no" ]]; then
        echo -e "${YELLOW}⚠️  Resource group exists but not in Terraform state${NC}"
        echo "  This may cause conflicts during deployment."
        echo ""
      fi
    fi
  fi
fi

echo ""

echo -e "${BLUE}🔧 Initializing Terraform${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━"

terraform init

echo ""
echo -e "${BLUE}✅ Validating Configuration${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━"

terraform validate

if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}✅ Validation successful${NC}"
else
    echo -e "${RED}❌ Validation failed${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}📊 Planning Deployment${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━"
echo "This will show you what resources will be created/modified/destroyed."
echo ""

terraform plan -out=tfplan

if [[ $? -eq 0 ]]; then
    echo ""
    echo -e "${GREEN}✅ Plan Completed Successfully${NC}"
    echo ""
    echo -e "${BLUE}📝 Next Steps${NC}"
    echo "━━━━━━━━━━━━"
    echo "1. Review the plan output above"
    echo "2. Verify all resources are correct"
    echo "3. Run: ./tf-apply.sh"
    echo ""
    echo -e "${YELLOW}💡 Estimated deployment time: 15-25 minutes${NC}"
    echo ""
else
    echo ""
    echo -e "${RED}❌ Plan Failed${NC}"
    [[ -f "tfplan" ]] && rm tfplan
    exit 1
fi
