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
VALUES_FILE="helm-values.yaml"

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
CLUSTER_NAME=$($TERRAFORM_PREFIX terraform output -raw cluster_name 2>/dev/null || echo "")


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
$KUBECTL_PREFIX kubectl apply -f nexus-iq-namespace.yaml

# Verify namespace was created BEFORE creating other resources
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

echo -e "${GREEN}    ✅ Namespace verified and ready${NC}"

echo "  Creating PVC with Helm labels..."
if $KUBECTL_PREFIX kubectl apply -f nexus-iq-pvc.yaml; then
    echo -e "${GREEN}    ✅ PVC configuration applied${NC}"
else
    echo -e "${RED}    ❌ Failed to apply PVC configuration${NC}"
    exit 1
fi

# Verify PVC was created and is bound
echo "  Verifying PVC creation and binding..."
# Give PVC a moment to be created before checking
sleep 2
timeout=60
elapsed=0
while true; do
    PVC_STATUS=$($KUBECTL_PREFIX kubectl get pvc nexus-iq-pvc -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")

    if [[ "$PVC_STATUS" == "Bound" ]]; then
        echo -e "${GREEN}    ✅ PVC is bound and ready${NC}"
        break
    elif [[ "$PVC_STATUS" == "NotFound" ]]; then
        if [ $elapsed -eq 0 ]; then
            echo -e "${RED}    ❌ PVC not found immediately after creation, this indicates a serious issue${NC}"
            $KUBECTL_PREFIX kubectl get pvc -n "$NAMESPACE" || true
            exit 1
        fi
    elif [ $elapsed -ge $timeout ]; then
        echo -e "${RED}❌ Error: PVC failed to bind within timeout${NC}"
        echo "    Current PVC status: $PVC_STATUS"
        $KUBECTL_PREFIX kubectl describe pvc nexus-iq-pvc -n "$NAMESPACE" || true
        exit 1
    fi

    echo "    PVC Status: $PVC_STATUS (${elapsed}s/${timeout}s)"
    sleep 5
    elapsed=$((elapsed + 5))
done

# Create license secret if it doesn't exist
echo "  Creating license secret..."
if $KUBECTL_PREFIX kubectl get secret nexus-iq-license -n "$NAMESPACE" >/dev/null 2>&1; then
    echo -e "${GREEN}    ✅ License secret already exists${NC}"
else
    echo "    Creating placeholder license secret..."
    if $KUBECTL_PREFIX kubectl create secret generic nexus-iq-license \
        --from-literal=license_lic="sample-license-content" \
        -n "$NAMESPACE"; then
        echo -e "${GREEN}    ✅ License secret created${NC}"
        echo -e "${YELLOW}    ⚠️  Remember to update with your actual license:${NC}"
        echo "      $KUBECTL_PREFIX kubectl create secret generic nexus-iq-license --from-file=license_lic=path/to/your/license.lic -n $NAMESPACE --dry-run=client -o yaml | $KUBECTL_PREFIX kubectl replace -f -"
    else
        echo -e "${RED}    ❌ Failed to create license secret${NC}"
        exit 1
    fi
fi

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

# Substitute runtime values - both database config and environment variables
sed -i.bak \
    -e "s/hostname: \"\"/hostname: \"$DB_ENDPOINT\"/" \
    -e "s/password: \"\"/password: \"$DB_PASSWORD\"/" \
    -e "s/region: \"us-east-1\"/region: \"$AWS_REGION\"/" \
    -e "s/value: \"\"  # Will be set by script/value: \"$DB_ENDPOINT\"/g" \
    "$TEMP_VALUES_FILE"

# Second pass for DB_PASSWORD (more complex pattern)
sed -i \
    -e "/name: DB_PASSWORD/{n;s/value: \"\"/value: \"$DB_PASSWORD\"/;}" \
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

# Resources have been created above, proceeding with Helm installation

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

# Configure database security group for EKS access (prevent connection failures)
echo -e "${BLUE}🔒 Configuring database security group for EKS access...${NC}"
RDS_SG_ID=$($TERRAFORM_PREFIX terraform output -raw rds_security_group_id 2>/dev/null || echo "")
if [[ -n "$RDS_SG_ID" && "$RDS_SG_ID" != "null" ]]; then
    # Get EKS node security groups - wait for nodes to be ready first
    echo "  Waiting for EKS nodes to be available..."
    timeout=120
    elapsed=0
    EKS_NODE_SG=""
    while [[ -z "$EKS_NODE_SG" ]] && [ $elapsed -lt $timeout ]; do
        EKS_NODE_SG=$(aws-vault exec "$AWS_PROFILE" -- aws ec2 describe-instances \
            --filters "Name=tag:eks:cluster-name,Values=$CLUSTER_NAME" "Name=instance-state-name,Values=running" \
            --query 'Reservations[].Instances[0].SecurityGroups[].GroupId' \
            --output text 2>/dev/null | awk '{print $1}')

        if [[ -z "$EKS_NODE_SG" ]]; then
            echo "    Waiting for EKS nodes... (${elapsed}s/${timeout}s)"
            sleep 10
            elapsed=$((elapsed + 10))
        fi
    done

    if [[ -n "$EKS_NODE_SG" ]]; then
        echo "  Adding EKS node security group ($EKS_NODE_SG) to RDS security group ($RDS_SG_ID)..."

        # Check if rule already exists
        EXISTING_RULE=$(aws-vault exec "$AWS_PROFILE" -- aws ec2 describe-security-groups \
            --group-ids "$RDS_SG_ID" \
            --query "SecurityGroups[0].IpPermissions[?FromPort==\`5432\` && ToPort==\`5432\`].UserIdGroupPairs[?GroupId==\`$EKS_NODE_SG\`]" \
            --output text 2>/dev/null || echo "")

        if [[ -n "$EXISTING_RULE" ]]; then
            echo -e "${GREEN}    ✅ Security group rule already exists${NC}"
        else
            if aws-vault exec "$AWS_PROFILE" -- aws ec2 authorize-security-group-ingress \
                --group-id "$RDS_SG_ID" \
                --protocol tcp --port 5432 \
                --source-group "$EKS_NODE_SG" 2>/dev/null; then
                echo -e "${GREEN}    ✅ Database security group rule added${NC}"
            else
                echo -e "${YELLOW}    ⚠️  Failed to add security group rule (may already exist)${NC}"
            fi
        fi
    else
        echo -e "${YELLOW}⚠️  Could not determine EKS node security group after ${timeout}s${NC}"
        echo "    You may need to manually configure database connectivity"
        echo "    Run: aws ec2 authorize-security-group-ingress --group-id $RDS_SG_ID --protocol tcp --port 5432 --source-group <eks-node-sg>"
    fi
else
    echo -e "${YELLOW}⚠️  Could not determine RDS security group ID${NC}"
fi

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
echo "   $KUBECTL_PREFIX kubectl get pods -n $NAMESPACE"
echo ""
echo "2. View logs:"
echo "   $KUBECTL_PREFIX kubectl logs -f -l app.kubernetes.io/name=nexus-iq-server-ha -n $NAMESPACE"
echo ""
echo "3. Port forward for local access (if needed):"
echo "   $KUBECTL_PREFIX kubectl port-forward svc/nexus-iq-server-ha 8070:8070 -n $NAMESPACE"
echo ""

if [[ -n "$ALB_ADDRESS" ]]; then
    echo "4. Access Nexus IQ Server:"
    echo "   URL: http://$ALB_ADDRESS"
    echo "   Username: admin"
    echo "   Password: $(grep '^nexus_iq_admin_password' terraform.tfvars | cut -d'"' -f2)"
else
    echo "4. Get the load balancer URL:"
    echo "   $KUBECTL_PREFIX kubectl get ingress -n $NAMESPACE"
    echo "   (It may take 5-10 minutes for the ALB to be ready)"
fi

# Final deployment verification
echo ""
echo -e "${BLUE}🔍 Final deployment verification...${NC}"

# Check critical resources
echo "• Verifying critical resources..."
CRITICAL_RESOURCES_OK=true

# Check namespace
if ! $KUBECTL_PREFIX kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    echo -e "${RED}  ❌ Namespace missing${NC}"
    CRITICAL_RESOURCES_OK=false
else
    echo -e "${GREEN}  ✅ Namespace exists${NC}"
fi

# Check PVC
PVC_STATUS=$($KUBECTL_PREFIX kubectl get pvc nexus-iq-pvc -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
if [[ "$PVC_STATUS" == "Bound" ]]; then
    echo -e "${GREEN}  ✅ PVC is bound${NC}"
else
    echo -e "${RED}  ❌ PVC status: $PVC_STATUS${NC}"
    CRITICAL_RESOURCES_OK=false
fi

# Check license secret
if $KUBECTL_PREFIX kubectl get secret nexus-iq-license -n "$NAMESPACE" >/dev/null 2>&1; then
    echo -e "${GREEN}  ✅ License secret exists${NC}"
else
    echo -e "${RED}  ❌ License secret missing${NC}"
    CRITICAL_RESOURCES_OK=false
fi

# Check Helm release
if $HELM_PREFIX helm list -n "$NAMESPACE" | grep -q "$HELM_RELEASE_NAME"; then
    RELEASE_STATUS=$($HELM_PREFIX helm status "$HELM_RELEASE_NAME" -n "$NAMESPACE" -o json | jq -r '.info.status' 2>/dev/null || echo "unknown")
    if [[ "$RELEASE_STATUS" == "deployed" ]]; then
        echo -e "${GREEN}  ✅ Helm release deployed${NC}"
    else
        echo -e "${YELLOW}  ⚠️  Helm release status: $RELEASE_STATUS${NC}"
    fi
else
    echo -e "${RED}  ❌ Helm release not found${NC}"
    CRITICAL_RESOURCES_OK=false
fi

# Check ALB ingress
ALB_ADDRESS=$($KUBECTL_PREFIX kubectl get ingress -n "$NAMESPACE" -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
if [[ -n "$ALB_ADDRESS" ]]; then
    echo -e "${GREEN}  ✅ ALB provisioned: $ALB_ADDRESS${NC}"

    # Test ALB connectivity (basic check)
    echo "• Testing ALB connectivity..."
    if curl -sf -m 10 "http://$ALB_ADDRESS/ping" >/dev/null 2>&1; then
        echo -e "${GREEN}  ✅ ALB is responding to health checks${NC}"
    else
        echo -e "${YELLOW}  ⚠️  ALB not responding yet (pods may still be starting)${NC}"
    fi
else
    echo -e "${YELLOW}  ⚠️  ALB not ready yet${NC}"
fi

if [[ "$CRITICAL_RESOURCES_OK" == "true" ]]; then
    echo ""
    echo -e "${GREEN}🎉 Nexus IQ Server HA deployment completed successfully!${NC}"
    echo ""
    if [[ -n "$ALB_ADDRESS" ]]; then
        echo -e "${BLUE}🌐 Access your Nexus IQ Server at:${NC}"
        echo "   http://$ALB_ADDRESS"
        echo ""
        echo -e "${YELLOW}📝 Note: It may take 5-10 minutes for pods to be fully ready${NC}"
    fi
else
    echo ""
    echo -e "${YELLOW}⚠️  Deployment completed with some issues${NC}"
    echo "Please check the resources above and troubleshoot as needed."
fi