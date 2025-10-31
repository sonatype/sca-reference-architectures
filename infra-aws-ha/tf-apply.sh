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

# Pre-deployment cleanup
echo -e "${BLUE}🧹 Pre-deployment checks...${NC}"

# Import existing CloudWatch log group if it exists
echo "📋 Checking for existing CloudWatch log group..."
CLUSTER_NAME=$(grep '^cluster_name' terraform.tfvars | cut -d'"' -f2 || echo "ref-arch-iq-ha-cluster")
LOG_GROUP_NAME="/ecs/${CLUSTER_NAME}/nexus-iq-server"

LOG_GROUP_EXISTS=$(aws-vault exec "$AWS_PROFILE" -- aws logs describe-log-groups \
  --log-group-name-prefix "$LOG_GROUP_NAME" \
  --region us-east-1 \
  --query "logGroups[?logGroupName==\`$LOG_GROUP_NAME\`].logGroupName" \
  --output text 2>/dev/null || echo "")

if [[ -n "$LOG_GROUP_EXISTS" ]]; then
  echo "• CloudWatch log group exists, checking if it's in Terraform state..."
  if ! terraform state show aws_cloudwatch_log_group.iq_logs >/dev/null 2>&1; then
    echo "• Importing existing log group into Terraform state..."
    aws-vault exec "$AWS_PROFILE" -- terraform import aws_cloudwatch_log_group.iq_logs "$LOG_GROUP_NAME"
    echo -e "${GREEN}✅ Log group imported successfully${NC}"
  else
    echo "• Log group already in Terraform state"
  fi
else
  echo "• No existing log group found"
fi

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
    CLUSTER_ARN=$(aws-vault exec "$AWS_PROFILE" -- terraform output -raw cluster_arn 2>/dev/null || echo "N/A")
    ALB_DNS=$(aws-vault exec "$AWS_PROFILE" -- terraform output -raw alb_dns_name 2>/dev/null || echo "N/A")
    APP_URL=$(aws-vault exec "$AWS_PROFILE" -- terraform output -raw application_url 2>/dev/null || echo "N/A")
    SERVICE_NAME=$(aws-vault exec "$AWS_PROFILE" -- terraform output -raw ecs_service_name 2>/dev/null || echo "N/A")
    LOG_GROUP_APP=$(aws-vault exec "$AWS_PROFILE" -- terraform output -json cloudwatch_log_groups 2>/dev/null | jq -r '.application' || echo "N/A")
    LOG_GROUP_STDERR=$(aws-vault exec "$AWS_PROFILE" -- terraform output -json cloudwatch_log_groups 2>/dev/null | jq -r '.stderr' || echo "N/A")
    LOG_GROUP_REQUEST=$(aws-vault exec "$AWS_PROFILE" -- terraform output -json cloudwatch_log_groups 2>/dev/null | jq -r '.request' || echo "N/A")
    LOG_GROUP_AUDIT=$(aws-vault exec "$AWS_PROFILE" -- terraform output -json cloudwatch_log_groups 2>/dev/null | jq -r '.audit' || echo "N/A")
    EFS_ID=$(aws-vault exec "$AWS_PROFILE" -- terraform output -raw efs_id 2>/dev/null || echo "N/A")

    echo "• ECS Cluster: $CLUSTER_NAME"
    echo "• ECS Service: $SERVICE_NAME"
    echo "• Load Balancer DNS: $ALB_DNS"
    echo "• Application URL: $APP_URL"
    echo "• Database: Aurora PostgreSQL (Multi-AZ cluster)"
    echo "• EFS File System: $EFS_ID"
    echo "• CloudWatch Logs: 6 log groups (application, request, audit, policy-violation, stderr, fluent-bit)"
    echo ""

    echo -e "${BLUE}🔍 Monitoring Commands${NC}"
    echo "===================="
    echo ""
    echo "View cluster info:"
    echo "  aws ecs describe-clusters --clusters $CLUSTER_NAME"
    echo ""
    echo "Check service status:"
    echo "  aws ecs describe-services --cluster $CLUSTER_NAME --services $SERVICE_NAME"
    echo ""
    echo "Monitor running tasks:"
    echo "  aws ecs list-tasks --cluster $CLUSTER_NAME --service-name $SERVICE_NAME"
    echo ""
    echo "View all log groups:"
    echo "  aws logs describe-log-groups --log-group-name-prefix /ecs/$CLUSTER_NAME/nexus-iq-server"
    echo ""
    echo "Tail application logs:"
    echo "  aws logs tail $LOG_GROUP_APP --follow"
    echo ""
    echo "Tail stderr logs:"
    echo "  aws logs tail $LOG_GROUP_STDERR --follow"
    echo ""
    echo "Tail request logs:"
    echo "  aws logs tail $LOG_GROUP_REQUEST --follow"
    echo ""
    echo "Tail audit logs:"
    echo "  aws logs tail $LOG_GROUP_AUDIT --follow"
    echo ""
    echo "Search for errors with CloudWatch Insights:"
    echo "  aws logs start-query \\"
    echo "    --log-group-name $LOG_GROUP_APP \\"
    echo "    --start-time \$(date -u -d '1 hour ago' +%s) \\"
    echo "    --end-time \$(date -u +%s) \\"
    echo "    --query-string 'fields @timestamp, @message | filter @message like /ERROR/'"
    echo ""
    echo "Check auto scaling status:"
    echo "  aws application-autoscaling describe-scalable-targets --service-namespace ecs \\
    --resource-ids service/$CLUSTER_NAME/$SERVICE_NAME"
    echo ""
    echo "View EFS file system:"
    echo "  aws efs describe-file-systems --file-system-id $EFS_ID"
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
    echo "3. Monitor logs (choose one):"
    echo "   Application logs:  aws logs tail $LOG_GROUP_APP --follow"
    echo "   Stderr logs:       aws logs tail $LOG_GROUP_STDERR --follow"
    echo "   Request logs:      aws logs tail $LOG_GROUP_REQUEST --follow"
    echo "   Audit logs:        aws logs tail $LOG_GROUP_AUDIT --follow"
    echo "   Policy violations: aws logs tail /ecs/$CLUSTER_NAME/nexus-iq-server/policy-violation --follow"
    echo "   Fluent Bit logs:   aws logs tail /ecs/$CLUSTER_NAME/nexus-iq-server/fluent-bit --follow"
    echo ""
    echo "4. View aggregated logs on EFS:"
    echo "   EFS ID: $EFS_ID"
    echo "   Location: /var/log/nexus-iq-server/aggregated/"
    echo ""
    echo "5. Access IQ Server at: $APP_URL"
    echo "   Default credentials: admin / admin123"
    echo ""

    echo -e "${YELLOW}⚠️  Important Security Notes${NC}"
    echo "• Change default IQ Server admin password immediately"
    echo "• Consider enabling HTTPS with SSL certificate"
    echo "• Review security group rules for production use"
    echo "• Set up monitoring and alerting"
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