#!/bin/bash

# Helm install script for Nexus IQ Server HA on AKS deployment
# Usage: ./helm-install.sh

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

echo -e "${BLUE}🚀 Nexus IQ Server HA on AKS - Helm Installation${NC}"
echo "===================================================="
echo ""

# Check prerequisites
echo -e "${BLUE}🔍 Checking prerequisites...${NC}"

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}❌ Error: kubectl not found in PATH${NC}"
    exit 1
fi

if ! command -v helm &> /dev/null; then
    echo -e "${RED}❌ Error: helm not found in PATH${NC}"
    exit 1
fi

if ! kubectl cluster-info >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  Cannot connect to Kubernetes cluster${NC}"
    echo "Attempting to configure kubectl..."

    RG_NAME=$(terraform output -raw resource_group_name 2>/dev/null)
    CLUSTER_NAME=$(terraform output -raw aks_cluster_name 2>/dev/null)

    if [[ -n "$RG_NAME" && -n "$CLUSTER_NAME" ]]; then
        az aks get-credentials --resource-group "$RG_NAME" --name "$CLUSTER_NAME" --overwrite-existing
    else
        echo -e "${RED}❌ Error: Could not configure kubectl${NC}"
        exit 1
    fi
fi

if [[ ! -f "$VALUES_FILE" ]]; then
    echo -e "${RED}❌ Error: $VALUES_FILE not found${NC}"
    exit 1
fi

if [[ ! -f "terraform.tfstate" ]]; then
    echo -e "${RED}❌ Error: Terraform state not found${NC}"
    echo "Please run terraform apply first"
    exit 1
fi

echo -e "${GREEN}✅ Prerequisites check passed${NC}"
echo ""

# Get Terraform outputs
echo -e "${BLUE}📊 Getting infrastructure details from Terraform...${NC}"

DB_FQDN=$(terraform output -raw postgres_server_fqdn 2>/dev/null || echo "")
DB_PASSWORD=$(grep '^database_password' terraform.tfvars | cut -d'"' -f2)

echo "   Database FQDN: $DB_FQDN"
echo ""

if [[ -z "$DB_FQDN" ]]; then
    echo -e "${RED}❌ Error: Could not get database FQDN from terraform outputs${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Infrastructure details retrieved successfully${NC}"
echo ""

# Create license secret if it doesn't exist
echo -e "${BLUE}🔐 Setting up license secret...${NC}"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

if kubectl get secret nexus-iq-license -n "$NAMESPACE" >/dev/null 2>&1; then
    echo -e "${GREEN}✅ License secret already exists${NC}"
else
    echo "Creating placeholder license secret..."
    kubectl create secret generic nexus-iq-license \
        --from-literal=license_lic="sample-license-content" \
        -n "$NAMESPACE"
    echo -e "${GREEN}✅ License secret created${NC}"
    echo -e "${YELLOW}⚠️  Remember to update with your actual license${NC}"
fi

echo ""

# Add Helm repository
echo -e "${BLUE}📦 Adding Helm repository...${NC}"
if helm repo list | grep -q sonatype; then
    helm repo update sonatype
else
    helm repo add sonatype "$HELM_CHART_REPO"
    helm repo update
fi
echo -e "${GREEN}✅ Helm repository ready${NC}"
echo ""

# Prepare values file with runtime values
echo -e "${BLUE}⚙️  Preparing Helm values...${NC}"

TEMP_VALUES_FILE="helm-values-runtime.yaml"
cp "$VALUES_FILE" "$TEMP_VALUES_FILE"

# Substitute runtime values
sed -i.bak \
    -e "s/hostname: \"\"/hostname: \"$DB_FQDN\"/" \
    -e "s/password: \"\"/password: \"$DB_PASSWORD\"/" \
    "$TEMP_VALUES_FILE"

# Fix DB_PASSWORD environment variable
sed -i \
    -e "/name: DB_PASSWORD/{n;s/value: \"\"/value: \"$DB_PASSWORD\"/;}" \
    "$TEMP_VALUES_FILE"

# Fix DB_HOSTNAME environment variable
sed -i \
    -e "/name: DB_HOSTNAME/{n;s/value: \"\"/value: \"$DB_FQDN\"/;}" \
    "$TEMP_VALUES_FILE"

echo -e "${GREEN}✅ Helm values prepared${NC}"
echo ""

# Check if release already exists
if helm list -n "$NAMESPACE" | grep -q "$HELM_RELEASE_NAME"; then
    echo -e "${YELLOW}⚠️  Helm release '$HELM_RELEASE_NAME' already exists${NC}"
    echo "Use helm-upgrade.sh to upgrade or uninstall first"
    exit 1
fi

# Install Nexus IQ Server HA
echo -e "${BLUE}🚀 Installing Nexus IQ Server HA...${NC}"
echo ""

CHART_VERSION=$(grep '^helm_chart_version' terraform.tfvars | cut -d'"' -f2)

