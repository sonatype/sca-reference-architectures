#!/bin/bash

# Terraform destroy script for Nexus IQ Server HA on EKS deployment
# Usage: ./tf-destroy.sh

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

echo -e "${RED}💥 Nexus IQ Server HA on EKS - Terraform Destroy${NC}"
echo "======================================================="
echo ""

# Check if we're in the right directory
if [[ ! -f "main.tf" ]]; then
    echo -e "${RED}❌ Error: main.tf not found in current directory${NC}"
    echo "Please run this script from the infra-aws-ha-k8s-helm directory"
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

# Check for Nexus IQ Server deployment
if command -v kubectl &> /dev/null; then
    echo -e "${BLUE}🔍 Checking for Nexus IQ Server deployment...${NC}"

    # Try to get cluster info first
    CLUSTER_NAME=""
    if [[ -f "terraform.tfstate" ]]; then
        CLUSTER_NAME=$(aws-vault exec "$AWS_PROFILE" -- terraform output -raw cluster_id 2>/dev/null || echo "")
    fi

    if [[ -n "$CLUSTER_NAME" ]]; then
        AWS_REGION=$(aws-vault exec "$AWS_PROFILE" -- terraform output -raw aws_region 2>/dev/null || grep '^aws_region' terraform.tfvars | cut -d'"' -f2 2>/dev/null || echo "us-east-1")

        # Configure kubectl silently
        aws-vault exec "$AWS_PROFILE" -- aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME" >/dev/null 2>&1 || true

        # Check for Nexus IQ Server deployment
        if aws-vault exec "$AWS_PROFILE" -- kubectl get namespace nexus-iq >/dev/null 2>&1; then
            echo -e "${YELLOW}⚠️  Found Nexus IQ Server namespace${NC}"
            echo ""
            echo -e "${RED}IMPORTANT: Nexus IQ Server appears to be deployed!${NC}"
            echo ""
            echo "Before destroying the infrastructure, you should:"
            echo "1. Backup any important Nexus IQ Server data"
            echo "2. Export configuration and policies"
            echo "3. Uninstall the Nexus IQ Server Helm release:"
            echo "   helm uninstall nexus-iq-server-ha -n nexus-iq"
            echo "4. Delete persistent volumes if needed:"
            echo "   kubectl delete pvc -n nexus-iq --all"
            echo ""

            echo -e "${YELLOW}⚠️  Proceeding with destruction - ensure data is backed up!${NC}"
        fi
    fi
fi

# Show what will be destroyed
echo -e "${BLUE}📊 Resources to be destroyed${NC}"
echo "=============================="
aws-vault exec "$AWS_PROFILE" -- terraform plan -destroy

echo ""
echo -e "${RED}⚠️  DANGER: This will permanently destroy ALL infrastructure${NC}"
echo ""
echo -e "${YELLOW}Resources that will be PERMANENTLY DELETED:${NC}"
echo "• EKS cluster and all workloads"
echo "• Aurora PostgreSQL cluster and ALL DATA"
echo "• EFS file system and ALL FILES"
echo "• Load balancers and networking components"
echo "• IAM roles and policies"
echo "• All associated AWS resources"
echo ""

# Get cluster info if available
if [[ -f "terraform.tfstate" ]]; then
    CLUSTER_NAME=$(aws-vault exec "$AWS_PROFILE" -- terraform output -raw cluster_id 2>/dev/null || echo "N/A")
    VPC_ID=$(aws-vault exec "$AWS_PROFILE" -- terraform output -raw vpc_id 2>/dev/null || echo "N/A")
    RDS_ENDPOINT=$(aws-vault exec "$AWS_PROFILE" -- terraform output -raw rds_cluster_endpoint 2>/dev/null || echo "N/A")
    EFS_ID=$(aws-vault exec "$AWS_PROFILE" -- terraform output -raw efs_id 2>/dev/null || echo "N/A")

    echo -e "${YELLOW}Current infrastructure:${NC}"
    echo "• EKS Cluster: $CLUSTER_NAME"
    echo "• VPC ID: $VPC_ID"
    echo "• EFS ID: $EFS_ID"
    echo "• RDS Cluster: ${RDS_ENDPOINT:0:50}..."
    echo ""
fi

# Proceeding with destruction
echo -e "${RED}💀 PROCEEDING WITH DESTRUCTION - THIS ACTION CANNOT BE UNDONE! 💀${NC}"

echo ""
echo -e "${BLUE}🧹 Destroying infrastructure...${NC}"
echo "This may take 15-20 minutes to complete."
echo ""

