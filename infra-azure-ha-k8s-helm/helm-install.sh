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
DB_PASSWORD=$(grep '^database_password' terraform.tfvars | cut -d'"' -f2)
STORAGE_ACCOUNT=$(terraform output -raw storage_account_name 2>/dev/null || echo "")
RESOURCE_GROUP=$(terraform output -raw resource_group_name 2>/dev/null || echo "")

echo "• Database: $DB_FQDN"
echo "• Storage Account: $STORAGE_ACCOUNT"
echo "• Resource Group: $RESOURCE_GROUP"
echo ""

if [[ -z "$DB_FQDN" || -z "$STORAGE_ACCOUNT" || -z "$RESOURCE_GROUP" ]]; then
    echo -e "${RED}❌ Error: Missing required infrastructure outputs${NC}"
    exit 1
fi

echo -e "${BLUE}💾 Configuring Storage${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━"

cat > k8s-storageclass-nfs-runtime.yaml << EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: azurefile-nfs
provisioner: file.csi.azure.com
allowVolumeExpansion: true
parameters:
  skuName: Premium_ZRS
  storageAccount: $STORAGE_ACCOUNT
  resourceGroup: $RESOURCE_GROUP
mountOptions:
  - dir_mode=0777
  - file_mode=0777
  - uid=1000
  - gid=1000
  - mfsymlinks
  - cache=strict
  - actimeo=30
reclaimPolicy: Retain
volumeBindingMode: Immediate
EOF

kubectl apply -f k8s-storageclass-nfs-runtime.yaml >/dev/null 2>&1

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1

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

sed -i.bak \
    -e "s/hostname: \"\"/hostname: \"$DB_FQDN\"/" \
    -e "s/password: \"\"/password: \"$DB_PASSWORD\"/" \
    "$TEMP_VALUES_FILE"

if helm list -n "$NAMESPACE" 2>/dev/null | grep -q "$HELM_RELEASE_NAME"; then
    echo -e "${YELLOW}⚠️  Helm release already exists - use ./helm-upgrade.sh${NC}"
    rm -f "$TEMP_VALUES_FILE" "${TEMP_VALUES_FILE}.bak" k8s-storageclass-nfs-runtime.yaml
    exit 1
fi

echo -e "${GREEN}✅ Helm chart configured${NC}"
echo ""

CHART_VERSION=$(grep '^helm_chart_version' terraform.tfvars | cut -d'"' -f2 2>/dev/null || echo "latest")

echo -e "${BLUE}🚀 Installing Helm Release${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "This may take 10-15 minutes..."
echo ""

if helm install "$HELM_RELEASE_NAME" sonatype/nexus-iq-server-ha \
    --namespace "$NAMESPACE" \
    --version "$CHART_VERSION" \
    --values "$TEMP_VALUES_FILE" \
    --timeout 15m; then

    rm -f "$TEMP_VALUES_FILE" "${TEMP_VALUES_FILE}.bak" k8s-storageclass-nfs-runtime.yaml

    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=nexus-iq-server-ha -n "$NAMESPACE" --timeout=300s >/dev/null 2>&1 || true

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

    rm -f "$TEMP_VALUES_FILE" "${TEMP_VALUES_FILE}.bak" k8s-storageclass-nfs-runtime.yaml
    exit 1
fi
