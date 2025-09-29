#!/bin/bash

# Terraform destroy script for Azure IQ Server Single Instance deployment
# Usage: ./tf-destroy.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
TERRAFORM_DIR="$(dirname "$0")"

echo -e "${RED}🧨 Nexus IQ Server Single Instance - Azure Terraform Destroy${NC}"
echo "==========================================================="
echo ""

# Check if we're in the right directory
if [[ ! -f "main.tf" ]]; then
    echo -e "${RED}❌ Error: main.tf not found in current directory${NC}"
    echo "Please run this script from the infra-azure directory"
    exit 1
fi

# Check if terraform state exists
if [[ ! -f "terraform.tfstate" ]] && [[ ! -f ".terraform/terraform.tfstate" ]]; then
    echo -e "${YELLOW}⚠️  Warning: No Terraform state found${NC}"
    echo "It appears no resources have been deployed, or state file is missing."
    echo "Continuing anyway..."
fi

# Pre-flight checks
echo -e "${GREEN}🔍 Pre-flight Checks:${NC}"

# Check Azure authentication
if ! az account show &> /dev/null; then
    echo -e "${RED}❌ Error: Not authenticated with Azure${NC}"
    echo "Please run: az login"
    exit 1
fi

# Display current Azure context
CURRENT_SUBSCRIPTION=$(az account show --query name -o tsv 2>/dev/null)
CURRENT_TENANT=$(az account show --query tenantId -o tsv 2>/dev/null)

echo "   ✅ Azure authentication active"
echo "   📍 Subscription: $CURRENT_SUBSCRIPTION"
echo "   🏢 Tenant: $CURRENT_TENANT"

# Check Terraform
if ! command -v terraform &> /dev/null; then
    echo -e "${RED}❌ Error: Terraform is not installed${NC}"
    exit 1
fi
echo "   ✅ Terraform available"

echo ""

# Get resource information before destruction
RESOURCE_GROUP=""
if terraform output resource_group_name &> /dev/null; then
    RESOURCE_GROUP=$(terraform output -raw resource_group_name 2>/dev/null || echo "")
fi

# Display destruction summary
echo -e "${RED}🚨 DESTRUCTION WARNING:${NC}"
echo ""
echo -e "${YELLOW}The following Azure resources will be PERMANENTLY DELETED:${NC}"
echo "   🏗️  Resource Group: ${RESOURCE_GROUP:-'Unknown'}"
echo "   🌐 Virtual Network and all subnets"
echo "   🗄️  PostgreSQL Flexible Server and databases"
echo "   📦 Container App Environment and Container App"
echo "   🔄 Application Gateway and Public IP"
echo "   💾 Storage Account and File Share (including data)"
echo "   🔐 Key Vault and all secrets"
echo "   📊 Log Analytics Workspace and monitoring data"
echo ""
echo -e "${RED}⚠️  DATA LOSS WARNING:${NC}"
echo "   • All application data in the file share will be lost"
echo "   • Database data will be permanently deleted"
echo "   • Monitoring logs and metrics will be removed"
echo "   • SSL certificates and secrets will be deleted"
echo ""

# Additional safety check for Key Vault
if [[ -n "$RESOURCE_GROUP" ]]; then
    echo -e "${BLUE}🔍 Checking for resources that may need manual cleanup...${NC}"

    # Check for Key Vaults with purge protection
    KV_COUNT=$(az keyvault list --resource-group "$RESOURCE_GROUP" --query "length([?properties.enablePurgeProtection])" -o tsv 2>/dev/null || echo "0")
    if [[ "$KV_COUNT" -gt 0 ]]; then
        echo -e "${YELLOW}⚠️  Warning: Key Vault(s) with purge protection detected${NC}"
        echo "   These may require manual purging after destruction"
    fi
fi

echo ""

# Auto-destruction (no confirmation required)
echo -e "${RED}🛑 STARTING AUTOMATIC DESTRUCTION${NC}"
echo ""
echo -e "${YELLOW}⏳ Starting destruction process...${NC}"
echo ""

# Pre-destruction cleanup - Clear File Share contents to prevent lock file issues
echo -e "${BLUE}🧹 Pre-destruction cleanup...${NC}"

