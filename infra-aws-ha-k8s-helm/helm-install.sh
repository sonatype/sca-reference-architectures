#!/bin/bash

# Helm install script for Nexus IQ Server HA deployment
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
VALUES_FILE="helm-values-fixed.yaml"

echo -e "${BLUE}🚀 Nexus IQ Server HA - Helm Installation${NC}"
echo "=============================================="
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

# Configuration
AWS_PROFILE="admin@iq-sandbox"

# Set aws-vault prefixes for all commands if available
KUBECTL_PREFIX=""
TERRAFORM_PREFIX=""
HELM_PREFIX=""
if command -v aws-vault >/dev/null 2>&1; then
    KUBECTL_PREFIX="aws-vault exec $AWS_PROFILE --"
    TERRAFORM_PREFIX="aws-vault exec $AWS_PROFILE --"
    HELM_PREFIX="aws-vault exec $AWS_PROFILE --"
fi

if ! $KUBECTL_PREFIX kubectl cluster-info >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  Cannot connect to Kubernetes cluster, attempting to configure kubectl...${NC}"

    # Try to get kubectl config command from terraform outputs
    echo "• Attempting to get cluster info from terraform..."
    KUBECTL_COMMAND=$($TERRAFORM_PREFIX terraform output -raw kubectl_config_command 2>/dev/null || echo "")

    if [[ -n "$KUBECTL_COMMAND" ]]; then
        echo "• Using terraform kubectl command: $KUBECTL_COMMAND"
        if command -v aws-vault >/dev/null 2>&1; then
            aws-vault exec "$AWS_PROFILE" -- $KUBECTL_COMMAND
        else
            $KUBECTL_COMMAND
        fi
    else
        echo "• Terraform outputs not available, using default cluster info..."
        # Fallback to hardcoded values based on your infrastructure
        AWS_REGION="us-east-1"
        CLUSTER_NAME="nexus-iq-ha"

        echo "• Configuring kubectl for cluster: $CLUSTER_NAME in region: $AWS_REGION"
        if command -v aws-vault >/dev/null 2>&1; then
            aws-vault exec "$AWS_PROFILE" -- aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"
        else
            aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"
        fi
    fi

    # Test connection again
    echo "• Testing kubectl connection..."
    sleep 2
    if $KUBECTL_PREFIX kubectl cluster-info >/dev/null 2>&1; then
        echo -e "${GREEN}✅ kubectl configured successfully${NC}"
    else
        echo -e "${RED}❌ Error: kubectl configuration failed${NC}"
        echo "Please configure kubectl manually with:"
        echo "  aws-vault exec $AWS_PROFILE -- aws eks update-kubeconfig --region us-east-1 --name nexus-iq-ha"
        exit 1
    fi
fi

# Check if values file exists
if [[ ! -f "$VALUES_FILE" ]]; then
    echo -e "${RED}❌ Error: $VALUES_FILE not found${NC}"
    echo "Please ensure the Helm values file is available"
    exit 1
fi

# Check if Terraform outputs are available
if [[ ! -f "terraform.tfstate" ]]; then
    echo -e "${RED}❌ Error: Terraform state not found${NC}"
    echo "Please run terraform apply first to create the infrastructure"
    exit 1
fi

echo -e "${GREEN}✅ Prerequisites check passed${NC}"
echo ""

# Get Terraform outputs
echo -e "${BLUE}📊 Getting infrastructure details from Terraform...${NC}"

# Using terraform with aws-vault credentials

DB_ENDPOINT=$($TERRAFORM_PREFIX terraform output -raw rds_cluster_endpoint 2>/dev/null || echo "")
EFS_ID=$($TERRAFORM_PREFIX terraform output -raw efs_id 2>/dev/null || echo "")
EFS_DATA_ACCESS_POINT=$($TERRAFORM_PREFIX terraform output -raw efs_data_access_point_id 2>/dev/null || echo "")
EFS_LOGS_ACCESS_POINT=$($TERRAFORM_PREFIX terraform output -raw efs_logs_access_point_id 2>/dev/null || echo "")
AWS_REGION=$($TERRAFORM_PREFIX terraform output -raw aws_region 2>/dev/null || grep '^aws_region' terraform.tfvars | cut -d'"' -f2 || echo "us-east-1")
CLUSTER_NAME=$($TERRAFORM_PREFIX terraform output -raw cluster_id 2>/dev/null || echo "")

