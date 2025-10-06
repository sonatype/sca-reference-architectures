#!/bin/bash

# Terraform apply script for Nexus IQ Server HA on EKS deployment
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

echo -e "${BLUE}🚀 Nexus IQ Server HA on EKS - Terraform Apply${NC}"
echo "======================================================="
echo ""

# Check if we're in the right directory
if [[ ! -f "main.tf" ]]; then
    echo -e "${RED}❌ Error: main.tf not found in current directory${NC}"
    echo "Please run this script from the infra-aws-ha-k8s-helm directory"
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

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo -e "${YELLOW}⚠️  Warning: kubectl not found in PATH${NC}"
    echo "kubectl is required for EKS cluster management"
    echo "Install kubectl: https://kubernetes.io/docs/tasks/tools/install-kubectl/"
    echo ""
fi

# Check if helm is installed
if ! command -v helm &> /dev/null; then
    echo -e "${YELLOW}⚠️  Warning: helm not found in PATH${NC}"
    echo "Helm is required for Nexus IQ Server deployment"
    echo "Install Helm: https://helm.sh/docs/intro/install/"
    echo ""
fi

echo -e "${YELLOW}⚠️  You are about to deploy Nexus IQ Server HA on EKS infrastructure${NC}"
echo "This will create AWS resources that may incur costs."
echo ""
echo -e "${YELLOW}Resources to be created:${NC}"
echo "• EKS cluster with managed node groups"
echo "• Aurora PostgreSQL cluster (2 instances)"
echo "• EFS file system with access points"
echo "• Application Load Balancer components"
echo "• Security groups and networking"
echo "• IAM roles and policies"
echo "• AWS Load Balancer Controller"
echo ""

echo "🚀 Proceeding with deployment..."
echo ""

# Pre-deployment cleanup
echo -e "${BLUE}🧹 Pre-deployment cleanup...${NC}"

# Check and disable RDS deletion protection if cluster exists
echo "🛡️  Checking RDS cluster deletion protection..."
RDS_EXISTS=$(aws-vault exec "$AWS_PROFILE" -- aws rds describe-db-clusters \
  --db-cluster-identifier "nexus-iq-ha-aurora-cluster" \
  --region us-east-1 \
  --query 'DBClusters[0].DeletionProtection' \
  --output text 2>/dev/null || echo "None")

if [[ "$RDS_EXISTS" == "True" ]]; then
    echo "• RDS deletion protection is enabled, disabling..."
    aws-vault exec "$AWS_PROFILE" -- aws rds modify-db-cluster \
      --db-cluster-identifier "nexus-iq-ha-aurora-cluster" \
      --no-deletion-protection \
      --apply-immediately \
      --region us-east-1

    # Wait for modification to complete
    echo "• Waiting for RDS modification to complete..."
    sleep 15

    # Verify the change
    PROTECTION_STATUS=$(aws-vault exec "$AWS_PROFILE" -- aws rds describe-db-clusters \
      --db-cluster-identifier "nexus-iq-ha-aurora-cluster" \
      --region us-east-1 \
      --query 'DBClusters[0].DeletionProtection' \
      --output text 2>/dev/null || echo "None")

    echo "• RDS deletion protection status: $PROTECTION_STATUS"
elif [[ "$RDS_EXISTS" == "False" ]]; then
    echo "• RDS cluster exists but deletion protection is already disabled"
else
    echo "• RDS cluster does not exist or is not accessible"
fi

# Force delete any existing secrets to avoid conflicts
echo "🗑️  Cleaning up existing secrets..."
aws-vault exec "$AWS_PROFILE" -- aws secretsmanager delete-secret \
  --secret-id "nexus-iq-ha-db-credentials" \
  --force-delete-without-recovery \
  --region us-east-1 >/dev/null 2>&1 || echo "• No existing secrets to clean up"

# Wait a moment for changes to propagate
echo "• Waiting for changes to propagate..."
sleep 10

echo ""
echo -e "${BLUE}🏗️  Applying Terraform configuration...${NC}"
echo "This may take 15-25 minutes to complete."
echo ""

