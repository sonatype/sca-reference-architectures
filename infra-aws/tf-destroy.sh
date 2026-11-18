#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

export AWS_PAGER=""

DEPLOYMENT_NAME="Nexus IQ Server"
DEPLOYMENT_TYPE="Single Instance"
CLOUD_PROVIDER="AWS"
TERRAFORM_DIR="$(dirname "$0")"
AWS_REGION="${AWS_REGION:-us-east-1}"

# --delete-opensearch-domain: the OpenSearch domain carries prevent_destroy, because it holds
# the Nexus One index, so Terraform refuses to plan its destruction. With this option the
# script removes the domain from state, deletes it and waits for the delete, so the rest of
# the destroy can remove the VPC its network interfaces sit in.
DELETE_OPENSEARCH_DOMAIN=false
for arg in "$@"; do
    case "$arg" in
        --delete-opensearch-domain) DELETE_OPENSEARCH_DOMAIN=true ;;
        -h | --help)
            echo "Usage: ./tf-destroy.sh [--delete-opensearch-domain]"
            exit 0
            ;;
        *)
            echo -e "${RED}❌ Error: unknown option $arg${NC}"
            echo "Usage: ./tf-destroy.sh [--delete-opensearch-domain]"
            exit 1
            ;;
    esac
done

# The deployment's own region, for the aws calls this script makes itself.
TFVARS_REGION=$(sed -n 's/^[[:space:]]*aws_region[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' terraform.tfvars 2>/dev/null | head -n 1)
AWS_REGION="${TFVARS_REGION:-${AWS_REGION:-us-east-1}}"

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

# Removes the OpenSearch domain from state, deletes it, and waits until AWS no longer
# knows it, which takes about 15 minutes.
delete_opensearch_domain() {
    local domain="$1" waited=0 out
    echo "Removing the OpenSearch domain $domain from state, then deleting it"
    terraform state rm aws_opensearch_domain.nexus_one >/dev/null
    aws opensearch delete-domain --domain-name "$domain" --region "$AWS_REGION" >/dev/null
    while out=$(aws opensearch describe-domain --domain-name "$domain" --region "$AWS_REGION" 2>&1); do
        if [[ $waited -ge 3600 ]]; then
            echo -e "${RED}❌ The OpenSearch domain $domain was still deleting after an hour${NC}"
            exit 1
        fi
        sleep 30
        waited=$((waited + 30))
        if [[ $((waited % 300)) -eq 0 ]]; then
            echo "  still deleting after ${waited}s"
        fi
    done
    if ! grep -q "ResourceNotFoundException" <<<"$out"; then
        echo -e "${RED}❌ Could not read the OpenSearch domain's state: $out${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ OpenSearch domain $domain deleted${NC}"
}

# set -e is on, so the status is captured on the failure branch: `$?` after
# `|| true` is always 0.
PLAN_STATUS=0
PLAN_OUTPUT=$(terraform plan -destroy 2>&1) || PLAN_STATUS=$?

if [[ $PLAN_STATUS -ne 0 ]]; then
    if ! grep -q "prevent_destroy" <<<"$PLAN_OUTPUT"; then
        if [[ -z "$(terraform state list 2>/dev/null)" ]]; then
            echo -e "${YELLOW}⚠️  No infrastructure found${NC}"
            echo "Nothing to destroy."
            exit 0
        fi
        printf '%s\n' "$PLAN_OUTPUT"
        echo -e "${RED}❌ The destroy plan failed, so nothing was destroyed. Fix the error above, then run this script again.${NC}"
        exit 1
    fi
    DOMAIN_NAME=$(terraform output -raw opensearch_domain_name 2>/dev/null || true)
    if [[ "$DELETE_OPENSEARCH_DOMAIN" != true || -z "$DOMAIN_NAME" ]]; then
        echo -e "${RED}❌ A resource carrying prevent_destroy is in the way${NC}"
        echo ""
        echo "The OpenSearch domain holds the Nexus One index, so Terraform refuses to"
        echo "plan its destruction. Run this script again with --delete-opensearch-domain"
        echo "to remove it from state, delete it and wait for the delete, or do it by hand:"
        echo ""
        echo "  terraform state rm aws_opensearch_domain.nexus_one"
        echo "  aws opensearch delete-domain --domain-name ${DOMAIN_NAME:-<the domain>}"
        echo "  # wait for the domain to finish deleting, then re-run this script"
        echo ""
        echo "See the OpenSearch section of README.md before doing any of that."
        exit 1
    fi
    delete_opensearch_domain "$DOMAIN_NAME"
    PLAN_STATUS=0
    PLAN_OUTPUT=$(terraform plan -destroy 2>&1) || PLAN_STATUS=$?
    if [[ $PLAN_STATUS -ne 0 ]]; then
        printf '%s\n' "$PLAN_OUTPUT"
        echo -e "${RED}❌ The destroy plan failed after the OpenSearch domain was deleted${NC}"
        exit 1
    fi
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
ADMIN_SECRET_ARN=$(terraform output -raw iq_admin_password_secret_arn 2>/dev/null || true)
# When the output has no value, read the ARN from the state.
if [[ -z "$ADMIN_SECRET_ARN" ]]; then
  ADMIN_SECRET_ARN=$(terraform state show -no-color aws_secretsmanager_secret.iq_admin_password 2>/dev/null |
    sed -n 's/^ *arn *= *"\(.*\)"$/\1/p' || true)
