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

# search-values.sh defines tfvar, load_search_vars and write_search_block. The
# upgrade rebuilds the values file without --reuse-values, so the search: block is
# written here too.
# shellcheck source=search-values.sh
source "$(dirname "$0")/search-values.sh"

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
    DB_ENDPOINT=$(terraform output -raw postgres_server_fqdn 2>/dev/null)
    AZURE_REGION=$(tfvar azure_region)
    AZURE_REGION=${AZURE_REGION:-eastus}
    CLUSTER_NAME=$(terraform output -raw aks_cluster_name 2>/dev/null)
    RESOURCE_GROUP=$(terraform output -raw resource_group_name 2>/dev/null)

    echo "• Database: $DB_ENDPOINT"
    echo "• Region: $AZURE_REGION"
    echo "• Cluster: $CLUSTER_NAME"
    echo "• Resource Group: $RESOURCE_GROUP"
else
    AZURE_REGION=$(tfvar azure_region)
    AZURE_REGION=${AZURE_REGION:-eastus}
fi
echo ""

helm repo update >/dev/null 2>&1

CHART_VERSION=$(tfvar helm_chart_version)
# Unset in terraform.tfvars, keep the chart version the release already runs.
if [[ -z "$CHART_VERSION" ]]; then
    CHART_VERSION=$(helm list -n "$NAMESPACE" -f "^${HELM_RELEASE_NAME}\$" -o json | sed -n 's/.*"chart":"nexus-iq-server-ha-\([^"]*\)".*/\1/p')
fi
CHART_VERSION=${CHART_VERSION:-201.0.0}

echo -e "${BLUE}📦 Preparing Upgrade${NC}"
echo "━━━━━━━━━━━━━━━━━━━"

TEMP_VALUES_FILE="helm-values-runtime.yaml"
cp "$VALUES_FILE" "$TEMP_VALUES_FILE"

DB_PASSWORD=$(tfvar database_password)
# Unset in terraform.tfvars, Terraform uses the variables.tf default, which is nexusiq for both.
DB_NAME=$(tfvar database_name)
DB_NAME=${DB_NAME:-nexusiq}
DB_USERNAME=$(tfvar database_username)
DB_USERNAME=${DB_USERNAME:-nexusiq}
REPLICA_COUNT=$(tfvar nexus_iq_replica_count)
# An absent key gives an empty count, which would write an invalid "replicas:" line.
REPLICA_COUNT=${REPLICA_COUNT:-3}

if [[ -f "terraform.tfstate" && -n "$DB_ENDPOINT" ]]; then
    sed -i.bak \
        -e "s/hostname: \"\"/hostname: \"$DB_ENDPOINT\"/" \
        -e "s/password: \"\"/password: \"$DB_PASSWORD\"/" \
        -e "s/^    name: \"nexusiq\"/    name: \"$DB_NAME\"/" \
        -e "s/^    username: \"nexusiq\"/    username: \"$DB_USERNAME\"/" \
        -e "/name: DB_NAME/{n;s/value: \"nexusiq\"/value: \"$DB_NAME\"/;}" \
        -e "/name: DB_USERNAME/{n;s/value: \"nexusiq\"/value: \"$DB_USERNAME\"/;}" \
        -e "s/^  replicas: [0-9]*/  replicas: $REPLICA_COUNT/" \
        "$TEMP_VALUES_FILE"
fi

load_search_vars
if ! write_search_block "$TEMP_VALUES_FILE"; then
    rm -f "$TEMP_VALUES_FILE" "${TEMP_VALUES_FILE}.bak"
    exit 1
fi

# A CHANGE_ME from terraform.tfvars, such as the database password, stops the upgrade here.
if grep -v '^[[:space:]]*#' "$TEMP_VALUES_FILE" | grep -q "CHANGE_ME"; then
    echo -e "${RED}❌ Error: $TEMP_VALUES_FILE still has CHANGE_ME placeholders${NC}"
    grep -n "CHANGE_ME" "$TEMP_VALUES_FILE" | grep -v '^[0-9]*:[[:space:]]*#' || true
    rm -f "$TEMP_VALUES_FILE" "${TEMP_VALUES_FILE}.bak"
    exit 1
fi

if [[ "$SEARCH_ENGINE" == "opensearch" ]]; then
    echo "• Search backend: OpenSearch at $SEARCH_URI"
else
    echo "• Search backend: Lucene (embedded)"
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
(umask 077; helm get values "$HELM_RELEASE_NAME" -n "$NAMESPACE" > "backup-values-revision-${CURRENT_REVISION}.yaml")
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

AGW_NAME=$(terraform output -raw application_gateway_name 2>/dev/null || echo "")
if [[ -n "$AGW_NAME" && "$AGW_NAME" != "null" ]]; then
    LB_IP=$(kubectl get svc nexus-iq-server-ha-iq-server-application-service -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

    if [[ -n "$LB_IP" ]]; then
        CURRENT_BACKEND=$(az network application-gateway address-pool show \
            --gateway-name "$AGW_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --name aks-backend-pool \
            --query 'backendAddresses[0].ipAddress' -o tsv 2>/dev/null || echo "")

        if [[ "$CURRENT_BACKEND" != "$LB_IP" ]]; then
            az network application-gateway address-pool update \
                --gateway-name "$AGW_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --name aks-backend-pool \
                --set backendAddresses[0].ipAddress="$LB_IP" >/dev/null 2>&1 || true
        fi
    fi
fi

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
