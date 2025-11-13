#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DEPLOYMENT_NAME="Nexus IQ Server"
DEPLOYMENT_TYPE="High Availability on GKE"
CLOUD_PROVIDER="GCP"
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

if [ ! -f "terraform.tfvars" ]; then
    echo -e "${RED}❌ Error: terraform.tfvars not found${NC}"
    echo "Please create terraform.tfvars from terraform.tfvars.example"
    exit 1
fi

PLAN_FILE=$(ls -t tfplan-* 2>/dev/null | head -1)
if [[ -z "$PLAN_FILE" ]]; then
    echo -e "${RED}❌ Error: No tfplan file found${NC}"
    echo "Please run ./tf-plan.sh first"
    exit 1
fi

command -v terraform >/dev/null 2>&1 || {
    echo -e "${RED}❌ Error: terraform not installed${NC}"
    exit 1
}

command -v gcloud >/dev/null 2>&1 || {
    echo -e "${RED}❌ Error: gcloud not installed${NC}"
    exit 1
}

PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
if [[ -z "$PROJECT_ID" ]]; then
    echo -e "${RED}❌ Error: No GCP project configured${NC}"
    exit 1
fi

echo "• Cloud Provider: GCP"
echo "• GCP Project: $PROJECT_ID"
echo "• Deployment: $DEPLOYMENT_NAME $DEPLOYMENT_TYPE"
echo "• Plan file: $PLAN_FILE ✓"
echo ""

echo -e "${YELLOW}⚠️  Deployment Confirmation${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "This will create GCP resources that may incur costs."
echo ""
echo "🚀 Proceeding with deployment..."
echo ""

echo -e "${BLUE}🏗️  Applying Configuration${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━"
echo "This may take 15-30 minutes to complete."
echo ""

terraform apply "$PLAN_FILE"

if [[ $? -eq 0 ]]; then
    echo ""
    echo "Configuring kubectl..."
    CLUSTER_NAME=$(terraform output -raw gke_cluster_name 2>/dev/null || echo "")
    REGION=$(terraform output -raw region 2>/dev/null || echo "")
    PROJECT_ID=$(terraform output -raw project_id 2>/dev/null || echo "")
    
    if [[ -n "$CLUSTER_NAME" && -n "$REGION" && -n "$PROJECT_ID" ]]; then
        gcloud container clusters get-credentials "${CLUSTER_NAME}" --region "${REGION}" --project "${PROJECT_ID}" >/dev/null 2>&1
    fi

    echo ""
    echo -e "${GREEN}✅ Deployment Completed Successfully${NC}"
    echo ""
    
    echo -e "${BLUE}📊 Deployment Summary${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━"
    
    echo "• Deployment Type: High Availability on GKE"
    echo "• Status: Ready"
    echo ""
    
    echo -e "${BLUE}🎯 Next Steps${NC}"
    echo "━━━━━━━━━━━━"
    echo "1. Add cluster license: kubectl create secret generic nexus-iq-license --from-file=node-cluster.lic -n nexus-iq"
    echo "2. Deploy Nexus IQ Server: ./helm-install.sh"
    echo "3. Monitor deployment health"
    echo ""
    
    echo -e "${YELLOW}⚠️  Important Security Notes${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "• Change default admin password immediately"
    echo "• Review firewall rules"
    echo "• Set up monitoring and alerting"
    echo ""
    
    rm -f tfplan-*
    echo -e "${GREEN}✅ Deployment artifacts cleaned up${NC}"
    
else
    echo ""
    echo -e "${RED}❌ Deployment Failed${NC}"
    echo "Check error messages above and fix issues."
    echo "Run ./tf-plan.sh again after making changes."
    exit 1
fi
