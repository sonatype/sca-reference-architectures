#!/bin/bash

# Terraform destroy script with MFA support for IQ Server Single Instance deployment
# Usage: ./tf-destroy.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Disable AWS CLI pager to prevent interactive prompts
export AWS_PAGER=""

# Configuration
AWS_PROFILE="admin@iq-sandbox"
AWS_REGION="us-east-1"
TERRAFORM_DIR="$(dirname "$0")"

echo -e "${BLUE}🧹 Nexus IQ Server Single Instance - Terraform Destroy${NC}"
echo "===================================================="
echo ""

# Check if we're in the right directory
if [[ ! -f "main.tf" ]]; then
    echo -e "${RED}❌ Error: main.tf not found in current directory${NC}"
    echo "Please run this script from the infra-aws directory"
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

echo -e "${BLUE}📋 Pre-destruction checks${NC}"
echo "• AWS Profile: $AWS_PROFILE"
echo "• Terraform Directory: $TERRAFORM_DIR"
echo ""

# Check if infrastructure exists
echo -e "${BLUE}🔍 Checking existing infrastructure...${NC}"
aws-vault exec "$AWS_PROFILE" -- terraform plan -destroy > /dev/null 2>&1

if [[ $? -ne 0 ]]; then
    echo -e "${YELLOW}⚠️  No infrastructure found or unable to plan destruction${NC}"
    echo "Either there's no infrastructure to destroy or there's a configuration issue."
    echo "Run 'terraform plan -destroy' manually to see detailed information."
    exit 0
fi

# Show what will be destroyed
echo -e "${BLUE}📊 Resources to be destroyed${NC}"
echo "=============================="
aws-vault exec "$AWS_PROFILE" -- terraform plan -destroy

echo ""
echo -e "${RED}⚠️  DANGER: This will permanently destroy ALL infrastructure${NC}"
echo ""
echo -e "${YELLOW}Resources that will be PERMANENTLY DELETED:${NC}"
echo "• ECS cluster and running task"
echo "• RDS PostgreSQL database and ALL data"
echo "• EFS file system and ALL stored data"
echo "• Application Load Balancer and target groups"
echo "• NAT Gateway and Elastic IP"
echo "• All security groups, IAM roles, and policies"
echo "• All CloudWatch logs (based on retention settings)"
echo ""

echo -e "${RED}⚠️  DATA LOSS WARNING:${NC}"
echo "• Database data will be permanently lost"
echo "• Application data stored in EFS will be permanently lost"
echo "• Secrets Manager secrets will be force-deleted (no recovery period)"
echo "• This action CANNOT be undone"
echo ""

echo ""
echo -e "${BLUE}🧹 Pre-destruction cleanup...${NC}"

echo "🗑️  Cleaning up secrets manager secrets..."

# Force delete the database credentials secret to avoid retention period issues
aws-vault exec "$AWS_PROFILE" -- aws secretsmanager delete-secret \
  --secret-id "ref-arch-iq-db-credentials" \
  --force-delete-without-recovery \
  --region $AWS_REGION || echo "⚠️  Secret may not exist or already deleted"

echo ""
echo -e "${BLUE}🧹 Destroying infrastructure...${NC}"
echo "This may take 15-20 minutes to complete."
echo ""

# Destroy the infrastructure
aws-vault exec "$AWS_PROFILE" -- terraform destroy -auto-approve

if [[ $? -eq 0 ]]; then
    echo ""
    echo -e "${GREEN}✅ Infrastructure destroyed successfully${NC}"
    echo ""

    echo -e "${BLUE}🧹 Clean-up completed${NC}"
    echo "==================="
    echo "• All AWS resources have been destroyed"
    echo "• Secrets Manager secrets force-deleted (no recovery period)"
    echo "• ECS task, RDS database, EFS, and ALB completely removed"
    echo "• Terraform state has been updated"
    echo "• Local plan files have been removed"
    echo ""

    # Clean up local files
    rm -f tfplan terraform.tfstate.backup

    echo -e "${YELLOW}📝 Manual clean-up tasks (if needed):${NC}"
    echo "• Remove any manually created DNS records"
    echo "• Clean up any external monitoring configurations"
    echo "• Verify no orphaned ECS tasks or services remain"
    echo "• Check for any remaining CloudWatch alarms or dashboards"
    echo ""

    echo -e "${GREEN}✅ Destruction process completed${NC}"

else
    echo -e "${RED}❌ Destruction failed${NC}"
    echo ""
    echo -e "${YELLOW}Common issues and solutions:${NC}"
    echo "• ELBs may take time to delete - wait and retry"
    echo "• Security groups might have dependencies - check for attached resources"
    echo "• RDS deletion protection might be enabled - disable and retry"
    echo "• Some resources might need manual cleanup"
    echo ""
    echo "You can retry destruction with: ./tf-destroy.sh"
    echo "Or run 'terraform destroy' manually for more detailed error information"
    exit 1
fi
