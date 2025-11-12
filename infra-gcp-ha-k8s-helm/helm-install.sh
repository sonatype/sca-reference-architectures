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

echo -e "${BLUE}🚀 Nexus IQ Server HA on GKE - Helm Installation${NC}"
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

if ! command -v gcloud &> /dev/null; then
    echo -e "${RED}❌ Error: gcloud not found${NC}"
    exit 1
fi

if ! kubectl cluster-info >/dev/null 2>&1; then
    echo -e "${RED}❌ Error: Cannot connect to Kubernetes cluster${NC}"
    exit 1
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

DB_HOST=$(terraform output -raw database_private_ip 2>/dev/null || echo "")
DB_PASSWORD=$(terraform output -raw database_password 2>/dev/null || echo "")
FILESTORE_IP=$(terraform output -raw filestore_ip 2>/dev/null || echo "")
PROJECT_ID=$(terraform output -raw project_id 2>/dev/null || echo "")
REGION=$(terraform output -raw region 2>/dev/null || echo "")
WORKLOAD_IDENTITY=$(terraform output -raw workload_identity_email 2>/dev/null || echo "")
FLUENTD_IDENTITY=$(terraform output -raw fluentd_workload_identity_email 2>/dev/null || echo "")
INGRESS_IP_NAME=$(terraform output -raw ingress_ip_name 2>/dev/null || echo "")

echo "• Database: $DB_HOST"
echo "• Filestore: $FILESTORE_IP"
echo "• Region: $REGION"
echo "• Project: $PROJECT_ID"
echo ""

if [[ -z "$FILESTORE_IP" || -z "$DB_HOST" ]]; then
    echo -e "${RED}❌ Error: Missing required infrastructure outputs${NC}"
    exit 1
fi

echo -e "${BLUE}💾 Configuring Storage${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━"

kubectl apply -f nexus-iq-namespace.yaml >/dev/null 2>&1

timeout=30
elapsed=0
while ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; do
    if [ $elapsed -ge $timeout ]; then
        echo -e "${RED}❌ Error: Namespace creation failed${NC}"
        exit 1
    fi
    sleep 2
    elapsed=$((elapsed + 2))
done

sed "s/FILESTORE_IP_PLACEHOLDER/${FILESTORE_IP}/g" filestore-pv.yaml | kubectl apply -f - >/dev/null 2>&1
kubectl apply -f filestore-pvc.yaml >/dev/null 2>&1

