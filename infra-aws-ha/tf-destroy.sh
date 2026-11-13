#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

export AWS_PAGER=""

DEPLOYMENT_NAME="Nexus IQ Server"
DEPLOYMENT_TYPE="High Availability"
CLOUD_PROVIDER="AWS"
TERRAFORM_DIR="$(dirname "$0")"
AWS_REGION="us-east-1"

# Credentials come from the standard AWS chain: the named profile in AWS_PROFILE,
# such as an IAM Identity Center profile, or credentials already in the environment.
if [[ -z "$AWS_PROFILE" && -z "$AWS_ACCESS_KEY_ID" ]]; then
    echo -e "${RED}❌ Error: AWS_PROFILE environment variable is not set${NC}"
    echo ""
    echo "Please set your AWS profile name:"
    echo "  export AWS_PROFILE=your-profile-name"
    echo ""
    echo "Or run with inline variable:"
    echo "  AWS_PROFILE=your-profile-name ./tf-destroy.sh"
    echo ""
    exit 1
fi

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

command -v aws >/dev/null 2>&1 || {
    echo -e "${RED}❌ Error: aws not installed${NC}"
    exit 1
}

if ! aws sts get-caller-identity --region "${AWS_REGION:-us-east-1}" >/dev/null 2>&1; then
    echo -e "${RED}❌ Error: no valid AWS credentials${NC}"
    echo ""
    echo "The credentials are missing or have expired. For an IAM Identity Center"
    echo "profile, sign in again:"
    echo "  aws sso login --profile ${AWS_PROFILE:-your-profile-name}"
    echo ""
    exit 1
fi

echo "• Cloud Provider: AWS"
echo "• AWS Profile: ${AWS_PROFILE:-not set, using credentials from the environment}"
echo "• Deployment: $DEPLOYMENT_NAME $DEPLOYMENT_TYPE"
echo ""

echo -e "${BLUE}🔍 Checking Existing Infrastructure${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# set -e is on, so the status is captured on the failure branch: `$?` after
# `|| true` is always 0.
PLAN_STATUS=0
PLAN_OUTPUT=$(terraform plan -destroy 2>&1) || PLAN_STATUS=$?

if [[ $PLAN_STATUS -ne 0 ]]; then
    if grep -q "prevent_destroy" <<<"$PLAN_OUTPUT"; then
        DOMAIN_NAME=$(terraform output -raw opensearch_domain_name 2>/dev/null || true)
        DOMAIN_NAME=${DOMAIN_NAME:-<the domain>}
        echo -e "${RED}❌ A resource carrying prevent_destroy is in the way${NC}"
        echo ""
        echo "The OpenSearch domain holds the Nexus One index, so Terraform refuses to"
        echo "plan its destruction. Removing it from state gets past that, and the domain"
        echo "itself then has to be deleted before the VPC can be, because its network"
        echo "interfaces sit in these subnets:"
        echo ""
        echo "  terraform state rm aws_opensearch_domain.nexus_one"
        echo "  aws opensearch delete-domain --domain-name ${DOMAIN_NAME}"
        echo "  # wait for the domain to finish deleting, then re-run this script"
        echo ""
        echo "See the OpenSearch section of README.md before doing any of that."
        exit 1
    fi

    echo -e "${YELLOW}⚠️  No infrastructure found${NC}"
    echo "Nothing to destroy."
    exit 0
fi

echo -e "${BLUE}📊 Resources to be Destroyed${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

printf '%s\n' "$PLAN_OUTPUT"

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

# Read from state, since cluster_name may also come from -var, TF_VAR_ or *.auto.tfvars.
DB_SECRET_ARN=$(terraform output -raw db_credentials_secret_arn 2>/dev/null || true)
BACKUP_VAULT_NAME=$(terraform output -raw backup_vault_name 2>/dev/null || true)

if [[ -n "$DB_SECRET_ARN" ]]; then
  aws secretsmanager delete-secret \
    --secret-id "$DB_SECRET_ARN" \
    --force-delete-without-recovery \
    --region $AWS_REGION 2>/dev/null || true
fi

RECOVERY_POINTS=$(aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name "$BACKUP_VAULT_NAME" \
  --region $AWS_REGION \
  --query 'RecoveryPoints[].RecoveryPointArn' \
  --output text 2>/dev/null || echo "")

if [[ -n "$RECOVERY_POINTS" ]]; then
  for arn in $RECOVERY_POINTS; do
    aws backup delete-recovery-point \
      --backup-vault-name "$BACKUP_VAULT_NAME" \
      --recovery-point-arn "$arn" \
      --region $AWS_REGION 2>/dev/null || true
  done
fi



echo -e "${BLUE}🔥 Destroying Infrastructure${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "This may take 15-30 minutes to complete."
echo ""

terraform destroy -auto-approve

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
