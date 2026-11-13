#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

NAMESPACE="nexus-iq"
HELM_RELEASE_NAME="nexus-iq-server-ha"

echo -e "${RED}🧹 Nexus IQ Server HA on EKS - Complete Cleanup${NC}"
echo "===================================================="
echo ""

# Credentials come from the standard AWS chain: the named profile in AWS_PROFILE,
# such as an IAM Identity Center profile, or credentials already in the environment.
if [[ -z "$AWS_PROFILE" && -z "$AWS_ACCESS_KEY_ID" ]]; then
    echo -e "${RED}❌ Error: AWS_PROFILE environment variable is not set${NC}"
    echo ""
    echo "Please set your AWS profile name:"
    echo "  export AWS_PROFILE=your-profile-name"
    echo ""
    echo "Or run with inline variable:"
    echo "  AWS_PROFILE=your-profile-name ./helm-uninstall.sh"
    echo ""
    exit 1
fi

if ! command -v aws &> /dev/null; then
    echo -e "${RED}❌ Error: aws not found${NC}"
    exit 1
fi

if ! aws sts get-caller-identity --region "${AWS_REGION:-us-east-1}" >/dev/null 2>&1; then
    echo -e "${RED}❌ Error: no valid AWS credentials${NC}"
    echo ""
    echo "The credentials are missing or have expired. For an IAM Identity Center"
    echo "profile, sign in again:"
    echo "  aws sso login --profile ${AWS_PROFILE:-your-profile-name}"
    echo ""
    exit 1
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

helm uninstall "$HELM_RELEASE_NAME" -n "$NAMESPACE" --ignore-not-found --timeout=2m >/dev/null 2>&1 || true

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

kubectl delete storageclass efs-sc --ignore-not-found=true >/dev/null 2>&1 || true

kubectl get pv -o name 2>/dev/null | grep -iE "(nexus|iq)" | xargs -r kubectl delete --ignore-not-found=true >/dev/null 2>&1 || true
kubectl delete pv nexus-iq-data-pv nexus-iq-logs-pv iq-server-pv --ignore-not-found=true >/dev/null 2>&1 || true

for resource in pv pvc; do
    for item in $(kubectl get $resource -o name 2>/dev/null | grep -iE "(nexus|iq)" || true); do
        kubectl patch $item -p '{"metadata":{"finalizers":[]}}' --type=merge >/dev/null 2>&1 || true
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
