#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

NAMESPACE="nexus-iq"
HELM_RELEASE_NAME="nexus-iq-server-ha"
HELM_CHART_REPO="https://sonatype.github.io/helm3-charts"
HELM_CHART_NAME="nexus-iq-server-ha"
VALUES_FILE="helm-values.yaml"
AWS_PROFILE="admin@iq-sandbox"

echo -e "${BLUE}🔄 Nexus IQ Server HA on EKS - Helm Upgrade${NC}"
echo "================================================"
echo ""

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}❌ Error: kubectl not found${NC}"
    exit 1
fi

if ! command -v helm &> /dev/null; then
    echo -e "${RED}❌ Error: helm not found${NC}"
    exit 1
fi

KUBECTL_PREFIX=""
TERRAFORM_PREFIX=""
HELM_PREFIX=""
if command -v aws-vault >/dev/null 2>&1; then
    KUBECTL_PREFIX="aws-vault exec $AWS_PROFILE --"
    TERRAFORM_PREFIX="aws-vault exec $AWS_PROFILE --"
    HELM_PREFIX="aws-vault exec $AWS_PROFILE --"
fi

if ! $KUBECTL_PREFIX kubectl cluster-info >/dev/null 2>&1; then
    KUBECTL_COMMAND=$($TERRAFORM_PREFIX terraform output -raw kubectl_config_command 2>/dev/null || echo "")

    if [[ -n "$KUBECTL_COMMAND" ]]; then
        if command -v aws-vault >/dev/null 2>&1; then
            aws-vault exec "$AWS_PROFILE" -- $KUBECTL_COMMAND >/dev/null 2>&1
        else
            $KUBECTL_COMMAND >/dev/null 2>&1
        fi

        sleep 2
        if ! $KUBECTL_PREFIX kubectl cluster-info >/dev/null 2>&1; then
            echo -e "${RED}❌ Error: kubectl configuration failed${NC}"
            exit 1
        fi
    else
        echo -e "${RED}❌ Error: Cannot configure kubectl${NC}"
        exit 1
    fi
fi

if [[ ! -f "$VALUES_FILE" ]]; then
    echo -e "${RED}❌ Error: $VALUES_FILE not found${NC}"
    exit 1
fi

if ! $KUBECTL_PREFIX kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    echo -e "${RED}❌ Error: Namespace '$NAMESPACE' does not exist${NC}"
    exit 1
fi

if ! $HELM_PREFIX helm list -n "$NAMESPACE" 2>/dev/null | grep -q "$HELM_RELEASE_NAME"; then
    echo -e "${RED}❌ Error: Helm release '$HELM_RELEASE_NAME' not found${NC}"
    exit 1
fi

echo -e "${BLUE}📊 Current Release${NC}"
echo "━━━━━━━━━━━━━━━━━━"
$HELM_PREFIX helm list -n "$NAMESPACE"
echo ""

CURRENT_REVISION=$($HELM_PREFIX helm list -n "$NAMESPACE" -o json | jq -r ".[] | select(.name==\"$HELM_RELEASE_NAME\") | .revision")
CURRENT_CHART=$($HELM_PREFIX helm list -n "$NAMESPACE" -o json | jq -r ".[] | select(.name==\"$HELM_RELEASE_NAME\") | .chart")

echo "• Current Revision: $CURRENT_REVISION"
echo "• Current Chart: $CURRENT_CHART"
echo ""

echo -e "${BLUE}📊 Infrastructure Details${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ -f "terraform.tfstate" ]]; then
    DB_ENDPOINT=$($TERRAFORM_PREFIX terraform output -raw rds_cluster_endpoint 2>/dev/null)
    AWS_REGION=$($TERRAFORM_PREFIX terraform output -raw aws_region 2>/dev/null || echo "us-east-1")
    CLUSTER_NAME=$($TERRAFORM_PREFIX terraform output -raw cluster_id 2>/dev/null)

    echo "• Database: $DB_ENDPOINT"
    echo "• Region: $AWS_REGION"
    echo "• Cluster: $CLUSTER_NAME"