# Apply terraform with plan file
if aws-vault exec "$AWS_PROFILE" -- terraform apply tfplan; then
    echo ""
    echo -e "${GREEN}✅ Deployment completed successfully!${NC}"
    echo ""

    # Get important outputs
    echo -e "${BLUE}📊 Deployment Summary${NC}"
    echo "===================="

    CLUSTER_NAME=$(aws-vault exec "$AWS_PROFILE" -- terraform output -raw cluster_id 2>/dev/null || echo "N/A")
    # If cluster_id fails, try cluster_name
    if [[ "$CLUSTER_NAME" == "N/A" ]]; then
        CLUSTER_NAME=$(aws-vault exec "$AWS_PROFILE" -- terraform output -raw cluster_name 2>/dev/null || echo "N/A")
    fi
    CLUSTER_ENDPOINT=$(aws-vault exec "$AWS_PROFILE" -- terraform output -raw cluster_endpoint 2>/dev/null || echo "N/A")
    VPC_ID=$(aws-vault exec "$AWS_PROFILE" -- terraform output -raw vpc_id 2>/dev/null || echo "N/A")
    RDS_ENDPOINT=$(aws-vault exec "$AWS_PROFILE" -- terraform output -raw rds_cluster_endpoint 2>/dev/null || echo "N/A")
    EFS_ID=$(aws-vault exec "$AWS_PROFILE" -- terraform output -raw efs_id 2>/dev/null || echo "N/A")

    echo "• EKS Cluster: $CLUSTER_NAME"
    echo "• Cluster Endpoint: $CLUSTER_ENDPOINT"
    echo "• VPC ID: $VPC_ID"
    echo "• EFS ID: $EFS_ID"
    echo "• Database: Aurora PostgreSQL (HA cluster)"
    echo ""

    # Configure kubectl
    if command -v kubectl &> /dev/null; then
        echo -e "${BLUE}⚙️  Configuring kubectl...${NC}"
        # Get AWS region from terraform output or tfvars
        AWS_REGION=$(aws-vault exec "$AWS_PROFILE" -- terraform output -raw aws_region 2>/dev/null || grep '^aws_region' terraform.tfvars | cut -d'"' -f2)

        # Use the kubectl config command from terraform output if available
        KUBECTL_COMMAND=$(aws-vault exec "$AWS_PROFILE" -- terraform output -raw kubectl_config_command 2>/dev/null || echo "")

        if [[ -n "$KUBECTL_COMMAND" ]]; then
            echo "• Using terraform output command: $KUBECTL_COMMAND"
            if aws-vault exec "$AWS_PROFILE" -- $KUBECTL_COMMAND; then
                echo -e "${GREEN}✅ kubectl configured successfully${NC}"
            else
                echo -e "${YELLOW}⚠️  kubectl config command failed, trying manual approach${NC}"
                aws-vault exec "$AWS_PROFILE" -- aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"
            fi
        elif [[ "$CLUSTER_NAME" != "N/A" ]]; then
            echo "• Configuring kubectl manually: aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME"
            if aws-vault exec "$AWS_PROFILE" -- aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"; then
                echo -e "${GREEN}✅ kubectl configured successfully${NC}"
            else
                echo -e "${YELLOW}⚠️  Failed to configure kubectl${NC}"
            fi
        else
            echo -e "${YELLOW}⚠️  No valid cluster name found, skipping kubectl configuration${NC}"
        fi

        if [[ "$CLUSTER_NAME" != "N/A" ]]; then
            echo ""
            # Wait for cluster to be ready
            echo -e "${BLUE}⏳ Waiting for EKS cluster to be ready...${NC}"
            timeout=900  # Increased to 15 minutes
            elapsed=0
            while ! aws-vault exec "$AWS_PROFILE" -- kubectl get nodes >/dev/null 2>&1; do
                if [ $elapsed -ge $timeout ]; then
                    echo -e "${YELLOW}⚠️  Timeout waiting for cluster nodes. You may need to wait longer.${NC}"
                    break
                fi
                echo "   Waiting for nodes to be ready... (${elapsed}s/${timeout}s)"
                sleep 10
                elapsed=$((elapsed + 10))
            done

            if aws-vault exec "$AWS_PROFILE" -- kubectl get nodes >/dev/null 2>&1; then
                echo -e "${GREEN}✅ EKS cluster is ready${NC}"
                aws-vault exec "$AWS_PROFILE" -- kubectl get nodes -o wide
                echo ""
            fi
        else
            echo -e "${YELLOW}⚠️  Failed to configure kubectl. You can manually configure it with:${NC}"
            echo "   aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME"
            echo ""
        fi
    fi

    echo -e "${BLUE}🎯 Next Steps${NC}"
    echo "============"
    echo "1. Wait for AWS Load Balancer Controller to be deployed (5-10 minutes)"
    echo "2. Deploy Nexus IQ Server using Helm:"
    echo "   ./helm-install.sh"
    echo ""
    echo "3. Monitor the deployment:"
    echo "   kubectl get pods -n nexus-iq -w"
    echo ""
    echo "4. Check cluster status:"
    echo "   kubectl get nodes"
    echo "   kubectl get pods --all-namespaces"
    echo ""

    # Clean up plan file
    if [[ -f "tfplan" ]]; then
        rm tfplan
        echo -e "${GREEN}✅ Deployment artifacts cleaned up${NC}"
    fi

else
    echo -e "${RED}❌ Deployment failed${NC}"
    echo "Check the error messages above and fix any issues."
    echo "You may need to run './tf-plan.sh' again after making changes."
    exit 1
fi