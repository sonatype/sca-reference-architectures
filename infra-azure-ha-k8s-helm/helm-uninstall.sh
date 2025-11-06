#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

NAMESPACE="nexus-iq"
HELM_RELEASE_NAME="nexus-iq-server-ha"

echo -e "${RED}🧹 Nexus IQ Server HA on AKS - Complete Cleanup${NC}"
echo "===================================================="
echo ""

echo -e "${RED}⚠️  COMPLETE CLEANUP: This will remove EVERYTHING:${NC}"
echo "• Helm release: $HELM_RELEASE_NAME"
echo "• Namespace: $NAMESPACE"
echo "• All PersistentVolumeClaims"
echo "• All Services (including LoadBalancer)"
echo ""

echo -e "${RED}🚀 Beginning Uninstallation${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

helm uninstall "$HELM_RELEASE_NAME" -n "$NAMESPACE" --ignore-not-found --timeout=2m >/dev/null 2>&1 || true

kubectl delete pvc --all -n "$NAMESPACE" --ignore-not-found=true >/dev/null 2>&1 || true

kubectl delete namespace "$NAMESPACE" --force --grace-period=0 --ignore-not-found=true >/dev/null 2>&1 || true

timeout=60
elapsed=0
while kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; do
    if [ $elapsed -ge $timeout ]; then
        kubectl patch namespace "$NAMESPACE" -p '{"metadata":{"finalizers":[]}}' --type=merge >/dev/null 2>&1 || true
        break
    fi
    sleep 3
    elapsed=$((elapsed + 3))
done

for resource in pv pvc; do
    for item in $(kubectl get $resource -o name 2>/dev/null | grep -iE "(nexus|iq)" || true); do
        kubectl patch $item -p '{"metadata":{"finalizers":[]}}' --type=merge >/dev/null 2>&1 || true
    done
done

kubectl delete storageclass azurefile-nfs --ignore-not-found=true >/dev/null 2>&1 || true

echo ""
echo -e "${GREEN}✅ Uninstallation Completed${NC}"
echo ""

echo -e "${BLUE}📝 Cleanup Summary${NC}"
echo "━━━━━━━━━━━━━━━━━"
echo "• Helm release: $HELM_RELEASE_NAME"
echo "• Namespace: $NAMESPACE"
echo "• All PersistentVolumeClaims and data"
echo "• All Services (including LoadBalancer)"
echo ""
echo -e "${YELLOW}💡 Ready for fresh installation: ./helm-install.sh${NC}"

echo ""
echo -e "${YELLOW}Note: Infrastructure (AKS, PostgreSQL, Storage) remains running${NC}"
echo "Use ./tf-destroy.sh to remove Azure infrastructure"