else
    AWS_REGION=$(grep '^aws_region' terraform.tfvars | cut -d'"' -f2 2>/dev/null || echo "us-east-1")
fi
echo ""

$HELM_PREFIX helm repo update >/dev/null 2>&1

CHART_VERSION=$(grep '^helm_chart_version' terraform.tfvars | cut -d'"' -f2 2>/dev/null || echo "latest")

echo -e "${BLUE}📦 Preparing Upgrade${NC}"
echo "━━━━━━━━━━━━━━━━━━━"

TEMP_VALUES_FILE="helm-values-runtime.yaml"
cp "$VALUES_FILE" "$TEMP_VALUES_FILE"

DB_NAME=$($TERRAFORM_PREFIX terraform output -raw rds_cluster_database_name 2>/dev/null)
DB_PORT=$($TERRAFORM_PREFIX terraform output -raw rds_cluster_port 2>/dev/null)

SECRET_NAME=$($TERRAFORM_PREFIX terraform output -raw secrets_manager_secret_name 2>/dev/null)
if [[ -n "$SECRET_NAME" ]]; then
    SECRET_JSON=$($TERRAFORM_PREFIX aws secretsmanager get-secret-value \
        --secret-id "$SECRET_NAME" \
        --query 'SecretString' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null)

    DB_USERNAME=$(echo "$SECRET_JSON" | jq -r '.username')
    DB_PASSWORD=$(echo "$SECRET_JSON" | jq -r '.password')
else
    DB_USERNAME=$(grep '^database_username' terraform.tfvars | cut -d'"' -f2)
    DB_PASSWORD=$(grep '^database_password' terraform.tfvars | cut -d'"' -f2)
fi

FLUENTD_IRSA_ROLE_ARN=$($TERRAFORM_PREFIX terraform output -raw fluentd_irsa_role_arn 2>/dev/null)
REPLICA_COUNT=$(grep '^nexus_iq_replica_count' terraform.tfvars | cut -d'=' -f2 | tr -d ' ' 2>/dev/null || echo "3")

if [[ -f "terraform.tfstate" && -n "$DB_ENDPOINT" ]]; then
    sed -i.bak \
        -e "s/hostname: \"\"/hostname: \"$DB_ENDPOINT\"/" \
        -e "s/password: \"\"/password: \"$DB_PASSWORD\"/" \
        -e "s/username: \"nexusiq\"/username: \"$DB_USERNAME\"/" \
        -e "s/name: \"nexusiq\"/name: \"$DB_NAME\"/" \
        -e "s/port: 5432/port: $DB_PORT/" \
        -e "s/region: \"us-east-1\"/region: \"$AWS_REGION\"/" \
        -e "s|eks.amazonaws.com/role-arn: \".*\"|eks.amazonaws.com/role-arn: \"$FLUENTD_IRSA_ROLE_ARN\"|g" \
        -e "s/replicaCount: [0-9]*/replicaCount: $REPLICA_COUNT/" \
        "$TEMP_VALUES_FILE"

    sed -i '' \
        -e "/name: DB_HOSTNAME/{n;s/value: \".*\"/value: \"$DB_ENDPOINT\"/;}" \
        -e "/name: DB_PASSWORD/{n;s/value: \".*\"/value: \"$DB_PASSWORD\"/;}" \
        -e "/name: DB_USERNAME/{n;s/value: \".*\"/value: \"$DB_USERNAME\"/;}" \
        -e "/name: DB_NAME/{n;s/value: \".*\"/value: \"$DB_NAME\"/;}" \
        -e "/name: DB_PORT/{n;s/value: \".*\"/value: \"$DB_PORT\"/;}" \
        "$TEMP_VALUES_FILE"
fi

echo "• Chart Version: $CHART_VERSION"
echo ""

