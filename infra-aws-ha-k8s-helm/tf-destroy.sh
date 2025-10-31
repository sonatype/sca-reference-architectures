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

# Disable AWS CLI pager to prevent interactive prompts
export AWS_PAGER=""

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

  echo "   Waiting for RDS cluster modification to complete..."
  # Wait for modification to complete (silently)
  timeout=600  # 10 minutes timeout
  elapsed=0

  # Use a single aws-vault session to avoid re-authentication in the loop
  while true; do
    # Get both status and deletion protection in a single call to minimize aws-vault overhead
    CLUSTER_INFO=$(aws-vault exec "$AWS_PROFILE" -- aws rds describe-db-clusters \
      --db-cluster-identifier "nexus-iq-ha-aurora-cluster" \
      --region us-east-1 \
      --query 'DBClusters[0].[Status,DeletionProtection]' \
      --output text 2>/dev/null || echo "deleted false")

    STATUS=$(echo "$CLUSTER_INFO" | awk '{print $1}')
    DELETION_PROTECTION=$(echo "$CLUSTER_INFO" | awk '{print $2}')

    if [[ "$STATUS" == "available" && "$DELETION_PROTECTION" == "False" ]]; then
      echo "   ✅ Deletion protection disabled"
      break
    elif [[ "$STATUS" == "deleted" ]]; then
      echo "   ✅ Cluster already deleted"
      break
    elif [ $elapsed -ge $timeout ]; then
      echo "   ⚠️  Timeout waiting for cluster modification, continuing anyway..."
      break
    fi

    sleep 15
    elapsed=$((elapsed + 15))
    echo "   Still waiting... (${elapsed}s elapsed)"
  done
else
  echo "   ✅ RDS cluster not found or already deleted"
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

