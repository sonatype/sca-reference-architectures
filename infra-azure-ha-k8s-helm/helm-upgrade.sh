#!/bin/bash

# Helm upgrade script for Nexus IQ Server HA deployment on AKS
# Usage: ./helm-upgrade.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="nexus-iq"
HELM_RELEASE_NAME="nexus-iq-server-ha"
HELM_CHART_REPO="https://sonatype.github.io/helm3-charts"
HELM_CHART_NAME="nexus-iq-server-ha"
VALUES_FILE="helm-values.yaml"

echo -e "${BLUE}🔄 Nexus IQ Server HA - Helm Upgrade (Azure AKS)${NC}"
echo "=========================================="
echo ""

# Check prerequisites
echo -e "${BLUE}🔍 Checking prerequisites...${NC}"

# Check if kubectl is available and configured
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}❌ Error: kubectl not found in PATH${NC}"
    echo "Please install kubectl: https://kubernetes.io/docs/tasks/tools/install-kubectl/"
    exit 1
fi

# Check if helm is available
if ! command -v helm &> /dev/null; then
    echo -e "${RED}❌ Error: helm not found in PATH${NC}"
    echo "Please install Helm: https://helm.sh/docs/intro/install/"
    exit 1
fi

# Check if az CLI is available
if ! command -v az &> /dev/null; then
    echo -e "${RED}❌ Error: Azure CLI (az) not found in PATH${NC}"
    echo "Please install Azure CLI: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

# Check if we can connect to Kubernetes cluster, if not try to configure kubectl
if ! kubectl cluster-info >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  Cannot connect to Kubernetes cluster, attempting to configure kubectl...${NC}"

    # Get kubectl config command from terraform outputs
    KUBECTL_COMMAND=$(terraform output -raw kubectl_config_command 2>/dev/null || echo "")

    if [[ -n "$KUBECTL_COMMAND" ]]; then
        echo "• Using terraform kubectl command: $KUBECTL_COMMAND"
        eval "$KUBECTL_COMMAND"

        # Test connection again
        echo "• Testing kubectl connection..."
        sleep 2
        if kubectl cluster-info >/dev/null 2>&1; then
            echo -e "${GREEN}✅ kubectl configured successfully${NC}"
        else
            echo -e "${RED}❌ Error: kubectl configuration failed${NC}"
            echo "Please configure kubectl manually with:"
            echo "  $KUBECTL_COMMAND"
            exit 1
        fi
    else
        echo -e "${RED}❌ Error: Cannot get kubectl config command from terraform outputs${NC}"
        echo "Please configure kubectl manually with:"
        echo "  az aks get-credentials --resource-group rg-nexus-iq-ha --name aks-nexus-iq-ha"
        exit 1
    fi
fi

# Check if values file exists
if [[ ! -f "$VALUES_FILE" ]]; then
    echo -e "${RED}❌ Error: $VALUES_FILE not found${NC}"
    echo "Please ensure the Helm values file is available"
    exit 1
fi

# Check if namespace exists
if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    echo -e "${RED}❌ Error: Namespace '$NAMESPACE' does not exist${NC}"
    echo "Please run ./helm-install.sh first to install Nexus IQ Server HA"
    exit 1
fi

# Check if release exists
if ! helm list -n "$NAMESPACE" | grep -q "$HELM_RELEASE_NAME"; then
    echo -e "${RED}❌ Error: Helm release '$HELM_RELEASE_NAME' not found${NC}"
    echo "Please run ./helm-install.sh first to install Nexus IQ Server HA"
    exit 1
fi

echo -e "${GREEN}✅ Prerequisites check passed${NC}"
echo ""

# Get current release information
echo -e "${BLUE}📊 Current Release Information:${NC}"
helm list -n "$NAMESPACE"
echo ""

CURRENT_REVISION=$(helm list -n "$NAMESPACE" -o json | jq -r ".[] | select(.name==\"$HELM_RELEASE_NAME\") | .revision")
CURRENT_CHART=$(helm list -n "$NAMESPACE" -o json | jq -r ".[] | select(.name==\"$HELM_RELEASE_NAME\") | .chart")

echo "   Current Revision: $CURRENT_REVISION"
echo "   Current Chart: $CURRENT_CHART"
echo ""

# Get Terraform outputs
echo -e "${BLUE}📊 Getting infrastructure details from Terraform...${NC}"

if [[ -f "terraform.tfstate" ]]; then
    DB_ENDPOINT=$(terraform output -raw postgres_fqdn 2>/dev/null)
    AZURE_REGION=$(terraform output -raw location 2>/dev/null || grep '^location' terraform.tfvars | cut -d'"' -f2)
    CLUSTER_NAME=$(terraform output -raw aks_cluster_name 2>/dev/null)
    RESOURCE_GROUP=$(terraform output -raw resource_group_name 2>/dev/null)

    echo "   Database Endpoint: $DB_ENDPOINT"
    echo "   Azure Region: $AZURE_REGION"
    echo "   AKS Cluster: $CLUSTER_NAME"
    echo "   Resource Group: $RESOURCE_GROUP"
else
    echo -e "${YELLOW}⚠️  Terraform state not found, using defaults${NC}"
    AZURE_REGION=$(grep '^location' terraform.tfvars | cut -d'"' -f2 2>/dev/null || echo "eastus")
fi
echo ""

# Update Helm repository
echo -e "${BLUE}📦 Updating Helm repository...${NC}"
helm repo update
echo -e "${GREEN}✅ Helm repository updated${NC}"
echo ""

# Show available chart versions
echo -e "${BLUE}📋 Available Chart Versions:${NC}"
helm search repo sonatype/nexus-iq-server-ha --versions | head -5
echo ""

