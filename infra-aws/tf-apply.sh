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
AWS_PROFILE="${AWS_PROFILE}"
AWS_REGION="${AWS_REGION:-us-east-1}"

# Check if AWS_PROFILE is set
if [[ -z "$AWS_PROFILE" ]]; then
    echo -e "${RED}❌ Error: AWS_PROFILE environment variable is not set${NC}"
    echo ""
    echo "Please set your AWS profile name:"
    echo "  export AWS_PROFILE=your-profile-name"
    echo ""
    echo "Or run with inline variable:"
    echo "  AWS_PROFILE=your-profile-name ./tf-apply.sh"
    echo ""
    exit 1
fi

echo -e "${BLUE}🚀 ${DEPLOYMENT_NAME} ${DEPLOYMENT_TYPE} - Terraform Apply${NC}"
echo "========================================================="
echo ""

echo -e "${BLUE}📋 Pre-deployment Checks${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ ! -f "main.tf" ]]; then
    echo -e "${RED}❌ Error: main.tf not found${NC}"
    exit 1
fi

if [[ ! -f "tfplan" ]]; then
    echo -e "${RED}❌ Error: tfplan not found${NC}"
    echo "Please run ./tf-plan.sh first"
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
echo "• Plan file: tfplan ✓"
echo ""

echo -e "${YELLOW}⚠️  Deployment Confirmation${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "This will create AWS resources that may incur costs."
echo ""
echo "🚀 Proceeding with deployment..."
echo ""

LOG_GROUP_EXISTS=$(aws-vault exec "$AWS_PROFILE" -- aws logs describe-log-groups \
  --log-group-name-prefix "/ecs/ref-arch-nexus-iq-server" \
  --region $AWS_REGION \
  --query 'logGroups[?logGroupName==`/ecs/ref-arch-nexus-iq-server`].logGroupName' \
  --output text 2>/dev/null || echo "")

if [[ -n "$LOG_GROUP_EXISTS" ]]; then
  if ! terraform state show aws_cloudwatch_log_group.iq_logs >/dev/null 2>&1; then
    aws-vault exec "$AWS_PROFILE" -- terraform import aws_cloudwatch_log_group.iq_logs /ecs/ref-arch-nexus-iq-server >/dev/null 2>&1 || true
  fi
fi


echo -e "${BLUE}🏗️  Applying Configuration${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━"
echo "This may take 15-30 minutes to complete."
echo ""

aws-vault exec "$AWS_PROFILE" -- terraform apply tfplan

if [[ $? -eq 0 ]]; then
    echo ""
    echo -e "${GREEN}✅ Deployment Completed Successfully${NC}"
    echo ""
    
    echo -e "${BLUE}📊 Deployment Summary${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━"
    
    APP_URL=$(aws-vault exec "$AWS_PROFILE" -- terraform output -raw application_url 2>/dev/null || echo "N/A")
    
    echo "• Application URL: $APP_URL"
    echo "• Deployment Type: $DEPLOYMENT_TYPE"
    echo "• Status: Ready"
    echo ""
    
    echo -e "${BLUE}🎯 Next Steps${NC}"
    echo "━━━━━━━━━━━━"
    echo "1. Access IQ Server at: $APP_URL"
    echo "2. Default credentials: admin / admin123"
    echo "3. Monitor deployment health"
    echo ""
    
    echo -e "${YELLOW}⚠️  Important Security Notes${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "• Change default admin password immediately"
    echo "• Review security group rules"
    echo "• Set up monitoring and alerting"
    echo ""
    
    rm -f tfplan
    echo -e "${GREEN}✅ Deployment artifacts cleaned up${NC}"
    
else
    echo ""
    echo -e "${RED}❌ Deployment Failed${NC}"
    echo "Check error messages above and fix issues."
    echo "Run ./tf-plan.sh again after making changes."
    exit 1
fi