fi

LICENSE_SECRET_ARN=$(terraform output -raw iq_license_secret_arn 2>/dev/null || true)

# A secret left in its recovery window keeps its name, so a later apply with the same
# cluster_name would fail to create it. Deleting each without recovery frees the name at once.
for secret_arn in "$DB_SECRET_ARN" "$ADMIN_SECRET_ARN" "$LICENSE_SECRET_ARN"; do
  if [[ -n "$secret_arn" ]]; then
    aws secretsmanager delete-secret \
      --secret-id "$secret_arn" \
      --force-delete-without-recovery \
      --region "$AWS_REGION" 2>/dev/null || true
  fi
done


# AWS creates these log groups itself, outside Terraform: the database's PostgreSQL log
# export and ECS Container Insights. They are read from state before the destroy and deleted after the
# destroy, so nothing named after this deployment is left behind.
state_attr() {
    terraform state show -no-color "$1" 2>/dev/null | sed -n "s/^    $2 *= *\"\(.*\)\"$/\1/p" | head -n 1
}
LEFTOVER_LOG_PREFIXES=""
for addr in $(terraform state list 2>/dev/null | grep -E '^aws_(rds_cluster|db_instance|ecs_cluster)\.' || true); do
    case "$addr" in
        aws_rds_cluster.*) id=$(state_attr "$addr" cluster_identifier); prefix="/aws/rds/cluster/$id/" ;;
        aws_db_instance.*) id=$(state_attr "$addr" identifier); prefix="/aws/rds/instance/$id/" ;;
        aws_ecs_cluster.*) id=$(state_attr "$addr" name); prefix="/aws/ecs/containerinsights/$id/" ;;
    esac
    if [[ -n "$id" ]]; then
        LEFTOVER_LOG_PREFIXES="$LEFTOVER_LOG_PREFIXES $prefix"
    fi
done

echo -e "${BLUE}🔥 Destroying Infrastructure${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "This may take 15-30 minutes to complete."
echo ""

# set -e is on, so the destroy's status is captured on the failure branch.
DESTROY_STATUS=0
terraform destroy -auto-approve || DESTROY_STATUS=$?

if [[ $DESTROY_STATUS -ne 0 ]]; then
    echo ""
    echo -e "${RED}❌ Destruction Failed: terraform destroy exited with status $DESTROY_STATUS${NC}"
    echo ""
    echo -e "${YELLOW}Common Issues:${NC}"
    echo "• Resources may have dependencies - check and retry"
    echo "• Deletion protection may be enabled"
    echo "• Some resources may need manual cleanup"
    echo ""
    echo "Retry with: ./tf-destroy.sh"
    exit "$DESTROY_STATUS"
fi

# Best effort: a log group that cannot be listed or deleted is reported, and does not fail
# a destroy that succeeded.
CLEANUP_WARNINGS=0
for prefix in $LEFTOVER_LOG_PREFIXES; do
    if ! groups=$(aws logs describe-log-groups --log-group-name-prefix "$prefix" --region "$AWS_REGION" \
        --query 'logGroups[].logGroupName' --output text 2>/dev/null); then
        echo -e "${YELLOW}⚠️  Could not list the log groups under $prefix, delete any left by hand${NC}"
        CLEANUP_WARNINGS=$((CLEANUP_WARNINGS + 1))
        continue
    fi
    for group in $groups; do
        [[ "$group" == "None" ]] && continue
        if aws logs delete-log-group --log-group-name "$group" --region "$AWS_REGION" 2>/dev/null; then
            echo "• Deleted log group $group, which AWS created outside Terraform"
        else
            echo -e "${YELLOW}⚠️  Could not delete log group $group, delete it by hand${NC}"
            CLEANUP_WARNINGS=$((CLEANUP_WARNINGS + 1))
        fi
    done
done

echo ""
echo -e "${GREEN}✅ Infrastructure Destroyed Successfully${NC}"
echo ""

echo -e "${BLUE}🧹 Cleanup Summary${NC}"
echo "━━━━━━━━━━━━━━━━━━"
echo "• All AWS resources destroyed"
echo "• Terraform state updated, terraform.tfstate.backup kept"
if [[ $CLEANUP_WARNINGS -gt 0 ]]; then
    echo -e "${YELLOW}• $CLEANUP_WARNINGS log group cleanup step(s) failed, see the warnings above${NC}"
fi
echo ""

rm -f tfplan

echo -e "${YELLOW}📝 Manual Cleanup Tasks (if needed)${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "• Remove any manual DNS records"
echo "• Clean up external monitoring"
echo "• Verify no orphaned resources"
echo ""

echo -e "${GREEN}✅ Destruction Process Completed${NC}"
