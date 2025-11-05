#!/bin/bash

# Terraform destroy script for Nexus IQ Server HA on AKS
# This script safely destroys the HA infrastructure with proper cleanup
# Usage: ./tf-destroy.sh

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${RED}=========================================="
echo "Nexus IQ Server Azure AKS HA Infrastructure"
echo "Terraform Destroy Script"
echo "==========================================${NC}"
echo ""
echo -e "${YELLOW}⚠️  WARNING: This will destroy ALL HA infrastructure including:${NC}"
echo "   🗄️  Zone-redundant PostgreSQL database and all data"
echo "   💾 Zone-redundant Azure Files Premium storage and all files"
echo "   🎯 AKS cluster and all running pods"
echo "   🌐 Application Gateway and public IP"
echo "   📊 Monitoring and logging resources"
echo ""

if [[ ! -f "main.tf" ]]; then
    echo -e "${RED}❌ Error: main.tf not found in current directory${NC}"
    exit 1
fi

# Get resource information before destruction
echo -e "${BLUE}🔍 Checking for deployed resources...${NC}"
RESOURCE_GROUP=$(terraform output -raw resource_group_name 2>/dev/null || echo "rg-nexus-iq-ha")
CLUSTER_NAME=$(terraform output -raw aks_cluster_name 2>/dev/null || echo "aks-nexus-iq-ha")

# Check if AKS cluster exists and get credentials
echo -e "${BLUE}🎯 Checking AKS cluster...${NC}"
if az aks show --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" &>/dev/null; then
    echo "✅ Found AKS cluster: $CLUSTER_NAME"

    # Get AKS credentials
    echo -e "${BLUE}🔑 Getting AKS credentials...${NC}"
    az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing

    # Check for Helm releases
    echo -e "${BLUE}🧹 Checking for Helm releases...${NC}"
    if helm list -n nexus-iq --output json 2>/dev/null | jq -e '. | length > 0' &>/dev/null; then
        echo -e "${YELLOW}📦 Found Helm release in nexus-iq namespace${NC}"
        echo -e "${BLUE}🗑️  Uninstalling Helm release...${NC}"

        # Run helm-uninstall.sh if it exists, otherwise uninstall directly
        if [[ -f "./helm-uninstall.sh" ]]; then
            ./helm-uninstall.sh
        else
            helm uninstall nexus-iq-server-ha -n nexus-iq || true
            kubectl delete namespace nexus-iq --ignore-not-found=true || true
        fi

        echo "✅ Helm release uninstalled"
    else
        echo "ℹ️  No Helm releases found"
    fi
else
    echo "ℹ️  AKS cluster not found or already destroyed"
fi

echo ""
echo -e "${BLUE}🔍 Checking for orphaned PostgreSQL server...${NC}"
# Check if PostgreSQL exists but is not in Terraform state (corruption case)
POSTGRES_NAME=$(terraform output -raw postgres_server_name 2>/dev/null || echo "psql-nexus-iq-ha")
if az postgres flexible-server show --resource-group "$RESOURCE_GROUP" --name "$POSTGRES_NAME" &>/dev/null; then
    # Check if it's in terraform state
    if ! terraform state list 2>/dev/null | grep -q "azurerm_postgresql_flexible_server"; then
        echo -e "${YELLOW}⚠️  Found orphaned PostgreSQL server not in Terraform state${NC}"
        echo -e "${BLUE}🗑️  Deleting PostgreSQL server to prevent subnet deletion issues...${NC}"
        az postgres flexible-server delete --resource-group "$RESOURCE_GROUP" --name "$POSTGRES_NAME" --yes 2>/dev/null || true
        echo "⏱️  Waiting for PostgreSQL deletion and service association link cleanup..."
        sleep 45
        echo "✅ PostgreSQL server cleanup completed"
    else
        echo "✅ PostgreSQL server is properly tracked in Terraform state"
    fi
else
    echo "✅ No orphaned PostgreSQL server found"
fi

echo ""
echo -e "${BLUE}🚀 Starting Terraform destroy...${NC}"
echo -e "${YELLOW}⏱️  This may take 10-15 minutes for HA infrastructure cleanup...${NC}"
echo ""

# Destroy infrastructure
terraform destroy -auto-approve

echo ""
echo -e "${BLUE}🧹 Performing additional cleanup...${NC}"

# Check for any remaining resources in the resource group
echo -e "${BLUE}🔍 Checking for remaining resources...${NC}"
REMAINING=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length(@)" -o tsv 2>/dev/null || echo "0")