# Pre-destruction cleanup
echo -e "${BLUE}🧹 Pre-destruction cleanup...${NC}"

# Force delete secrets manager secrets to avoid retention period issues
echo "🗑️  Cleaning up Secrets Manager secrets..."
aws-vault exec "$AWS_PROFILE" -- aws secretsmanager delete-secret \
  --secret-id "nexus-iq-ha-db-credentials" \
  --force-delete-without-recovery \
  --region us-east-1 || echo "⚠️  Secret may not exist or already deleted"

# Disable RDS deletion protection if it exists
echo "🛡️  Disabling RDS deletion protection..."
if aws-vault exec "$AWS_PROFILE" -- aws rds modify-db-cluster \
  --db-cluster-identifier "nexus-iq-ha-aurora-cluster" \
  --no-deletion-protection \
  --apply-immediately \
  --region us-east-1 2>/dev/null; then

  # Wait for modification to complete (silently)
  timeout=600  # 10 minutes timeout
  elapsed=0
  while true; do
    STATUS=$(aws-vault exec "$AWS_PROFILE" -- aws rds describe-db-clusters \
      --db-cluster-identifier "nexus-iq-ha-aurora-cluster" \
      --region us-east-1 \
      --query 'DBClusters[0].Status' \
      --output text 2>/dev/null || echo "deleted")

    DELETION_PROTECTION=$(aws-vault exec "$AWS_PROFILE" -- aws rds describe-db-clusters \
      --db-cluster-identifier "nexus-iq-ha-aurora-cluster" \
      --region us-east-1 \
      --query 'DBClusters[0].DeletionProtection' \
      --output text 2>/dev/null || echo "false")

    if [[ "$STATUS" == "available" && "$DELETION_PROTECTION" == "False" ]]; then
      break
    elif [[ "$STATUS" == "deleted" ]]; then
      break
    elif [ $elapsed -ge $timeout ]; then
      break
    fi

    sleep 15
    elapsed=$((elapsed + 15))
  done
fi

# Check for Load Balancers that might block destruction
if command -v kubectl &> /dev/null && [[ -n "$CLUSTER_NAME" ]]; then
    echo "🔍  Checking for load balancers..."

    # Delete any LoadBalancer services that might create ELBs
    aws-vault exec "$AWS_PROFILE" -- kubectl delete svc --all-namespaces --field-selector spec.type=LoadBalancer --ignore-not-found=true >/dev/null 2>&1 || true

    # Wait a moment for ELBs to be cleaned up
    echo "   Waiting for load balancer cleanup..."
    sleep 30
fi

# Run terraform destroy
echo -e "${RED}💥 Running terraform destroy...${NC}"
echo ""

# Destroy in stages to handle dependencies
echo -e "${BLUE}Stage 1: Destroying Kubernetes resources...${NC}"
aws-vault exec "$AWS_PROFILE" -- terraform destroy -target=helm_release.aws_load_balancer_controller -auto-approve || true

echo ""
echo -e "${BLUE}Stage 2: Destroying remaining infrastructure...${NC}"

if aws-vault exec "$AWS_PROFILE" -- terraform destroy -auto-approve; then
    echo ""
    echo -e "${GREEN}✅ Infrastructure destroyed successfully${NC}"
    echo ""

    echo -e "${BLUE}🧹 Clean-up completed${NC}"
    echo "==================="
    echo "• All AWS resources have been destroyed"
    echo "• EKS cluster, Aurora database, EFS, and ALB completely removed"
    echo "• Terraform state has been updated"
    echo "• Local plan files have been removed"
    echo ""

    # Clean up local files
    rm -f tfplan terraform.tfstate.backup

    echo -e "${YELLOW}📝 Manual clean-up tasks (if needed):${NC}"
    echo "• Remove any manually created DNS records"
    echo "• Clean up any external monitoring configurations"
    echo "• Verify no orphaned EKS resources remain"
    echo "• Check for any remaining CloudWatch alarms or dashboards"
    echo ""

    echo -e "${GREEN}✅ Destruction process completed${NC}"

else
    echo -e "${RED}❌ Destruction failed${NC}"
    echo ""
    echo -e "${YELLOW}Common issues and solutions:${NC}"
    echo "• ELBs may take time to delete - wait and retry"
    echo "• Security groups might have dependencies - check for attached resources"
    echo "• EKS deletion protection might be enabled - disable and retry"
    echo "• Some resources might need manual cleanup"
    echo ""
    echo "You can retry destruction with: ./tf-destroy.sh"
    echo "Or run 'terraform destroy' manually for more detailed error information"
    exit 1
fi