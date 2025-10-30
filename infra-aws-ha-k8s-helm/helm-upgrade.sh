#!/bin/bash

# Helm upgrade script for Nexus IQ Server HA deployment
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

echo -e "${BLUE}🔄 Nexus IQ Server HA - Helm Upgrade${NC}"
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

# Check if we can connect to Kubernetes cluster, if not try to configure kubectl
if ! $KUBECTL_PREFIX kubectl cluster-info >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  Cannot connect to Kubernetes cluster, attempting to configure kubectl...${NC}"

    # Get kubectl config command from terraform outputs
    KUBECTL_COMMAND=$($TERRAFORM_PREFIX terraform output -raw kubectl_config_command 2>/dev/null || echo "")

    if [[ -n "$KUBECTL_COMMAND" ]]; then
        echo "• Using terraform kubectl command: $KUBECTL_COMMAND"
        if command -v aws-vault >/dev/null 2>&1; then
            # Use aws-vault if available
            aws-vault exec admin@iq-sandbox -- $KUBECTL_COMMAND
        else
            # Use direct AWS CLI
            $KUBECTL_COMMAND
        fi

        # Test connection again
        echo "• Testing kubectl connection..."
        sleep 2
        if $KUBECTL_PREFIX kubectl cluster-info >/dev/null 2>&1; then
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
        echo "  aws eks update-kubeconfig --region us-east-1 --name nexus-iq-ha"
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
if ! $KUBECTL_PREFIX kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    echo -e "${RED}❌ Error: Namespace '$NAMESPACE' does not exist${NC}"
    echo "Please run ./helm-install.sh first to install Nexus IQ Server HA"
    exit 1
fi

# Check if release exists
if ! $HELM_PREFIX helm list -n "$NAMESPACE" | grep -q "$HELM_RELEASE_NAME"; then
    echo -e "${RED}❌ Error: Helm release '$HELM_RELEASE_NAME' not found${NC}"
    echo "Please run ./helm-install.sh first to install Nexus IQ Server HA"
    exit 1
fi

echo -e "${GREEN}✅ Prerequisites check passed${NC}"
echo ""

# Get current release information
echo -e "${BLUE}📊 Current Release Information:${NC}"
$HELM_PREFIX helm list -n "$NAMESPACE"
echo ""

CURRENT_REVISION=$($HELM_PREFIX helm list -n "$NAMESPACE" -o json | jq -r ".[] | select(.name==\"$HELM_RELEASE_NAME\") | .revision")
CURRENT_CHART=$($HELM_PREFIX helm list -n "$NAMESPACE" -o json | jq -r ".[] | select(.name==\"$HELM_RELEASE_NAME\") | .chart")

echo "   Current Revision: $CURRENT_REVISION"
echo "   Current Chart: $CURRENT_CHART"
echo ""

# Get Terraform outputs
echo -e "${BLUE}📊 Getting infrastructure details from Terraform...${NC}"

if [[ -f "terraform.tfstate" ]]; then
    DB_ENDPOINT=$($TERRAFORM_PREFIX terraform output -raw rds_cluster_endpoint 2>/dev/null)
    AWS_REGION=$($TERRAFORM_PREFIX terraform output -raw aws_region 2>/dev/null || grep '^aws_region' terraform.tfvars | cut -d'"' -f2)
    CLUSTER_NAME=$($TERRAFORM_PREFIX terraform output -raw cluster_id 2>/dev/null)

    echo "   Database Endpoint: $DB_ENDPOINT"
    echo "   AWS Region: $AWS_REGION"
    echo "   EKS Cluster: $CLUSTER_NAME"
else
    echo -e "${YELLOW}⚠️  Terraform state not found, using defaults${NC}"
    AWS_REGION=$(grep '^aws_region' terraform.tfvars | cut -d'"' -f2 2>/dev/null || echo "us-east-1")
fi
echo ""

# Update Helm repository
echo -e "${BLUE}📦 Updating Helm repository...${NC}"
$HELM_PREFIX helm repo update
echo -e "${GREEN}✅ Helm repository updated${NC}"
echo ""

# Show available chart versions
echo -e "${BLUE}📋 Available Chart Versions:${NC}"
$HELM_PREFIX helm search repo sonatype/nexus-iq-server-ha --versions | head -5
echo ""

# Get target chart version
CHART_VERSION=$(grep '^helm_chart_version' terraform.tfvars | cut -d'"' -f2 2>/dev/null || echo "latest")
echo "   Target Chart Version: $CHART_VERSION"
echo ""

# Create temporary values file with substituted variables
echo -e "${BLUE}⚙️  Preparing Helm values from Terraform outputs...${NC}"

TEMP_VALUES_FILE="helm-values-runtime.yaml"
cp "$VALUES_FILE" "$TEMP_VALUES_FILE"

# Get infrastructure details from Terraform outputs
DB_NAME=$($TERRAFORM_PREFIX terraform output -raw rds_cluster_database_name 2>/dev/null)
DB_PORT=$($TERRAFORM_PREFIX terraform output -raw rds_cluster_port 2>/dev/null)

# Get database credentials from AWS Secrets Manager (consistent with other deployments)
SECRET_NAME=$($TERRAFORM_PREFIX terraform output -raw secrets_manager_secret_name 2>/dev/null)
if [[ -n "$SECRET_NAME" ]]; then
    echo "• Retrieving database credentials from AWS Secrets Manager..."
    SECRET_JSON=$($TERRAFORM_PREFIX aws secretsmanager get-secret-value \
        --secret-id "$SECRET_NAME" \
        --query 'SecretString' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null)

    # Parse JSON to get username and password
    DB_USERNAME=$(echo "$SECRET_JSON" | jq -r '.username')
    DB_PASSWORD=$(echo "$SECRET_JSON" | jq -r '.password')
