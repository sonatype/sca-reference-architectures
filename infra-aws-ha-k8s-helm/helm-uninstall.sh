#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

NAMESPACE="nexus-iq"
HELM_RELEASE_NAME="nexus-iq-server-ha"
AWS_PROFILE="admin@iq-sandbox"

echo -e "${RED}🧹 Nexus IQ Server HA on EKS - Complete Cleanup${NC}"
echo "===================================================="
echo ""

KUBECTL_PREFIX=""
HELM_PREFIX=""
if command -v aws-vault >/dev/null 2>&1; then
    KUBECTL_PREFIX="aws-vault exec $AWS_PROFILE --"
    HELM_PREFIX="aws-vault exec $AWS_PROFILE --"
fi

echo -e "${RED}⚠️  COMPLETE CLEANUP: This will remove EVERYTHING:${NC}"
echo "• Helm release: $HELM_RELEASE_NAME"
echo "• Namespace: $NAMESPACE"
echo "• StorageClass: efs-sc"
echo "• All PersistentVolumes with 'nexus' or 'iq' in the name"
echo ""

echo -e "${RED}🚀 Beginning Uninstallation${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

$HELM_PREFIX helm uninstall "$HELM_RELEASE_NAME" -n "$NAMESPACE" --ignore-not-found --timeout=2m >/dev/null 2>&1 || true

$KUBECTL_PREFIX kubectl delete namespace "$NAMESPACE" --force --grace-period=0 --ignore-not-found=true >/dev/null 2>&1 || true

timeout=60
elapsed=0
while $KUBECTL_PREFIX kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; do
    if [ $elapsed -ge $timeout ]; then
        $KUBECTL_PREFIX kubectl patch namespace "$NAMESPACE" -p '{"metadata":{"finalizers":[]}}' --type=merge >/dev/null 2>&1 || true
        break
    fi
    sleep 3
    elapsed=$((elapsed + 3))
done

$KUBECTL_PREFIX kubectl delete storageclass efs-sc --ignore-not-found=true >/dev/null 2>&1 || true

$KUBECTL_PREFIX kubectl get pv -o name 2>/dev/null | grep -iE "(nexus|iq)" | xargs -r $KUBECTL_PREFIX kubectl delete --ignore-not-found=true >/dev/null 2>&1 || true
$KUBECTL_PREFIX kubectl delete pv nexus-iq-data-pv nexus-iq-logs-pv iq-server-pv --ignore-not-found=true >/dev/null 2>&1 || true

for resource in pv pvc; do
    for item in $($KUBECTL_PREFIX kubectl get $resource -o name 2>/dev/null | grep -iE "(nexus|iq)" || true); do
        $KUBECTL_PREFIX kubectl patch $item -p '{"metadata":{"finalizers":[]}}' --type=merge >/dev/null 2>&1 || true
    done
done

echo ""
echo -e "${GREEN}✅ Uninstallation Completed${NC}"
echo ""

echo -e "${BLUE}📝 Cleanup Summary${NC}"
echo "━━━━━━━━━━━━━━━━━"
echo "• Helm release: $HELM_RELEASE_NAME"
echo "• Namespace: $NAMESPACE"
echo "• StorageClass: efs-sc"
echo "• All PersistentVolumes"
echo ""
echo -e "${YELLOW}💡 Ready for fresh installation: ./helm-install.sh${NC}"

echo ""
echo -e "${YELLOW}Note: Infrastructure (EKS, RDS, EFS) remains running${NC}"
echo "Use ./tf-destroy.sh to remove AWS infrastructure"
