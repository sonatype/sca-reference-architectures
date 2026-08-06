#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DEPLOYMENT_NAME="Nexus IQ Server"
DEPLOYMENT_TYPE="High Availability (VPN-Only, Size XL)"
CLOUD_PROVIDER="AWS"
TERRAFORM_DIR="$(dirname "$0")"
AWS_PROFILE="admin@iq-sandbox"
AWS_REGION="us-east-1"

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

CLUSTER_NAME=$(grep '^cluster_name' terraform.tfvars | cut -d'"' -f2 || echo "ref-arch-iq-ha-vpn-cluster")
LOG_GROUP_NAME="/ecs/${CLUSTER_NAME}/nexus-iq-server"

LOG_GROUP_EXISTS=$(aws-vault exec "$AWS_PROFILE" -- aws logs describe-log-groups \
  --log-group-name-prefix "$LOG_GROUP_NAME" \
  --region $AWS_REGION \
  --query "logGroups[?logGroupName==\`$LOG_GROUP_NAME\`].logGroupName" \
  --output text 2>/dev/null || echo "")

if [[ -n "$LOG_GROUP_EXISTS" ]]; then
  if ! terraform state show aws_cloudwatch_log_group.iq_logs >/dev/null 2>&1; then
    aws-vault exec "$AWS_PROFILE" -- terraform import aws_cloudwatch_log_group.iq_logs "$LOG_GROUP_NAME" >/dev/null 2>&1 || true
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

    echo "• Application URL (internal, VPN-only): $APP_URL"
    echo "• Deployment Type: $DEPLOYMENT_TYPE"
    echo "• Status: Ready"
    echo ""

    echo -e "${YELLOW}🔒 This environment has NO public internet path.${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "1. Connect to the Sonatype CloudConnexa VPN first"
    echo "2. Then browse to: $APP_URL"
    echo "3. Default credentials: admin / admin123"
    echo "4. Change default admin password immediately"
    echo ""

    echo -e "${BLUE}🎯 Next Steps${NC}"
    echo "━━━━━━━━━━━━"
    echo "1. Confirm your CloudConnexa VPN client is connected"
    echo "2. Access IQ Server at: $APP_URL"
    echo "3. Change default admin password immediately"
    echo "4. Monitor deployment health"
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