else
    echo -e "${YELLOW}⚠️  Secrets Manager secret not found, falling back to terraform.tfvars${NC}"
    DB_USERNAME=$(grep '^database_username' terraform.tfvars | cut -d'"' -f2)
    DB_PASSWORD=$(grep '^database_password' terraform.tfvars | cut -d'"' -f2)
fi

echo "• Database endpoint: $DB_ENDPOINT"
echo "• Database name: $DB_NAME"
echo "• Database username: $DB_USERNAME"
echo "• Database port: $DB_PORT"
echo "• AWS region: $AWS_REGION"

# Get IRSA role ARN for Fluentd CloudWatch logging
FLUENTD_IRSA_ROLE_ARN=$($TERRAFORM_PREFIX terraform output -raw fluentd_irsa_role_arn 2>/dev/null)
if [[ -n "$FLUENTD_IRSA_ROLE_ARN" ]]; then
    echo "• Fluentd IRSA Role: $FLUENTD_IRSA_ROLE_ARN"
else
    echo -e "${YELLOW}⚠️  Warning: Fluentd IRSA role not found, CloudWatch logging may not work${NC}"
fi
echo ""

# Substitute runtime values from Terraform outputs
if [[ -f "terraform.tfstate" && -n "$DB_ENDPOINT" ]]; then
    sed -i.bak \
        -e "s/hostname: \"\"/hostname: \"$DB_ENDPOINT\"/" \
        -e "s/password: \"\"/password: \"$DB_PASSWORD\"/" \
        -e "s/username: \"nexusiq\"/username: \"$DB_USERNAME\"/" \
        -e "s/name: \"nexusiq\"/name: \"$DB_NAME\"/" \
        -e "s/port: 5432/port: $DB_PORT/" \
        -e "s/region: \"us-east-1\"/region: \"$AWS_REGION\"/" \
        -e "s|eks.amazonaws.com/role-arn: \".*\"|eks.amazonaws.com/role-arn: \"$FLUENTD_IRSA_ROLE_ARN\"|g" \
        "$TEMP_VALUES_FILE"

    # Update environment variables
    sed -i '' \
        -e "/name: DB_HOSTNAME/{n;s/value: \".*\"/value: \"$DB_ENDPOINT\"/;}" \
        -e "/name: DB_PASSWORD/{n;s/value: \".*\"/value: \"$DB_PASSWORD\"/;}" \
        -e "/name: DB_USERNAME/{n;s/value: \".*\"/value: \"$DB_USERNAME\"/;}" \
        -e "/name: DB_NAME/{n;s/value: \".*\"/value: \"$DB_NAME\"/;}" \
        -e "/name: DB_PORT/{n;s/value: \".*\"/value: \"$DB_PORT\"/;}" \
        "$TEMP_VALUES_FILE"
fi

echo -e "${GREEN}✅ Helm values prepared from Terraform infrastructure${NC}"
echo ""

# Show what will be upgraded
echo -e "${BLUE}🔍 Checking upgrade changes...${NC}"
echo ""

$HELM_PREFIX helm diff upgrade "$HELM_RELEASE_NAME" sonatype/nexus-iq-server-ha \
    --namespace "$NAMESPACE" \
    --version "$CHART_VERSION" \
    --values "$TEMP_VALUES_FILE" \
    --allow-unreleased || echo -e "${YELLOW}⚠️  helm diff plugin not available, continuing with upgrade${NC}"

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
$HELM_PREFIX helm get values "$HELM_RELEASE_NAME" -n "$NAMESPACE" > "backup-values-revision-${CURRENT_REVISION}.yaml"
echo -e "${GREEN}✅ Backup saved as: backup-values-revision-${CURRENT_REVISION}.yaml${NC}"
echo ""

# Perform rolling upgrade
echo -e "${BLUE}🔄 Performing Helm upgrade...${NC}"
echo "Using remote chart: sonatype/nexus-iq-server-ha version $CHART_VERSION"
echo ""

$HELM_PREFIX helm upgrade "$HELM_RELEASE_NAME" sonatype/nexus-iq-server-ha \
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
$HELM_PREFIX helm list -n "$NAMESPACE"
echo ""

NEW_REVISION=$($HELM_PREFIX helm list -n "$NAMESPACE" -o json | jq -r ".[] | select(.name==\"$HELM_RELEASE_NAME\") | .revision")
echo "   Previous Revision: $CURRENT_REVISION"
echo "   New Revision: $NEW_REVISION"
echo ""

# Show pod status
echo -e "${BLUE}📊 Pod Status:${NC}"
$KUBECTL_PREFIX kubectl get pods -n "$NAMESPACE" -o wide
echo ""

# Check rollout status
echo -e "${BLUE}⏳ Checking rollout status...${NC}"
$KUBECTL_PREFIX kubectl rollout status deployment/nexus-iq-server-ha-iq-server-deployment -n "$NAMESPACE" --timeout=600s || true
echo ""

# Show service and ingress information
echo -e "${BLUE}🔗 Service Information:${NC}"
$KUBECTL_PREFIX kubectl get svc -n "$NAMESPACE"
echo ""

if $KUBECTL_PREFIX kubectl get ingress -n "$NAMESPACE" >/dev/null 2>&1; then
    echo -e "${BLUE}🌐 Ingress Information:${NC}"
    $KUBECTL_PREFIX kubectl get ingress -n "$NAMESPACE"
    echo ""
fi

# Show recent events
echo -e "${BLUE}📋 Recent Events:${NC}"
$KUBECTL_PREFIX kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -10
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
echo "4. If everything looks good, you can clean up old backups"
echo ""

echo -e "${GREEN}🎉 Nexus IQ Server HA upgrade completed successfully!${NC}"