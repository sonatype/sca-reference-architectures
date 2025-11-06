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

echo -e "${BLUE}🔄 Nexus IQ Server HA on AKS - Helm Upgrade${NC}"
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

if ! command -v az &> /dev/null; then
    echo -e "${RED}❌ Error: Azure CLI not found${NC}"
    exit 1
fi

if ! kubectl cluster-info >/dev/null 2>&1; then
    KUBECTL_COMMAND=$(terraform output -raw kubectl_config_command 2>/dev/null || echo "")

    if [[ -n "$KUBECTL_COMMAND" ]]; then
        eval "$KUBECTL_COMMAND" >/dev/null 2>&1

        sleep 2
        if ! kubectl cluster-info >/dev/null 2>&1; then
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

if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    echo -e "${RED}❌ Error: Namespace '$NAMESPACE' does not exist${NC}"
    exit 1
fi

if ! helm list -n "$NAMESPACE" 2>/dev/null | grep -q "$HELM_RELEASE_NAME"; then
    echo -e "${RED}❌ Error: Helm release '$HELM_RELEASE_NAME' not found${NC}"
    exit 1
fi

echo -e "${BLUE}📊 Current Release${NC}"
echo "━━━━━━━━━━━━━━━━━━"
helm list -n "$NAMESPACE"
echo ""

CURRENT_REVISION=$(helm list -n "$NAMESPACE" -o json | jq -r ".[] | select(.name==\"$HELM_RELEASE_NAME\") | .revision")
CURRENT_CHART=$(helm list -n "$NAMESPACE" -o json | jq -r ".[] | select(.name==\"$HELM_RELEASE_NAME\") | .chart")

echo "• Current Revision: $CURRENT_REVISION"
echo "• Current Chart: $CURRENT_CHART"
echo ""

echo -e "${BLUE}📊 Infrastructure Details${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ -f "terraform.tfstate" ]]; then
    DB_ENDPOINT=$(terraform output -raw postgres_fqdn 2>/dev/null)
    AZURE_REGION=$(terraform output -raw location 2>/dev/null || echo "eastus")
    CLUSTER_NAME=$(terraform output -raw aks_cluster_name 2>/dev/null)
    RESOURCE_GROUP=$(terraform output -raw resource_group_name 2>/dev/null)

    echo "• Database: $DB_ENDPOINT"
    echo "• Region: $AZURE_REGION"
    echo "• Cluster: $CLUSTER_NAME"
    echo "• Resource Group: $RESOURCE_GROUP"
else
    AZURE_REGION=$(grep '^location' terraform.tfvars | cut -d'"' -f2 2>/dev/null || echo "eastus")
fi
echo ""

helm repo update >/dev/null 2>&1

CHART_VERSION=$(grep '^helm_chart_version' terraform.tfvars | cut -d'"' -f2 2>/dev/null || echo "latest")

echo -e "${BLUE}📦 Preparing Upgrade${NC}"
echo "━━━━━━━━━━━━━━━━━━━"

TEMP_VALUES_FILE="helm-values-runtime.yaml"
cp "$VALUES_FILE" "$TEMP_VALUES_FILE"

DB_PASSWORD=$(grep '^database_password' terraform.tfvars | cut -d'"' -f2)

if [[ -f "terraform.tfstate" && -n "$DB_ENDPOINT" ]]; then
    sed -i.bak \
        -e "s/hostname: \"\"/hostname: \"$DB_ENDPOINT\"/" \
        -e "s/password: \"\"/password: \"$DB_PASSWORD\"/" \
        "$TEMP_VALUES_FILE"
fi

echo "• Chart Version: $CHART_VERSION"
echo ""

helm diff upgrade "$HELM_RELEASE_NAME" sonatype/nexus-iq-server-ha \
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
helm get values "$HELM_RELEASE_NAME" -n "$NAMESPACE" > "backup-values-revision-${CURRENT_REVISION}.yaml"
echo "• Saved: backup-values-revision-${CURRENT_REVISION}.yaml"
echo ""

echo -e "${BLUE}🔄 Performing Upgrade${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━"
echo "This may take 15-20 minutes..."
echo ""

helm upgrade "$HELM_RELEASE_NAME" sonatype/nexus-iq-server-ha \
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
helm list -n "$NAMESPACE"
echo ""

NEW_REVISION=$(helm list -n "$NAMESPACE" -o json | jq -r ".[] | select(.name==\"$HELM_RELEASE_NAME\") | .revision")
echo "• Previous Revision: $CURRENT_REVISION"
echo "• New Revision: $NEW_REVISION"
echo ""

echo -e "${BLUE}📊 Pod Status${NC}"
echo "━━━━━━━━━━━━━"
kubectl get pods -n "$NAMESPACE" -o wide
echo ""

kubectl rollout status deployment/nexus-iq-server-ha-iq-server-deployment -n "$NAMESPACE" --timeout=600s >/dev/null 2>&1 || true

echo -e "${BLUE}🔗 Service Information${NC}"
echo "━━━━━━━━━━━━━━━━━━━━"
kubectl get svc -n "$NAMESPACE"
echo ""

if [[ -f "terraform.tfstate" ]]; then
    APP_GATEWAY_URL=$(terraform output -raw application_gateway_url 2>/dev/null || echo "")
    if [[ -n "$APP_GATEWAY_URL" ]]; then
        echo "• Application URL: $APP_GATEWAY_URL"
        echo ""
    fi
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