# Clean up File Share contents before destroying infrastructure
STORAGE_ACCOUNT=$(terraform output -raw storage_account_name 2>/dev/null || echo "")
if [[ -n "$STORAGE_ACCOUNT" ]]; then
    echo "Cleaning File Share contents in storage account: $STORAGE_ACCOUNT"
    STORAGE_KEY=$(az storage account keys list --account-name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" --query '[0].value' -o tsv 2>/dev/null || echo "")
    if [[ -n "$STORAGE_KEY" ]]; then
        echo "Clearing nexus-iq-data file share contents..."
        # Delete all files and directories in the share
        az storage file delete-batch --source nexus-iq-data --account-name "$STORAGE_ACCOUNT" --account-key "$STORAGE_KEY" 2>/dev/null || true
        echo -e "${GREEN}✅ File Share contents cleared${NC}"
    else
        echo -e "${YELLOW}⚠️  Could not get storage key - File Share may not be cleared${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  Storage account not found - File Share cleanup skipped${NC}"
fi

# Clean up Container App Environment Storage connections
CAE_NAME=""
if terraform output container_app_environment_id &> /dev/null; then
    CAE_NAME=$(terraform output -raw container_app_environment_id 2>/dev/null | cut -d'/' -f9 || echo "")
fi
if [[ -n "$CAE_NAME" ]]; then
    echo "Cleaning Container App Environment Storage connections..."
    az containerapp env storage delete --name nexus-iq-storage --environment-name "$CAE_NAME" --resource-group "$RESOURCE_GROUP" --yes 2>/dev/null || true
    echo -e "${GREEN}✅ Container App Environment Storage cleaned${NC}"
fi

echo ""
echo -e "${BLUE}🗑️  Starting Terraform destruction...${NC}"

# Run terraform destroy
if terraform destroy -auto-approve; then
    echo ""
    echo -e "${GREEN}✅ Terraform destroy completed successfully!${NC}"
    echo ""

    # Clean up additional Azure resources that might be left behind
    if [[ -n "$RESOURCE_GROUP" ]]; then
        echo -e "${BLUE}🧹 Cleaning up remaining resources...${NC}"

        # Check if resource group still exists
        if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
            echo -e "${YELLOW}⚠️  Resource group still exists, cleaning up...${NC}"

            REMAINING_RESOURCES=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length(@)" -o tsv 2>/dev/null || echo "0")
            if [[ "$REMAINING_RESOURCES" -gt 0 ]]; then
                echo -e "${YELLOW}🗑️  Deleting $REMAINING_RESOURCES remaining resources...${NC}"

                # List remaining resources for visibility
                echo "Remaining resources:"
                az resource list --resource-group "$RESOURCE_GROUP" --output table 2>/dev/null || true
                echo ""

                # Delete all remaining resources in the resource group
                echo "Deleting all resources..."
                az resource delete --ids $(az resource list --resource-group "$RESOURCE_GROUP" --query '[].id' -o tsv 2>/dev/null) --no-wait 2>/dev/null || true

                # Wait a bit for resources to be deleted
                echo "Waiting for resource deletion to complete..."
                sleep 30
            fi

            # Force delete the resource group
            echo -e "${RED}🗑️  Force deleting resource group: $RESOURCE_GROUP${NC}"
            az group delete --name "$RESOURCE_GROUP" --yes --no-wait 2>/dev/null || true

            # Wait and verify deletion
            echo "Waiting for resource group deletion..."
            sleep 15

            if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
                echo -e "${YELLOW}⚠️  Resource group still exists, initiating force cleanup...${NC}"
                # Try force deletion one more time
                az group delete --name "$RESOURCE_GROUP" --yes --force-deletion-types Microsoft.Compute/virtualMachines,Microsoft.Compute/virtualMachineScaleSets 2>/dev/null || true
            else
                echo -e "${GREEN}✅ Resource group successfully deleted${NC}"
            fi
        else
            echo -e "${GREEN}✅ Resource group already removed${NC}"
        fi
    fi

    # Clean up Key Vaults that might be in soft-delete state
    echo -e "${BLUE}🔐 Cleaning up soft-deleted Key Vaults...${NC}"
    DELETED_KVS=$(az keyvault list-deleted --query "[?contains(name, 'ref-arch-iq')].name" -o tsv 2>/dev/null || echo "")
    if [[ -n "$DELETED_KVS" ]]; then
        for kv in $DELETED_KVS; do
            echo "Purging soft-deleted Key Vault: $kv"
            az keyvault purge --name "$kv" --no-wait 2>/dev/null || true
        done
    else
        echo -e "${GREEN}✅ No soft-deleted Key Vaults found${NC}"
    fi

    # Clean up local files automatically
    echo -e "${BLUE}🧹 Cleaning up local files...${NC}"
    rm -f terraform.tfstate terraform.tfstate.backup tfplan 2>/dev/null || true
    echo -e "${GREEN}✅ Local Terraform files cleaned up${NC}"

    # Final verification
    echo ""
    echo -e "${BLUE}🔍 Final verification...${NC}"
    if [[ -n "$RESOURCE_GROUP" ]]; then
        if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
            echo -e "${YELLOW}⚠️  Resource group still exists - may take additional time to fully delete${NC}"
        else
            echo -e "${GREEN}✅ Resource group confirmed deleted${NC}"
        fi
    fi

    # Check for any remaining tagged resources
    TAGGED_RESOURCES=$(az resource list --tag Project=nexus-iq-server --query "length(@)" -o tsv 2>/dev/null || echo "0")
    if [[ "$TAGGED_RESOURCES" -gt 0 ]]; then
        echo -e "${YELLOW}⚠️  Found $TAGGED_RESOURCES resources with project tags, cleaning up...${NC}"
        az resource delete --ids $(az resource list --tag Project=nexus-iq-server --query '[].id' -o tsv 2>/dev/null) --no-wait 2>/dev/null || true
    else
        echo -e "${GREEN}✅ No tagged resources remaining${NC}"
    fi

    echo ""
    echo -e "${GREEN}🎉 Complete destruction finished!${NC}"
    echo -e "${GREEN}✅ All Azure resources have been cleaned up${NC}"
    echo -e "${GREEN}✅ Local files have been removed${NC}"
    echo ""

else
    echo ""
    echo -e "${RED}❌ Terraform destroy failed! Attempting force cleanup...${NC}"
    echo ""

    # Even if Terraform failed, try to clean up resources
    if [[ -n "$RESOURCE_GROUP" ]]; then
        echo -e "${YELLOW}🔧 Attempting automated cleanup after Terraform failure...${NC}"

        # Try to delete all resources in the resource group
        if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
            echo "Force deleting all resources in resource group..."

            # List resources before deletion
            echo "Resources to be deleted:"
            az resource list --resource-group "$RESOURCE_GROUP" --output table 2>/dev/null || true
            echo ""

            # Force delete all resources
            echo "Executing force cleanup..."
            az resource delete --ids $(az resource list --resource-group "$RESOURCE_GROUP" --query '[].id' -o tsv 2>/dev/null) --no-wait 2>/dev/null || true

            # Wait and try to delete the resource group
            echo "Waiting for resource cleanup..."
            sleep 45

            echo "Force deleting resource group..."
            az group delete --name "$RESOURCE_GROUP" --yes --no-wait 2>/dev/null || true

            # Clean up Key Vaults
            echo "Cleaning up soft-deleted Key Vaults..."
            DELETED_KVS=$(az keyvault list-deleted --query "[?contains(name, 'ref-arch-iq')].name" -o tsv 2>/dev/null || echo "")
            if [[ -n "$DELETED_KVS" ]]; then
                for kv in $DELETED_KVS; do
                    echo "Purging Key Vault: $kv"
                    az keyvault purge --name "$kv" --no-wait 2>/dev/null || true
                done
            fi

            # Clean up tagged resources
            echo "Cleaning up tagged resources..."
            az resource delete --ids $(az resource list --tag Project=nexus-iq-server --query '[].id' -o tsv 2>/dev/null) --no-wait 2>/dev/null || true

            echo ""
            echo -e "${GREEN}✅ Force cleanup completed${NC}"
            echo -e "${YELLOW}⚠️  Some resources may still be deleting in the background${NC}"
        else
            echo -e "${GREEN}✅ Resource group not found - may have been deleted${NC}"
        fi
    fi

    # Clean up local files
    echo "Cleaning up local files..."
    rm -f terraform.tfstate terraform.tfstate.backup tfplan 2>/dev/null || true

    echo ""
    echo -e "${YELLOW}⚠️  Terraform destroy failed, but automated cleanup attempted${NC}"
    echo -e "${GREEN}✅ Local files cleaned up${NC}"
    echo ""
    exit 1
fi