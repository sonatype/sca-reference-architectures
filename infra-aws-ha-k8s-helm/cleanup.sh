#!/bin/bash

# Manual cleanup script for complete resource removal
# Usage: ./cleanup.sh

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
AWS_PROFILE="admin@iq-sandbox"

echo -e "${RED}🧹 Complete Kubernetes Cleanup${NC}"
echo "================================="
echo ""

# Set aws-vault prefixes for all commands if available
KUBECTL_PREFIX=""
HELM_PREFIX=""
if command -v aws-vault >/dev/null 2>&1; then
    KUBECTL_PREFIX="aws-vault exec $AWS_PROFILE --"
    HELM_PREFIX="aws-vault exec $AWS_PROFILE --"
fi

echo -e "${BLUE}🗑️  Removing all Nexus IQ resources...${NC}"

# Remove helm releases
echo "• Removing Helm releases..."
$HELM_PREFIX helm uninstall "$HELM_RELEASE_NAME" -n "$NAMESPACE" --ignore-not-found --timeout=2m || true

# Force delete namespace
echo "• Force deleting namespace..."
$KUBECTL_PREFIX kubectl delete namespace "$NAMESPACE" --force --grace-period=0 --ignore-not-found=true || true

# Wait for namespace deletion
echo "• Waiting for namespace deletion..."
timeout=60
elapsed=0
while $KUBECTL_PREFIX kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; do
    if [ $elapsed -ge $timeout ]; then
        echo "  Force removing finalizers..."
        $KUBECTL_PREFIX kubectl patch namespace "$NAMESPACE" -p '{"metadata":{"finalizers":[]}}' --type=merge || true
        break
    fi
    sleep 3
    elapsed=$((elapsed + 3))
done

# Clean up cluster-wide resources
echo "• Cleaning up cluster-wide resources..."
$KUBECTL_PREFIX kubectl delete storageclass efs-sc --ignore-not-found=true || true

# Clean up all PVs with nexus or iq in the name
echo "• Cleaning up PersistentVolumes..."
$KUBECTL_PREFIX kubectl get pv -o name 2>/dev/null | grep -iE "(nexus|iq)" | xargs -r $KUBECTL_PREFIX kubectl delete --ignore-not-found=true || true
$KUBECTL_PREFIX kubectl delete pv nexus-iq-data-pv nexus-iq-logs-pv iq-server-pv --ignore-not-found=true || true

# Clean up any stuck finalizers on remaining resources
echo "• Cleaning up stuck resources..."
for resource in pv pvc; do
    for item in $($KUBECTL_PREFIX kubectl get $resource -o name 2>/dev/null | grep -iE "(nexus|iq)" || true); do
        echo "  Patching $item..."
        $KUBECTL_PREFIX kubectl patch $item -p '{"metadata":{"finalizers":[]}}' --type=merge || true
    done
done

echo ""
echo -e "${GREEN}✅ Cleanup completed!${NC}"
echo ""
echo -e "${BLUE}📝 What was cleaned up:${NC}"
echo "• Helm release: $HELM_RELEASE_NAME"
echo "• Namespace: $NAMESPACE"
echo "• StorageClass: efs-sc"
echo "• All PersistentVolumes with 'nexus' or 'iq' in the name"
echo "• All stuck finalizers"
echo ""
echo -e "${YELLOW}💡 Ready for fresh installation:${NC}"
echo "  ./helm-install.sh"