echo "   Database Endpoint: $DB_ENDPOINT"
echo "   EFS ID: $EFS_ID"
echo "   AWS Region: $AWS_REGION"
echo "   EKS Cluster: $CLUSTER_NAME"

# Validate required outputs
if [[ -z "$EFS_ID" ]]; then
    echo -e "${RED}❌ Error: Could not get EFS ID from terraform outputs${NC}"
    echo "Please ensure terraform has been applied successfully"
    exit 1
fi

if [[ -z "$EFS_DATA_ACCESS_POINT" ]]; then
    echo -e "${RED}❌ Error: Could not get EFS data access point from terraform outputs${NC}"
    echo "Please ensure terraform has been applied successfully"
    exit 1
fi

echo -e "${GREEN}✅ Infrastructure details retrieved successfully${NC}"
echo ""

# Namespace will be created automatically by Helm with --create-namespace flag

# Create EFS StorageClass and PersistentVolumes (cluster-wide resources)
echo -e "${BLUE}💾 Creating EFS StorageClass and PersistentVolumes...${NC}"

# Clean up any conflicting PVs first
echo "  Cleaning up any existing PVs..."
# Delete specific PVs
$KUBECTL_PREFIX kubectl delete pv nexus-iq-data-pv nexus-iq-logs-pv iq-server-pv --ignore-not-found=true || true
# Also clean up any PVs with nexus or iq in the name
$KUBECTL_PREFIX kubectl get pv -o name | grep -E "(nexus|iq)" | xargs -r $KUBECTL_PREFIX kubectl delete --ignore-not-found=true || true
$KUBECTL_PREFIX kubectl delete storageclass efs-sc --ignore-not-found=true || true

# Wait a moment for cleanup
sleep 3

# Create fresh resources
echo "  Creating EFS StorageClass..."
sed -e "s/\${EFS_ID}/$EFS_ID/g" \
    efs-storageclass.yaml | $KUBECTL_PREFIX kubectl apply -f -

echo "  Creating namespace..."
$KUBECTL_PREFIX kubectl apply -f pre-resources.yaml

echo "  Creating PVC with Helm labels..."
$KUBECTL_PREFIX kubectl apply -f manual-pvc.yaml

# Verify namespace was created
echo "  Verifying namespace creation..."
timeout=30
elapsed=0
while ! $KUBECTL_PREFIX kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; do
    if [ $elapsed -ge $timeout ]; then
        echo -e "${RED}❌ Error: Namespace creation failed${NC}"
        exit 1
    fi
    echo "    Waiting for namespace... (${elapsed}s/${timeout}s)"
    sleep 2
    elapsed=$((elapsed + 2))
done

echo -e "${GREEN}✅ EFS resources and prerequisites created${NC}"
echo ""

# Add Helm repository
echo -e "${BLUE}📦 Adding Helm repository...${NC}"
if $HELM_PREFIX helm repo list | grep -q sonatype; then
    echo -e "${YELLOW}⚠️  Sonatype Helm repository already exists${NC}"
    $HELM_PREFIX helm repo update sonatype
else
    $HELM_PREFIX helm repo add sonatype "$HELM_CHART_REPO"
    $HELM_PREFIX helm repo update
fi
echo -e "${GREEN}✅ Helm repository ready${NC}"
echo ""

# Create temporary values file with substituted variables
echo -e "${BLUE}⚙️  Preparing Helm values...${NC}"

TEMP_VALUES_FILE="helm-values-runtime.yaml"
cp "$VALUES_FILE" "$TEMP_VALUES_FILE"

# Get database password from terraform
DB_PASSWORD=$(grep '^database_password' terraform.tfvars | cut -d'"' -f2)

# Substitute runtime values
sed -i.bak \
    -e "s/hostname: \"\"/hostname: \"$DB_ENDPOINT\"/" \
    -e "s/password: \"\"/password: \"$DB_PASSWORD\"/" \
    -e "s/region: \"us-east-1\"/region: \"$AWS_REGION\"/" \
    "$TEMP_VALUES_FILE"