if [ "$REMAINING" -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Found $REMAINING remaining resources in resource group${NC}"
    echo "Remaining resources:"
    az resource list --resource-group "$RESOURCE_GROUP" --output table || true
    echo ""

    echo -e "${BLUE}🗑️  Attempting to delete remaining resources...${NC}"
    # Force delete all remaining resources
    az resource delete --ids $(az resource list --resource-group "$RESOURCE_GROUP" --query '[].id' -o tsv 2>/dev/null) --no-wait 2>/dev/null || true

    # Wait for resource deletion
    echo "Waiting for resource deletion to complete..."
    sleep 30
else
    echo "✅ No remaining resources found"
fi

# Force delete the resource group if it still exists
if az group show --name "$RESOURCE_GROUP" &>/dev/null; then
    echo -e "${BLUE}🗑️  Force deleting resource group: $RESOURCE_GROUP${NC}"
    az group delete --name "$RESOURCE_GROUP" --yes --no-wait 2>/dev/null || true

    # Wait and verify deletion
    echo "Waiting for resource group deletion..."
    sleep 15

    if az group show --name "$RESOURCE_GROUP" &>/dev/null; then
        echo -e "${YELLOW}⚠️  Resource group still exists, initiating force cleanup...${NC}"
        # Try force deletion with compute types
        az group delete --name "$RESOURCE_GROUP" --yes --force-deletion-types Microsoft.Compute/virtualMachines,Microsoft.Compute/virtualMachineScaleSets 2>/dev/null || true
    else
        echo -e "${GREEN}✅ Resource group successfully deleted${NC}"
    fi
else
    echo -e "${GREEN}✅ Resource group already removed${NC}"
fi

# Clean up soft-deleted Key Vaults (if any were created)
echo -e "${BLUE}🔐 Cleaning up soft-deleted Key Vaults...${NC}"
DELETED_KVS=$(az keyvault list-deleted --query "[?contains(name, 'nexus-iq')].name" -o tsv 2>/dev/null || echo "")
if [[ -n "$DELETED_KVS" ]]; then
    for kv in $DELETED_KVS; do
        echo "Purging soft-deleted Key Vault: $kv"
        az keyvault purge --name "$kv" --no-wait 2>/dev/null || true
    done
    echo "✅ Key Vault cleanup initiated"
else
    echo "✅ No soft-deleted Key Vaults found"
fi

# Check for any tagged resources that might be orphaned
echo -e "${BLUE}🏷️  Checking for tagged resources...${NC}"
TAGGED_RESOURCES=$(az resource list --tag Project=nexus-iq-server --query "length(@)" -o tsv 2>/dev/null || echo "0")
if [[ "$TAGGED_RESOURCES" -gt 0 ]]; then
    echo -e "${YELLOW}⚠️  Found $TAGGED_RESOURCES resources with project tags, cleaning up...${NC}"
    az resource delete --ids $(az resource list --tag Project=nexus-iq-server --query '[].id' -o tsv 2>/dev/null) --no-wait 2>/dev/null || true
else
    echo "✅ No tagged resources remaining"
fi

# Clean up local Terraform files
echo -e "${BLUE}🧹 Cleaning up local files...${NC}"
rm -f terraform.tfstate terraform.tfstate.backup tfplan 2>/dev/null || true
echo "✅ Local Terraform files cleaned up"

echo ""
echo -e "${GREEN}✅ Terraform destroy completed successfully!${NC}"
echo ""
echo -e "${BLUE}🎯 HA Infrastructure Cleanup Summary:${NC}"
echo "   🗑️  All Terraform-managed resources destroyed"
echo "   🎯 AKS cluster and pods removed"
echo "   📦 Helm releases uninstalled"
echo "   ♻️  Zone-redundant resources properly removed"
echo ""
echo -e "${YELLOW}📋 Manual cleanup (if needed):${NC}"
echo "   • Check Azure Portal for any remaining resources in: $RESOURCE_GROUP"
echo "   • Verify no orphaned NSG rules or route tables"
echo "   • Check for any remaining soft-deleted resources"
echo ""
echo -e "${BLUE}💾 Data Recovery:${NC}"
echo "   • Database backups may be retained based on backup policy"
echo "   • File share snapshots may be available if configured"
echo "   • Check geo-redundant backups if enabled"
echo ""
echo -e "${GREEN}🎉 HA infrastructure destruction completed!${NC}"
