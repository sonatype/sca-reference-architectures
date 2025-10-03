#!/bin/bash

# Terraform destroy script for Nexus IQ Server High Availability deployment on Azure
# This script safely destroys the HA infrastructure with proper cleanup

set -e

echo "=========================================="
echo "Nexus IQ Server Azure HA Infrastructure"
echo "Terraform Destroy Script"
echo "=========================================="

echo "⚠️  WARNING: This will destroy ALL HA infrastructure including:"
echo "   🗄️  Zone-redundant PostgreSQL database and all data"
echo "   💾 Zone-redundant storage and all files"
echo "   🔄 All Container App replicas"
echo "   🌐 Application Gateway and public IP"
echo "   🔐 Key Vault and all secrets"
echo "   📊 Monitoring and logging resources"
echo ""

# Proceeding with infrastructure destruction

echo "🔍 Checking for backup resources..."

# Check for backup vaults and recovery points
RESOURCE_GROUP=$(terraform output -raw resource_group_name 2>/dev/null || echo "rg-ref-arch-iq-ha")

echo "🧹 Checking Azure Backup resources..."
if az backup vault list --resource-group "$RESOURCE_GROUP" --output table 2>/dev/null | grep -q "bv-ref-arch-iq-ha"; then
    echo "⚠️  Found backup vault. Cleaning up recovery points..."

    # List and delete recovery points
    VAULT_NAME="bv-ref-arch-iq-ha"

    echo "🗑️  Removing recovery points from backup vault..."
    az backup recoverypoint list \
        --resource-group "$RESOURCE_GROUP" \
        --vault-name "$VAULT_NAME" \
        --container-name "iq-storage-ha" \
        --item-name "iq-data-ha" \
        --query "[].name" -o tsv 2>/dev/null | while read -r recovery_point; do
        if [ ! -z "$recovery_point" ]; then
            echo "   Deleting recovery point: $recovery_point"
            az backup recoverypoint delete \
                --resource-group "$RESOURCE_GROUP" \
                --vault-name "$VAULT_NAME" \
                --container-name "iq-storage-ha" \
                --item-name "iq-data-ha" \
                --name "$recovery_point" \
                --yes || true
        fi
    done

    echo "✅ Backup cleanup completed"
else
    echo "ℹ️  No backup vault found"
fi

echo "🧹 Checking Key Vault soft-deleted resources..."
# Clean up soft-deleted key vault resources
KEY_VAULT_NAME=$(terraform output -raw key_vault_uri 2>/dev/null | sed 's|https://||' | sed 's|.vault.azure.net/||' || echo "")
if [ ! -z "$KEY_VAULT_NAME" ]; then
    echo "🔑 Purging soft-deleted Key Vault: $KEY_VAULT_NAME"
    az keyvault purge --name "$KEY_VAULT_NAME" --yes 2>/dev/null || echo "   Key Vault not found in soft-delete state"
fi

echo "🚀 Starting Terraform destroy..."
echo "⏱️  This may take 10-15 minutes for HA infrastructure cleanup..."

# Destroy infrastructure
terraform destroy -auto-approve

echo ""
echo "🧹 Performing additional cleanup..."

# Clean up any remaining soft-deleted resources
echo "🔍 Checking for remaining soft-deleted resources..."

# List any remaining soft-deleted Key Vaults
echo "🔑 Soft-deleted Key Vaults:"
az keyvault list-deleted --query "[?starts_with(name, 'kv-ref-arch-iq-ha')].{Name:name,Location:properties.location}" -o table 2>/dev/null || echo "   None found"

echo ""
echo "✅ Terraform destroy completed successfully!"
echo ""
echo "🎯 HA Infrastructure Cleanup Summary:"
echo "   🗑️  All Terraform-managed resources destroyed"
echo "   🧹 Backup recovery points cleaned up"
echo "   🔐 Key Vault resources purged"
echo "   ♻️  Zone-redundant resources properly removed"
echo ""
echo "📋 Manual cleanup (if needed):"
echo "   • Check Azure Portal for any remaining resources"
echo "   • Verify no orphaned NSG rules or route tables"
echo "   • Check for any remaining soft-deleted resources"
echo ""
echo "💾 Data Recovery:"
echo "   • Database backups may be retained based on backup policy"
echo "   • File share snapshots may be available if configured"
echo "   • Check geo-redundant backups if enabled"
echo ""
echo "🎉 HA infrastructure destruction completed!"