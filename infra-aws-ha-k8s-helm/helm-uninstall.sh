#!/bin/bash

# Helm uninstall script for Nexus IQ Server HA deployment
# Usage: ./helm-uninstall.sh

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

echo -e "${RED}🗑️  Nexus IQ Server HA - Helm Uninstall${NC}"
echo "=============================================="
echo ""

# Set aws-vault prefixes for all commands if available
KUBECTL_PREFIX=""
HELM_PREFIX=""
if command -v aws-vault >/dev/null 2>&1; then
    KUBECTL_PREFIX="aws-vault exec $AWS_PROFILE --"
    HELM_PREFIX="aws-vault exec $AWS_PROFILE --"
fi

# Check prerequisites
echo -e "${BLUE}🔍 Checking prerequisites...${NC}"

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}❌ Error: kubectl not found in PATH${NC}"
    echo "Please install kubectl: https://kubernetes.io/docs/tasks/tools/install-kubectl/"
    exit 1
fi

# Check if helm is available
if ! command -v helm &> /dev/null; then
    echo -e "${RED}❌ Error: helm not found in PATH${NC}"
    echo "Please install Helm: https://helm.sh/docs/intro/install/"
    exit 1
fi

echo -e "${GREEN}✅ Prerequisites check passed${NC}"
echo ""

# Check if we can connect to Kubernetes cluster
if ! $KUBECTL_PREFIX kubectl cluster-info >/dev/null 2>&1; then
    echo -e "${RED}❌ Error: Cannot connect to Kubernetes cluster${NC}"
    echo "Please ensure kubectl is configured and cluster is accessible"
    echo "You can configure kubectl with:"
    echo "  aws-vault exec $AWS_PROFILE -- aws eks update-kubeconfig --region us-east-1 --name nexus-iq-ha"
    exit 1
fi

# Check if release exists
echo -e "${BLUE}🔍 Checking for existing Helm release...${NC}"
if ! $HELM_PREFIX helm list -n "$NAMESPACE" | grep -q "$HELM_RELEASE_NAME"; then
    echo -e "${YELLOW}⚠️  Helm release '$HELM_RELEASE_NAME' not found in namespace '$NAMESPACE'${NC}"
    echo "Nothing to uninstall."
    exit 0
fi

# Show what will be uninstalled
echo -e "${BLUE}📋 Helm release information:${NC}"
$HELM_PREFIX helm list -n "$NAMESPACE" | grep "$HELM_RELEASE_NAME" || true
echo ""

echo -e "${BLUE}🔍 Checking deployed resources...${NC}"
if $KUBECTL_PREFIX kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    echo "Pods in namespace $NAMESPACE:"
    $KUBECTL_PREFIX kubectl get pods -n "$NAMESPACE" 2>/dev/null | head -10 || echo "  No pods found"
    echo ""
    echo "Services in namespace $NAMESPACE:"
    $KUBECTL_PREFIX kubectl get svc -n "$NAMESPACE" 2>/dev/null | head -5 || echo "  No services found"
    echo ""
fi

# Warning about uninstallation
echo -e "${RED}⚠️  WARNING: This will permanently remove the following:${NC}"
echo "• Nexus IQ Server HA Helm release"
echo "• All application pods and services"
echo "• ConfigMaps and Secrets in the $NAMESPACE namespace"
echo "• The entire $NAMESPACE namespace"
echo ""
echo -e "${YELLOW}⚠️  This will NOT remove:${NC}"
echo "• Persistent data in EFS (your data will be preserved)"
echo "• EFS StorageClass and PersistentVolumes (cluster-wide resources)"
echo "• Database data in Aurora PostgreSQL"
echo ""

# Proceed with uninstallation
echo -e "${RED}🚀 Beginning Helm uninstallation...${NC}"
echo ""

# Uninstall Helm release
echo -e "${BLUE}📦 Uninstalling Helm release...${NC}"
if $HELM_PREFIX helm uninstall "$HELM_RELEASE_NAME" -n "$NAMESPACE" --timeout 10m; then
    echo -e "${GREEN}✅ Helm release uninstalled successfully${NC}"
else
    echo -e "${RED}❌ Helm uninstall failed${NC}"
    echo "You may need to clean up resources manually"
    exit 1
fi

# Wait for pods to terminate
if $KUBECTL_PREFIX kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    echo ""
    echo -e "${BLUE}⏳ Waiting for pods to terminate...${NC}"
    timeout=120
    elapsed=0
    while $KUBECTL_PREFIX kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep -v Terminating | grep -q .; do
        if [ $elapsed -ge $timeout ]; then
            echo -e "${YELLOW}⚠️  Some pods are taking longer to terminate${NC}"
            break
        fi
        echo "   Waiting for pods to terminate... (${elapsed}s/${timeout}s)"
        sleep 5
        elapsed=$((elapsed + 5))
    done
fi

# Delete namespace
echo ""
echo -e "${BLUE}🗑️  Deleting namespace...${NC}"
if $KUBECTL_PREFIX kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    $KUBECTL_PREFIX kubectl delete namespace "$NAMESPACE" --timeout=120s
    echo -e "${GREEN}✅ Namespace deleted${NC}"
else
    echo -e "${YELLOW}⚠️  Namespace already deleted${NC}"
fi

echo ""
echo -e "${BLUE}🧹 Cleanup Summary${NC}"
echo "==================="
echo "• Helm release '$HELM_RELEASE_NAME' uninstalled"
echo "• Namespace '$NAMESPACE' deleted"
echo "• Application pods and services removed"
echo ""

echo -e "${GREEN}✅ Uninstallation completed successfully!${NC}"
echo ""

echo -e "${BLUE}📝 Next Steps${NC}"
echo "============"
echo "• Your data is preserved in EFS and Aurora database"
echo "• To reinstall: ./helm-install.sh"
echo "• To clean up cluster-wide resources (StorageClass, PVs):"
echo "  kubectl delete storageclass efs-sc"
echo "  kubectl delete pv nexus-iq-data-pv nexus-iq-logs-pv"
echo ""

echo -e "${YELLOW}💡 Note: Infrastructure (EKS, RDS, EFS) remains running${NC}"
echo "Use ./tf-destroy.sh to remove AWS infrastructure"