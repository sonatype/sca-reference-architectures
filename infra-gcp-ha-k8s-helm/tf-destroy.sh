#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

export GCP_PAGER=""

DEPLOYMENT_NAME="Nexus IQ Server"
DEPLOYMENT_TYPE="High Availability on GKE"
CLOUD_PROVIDER="GCP"
TERRAFORM_DIR="$(dirname "$0")"

echo -e "${BLUE}🧹 ${DEPLOYMENT_NAME} ${DEPLOYMENT_TYPE} - Terraform Destroy${NC}"
echo "==========================================================="
echo ""

if [[ ! -f "main.tf" ]]; then
    echo -e "${RED}❌ Error: main.tf not found${NC}"
    exit 1
fi

command -v terraform >/dev/null 2>&1 || {
    echo -e "${RED}❌ Error: terraform not installed${NC}"
    exit 1
}

command -v gcloud >/dev/null 2>&1 || {
    echo -e "${RED}❌ Error: gcloud not installed${NC}"
    exit 1
}

PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
if [[ -z "$PROJECT_ID" ]]; then
    echo -e "${YELLOW}⚠️  Warning: No GCP project configured${NC}"
fi

echo "• Cloud Provider: GCP"
echo "• GCP Project: $PROJECT_ID"
echo "• Deployment: $DEPLOYMENT_NAME $DEPLOYMENT_TYPE"
echo ""

echo -e "${BLUE}🔍 Checking Existing Infrastructure${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# set -e is on, so the status is captured on the failure branch: `$?` after
# `|| true` is always 0.
PLAN_STATUS=0
PLAN_OUTPUT=$(terraform plan -destroy 2>&1) || PLAN_STATUS=$?

if [[ $PLAN_STATUS -ne 0 ]]; then
    if [[ -z "$(terraform state list 2>/dev/null)" ]]; then
        echo -e "${YELLOW}⚠️  No infrastructure found${NC}"
        echo "Nothing to destroy."
        exit 0
    fi
    printf '%s\n' "$PLAN_OUTPUT"
    echo -e "${RED}❌ The destroy plan failed, so nothing was destroyed. Fix the error above, then run this script again.${NC}"
    exit 1
fi

echo -e "${BLUE}📊 Resources to be Destroyed${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

printf '%s\n' "$PLAN_OUTPUT"

echo ""
echo -e "${RED}⚠️  DANGER: Permanent Destruction${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo -e "${YELLOW}This will PERMANENTLY DELETE:${NC}"
echo "• All compute resources (GKE cluster)"
echo "• All databases and data (Cloud SQL)"
echo "• All storage and files (Filestore)"
echo "• All load balancers and networking"
echo "• All service accounts and IAM roles"
echo "• All logs (based on retention settings)"
echo ""
echo -e "${RED}⚠️  DATA LOSS WARNING:${NC}"
echo "• All database data will be permanently lost"
echo "• All application data will be permanently lost"
echo "• This action CANNOT be undone"
echo ""

echo -e "${BLUE}🔥 Destroying Infrastructure${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "This may take 15-30 minutes to complete."
echo ""

# The OpenSearch cluster goes first, while GKE still runs the controllers that delete its
# volumes. Its volumes are deleted with it, and this waits until their disks are gone.
if terraform state list 2>/dev/null | grep -q '^helm_release.opensearch_cluster\['; then
    echo "Removing the OpenSearch cluster and its volumes first"
    terraform destroy -auto-approve -target='helm_release.opensearch_cluster[0]'
    if gcloud container clusters get-credentials "$(terraform output -raw gke_cluster_name)" \
        --region "$(terraform output -raw gke_cluster_location)" >/dev/null 2>&1; then
        kubectl delete pvc -n nexus-iq-opensearch -l opensearch.org/opensearch-cluster=nexus-iq-opensearch \
            --ignore-not-found --wait=true --timeout=10m || true
        for _ in $(seq 1 60); do
            left=$(kubectl get pv -o jsonpath='{range .items[?(@.spec.claimRef.namespace=="nexus-iq-opensearch")]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep -c . || true)
            [[ "$left" -eq 0 ]] && break
            sleep 10
        done
        [[ "${left:-0}" -eq 0 ]] || echo -e "${YELLOW}⚠️  ${left} OpenSearch volumes still present; check for leftover disks after the destroy${NC}"
    else
        echo -e "${YELLOW}⚠️  Could not reach the GKE cluster; check for leftover OpenSearch disks after the destroy${NC}"
    fi
fi

terraform destroy -auto-approve

if [[ $? -eq 0 ]]; then
    echo ""
    echo -e "${GREEN}✅ Infrastructure Destroyed Successfully${NC}"
    echo ""
    
    echo -e "${BLUE}🧹 Cleanup Summary${NC}"
    echo "━━━━━━━━━━━━━━━━━━"
    echo "• All GCP resources destroyed"
    echo "• Terraform state updated"
    echo "• Local artifacts removed"
    echo ""
    
    rm -f tfplan-* terraform.tfstate.backup helm-values-runtime.yaml*
    
    echo -e "${YELLOW}📝 Manual Cleanup Tasks (if needed)${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "• Remove any manual DNS records"
    echo "• Clean up external monitoring"
    echo "• Verify no orphaned resources"
    echo ""
    
    echo -e "${GREEN}✅ Destruction Process Completed${NC}"
    
else
    echo ""
    echo -e "${RED}❌ Destruction Failed${NC}"
    echo ""
    echo -e "${YELLOW}Common Issues:${NC}"
    echo "• Resources may have dependencies - check and retry"
    echo "• Deletion protection may be enabled"
    echo "• Some resources may need manual cleanup"
    echo ""
    echo "For manual cleanup, check: CLEANUP_INSTRUCTIONS.md"
    echo "Or run: ./force-cleanup.sh"
    echo ""
    echo "Retry with: ./tf-destroy.sh"
    exit 1
fi
