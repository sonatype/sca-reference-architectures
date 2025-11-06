#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

export AWS_PAGER=""

DEPLOYMENT_NAME="Nexus IQ Server"
DEPLOYMENT_TYPE="High Availability on EKS"
CLOUD_PROVIDER="AWS"
TERRAFORM_DIR="$(dirname "$0")"
AWS_PROFILE="admin@iq-sandbox"
AWS_REGION="us-east-1"

echo -e "${BLUE}🧹 ${DEPLOYMENT_NAME} ${DEPLOYMENT_TYPE} - Terraform Destroy${NC}"
echo "==========================================================="
echo ""

if [[ ! -f "main.tf" ]]; then
    echo -e "${RED}❌ Error: main.tf not found${NC}"
    exit 1
fi

command -v terraform >/dev/null 2>&1 || {
    echo -e "${RED}❌ Error: terraform not installed${NC}"
    exit 1
}

command -v aws-vault >/dev/null 2>&1 || {
    echo -e "${RED}❌ Error: aws-vault not installed${NC}"
    exit 1
}

echo "• Cloud Provider: AWS"
echo "• AWS Profile: $AWS_PROFILE"
echo "• Deployment: $DEPLOYMENT_NAME $DEPLOYMENT_TYPE"
echo ""

echo -e "${BLUE}🔍 Checking Existing Infrastructure${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

aws-vault exec "$AWS_PROFILE" -- terraform plan -destroy > /dev/null 2>&1

if [[ $? -ne 0 ]]; then
    echo -e "${YELLOW}⚠️  No infrastructure found${NC}"
    echo "Nothing to destroy."
    exit 0
fi

echo -e "${BLUE}📊 Resources to be Destroyed${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

aws-vault exec "$AWS_PROFILE" -- terraform plan -destroy

echo ""
echo -e "${RED}⚠️  DANGER: Permanent Destruction${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "${YELLOW}This will PERMANENTLY DELETE:${NC}"
echo "• All compute resources (ECS/EKS)"
echo "• All databases and data (RDS/Aurora)"
echo "• All storage and files (EFS)"
echo "• All load balancers and networking"
echo "• All security groups and IAM roles"
echo "• All logs (based on retention settings)"
echo ""
echo -e "${RED}⚠️  DATA LOSS WARNING:${NC}"
echo "• All database data will be permanently lost"
echo "• All application data will be permanently lost"
echo "• Secrets will be force-deleted (no recovery)"
echo "• This action CANNOT be undone"
echo ""

echo -e "${BLUE}🔥 Destroying Infrastructure${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "This may take 15-30 minutes to complete."
echo ""

aws-vault exec "$AWS_PROFILE" -- terraform destroy -auto-approve

if [[ $? -eq 0 ]]; then
    echo ""
    echo -e "${GREEN}✅ Infrastructure Destroyed Successfully${NC}"
    echo ""
    
    echo -e "${BLUE}🧹 Cleanup Summary${NC}"
    echo "━━━━━━━━━━━━━━━━━━"
    echo "• All AWS resources destroyed"
    echo "• Terraform state updated"
    echo "• Local artifacts removed"
    echo ""
    
    rm -f tfplan terraform.tfstate.backup
    
    echo -e "${YELLOW}📝 Manual Cleanup Tasks (if needed)${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "• Remove any manual DNS records"
    echo "• Clean up external monitoring"
    echo "• Verify no orphaned resources"
    echo ""
    
    echo -e "${GREEN}✅ Destruction Process Completed${NC}"
    
else
    echo ""
    echo -e "${RED}❌ Destruction Failed${NC}"
    echo ""
    echo -e "${YELLOW}Common Issues:${NC}"
    echo "• Resources may have dependencies - check and retry"
    echo "• Deletion protection may be enabled"
    echo "• Some resources may need manual cleanup"
    echo ""
    echo "Retry with: ./tf-destroy.sh"
    exit 1
fi