echo -e "${GREEN}✅ Helm values prepared${NC}"
echo ""

# Check if release already exists
if $HELM_PREFIX helm list -n "$NAMESPACE" | grep -q "$HELM_RELEASE_NAME"; then
    echo -e "${YELLOW}⚠️  Helm release '$HELM_RELEASE_NAME' already exists${NC}"
    echo "Use ./helm-upgrade.sh to upgrade the existing release"
    echo "Or delete the existing release first:"
    echo "  $HELM_PREFIX helm uninstall $HELM_RELEASE_NAME -n $NAMESPACE"
    echo ""
    exit 1
fi

# Check for conflicting resources and clean them up
echo -e "${BLUE}🧹 Checking for conflicting resources...${NC}"
if $KUBECTL_PREFIX kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  Namespace '$NAMESPACE' already exists${NC}"
    echo "Forcing cleanup of all resources in namespace..."

    # First try to delete any existing helm releases
    $HELM_PREFIX helm uninstall "$HELM_RELEASE_NAME" -n "$NAMESPACE" --ignore-not-found --timeout=2m || echo "  No helm release to uninstall"

    # Force delete all resources in the namespace
    echo "  Deleting all resources in namespace..."
    $KUBECTL_PREFIX kubectl delete all --all -n "$NAMESPACE" --timeout=60s --ignore-not-found=true || true
    $KUBECTL_PREFIX kubectl delete secrets --all -n "$NAMESPACE" --timeout=30s --ignore-not-found=true || true
    $KUBECTL_PREFIX kubectl delete configmaps --all -n "$NAMESPACE" --timeout=30s --ignore-not-found=true || true
    $KUBECTL_PREFIX kubectl delete serviceaccounts --all -n "$NAMESPACE" --timeout=30s --ignore-not-found=true || true
    $KUBECTL_PREFIX kubectl delete pvc --all -n "$NAMESPACE" --timeout=30s --ignore-not-found=true || true
    $KUBECTL_PREFIX kubectl delete rolebindings --all -n "$NAMESPACE" --timeout=30s --ignore-not-found=true || true
    $KUBECTL_PREFIX kubectl delete roles --all -n "$NAMESPACE" --timeout=30s --ignore-not-found=true || true

    # Force delete the namespace
    echo "  Force deleting namespace..."
    $KUBECTL_PREFIX kubectl delete namespace "$NAMESPACE" --force --grace-period=0 --ignore-not-found=true || true

    # Wait for complete deletion
    echo "  Waiting for namespace deletion to complete..."
    timeout=90
    elapsed=0
    while $KUBECTL_PREFIX kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; do
        if [ $elapsed -ge $timeout ]; then
            echo -e "${YELLOW}⚠️  Force removing namespace finalizers${NC}"
            # Remove finalizers if stuck
            $KUBECTL_PREFIX kubectl patch namespace "$NAMESPACE" -p '{"metadata":{"finalizers":[]}}' --type=merge || true
            break
        fi
        echo "   Still deleting... (${elapsed}s/${timeout}s)"
        sleep 5
        elapsed=$((elapsed + 5))
    done
    echo -e "${GREEN}✅ Namespace cleanup completed${NC}"
fi

# Install Nexus IQ Server HA
echo -e "${BLUE}🚀 Installing Nexus IQ Server HA...${NC}"
echo ""

# Final verification before install
echo -e "${BLUE}🔍 Final pre-installation checks...${NC}"
echo "• Checking namespace exists..."
if ! $KUBECTL_PREFIX kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    echo -e "${RED}❌ Error: Namespace '$NAMESPACE' does not exist${NC}"
    echo "Creating namespace manually..."
    $KUBECTL_PREFIX kubectl create namespace "$NAMESPACE"
fi

echo "• Checking StorageClass exists..."
if ! $KUBECTL_PREFIX kubectl get storageclass efs-sc >/dev/null 2>&1; then
    echo -e "${RED}❌ Error: StorageClass 'efs-sc' does not exist${NC}"
    exit 1
