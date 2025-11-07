#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DEPLOYMENT_NAME="Nexus IQ Server"
DEPLOYMENT_TYPE="High Availability on AKS"
CLOUD_PROVIDER="Azure"
TERRAFORM_DIR="$(dirname "$0")"

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

command -v az >/dev/null 2>&1 || {
    echo -e "${RED}❌ Error: Azure CLI not installed${NC}"
    exit 1
}

SUBSCRIPTION=$(az account show --query name -o tsv 2>/dev/null)

echo "• Cloud Provider: Azure"
echo "• Subscription: $SUBSCRIPTION"
echo "• Deployment: $DEPLOYMENT_NAME $DEPLOYMENT_TYPE"
echo "• Plan file: tfplan ✓"
echo ""

echo -e "${YELLOW}⚠️  Deployment Confirmation${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "This will create Azure resources that may incur costs."
echo ""
echo "🚀 Proceeding with deployment..."
echo ""

echo -e "${BLUE}🏗️  Applying Configuration${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━"
echo "This may take 15-30 minutes to complete."
echo ""

terraform apply tfplan

if [[ $? -eq 0 ]]; then
    echo ""
    echo -e "${GREEN}✅ Deployment Completed Successfully${NC}"
    echo ""
    
    echo -e "${BLUE}📊 Deployment Summary${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━"

    APP_URL=$(terraform output -raw application_gateway_fqdn 2>/dev/null || echo "N/A")
    
    echo "• Application URL: $APP_URL"
    echo "• Deployment Type: $DEPLOYMENT_TYPE"
    echo "• Status: Ready"
    echo ""
    
    echo -e "${BLUE}🎯 Next Steps${NC}"
    echo "━━━━━━━━━━━━"
    echo "1. Access IQ Server at: $APP_URL"
    echo "2. Default credentials: admin / admin123"
    echo "3. Monitor deployment health"

echo "4. Deploy Helm chart: ./helm-install.sh"
    echo ""
    
    echo -e "${YELLOW}⚠️  Important Security Notes${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "• Change default admin password immediately"
    echo "• Review network security rules"
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
