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

# search-values.sh defines tfvar, load_search_vars and write_search_block.
# shellcheck source=search-values.sh
source "$(dirname "$0")/search-values.sh"

echo -e "${BLUE}🚀 Nexus IQ Server HA on AKS - Helm Installation${NC}"
echo "===================================================="
echo ""

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}❌ Error: kubectl not found${NC}"
    exit 1
fi

if ! command -v helm &> /dev/null; then
    echo -e "${RED}❌ Error: helm not found${NC}"
    exit 1
fi

if ! kubectl cluster-info >/dev/null 2>&1; then
    RG_NAME=$(terraform output -raw resource_group_name 2>/dev/null)
    CLUSTER_NAME=$(terraform output -raw aks_cluster_name 2>/dev/null)

    if [[ -n "$RG_NAME" && -n "$CLUSTER_NAME" ]]; then
        az aks get-credentials --resource-group "$RG_NAME" --name "$CLUSTER_NAME" --overwrite-existing >/dev/null 2>&1
    else
        echo -e "${RED}❌ Error: Cannot configure kubectl${NC}"
        exit 1
    fi
fi

if [[ ! -f "$VALUES_FILE" ]]; then
    echo -e "${RED}❌ Error: $VALUES_FILE not found${NC}"
    exit 1
fi

if [[ ! -f "terraform.tfstate" ]]; then
    echo -e "${RED}❌ Error: Terraform state not found${NC}"
    exit 1
fi

echo -e "${BLUE}📊 Retrieving Infrastructure Details${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

DB_FQDN=$(terraform output -raw postgres_server_fqdn 2>/dev/null || echo "")
DB_PASSWORD=$(tfvar database_password)
# Unset in terraform.tfvars, Terraform uses the variables.tf default, which is nexusiq for both.
DB_NAME=$(tfvar database_name)
DB_NAME=${DB_NAME:-nexusiq}
DB_USERNAME=$(tfvar database_username)
DB_USERNAME=${DB_USERNAME:-nexusiq}
STORAGE_ACCOUNT=$(terraform output -raw storage_account_name 2>/dev/null || echo "")
STORAGE_SHARE=$(terraform output -raw storage_share_name 2>/dev/null || echo "")
STORAGE_SHARE_QUOTA_GB=$(terraform output -raw storage_share_quota_gb 2>/dev/null || echo "")
RESOURCE_GROUP=$(terraform output -raw resource_group_name 2>/dev/null || echo "")

load_search_vars

echo "• Database: $DB_FQDN"
echo "• Storage Account: $STORAGE_ACCOUNT"
echo "• File share: $STORAGE_SHARE, ${STORAGE_SHARE_QUOTA_GB} GiB"
echo "• Resource Group: $RESOURCE_GROUP"
echo ""

if [[ -z "$DB_FQDN" || -z "$STORAGE_ACCOUNT" || -z "$STORAGE_SHARE" || -z "$RESOURCE_GROUP" ]]; then
    echo -e "${RED}❌ Error: Missing required infrastructure outputs${NC}"
    exit 1
fi