helm install "$HELM_RELEASE_NAME" sonatype/nexus-iq-server-ha \
    --namespace "$NAMESPACE" \
    --create-namespace \
    --version "$CHART_VERSION" \
    --values "$TEMP_VALUES_FILE" \
    --timeout 10m

echo ""
echo -e "${GREEN}✅ Nexus IQ Server HA installation completed!${NC}"
echo ""

# Clean up temporary files
rm -f "$TEMP_VALUES_FILE" "${TEMP_VALUES_FILE}.bak"

# Show deployment status
echo -e "${BLUE}📊 Deployment Status:${NC}"
kubectl get pods -n "$NAMESPACE" -o wide
echo ""

echo -e "${BLUE}🔗 Service Information:${NC}"
kubectl get svc -n "$NAMESPACE"
echo ""

# Patch service to LoadBalancer type with Azure health probe annotations
echo -e "${BLUE}🔄 Configuring service as LoadBalancer...${NC}"
kubectl patch service nexus-iq-server-ha-iq-server-application-service -n "$NAMESPACE" -p '{
  "spec":{"type":"LoadBalancer"},
  "metadata":{
    "annotations":{
      "service.beta.kubernetes.io/azure-load-balancer-health-probe-request-path":"/ping",
      "service.beta.kubernetes.io/azure-load-balancer-health-probe-protocol":"http"
    }
  }
}'

# Delete and recreate the service to apply annotations
echo -e "${BLUE}🔄 Recreating LoadBalancer with health probe configuration...${NC}"
kubectl delete service nexus-iq-server-ha-iq-server-application-service -n "$NAMESPACE" --ignore-not-found
sleep 5
kubectl expose deployment nexus-iq-server-ha-iq-server-deployment -n "$NAMESPACE" \
  --name=nexus-iq-server-ha-iq-server-application-service \
  --type=LoadBalancer \
  --port=8070 \
  --target-port=8070 \
  --protocol=TCP

kubectl annotate service nexus-iq-server-ha-iq-server-application-service -n "$NAMESPACE" \
  service.beta.kubernetes.io/azure-load-balancer-health-probe-request-path=/ping \
  service.beta.kubernetes.io/azure-load-balancer-health-probe-protocol=http

# Wait for LoadBalancer IP
echo -e "${BLUE}⏳ Waiting for LoadBalancer IP...${NC}"
LB_IP=""
for i in {1..60}; do
    LB_IP=$(kubectl get service nexus-iq-server-ha-iq-server-application-service -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    if [[ -n "$LB_IP" ]]; then
        echo -e "${GREEN}✅ LoadBalancer IP assigned: $LB_IP${NC}"
        break
    fi
    echo "   Waiting for LoadBalancer IP... ($i/60)"
    sleep 5
done

if [[ -z "$LB_IP" ]]; then
    echo -e "${RED}❌ Timeout waiting for LoadBalancer IP${NC}"
    exit 1
fi
echo ""

# Configure Application Gateway
echo -e "${BLUE}🔧 Configuring Application Gateway...${NC}"
RG_NAME=$(terraform output -raw resource_group_name)
APPGW_NAME=$(terraform output -raw application_gateway_name)
APPGW_FQDN=$(terraform output -raw application_gateway_fqdn 2>/dev/null || echo "")
APPGW_IP=$(terraform output -raw application_gateway_public_ip)

az network application-gateway address-pool update \
    --resource-group "$RG_NAME" \
    --gateway-name "$APPGW_NAME" \
    --name aks-backend-pool \
    --servers "$LB_IP"

if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}✅ Application Gateway configured successfully${NC}"
else
    echo -e "${YELLOW}⚠️  Warning: Failed to configure Application Gateway${NC}"
fi
echo ""

echo -e "${GREEN}🎉 Nexus IQ Server HA is now available!${NC}"
echo ""
if [[ -n "$APPGW_FQDN" ]]; then
    echo -e "${GREEN}URL: http://$APPGW_FQDN${NC}"
else
    echo -e "${GREEN}URL: http://$APPGW_IP${NC}"
fi
echo ""
echo -e "${BLUE}Direct LoadBalancer access (for testing): http://$LB_IP:8070${NC}"
echo ""

ADMIN_PASSWORD=$(grep '^nexus_iq_admin_password' terraform.tfvars | cut -d'"' -f2)
echo "Default credentials:"
echo "   Username: admin"
echo "   Password: $ADMIN_PASSWORD"
echo ""

echo -e "${BLUE}🚀 Next Steps:${NC}"
echo "1. Check pod status:"
echo "   kubectl get pods -n $NAMESPACE -w"
echo ""
echo "2. View logs:"
echo "   kubectl logs -f -l app.kubernetes.io/name=nexus-iq-server-ha -n $NAMESPACE"
echo ""

echo -e "${GREEN}✅ Deployment completed successfully!${NC}"