sleep 2
timeout=60
elapsed=0
while true; do
    PVC_STATUS=$(kubectl get pvc nexus-iq-pvc -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")

    if [[ "$PVC_STATUS" == "Bound" ]]; then
        break
    elif [[ "$PVC_STATUS" == "NotFound" && $elapsed -eq 0 ]]; then
        echo -e "${RED}❌ Error: PVC not found${NC}"
        exit 1
    elif [ $elapsed -ge $timeout ]; then
        echo -e "${RED}❌ Error: PVC binding timeout${NC}"
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

sed -i.bak "s|hostname: \"\"|hostname: \"${DB_HOST}\"|g" "$TEMP_VALUES_FILE"
sed -i.bak "s|password: \"\"|password: \"${DB_PASSWORD}\"|g" "$TEMP_VALUES_FILE"
sed -i.bak "s|value: \"\"|value: \"${DB_HOST}\"|g" "$TEMP_VALUES_FILE"
sed -i.bak "s|DB_PASSWORD.*|DB_PASSWORD\n      value: \"${DB_PASSWORD}\"|g" "$TEMP_VALUES_FILE"
sed -i.bak "s|iam.gke.io/gcp-service-account: \"\"|iam.gke.io/gcp-service-account: \"${WORKLOAD_IDENTITY}\"|g" "$TEMP_VALUES_FILE"
sed -i.bak "s|projectId: \"\"|projectId: \"${PROJECT_ID}\"|g" "$TEMP_VALUES_FILE"
sed -i.bak "s|kubernetes.io/ingress.global-static-ip-name: \"\"|kubernetes.io/ingress.global-static-ip-name: \"${INGRESS_IP_NAME}\"|g" "$TEMP_VALUES_FILE"

rm -f "${TEMP_VALUES_FILE}.bak"

if helm list -n "$NAMESPACE" 2>/dev/null | grep -q "$HELM_RELEASE_NAME"; then
    echo -e "${YELLOW}⚠️  Helm release already exists - use ./helm-upgrade.sh${NC}"
    rm -f "$TEMP_VALUES_FILE"
    exit 1
fi

echo -e "${GREEN}✅ Helm chart configured${NC}"
echo ""

CHART_VERSION=$(grep '^helm_chart_version' terraform.tfvars | cut -d'"' -f2 2>/dev/null || echo "195.0.0")

echo -e "${BLUE}🚀 Installing Helm Release${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "This may take 10-15 minutes..."
echo ""

if helm install "$HELM_RELEASE_NAME" sonatype/nexus-iq-server-ha \
    --namespace "$NAMESPACE" \
    --create-namespace \
    --version "$CHART_VERSION" \
    --values "$TEMP_VALUES_FILE" \
    --timeout 10m; then

    rm -f "$TEMP_VALUES_FILE"

    kubectl apply -f backend-config.yaml >/dev/null 2>&1 || true
    
    kubectl annotate service nexus-iq-server-ha-iq-server-application-service \
        cloud.google.com/backend-config='{"default": "nexus-iq-backendconfig"}' \
        -n "$NAMESPACE" >/dev/null 2>&1 || true
    
    sed "s/INGRESS_IP_NAME_PLACEHOLDER/${INGRESS_IP_NAME}/g" ingress.yaml | kubectl apply -f - >/dev/null 2>&1 || true

    kubectl wait --for=condition=ready pod -l name=nexus-iq-server-ha-iq-server -n "$NAMESPACE" --timeout=5m >/dev/null 2>&1 || true

    INGRESS_IP=""
    INGRESS_TIMEOUT=120
    INGRESS_ELAPSED=0
    while [[ -z "$INGRESS_IP" ]] && [ $INGRESS_ELAPSED -lt $INGRESS_TIMEOUT ]; do
        INGRESS_IP=$(kubectl get ingress -n "$NAMESPACE" -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
        if [[ -z "$INGRESS_IP" ]]; then
            sleep 5
            INGRESS_ELAPSED=$((INGRESS_ELAPSED + 5))
        fi
    done

    echo ""
    echo -e "${GREEN}✅ Installation Completed Successfully${NC}"
    echo ""

    echo -e "${BLUE}📊 Deployment Summary${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━"

    kubectl get pods -n "$NAMESPACE"
    echo ""

    kubectl get svc -n "$NAMESPACE"
    echo ""

    if [[ -n "$INGRESS_IP" ]]; then
        echo "• Application URL: http://$INGRESS_IP"
        echo ""
    fi

    echo -e "${BLUE}🎯 Next Steps${NC}"
    echo "━━━━━━━━━━━━"
    echo "1. Access IQ Server (default credentials: admin / admin123)"
    echo "2. Monitor pods: kubectl get pods -n $NAMESPACE -w"
    echo "3. View logs: kubectl logs -f -l app.kubernetes.io/name=nexus-iq-server-ha -n $NAMESPACE"
    echo ""

    echo -e "${YELLOW}⚠️  Important Notes${NC}"
    echo "━━━━━━━━━━━━━━━━━━"
    echo "• Ingress may take 5-10 minutes for full provisioning"
    echo "• Update license: kubectl create secret generic nexus-iq-license --from-file=node-cluster.lic -n nexus-iq --dry-run=client -o yaml | kubectl replace -f -"
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

    rm -f "$TEMP_VALUES_FILE"
    exit 1
fi