# Additional cleanup for VPC resources that block deletion
if [[ -n "$VPC_ID" && "$VPC_ID" != "N/A" ]]; then
    echo "🧹  Cleaning up VPC dependencies..."
    AWS_REGION=$(grep '^aws_region' terraform.tfvars | cut -d'"' -f2 2>/dev/null || echo "us-east-1")

    # Clean up any remaining Load Balancers in the VPC
    echo "   Removing Load Balancers..."

    # Get list of ALB/NLB ARNs in this VPC using json output for reliability
    LB_ARNS=$(aws-vault exec "$AWS_PROFILE" -- aws elbv2 describe-load-balancers \
      --region "$AWS_REGION" 2>/dev/null | \
      jq -r ".LoadBalancers[] | select(.VpcId==\"$VPC_ID\") | .LoadBalancerArn" 2>/dev/null || echo "")

    if [[ -n "$LB_ARNS" ]]; then
        while IFS= read -r LB_ARN; do
            if [[ -n "$LB_ARN" ]]; then
                LB_NAME=$(echo "$LB_ARN" | awk -F'/' '{print $2"/"$3}')
                echo "   Deleting ALB/NLB: $LB_NAME"
                aws-vault exec "$AWS_PROFILE" -- aws elbv2 delete-load-balancer \
                  --load-balancer-arn "$LB_ARN" \
                  --region "$AWS_REGION" 2>&1 || echo "   Failed to delete, will retry"
            fi
        done <<< "$LB_ARNS"
    else
        echo "   No ALB/NLB found (or jq not installed, trying alternative method)"

        # Fallback if jq is not available
        ALL_LB_ARNS=$(aws-vault exec "$AWS_PROFILE" -- aws elbv2 describe-load-balancers \
          --region "$AWS_REGION" \
          --query "LoadBalancers[?VpcId=='$VPC_ID'].LoadBalancerArn" \
          --output text 2>/dev/null || echo "")

        for LB_ARN in $ALL_LB_ARNS; do
            if [[ -n "$LB_ARN" && "$LB_ARN" != "None" ]]; then
                echo "   Deleting ALB/NLB: $LB_ARN"
                aws-vault exec "$AWS_PROFILE" -- aws elbv2 delete-load-balancer \
                  --load-balancer-arn "$LB_ARN" \
                  --region "$AWS_REGION" 2>&1 || echo "   Failed to delete"
            fi
        done
    fi

    # Classic Load Balancers
    CLB_NAMES=$(aws-vault exec "$AWS_PROFILE" -- aws elb describe-load-balancers \
      --region "$AWS_REGION" \
      --query "LoadBalancerDescriptions[?VPCId=='$VPC_ID'].LoadBalancerName" \
      --output text 2>/dev/null || echo "")

    for CLB_NAME in $CLB_NAMES; do
        echo "   Deleting Classic ELB: $CLB_NAME"
        aws-vault exec "$AWS_PROFILE" -- aws elb delete-load-balancer \
          --load-balancer-name "$CLB_NAME" \
          --region "$AWS_REGION" 2>/dev/null || true
    done

    # Wait for load balancers to be deleted and ENIs to be released
    if [[ -n "$LB_ARNS" || -n "$ALL_LB_ARNS" || -n "$CLB_NAMES" ]]; then
        echo "   Waiting for load balancers to finish deleting (90 seconds)..."
        sleep 90
    fi

    # Clean up Network Interfaces (ENIs) that might be blocking subnet deletion
    echo "   Removing orphaned Network Interfaces..."

    # Wait for ENIs to become available after LB deletion
    echo "   Waiting for ENIs to be released (30 seconds)..."
    sleep 30

    # Get all ENIs in the VPC that are available or requester-managed
    ENI_IDS=$(aws-vault exec "$AWS_PROFILE" -- aws ec2 describe-network-interfaces \
      --region "$AWS_REGION" \
      --filters "Name=vpc-id,Values=$VPC_ID" \
      --query 'NetworkInterfaces[?Status==`available`].NetworkInterfaceId' \
      --output text 2>/dev/null || echo "")

    for ENI_ID in $ENI_IDS; do
        echo "   Deleting ENI: $ENI_ID"
        aws-vault exec "$AWS_PROFILE" -- aws ec2 delete-network-interface \
          --network-interface-id "$ENI_ID" \
          --region "$AWS_REGION" 2>/dev/null || true
    done

    # Additional wait for AWS to process ENI deletions
    if [[ -n "$ENI_IDS" ]]; then
        echo "   Waiting for ENI cleanup to complete (30 seconds)..."
        sleep 30
    fi

    # Clean up NAT Gateways (they can block public IP releases)
    echo "   Removing NAT Gateways..."
    NAT_IDS=$(aws-vault exec "$AWS_PROFILE" -- aws ec2 describe-nat-gateways \
      --region "$AWS_REGION" \
      --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available" \
      --query 'NatGateways[].NatGatewayId' \
      --output text 2>/dev/null || echo "")

    for NAT_ID in $NAT_IDS; do
        echo "   Deleting NAT Gateway: $NAT_ID"
        aws-vault exec "$AWS_PROFILE" -- aws ec2 delete-nat-gateway \
          --nat-gateway-id "$NAT_ID" \
          --region "$AWS_REGION" 2>/dev/null || true
    done

    if [[ -n "$NAT_IDS" ]]; then
        echo "   Waiting for NAT Gateways to finish deleting (90 seconds)..."
        sleep 90
    fi

    # Release Elastic IPs that might be blocking Internet Gateway detachment
    echo "   Releasing Elastic IPs..."
    EIP_ALLOCS=$(aws-vault exec "$AWS_PROFILE" -- aws ec2 describe-addresses \
      --region "$AWS_REGION" \
      --filters "Name=domain,Values=vpc" \
      --query "Addresses[?AssociationId==null].AllocationId" \
      --output text 2>/dev/null || echo "")

    for ALLOC_ID in $EIP_ALLOCS; do
        echo "   Releasing EIP: $ALLOC_ID"
        aws-vault exec "$AWS_PROFILE" -- aws ec2 release-address \
          --allocation-id "$ALLOC_ID" \
          --region "$AWS_REGION" 2>/dev/null || true
    done

    echo "   VPC cleanup completed"
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