#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DEPLOYMENT_NAME="Nexus IQ Server"
DEPLOYMENT_TYPE="Single Instance"
CLOUD_PROVIDER="AWS"
TERRAFORM_DIR="$(dirname "$0")"
AWS_PROFILE="admin@iq-sandbox"
AWS_REGION="us-east-1"

echo -e "${BLUE}📋 ${DEPLOYMENT_NAME} ${DEPLOYMENT_TYPE} - Terraform Plan${NC}"
echo "========================================================"
echo ""

echo -e "${BLUE}📋 Pre-flight Checks${NC}"
echo "━━━━━━━━━━━━━━━━━━━━"

if [[ ! -f "main.tf" ]]; then
    echo -e "${RED}❌ Error: main.tf not found in current directory${NC}"
    echo "Please run this script from the infra-aws directory"
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

command -v aws-vault >/dev/null 2>&1 || {
    echo -e "${RED}❌ Error: aws-vault is required but not installed${NC}"
    exit 1
}

echo "• Cloud Provider: AWS"
echo "• AWS Profile: $AWS_PROFILE"
echo "• AWS Region: $AWS_REGION"
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
echo ""

echo -e "${BLUE}🔧 Initializing Terraform${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━"

aws-vault exec "$AWS_PROFILE" -- terraform init

echo ""
echo -e "${BLUE}✅ Validating Configuration${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━"

aws-vault exec "$AWS_PROFILE" -- terraform validate

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

aws-vault exec "$AWS_PROFILE" -- terraform plan -out=tfplan

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
