#!/bin/bash

# Terraform plan script with MFA support for IQ Server HA deployment
# Usage: ./tf-plan.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
AWS_PROFILE="admin@iq-sandbox"
TERRAFORM_DIR="$(dirname "$0")"

echo -e "${BLUE}🚀 Nexus IQ Server HA - Terraform Plan${NC}"
echo "=========================================="
echo ""

# Check if we're in the right directory
if [[ ! -f "main.tf" ]]; then
    echo -e "${RED}❌ Error: main.tf not found in current directory${NC}"
    echo "Please run this script from the infra-aws-ha directory"
    exit 1
fi

# Check if terraform.tfvars exists
if [[ ! -f "terraform.tfvars" ]]; then
    echo -e "${RED}❌ Error: terraform.tfvars not found${NC}"
    echo "Please copy terraform.tfvars.example to terraform.tfvars and configure it:"
    echo "cp terraform.tfvars.example terraform.tfvars"
    exit 1
fi

# Check for required tools
command -v aws-vault >/dev/null 2>&1 || {
    echo -e "${RED}❌ Error: aws-vault is required but not installed${NC}"
    exit 1
}

command -v terraform >/dev/null 2>&1 || {
    echo -e "${RED}❌ Error: terraform is required but not installed${NC}"
    exit 1
}


echo -e "${BLUE}📋 Pre-flight checks${NC}"
echo "• AWS Profile: $AWS_PROFILE"
echo "• Terraform Directory: $TERRAFORM_DIR"
echo "• Configuration file: terraform.tfvars ✓"
echo ""

# Initialize Terraform
echo -e "${BLUE}🔧 Initializing Terraform...${NC}"
aws-vault exec "$AWS_PROFILE" -- terraform init

echo ""
echo -e "${BLUE}🔍 Validating Terraform configuration...${NC}"
aws-vault exec "$AWS_PROFILE" -- terraform validate

if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}✅ Validation successful${NC}"
else
    echo -e "${RED}❌ Validation failed${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}📊 Planning Terraform deployment...${NC}"
echo "This will show you what resources will be created/modified/destroyed."
echo ""

# Run terraform plan
aws-vault exec "$AWS_PROFILE" -- terraform plan -out=tfplan

if [[ $? -eq 0 ]]; then
    echo ""
    echo -e "${GREEN}✅ Plan completed successfully${NC}"
    echo ""
    echo -e "${YELLOW}📝 Next steps:${NC}"
    echo "1. Review the plan output above"
    echo "2. If everything looks correct, run: ./tf-apply.sh"
    echo "3. The plan has been saved to 'tfplan' file"
    echo ""
    echo -e "${YELLOW}⚠️  Important notes for HA deployment:${NC}"
    echo "• This will create an ECS cluster with minimum 2 Fargate tasks"
    echo "• Aurora PostgreSQL cluster with 2+ instances"
    echo "• EFS file system for shared storage with backup vault"
    echo "• Application Load Balancer with WAF protection"
    echo "• Auto scaling and service discovery enabled"
    echo "• Resources will be distributed across multiple AZs"
    echo "• Estimated deployment time: 15-20 minutes"
    echo ""
else
    echo -e "${RED}❌ Plan failed${NC}"
    exit 1
fi