$HELM_PREFIX helm diff upgrade "$HELM_RELEASE_NAME" sonatype/nexus-iq-server-ha \
    --namespace "$NAMESPACE" \
    --version "$CHART_VERSION" \
    --values "$TEMP_VALUES_FILE" \
    --allow-unreleased 2>/dev/null || echo -e "${YELLOW}⚠️  helm diff plugin not available${NC}"

echo ""

read -p "Continue with upgrade? (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo -e "${YELLOW}❌ Upgrade cancelled${NC}"
    rm -f "$TEMP_VALUES_FILE" "${TEMP_VALUES_FILE}.bak"
    exit 0
fi

echo -e "${BLUE}💾 Creating Backup${NC}"
echo "━━━━━━━━━━━━━━━━━━"
$HELM_PREFIX helm get values "$HELM_RELEASE_NAME" -n "$NAMESPACE" > "backup-values-revision-${CURRENT_REVISION}.yaml"
echo "• Saved: backup-values-revision-${CURRENT_REVISION}.yaml"
echo ""

echo -e "${BLUE}🔄 Performing Upgrade${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━"
echo "This may take 15-20 minutes..."
echo ""

$HELM_PREFIX helm upgrade "$HELM_RELEASE_NAME" sonatype/nexus-iq-server-ha \
    --namespace "$NAMESPACE" \
    --version "$CHART_VERSION" \
    --values "$TEMP_VALUES_FILE" \
    --timeout 20m \
    --wait \
    --atomic

echo ""
echo -e "${GREEN}✅ Upgrade Completed Successfully${NC}"
echo ""

rm -f "$TEMP_VALUES_FILE" "${TEMP_VALUES_FILE}.bak"

echo -e "${BLUE}📊 Upgrade Summary${NC}"
echo "━━━━━━━━━━━━━━━━━━"
$HELM_PREFIX helm list -n "$NAMESPACE"
echo ""

NEW_REVISION=$($HELM_PREFIX helm list -n "$NAMESPACE" -o json | jq -r ".[] | select(.name==\"$HELM_RELEASE_NAME\") | .revision")
echo "• Previous Revision: $CURRENT_REVISION"
echo "• New Revision: $NEW_REVISION"
echo ""

echo -e "${BLUE}📊 Pod Status${NC}"
echo "━━━━━━━━━━━━━"
$KUBECTL_PREFIX kubectl get pods -n "$NAMESPACE" -o wide
echo ""

$KUBECTL_PREFIX kubectl rollout status deployment/nexus-iq-server-ha-iq-server-deployment -n "$NAMESPACE" --timeout=600s >/dev/null 2>&1 || true

echo -e "${BLUE}🔗 Service Information${NC}"
echo "━━━━━━━━━━━━━━━━━━━━"
$KUBECTL_PREFIX kubectl get svc -n "$NAMESPACE"
echo ""

if $KUBECTL_PREFIX kubectl get ingress -n "$NAMESPACE" >/dev/null 2>&1; then
    $KUBECTL_PREFIX kubectl get ingress -n "$NAMESPACE"
    echo ""
fi

echo -e "${BLUE}🔄 Rollback Information${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━"
echo "To rollback: helm rollback $HELM_RELEASE_NAME $CURRENT_REVISION -n $NAMESPACE"
echo "Or restore from backup: helm upgrade $HELM_RELEASE_NAME sonatype/nexus-iq-server-ha -n $NAMESPACE -f backup-values-revision-${CURRENT_REVISION}.yaml"
echo ""

echo -e "${BLUE}🎯 Next Steps${NC}"
echo "━━━━━━━━━━━━"
echo "1. Monitor pods: kubectl get pods -n $NAMESPACE -w"
echo "2. Check logs: kubectl logs -f -l app.kubernetes.io/name=nexus-iq-server-ha -n $NAMESPACE"
echo "3. Test application functionality"
echo ""

echo -e "${GREEN}🎉 Upgrade completed successfully!${NC}"
