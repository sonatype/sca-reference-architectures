#!/bin/bash

# Terraform apply script with MFA support for IQ Server HA deployment
# Usage: ./tf-apply.sh

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

echo -e "${BLUE}🚀 Nexus IQ Server HA - Terraform Apply${NC}"
echo "==========================================="
echo ""

# Check if we're in the right directory
if [[ ! -f "main.tf" ]]; then
    echo -e "${RED}❌ Error: main.tf not found in current directory${NC}"
    echo "Please run this script from the infra-aws-ha directory"
    exit 1
fi

# Check if plan file exists
if [[ ! -f "tfplan" ]]; then
    echo -e "${RED}❌ Error: tfplan file not found${NC}"
    echo "Please run ./tf-plan.sh first to generate a plan"
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

echo -e "${BLUE}📋 Pre-deployment checks${NC}"
echo "• AWS Profile: $AWS_PROFILE"
echo "• Terraform Directory: $TERRAFORM_DIR"
echo "• Plan file: tfplan ✓"
echo ""

# Confirmation prompt
echo -e "${YELLOW}⚠️  You are about to deploy IQ Server HA infrastructure${NC}"
echo "This will create AWS resources that may incur costs."
echo ""
echo -e "${YELLOW}Resources to be created:${NC}"
echo "• ECS cluster with Fargate tasks (2+ instances)"
echo "• Aurora PostgreSQL cluster (2+ instances)"
echo "• Application Load Balancer with WAF"
echo "• EFS file system with backup vault"
echo "• NAT Gateways (if enabled)"
echo "• CloudWatch Log Groups"
echo "• Service Discovery and Auto Scaling"
echo "• Various security groups and IAM roles"
echo ""

echo "🚀 Proceeding with deployment..."
echo ""
echo -e "${BLUE}🏗️  Applying Terraform configuration...${NC}"
echo "This may take 20-30 minutes to complete."
echo ""

# Apply the plan
aws-vault exec "$AWS_PROFILE" -- terraform apply tfplan

if [[ $? -eq 0 ]]; then
    echo ""
    echo -e "${GREEN}✅ Deployment completed successfully!${NC}"
    echo ""

    # Get outputs
    echo -e "${BLUE}📊 Deployment Summary${NC}"
    echo "===================="

    # Extract key outputs
    CLUSTER_NAME=$(aws-vault exec "$AWS_PROFILE" -- terraform output -raw cluster_name 2>/dev/null || echo "N/A")
    ALB_DNS=$(aws-vault exec "$AWS_PROFILE" -- terraform output -raw alb_dns_name 2>/dev/null || echo "N/A")
    APP_URL=$(aws-vault exec "$AWS_PROFILE" -- terraform output -raw application_url 2>/dev/null || echo "N/A")
    SERVICE_NAME=$(aws-vault exec "$AWS_PROFILE" -- terraform output -raw ecs_service_name 2>/dev/null || echo "N/A")

    echo "• ECS Cluster: $CLUSTER_NAME"
    echo "• ECS Service: $SERVICE_NAME"
    echo "• Load Balancer DNS: $ALB_DNS"
    echo "• Application URL: $APP_URL"
    echo ""

    echo -e "${BLUE}🎯 Next Steps${NC}"
    echo "============"
    echo "1. Verify the ECS deployment:"
    echo "   aws ecs describe-services --cluster $CLUSTER_NAME --services $SERVICE_NAME"
    echo "   aws ecs list-tasks --cluster $CLUSTER_NAME --service-name $SERVICE_NAME"
    echo ""
    echo "2. Check task status and health:"
    echo "   aws ecs describe-tasks --cluster $CLUSTER_NAME --tasks \$(aws ecs list-tasks --cluster $CLUSTER_NAME --service-name $SERVICE_NAME --query 'taskArns[0]' --output text)"
    echo ""
    echo "3. Monitor application logs:"
    echo "   aws logs tail /ecs/$CLUSTER_NAME/nexus-iq-server --follow"
    echo ""
    echo "4. Access IQ Server at: $APP_URL"
    echo "   Default credentials: admin / admin123"
    echo ""

    echo -e "${YELLOW}⚠️  Important Security Notes${NC}"
    echo "• Change default IQ Server admin password immediately"
    echo "• Consider enabling HTTPS with SSL certificate"
    echo "• Review security group rules for production use"
    echo "• Set up monitoring and alerting"
    echo ""

    echo -e "${BLUE}🔍 Monitoring Commands${NC}"
    echo "• View cluster info: aws ecs describe-clusters --clusters $CLUSTER_NAME"
    echo "• Check service status: aws ecs describe-services --cluster $CLUSTER_NAME --services $SERVICE_NAME"
    echo "• Monitor tasks: aws ecs list-tasks --cluster $CLUSTER_NAME --service-name $SERVICE_NAME"
    echo "• View logs: aws logs tail /ecs/$CLUSTER_NAME/nexus-iq-server --follow"
    echo "• Check auto scaling: aws application-autoscaling describe-scalable-targets --service-namespace ecs"
    echo ""

    # Clean up plan file
    rm -f tfplan
    echo -e "${GREEN}✅ Deployment artifacts cleaned up${NC}"

else
    echo -e "${RED}❌ Deployment failed${NC}"
    echo "Check the error messages above and fix any issues."
    echo "You may need to run './tf-plan.sh' again after making changes."
    exit 1
fi