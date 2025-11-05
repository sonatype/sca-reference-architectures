#!/bin/bash

# Terraform apply script for Nexus IQ Server HA on AKS deployment
# Usage: ./tf-apply.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

TERRAFORM_DIR="$(dirname "$0")"

echo -e "${BLUE}🚀 Nexus IQ Server HA on AKS - Terraform Apply${NC}"
echo "======================================================="
echo ""

# Check if we're in the right directory
if [[ ! -f "main.tf" ]]; then
    echo -e "${RED}❌ Error: main.tf not found in current directory${NC}"
    echo "Please run this script from the infra-azure-ha-k8s-helm directory"
    exit 1
fi

# Check if plan file exists
if [[ ! -f "tfplan" ]]; then
    echo -e "${RED}❌ Error: tfplan file not found${NC}"
    echo "Please run ./tf-plan.sh first to generate a plan"
    exit 1
fi

# Check for required tools
command -v az >/dev/null 2>&1 || {
    echo -e "${RED}❌ Error: Azure CLI is required but not installed${NC}"
    exit 1
}

command -v terraform >/dev/null 2>&1 || {
    echo -e "${RED}❌ Error: terraform is required but not installed${NC}"
    exit 1
}

echo -e "${BLUE}📋 Pre-deployment checks${NC}"
echo "• Azure CLI installed ✓"
echo "• Terraform installed ✓"
echo "• Plan file: tfplan ✓"
echo ""

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo -e "${YELLOW}⚠️  Warning: kubectl not found in PATH${NC}"
    echo "kubectl is required for AKS cluster management"
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

echo -e "${BLUE}🚀 Proceeding with deployment...${NC}"
echo ""

# State validation check
echo -e "${BLUE}🔍 Validating Terraform state...${NC}"
if [[ -f "terraform.tfstate" ]]; then
    # Check if critical resources exist in state
    STATE_RESOURCES=$(terraform state list 2>/dev/null || echo "")

    if [[ -n "$STATE_RESOURCES" ]]; then
        # State has resources - check if major infrastructure exists
        CRITICAL_RESOURCES=(
            "azurerm_resource_group.iq_rg"
            "azurerm_kubernetes_cluster.iq_aks"
            "azurerm_postgresql_flexible_server.iq_db"
            "azurerm_storage_account.iq_storage"
            "azurerm_application_gateway.appgw"
        )

        MISSING_RESOURCES=()
        for resource in "${CRITICAL_RESOURCES[@]}"; do
            if ! echo "$STATE_RESOURCES" | grep -q "^${resource}$"; then
                MISSING_RESOURCES+=("$resource")
            fi
        done

        if [[ ${#MISSING_RESOURCES[@]} -gt 0 ]] && [[ ${#MISSING_RESOURCES[@]} -lt ${#CRITICAL_RESOURCES[@]} ]]; then
            echo -e "${RED}❌ ERROR: Terraform state is incomplete!${NC}"
            echo ""
            echo "The following critical resources exist in Azure but are MISSING from state:"
            for resource in "${MISSING_RESOURCES[@]}"; do
                echo "  • $resource"
            done
            echo ""
            echo -e "${YELLOW}This will cause Terraform to try recreating existing infrastructure!${NC}"
            echo ""
            echo "To fix this issue:"
            echo "1. Cancel this apply (if not already done)"
            echo "2. Import missing resources into state, OR"
            echo "3. Restore terraform.tfstate from backup (terraform.tfstate.backup)"
            echo ""
            echo "Example import command:"
            echo "  terraform import azurerm_postgresql_flexible_server.iq_db /subscriptions/SUBSCRIPTION_ID/resourceGroups/RESOURCE_GROUP/providers/Microsoft.DBforPostgreSQL/flexibleServers/SERVER_NAME"
            echo ""
            exit 1
        fi

        echo "• State validation passed ✓"
    else
        echo -e "${YELLOW}⚠️  Warning: Terraform state exists but appears empty${NC}"
        echo "This is normal for first-time deployment"
    fi
else
    echo "• No existing state file (first-time deployment)"
fi
echo ""

echo -e "${BLUE}🏗️  Applying Terraform configuration...${NC}"
echo "This may take 15-25 minutes to complete."
echo ""

# Apply terraform with plan file
if terraform apply tfplan; then
    echo ""
    echo -e "${GREEN}✅ Deployment completed successfully!${NC}"
    echo ""

    # Get important outputs
    echo -e "${BLUE}📊 Deployment Summary${NC}"
    echo "===================="

    CLUSTER_NAME=$(terraform output -raw aks_cluster_name 2>/dev/null || echo "N/A")
    CLUSTER_ENDPOINT=$(terraform output -raw aks_cluster_endpoint 2>/dev/null || echo "N/A")
    RG_NAME=$(terraform output -raw resource_group_name 2>/dev/null || echo "N/A")
    POSTGRES_FQDN=$(terraform output -raw postgres_server_fqdn 2>/dev/null || echo "N/A")
    APPGW_IP=$(terraform output -raw application_gateway_public_ip 2>/dev/null || echo "N/A")

    echo "• AKS Cluster: $CLUSTER_NAME"
    echo "• Resource Group: $RG_NAME"
    echo "• Cluster Endpoint: $CLUSTER_ENDPOINT"
    echo "• Database: PostgreSQL Flexible Server (Zone-Redundant HA)"
    echo "• PostgreSQL FQDN: $POSTGRES_FQDN"
    echo "• Application Gateway IP: $APPGW_IP"
    echo ""

    # Configure kubectl
    if command -v kubectl &> /dev/null; then
        echo -e "${BLUE}⚙️  Configuring kubectl...${NC}"

        if [[ "$CLUSTER_NAME" != "N/A" && "$RG_NAME" != "N/A" ]]; then
            echo "• Configuring kubectl: az aks get-credentials --resource-group $RG_NAME --name $CLUSTER_NAME"
            if az aks get-credentials --resource-group "$RG_NAME" --name "$CLUSTER_NAME" --overwrite-existing; then
                echo -e "${GREEN}✅ kubectl configured successfully${NC}"

                # Wait for cluster to be ready
                echo ""
                echo -e "${BLUE}⏳ Waiting for AKS cluster to be ready...${NC}"
                timeout=600  # 10 minutes
                elapsed=0
                while ! kubectl get nodes >/dev/null 2>&1; do
                    if [ $elapsed -ge $timeout ]; then
                        echo -e "${YELLOW}⚠️  Timeout waiting for cluster nodes. You may need to wait longer.${NC}"
                        break
                    fi
                    echo "   Waiting for nodes to be ready... (${elapsed}s/${timeout}s)"
                    sleep 10
                    elapsed=$((elapsed + 10))
                done

                if kubectl get nodes >/dev/null 2>&1; then
                    echo -e "${GREEN}✅ AKS cluster is ready${NC}"
                    kubectl get nodes -o wide
                    echo ""
                fi
            else
                echo -e "${YELLOW}⚠️  Failed to configure kubectl${NC}"
            fi
        fi
    fi

    echo -e "${BLUE}🎯 Next Steps${NC}"
    echo "============"
    echo "1. Wait for Application Gateway Ingress Controller to be deployed (5-10 minutes)"
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