fi

echo "• ServiceAccount will be created by Helm..."

echo -e "${GREEN}✅ Pre-installation checks passed${NC}"
echo ""

# Get chart version
CHART_VERSION=$(grep '^helm_chart_version' terraform.tfvars | cut -d'"' -f2)

echo -e "${BLUE}🚀 Installing Helm chart (version: $CHART_VERSION)...${NC}"
$HELM_PREFIX helm install "$HELM_RELEASE_NAME" sonatype/nexus-iq-server-ha \
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
echo ""

$KUBECTL_PREFIX kubectl get pods -n "$NAMESPACE" -o wide
echo ""

echo -e "${BLUE}🔗 Service Information:${NC}"
$KUBECTL_PREFIX kubectl get svc -n "$NAMESPACE"
echo ""

# Check for ingress
if $KUBECTL_PREFIX kubectl get ingress -n "$NAMESPACE" >/dev/null 2>&1; then
    echo -e "${BLUE}🌐 Ingress Information:${NC}"
    $KUBECTL_PREFIX kubectl get ingress -n "$NAMESPACE"
    echo ""

    # Get ALB address if available
    ALB_ADDRESS=$($KUBECTL_PREFIX kubectl get ingress -n "$NAMESPACE" -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    if [[ -n "$ALB_ADDRESS" ]]; then
        echo -e "${GREEN}🎉 Application Load Balancer URL: http://$ALB_ADDRESS${NC}"
        echo ""
    fi
fi

# Wait for pods to be ready
echo -e "${BLUE}⏳ Waiting for pods to be ready...${NC}"
echo "  Checking what pods exist in namespace..."
$KUBECTL_PREFIX kubectl get pods -n "$NAMESPACE" || echo "  No pods found yet"

# Try different label selectors that might be used by the chart
if $KUBECTL_PREFIX kubectl get pods -l app.kubernetes.io/name=nexus-iq-server-ha -n "$NAMESPACE" 2>/dev/null | grep -q "nexus"; then
    echo "  Found pods with app.kubernetes.io/name=nexus-iq-server-ha label"
    $KUBECTL_PREFIX kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=nexus-iq-server-ha -n "$NAMESPACE" --timeout=300s || echo "  Pods not ready yet"
elif $KUBECTL_PREFIX kubectl get pods -l app=nexus-iq-server-ha -n "$NAMESPACE" 2>/dev/null | grep -q "nexus"; then
    echo "  Found pods with app=nexus-iq-server-ha label"
    $KUBECTL_PREFIX kubectl wait --for=condition=ready pod -l app=nexus-iq-server-ha -n "$NAMESPACE" --timeout=300s || echo "  Pods not ready yet"
else
    echo "  Waiting 30 seconds for pods to appear..."
    sleep 30
    $KUBECTL_PREFIX kubectl get pods -n "$NAMESPACE" || echo "  Still no pods found"
fi

echo -e "${GREEN}✅ Nexus IQ Server pods are ready!${NC}"
echo ""

# Show access information
echo -e "${BLUE}🚀 Next Steps:${NC}"
echo "1. Check pod status:"
echo "   kubectl get pods -n $NAMESPACE"
echo ""
echo "2. View logs:"
echo "   kubectl logs -f -l app.kubernetes.io/name=nexus-iq-server-ha -n $NAMESPACE"
echo ""
echo "3. Port forward for local access (if needed):"
echo "   kubectl port-forward svc/nexus-iq-server-ha 8070:8070 -n $NAMESPACE"
echo ""

if [[ -n "$ALB_ADDRESS" ]]; then
    echo "4. Access Nexus IQ Server:"
    echo "   URL: http://$ALB_ADDRESS"
    echo "   Username: admin"
    echo "   Password: $(grep '^nexus_iq_admin_password' terraform.tfvars | cut -d'"' -f2)"
else
    echo "4. Get the load balancer URL:"
    echo "   kubectl get ingress -n $NAMESPACE"
    echo "   (It may take 5-10 minutes for the ALB to be ready)"
fi

echo ""
echo -e "${GREEN}🎉 Nexus IQ Server HA deployment completed successfully!${NC}"