if [[ ! "$STORAGE_SHARE_QUOTA_GB" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}❌ Error: no storage_share_quota_gb output found${NC}"
    echo "   Run ./tf-apply.sh again so the state carries it."
    exit 1
fi

echo -e "${BLUE}💾 Configuring Storage${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1

# IQ's claim binds to the Azure Files share Terraform created, through a static volume.
# Both state the share's quota, so they match at every size.
sed -e "s/RESOURCE_GROUP_PLACEHOLDER/${RESOURCE_GROUP}/g" \
    -e "s/STORAGE_ACCOUNT_PLACEHOLDER/${STORAGE_ACCOUNT}/g" \
    -e "s/SHARE_NAME_PLACEHOLDER/${STORAGE_SHARE}/g" \
    -e "s/SHARE_QUOTA_PLACEHOLDER/${STORAGE_SHARE_QUOTA_GB}Gi/g" \
    azurefiles-pv.yaml | kubectl apply -f - >/dev/null 2>&1
sed "s/SHARE_QUOTA_PLACEHOLDER/${STORAGE_SHARE_QUOTA_GB}Gi/g" azurefiles-pvc.yaml | kubectl apply -f - >/dev/null 2>&1

timeout=60
elapsed=0
while true; do
    PVC_STATUS=$(kubectl get pvc iq-server-pvc -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")

    if [[ "$PVC_STATUS" == "Bound" ]]; then
        break
    elif [ $elapsed -ge $timeout ]; then
        echo -e "${RED}❌ Error: iq-server-pvc did not bind, status $PVC_STATUS${NC}"
        exit 1
    fi

    sleep 5
    elapsed=$((elapsed + 5))
done

if ! kubectl get secret nexus-iq-license -n "$NAMESPACE" >/dev/null 2>&1; then
    kubectl create secret generic nexus-iq-license \
        --from-literal=license_lic="sample-license-content" \
        -n "$NAMESPACE" >/dev/null 2>&1
fi

echo -e "${GREEN}✅ Storage configured${NC}"
echo ""

echo -e "${BLUE}📦 Preparing Helm Chart${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━"

if helm repo list 2>/dev/null | grep -q sonatype; then
    helm repo update >/dev/null 2>&1
else
    helm repo add sonatype "$HELM_CHART_REPO" >/dev/null 2>&1
    helm repo update >/dev/null 2>&1
fi

TEMP_VALUES_FILE="helm-values-runtime.yaml"
cp "$VALUES_FILE" "$TEMP_VALUES_FILE"

# sed rather than cut, which keeps a trailing comment. The default covers an absent key.
REPLICA_COUNT=$(sed -n 's/^nexus_iq_replica_count *= *\([0-9]*\).*/\1/p' terraform.tfvars)
REPLICA_COUNT=${REPLICA_COUNT:-3}

sed -i.bak \
    -e "s/hostname: \"\"/hostname: \"$DB_FQDN\"/" \
    -e "s/password: \"\"/password: \"$DB_PASSWORD\"/" \
    -e "s/^    name: \"nexusiq\"/    name: \"$DB_NAME\"/" \
    -e "s/^    username: \"nexusiq\"/    username: \"$DB_USERNAME\"/" \
    -e "/name: DB_NAME/{n;s/value: \"nexusiq\"/value: \"$DB_NAME\"/;}" \
    -e "/name: DB_USERNAME/{n;s/value: \"nexusiq\"/value: \"$DB_USERNAME\"/;}" \
    -e "s/^  replicas: [0-9]*/  replicas: $REPLICA_COUNT/" \
    "$TEMP_VALUES_FILE"

if ! write_search_block "$TEMP_VALUES_FILE"; then
    rm -f "$TEMP_VALUES_FILE" "${TEMP_VALUES_FILE}.bak"
    exit 1
fi

# A CHANGE_ME from terraform.tfvars, such as the database password, stops the install here.
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

if helm list -n "$NAMESPACE" 2>/dev/null | grep -q "$HELM_RELEASE_NAME"; then
    echo -e "${YELLOW}⚠️  Helm release already exists - use ./helm-upgrade.sh${NC}"
    rm -f "$TEMP_VALUES_FILE" "${TEMP_VALUES_FILE}.bak"
    exit 1
fi

echo -e "${GREEN}✅ Helm chart configured${NC}"
echo ""

CHART_VERSION=$(tfvar helm_chart_version)
CHART_VERSION=${CHART_VERSION:-201.0.0}

echo -e "${BLUE}🚀 Installing Helm Release${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "This may take 10-15 minutes..."
echo ""

if helm install "$HELM_RELEASE_NAME" sonatype/nexus-iq-server-ha \
    --namespace "$NAMESPACE" \
    --version "$CHART_VERSION" \
    --values "$TEMP_VALUES_FILE" \
    --timeout 15m; then

    rm -f "$TEMP_VALUES_FILE" "${TEMP_VALUES_FILE}.bak"

    kubectl wait --for=condition=ready pod -l name=nexus-iq-server-ha-iq-server -n "$NAMESPACE" --timeout=5m >/dev/null 2>&1 || true

    AGW_NAME=$(terraform output -raw application_gateway_name 2>/dev/null || echo "")
    if [[ -n "$AGW_NAME" && "$AGW_NAME" != "null" ]]; then
        LB_IP=""
        timeout=120
        elapsed=0
        while [[ -z "$LB_IP" ]] && [ $elapsed -lt $timeout ]; do
            LB_IP=$(kubectl get svc nexus-iq-server-ha-iq-server-application-service -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
            if [[ -z "$LB_IP" ]]; then
                sleep 5
                elapsed=$((elapsed + 5))
            fi
        done

        if [[ -z "$LB_IP" ]]; then
            echo -e "${RED}❌ Error: the application service has no load balancer address after ${timeout}s${NC}"
            echo "   The Application Gateway backend pool is not set. Check: kubectl get svc -n $NAMESPACE"
            exit 1
        fi

        CURRENT_BACKEND=$(az network application-gateway address-pool show \
            --gateway-name "$AGW_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --name aks-backend-pool \
            --query 'backendAddresses[0].ipAddress' -o tsv 2>/dev/null || echo "")

        if [[ "$CURRENT_BACKEND" != "$LB_IP" ]]; then
            if ! az network application-gateway address-pool update \
                --gateway-name "$AGW_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --name aks-backend-pool \
                --servers "$LB_IP" >/dev/null; then
                echo -e "${RED}❌ Error: could not point the Application Gateway backend pool at $LB_IP${NC}"
                exit 1
            fi
        fi
    fi

    echo ""
    echo -e "${GREEN}✅ Installation Completed Successfully${NC}"
    echo ""

    echo -e "${BLUE}📊 Deployment Summary${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━"

    kubectl get pods -n "$NAMESPACE"
    echo ""

    kubectl get svc -n "$NAMESPACE"
    echo ""

    APP_URL=$(terraform output -raw application_gateway_fqdn 2>/dev/null || echo "")
    if [[ -n "$APP_URL" ]]; then
        echo "• Application URL: $APP_URL"
        echo ""
    fi

    echo -e "${BLUE}🎯 Next Steps${NC}"
    echo "━━━━━━━━━━━━"
    echo "1. Access IQ Server (default credentials: admin / admin123)"
    echo "2. Monitor pods: kubectl get pods -n $NAMESPACE -w"
    echo ""

else
    echo ""
    echo -e "${RED}❌ Installation Failed${NC}"

    echo ""
    echo -e "${BLUE}📋 Troubleshooting${NC}"
    echo "━━━━━━━━━━━━━━━━━━"

    kubectl get pods -n "$NAMESPACE" 2>/dev/null || true
    echo ""

    kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' 2>/dev/null | tail -10 || true
    echo ""

    rm -f "$TEMP_VALUES_FILE" "${TEMP_VALUES_FILE}.bak"
    exit 1
fi