# Get target chart version
CHART_VERSION=$(grep '^helm_chart_version' terraform.tfvars | cut -d'"' -f2 2>/dev/null || echo "latest")
echo "   Target Chart Version: $CHART_VERSION"
echo ""

# Create temporary values file with substituted variables
echo -e "${BLUE}⚙️  Preparing Helm values...${NC}"

TEMP_VALUES_FILE="helm-values-runtime.yaml"
cp "$VALUES_FILE" "$TEMP_VALUES_FILE"

# Get database password from terraform
DB_PASSWORD=$(grep '^database_password' terraform.tfvars | cut -d'"' -f2)

# Substitute runtime values if Terraform state is available
if [[ -f "terraform.tfstate" && -n "$DB_ENDPOINT" ]]; then
    sed -i.bak \
        -e "s/hostname: \"\"/hostname: \"$DB_ENDPOINT\"/" \
        -e "s/password: \"\"/password: \"$DB_PASSWORD\"/" \
        "$TEMP_VALUES_FILE"
fi

echo -e "${GREEN}✅ Helm values prepared${NC}"
echo ""

# Show what will be upgraded
echo -e "${BLUE}🔍 Checking upgrade changes...${NC}"
echo ""

helm diff upgrade "$HELM_RELEASE_NAME" sonatype/nexus-iq-server-ha \
    --namespace "$NAMESPACE" \
    --version "$CHART_VERSION" \
    --values "$TEMP_VALUES_FILE" \
    --allow-unreleased 2>/dev/null || echo -e "${YELLOW}⚠️  helm diff plugin not available, continuing with upgrade${NC}"

echo ""

# Confirm upgrade
read -p "Do you want to continue with the upgrade? (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo -e "${YELLOW}❌ Upgrade cancelled${NC}"
    rm -f "$TEMP_VALUES_FILE" "${TEMP_VALUES_FILE}.bak"
    exit 0
fi

# Backup current values before upgrade
echo -e "${BLUE}💾 Creating backup of current configuration...${NC}"
helm get values "$HELM_RELEASE_NAME" -n "$NAMESPACE" > "backup-values-revision-${CURRENT_REVISION}.yaml"
echo -e "${GREEN}✅ Backup saved as: backup-values-revision-${CURRENT_REVISION}.yaml${NC}"
echo ""

# Perform rolling upgrade
echo -e "${BLUE}🔄 Performing Helm upgrade...${NC}"
echo ""

helm upgrade "$HELM_RELEASE_NAME" sonatype/nexus-iq-server-ha \
    --namespace "$NAMESPACE" \
    --version "$CHART_VERSION" \
    --values "$TEMP_VALUES_FILE" \
    --timeout 20m \
    --wait \
    --atomic

echo ""
echo -e "${GREEN}✅ Nexus IQ Server HA upgrade completed!${NC}"
echo ""

# Clean up temporary files
rm -f "$TEMP_VALUES_FILE" "${TEMP_VALUES_FILE}.bak"

# Show upgrade information
echo -e "${BLUE}📊 Upgrade Information:${NC}"
helm list -n "$NAMESPACE"
echo ""

NEW_REVISION=$(helm list -n "$NAMESPACE" -o json | jq -r ".[] | select(.name==\"$HELM_RELEASE_NAME\") | .revision")
echo "   Previous Revision: $CURRENT_REVISION"
echo "   New Revision: $NEW_REVISION"
echo ""

# Show pod status
echo -e "${BLUE}📊 Pod Status:${NC}"
kubectl get pods -n "$NAMESPACE" -o wide
echo ""

# Check rollout status
echo -e "${BLUE}⏳ Checking rollout status...${NC}"
kubectl rollout status deployment/nexus-iq-server-ha-iq-server-deployment -n "$NAMESPACE" --timeout=600s || true
echo ""

# Show service information
echo -e "${BLUE}🔗 Service Information:${NC}"
kubectl get svc -n "$NAMESPACE"
echo ""

# Show Application Gateway URL if available
if [[ -f "terraform.tfstate" ]]; then
    APP_GATEWAY_URL=$(terraform output -raw application_gateway_url 2>/dev/null || echo "")
    if [[ -n "$APP_GATEWAY_URL" ]]; then
        echo -e "${BLUE}🌐 Application URL:${NC}"
        echo "   $APP_GATEWAY_URL"
        echo ""
    fi
fi

# Show recent events
echo -e "${BLUE}📋 Recent Events:${NC}"
kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -10
echo ""

# Provide rollback information
echo -e "${BLUE}🔄 Rollback Information:${NC}"
echo "If you need to rollback this upgrade, you can use:"
echo "   helm rollback $HELM_RELEASE_NAME $CURRENT_REVISION -n $NAMESPACE"
echo ""
echo "Or restore from backup:"
echo "   helm upgrade $HELM_RELEASE_NAME sonatype/nexus-iq-server-ha -n $NAMESPACE -f backup-values-revision-${CURRENT_REVISION}.yaml"
echo ""

# Next steps
echo -e "${BLUE}🚀 Next Steps:${NC}"
echo "1. Monitor the pods to ensure they're healthy:"
echo "   kubectl get pods -n $NAMESPACE -w"
echo ""
echo "2. Check logs if needed:"
echo "   kubectl logs -f -l app.kubernetes.io/name=nexus-iq-server-ha -n $NAMESPACE"
echo ""
echo "3. Test the application functionality"
echo ""
echo "4. Check Application Gateway backend health:"
echo "   az network application-gateway show-backend-health \\"
echo "       --resource-group $RESOURCE_GROUP \\"
echo "       --name agw-nexus-iq-ha"
echo ""
echo "5. If everything looks good, you can clean up old backups"
echo ""

echo -e "${GREEN}🎉 Nexus IQ Server HA upgrade completed successfully!${NC}"
