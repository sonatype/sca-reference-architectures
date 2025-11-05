#!/bin/bash

# Terraform apply script for Nexus IQ Server High Availability deployment on Azure
# This script applies the HA infrastructure with automatic import handling and validation

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Nexus IQ Server Azure HA Infrastructure"
echo "Terraform Apply Script"
echo "=========================================="

# Check if terraform.tfvars exists
if [ ! -f "terraform.tfvars" ]; then
    echo "❌ ERROR: terraform.tfvars not found!"
    echo "📝 Please copy terraform.tfvars.example to terraform.tfvars and customize it:"
    echo "   cp terraform.tfvars.example terraform.tfvars"
    echo "   vim terraform.tfvars"
    exit 1
fi

# Validate minimum HA requirements
echo "🔍 Validating HA configuration..."

# Check for minimum replicas
MIN_REPLICAS=$(grep "iq_min_replicas" terraform.tfvars | cut -d'=' -f2 | tr -d ' "')
if [ "$MIN_REPLICAS" -lt 2 ]; then
    echo "❌ ERROR: HA deployment requires minimum 2 replicas (iq_min_replicas = $MIN_REPLICAS)"
    echo "   Please set iq_min_replicas = 2 or higher in terraform.tfvars"
    exit 1
fi

# Check for zone-redundant database
DB_HA_MODE=$(grep "db_high_availability_mode" terraform.tfvars | cut -d'=' -f2 | tr -d ' "')
if [ "$DB_HA_MODE" != "ZoneRedundant" ]; then
    echo "⚠️  WARNING: Database HA mode is not ZoneRedundant (current: $DB_HA_MODE)"
    echo "   For true HA, set db_high_availability_mode = \"ZoneRedundant\""
fi

# Check for zone-redundant storage
STORAGE_REPLICATION=$(grep "storage_account_replication_type" terraform.tfvars | cut -d'=' -f2 | tr -d ' "')
if [ "$STORAGE_REPLICATION" != "ZRS" ]; then
    echo "⚠️  WARNING: Storage is not zone-redundant (current: $STORAGE_REPLICATION)"
    echo "   For true HA, set storage_account_replication_type = \"ZRS\""
fi

echo "✅ HA configuration validation completed"

# Initialize Terraform if needed
if [ ! -d ".terraform" ]; then
    echo "🔧 Initializing Terraform..."
    terraform init
fi

# Remove any old plan files
rm -f tfplan

echo ""
echo "📊 HA Deployment Summary:"
echo "========================="
echo "🔄 Container Replicas: $MIN_REPLICAS-$(grep "iq_max_replicas" terraform.tfvars | cut -d'=' -f2 | tr -d ' "')"
echo "🗄️  Database HA: $DB_HA_MODE"
echo "💾 Storage Redundancy: $STORAGE_REPLICATION"
echo "🌐 Availability Zones: $(grep "app_gateway_zones" terraform.tfvars | cut -d'=' -f2 | tr -d '[]')"
echo ""

# Proceeding with deployment

# Function to import existing resources automatically
import_existing_resource() {
    local resource_address="$1"
    local resource_id="$2"

    echo -e "${YELLOW}📥 Auto-importing existing resource: $resource_address${NC}"
    if terraform import "$resource_address" "$resource_id"; then
        echo -e "${GREEN}✅ Successfully imported: $resource_address${NC}"
        return 0
    else
        echo -e "${RED}❌ Failed to import: $resource_address${NC}"
        return 1
    fi
}

# Function to check if resource is already in terraform state
is_in_state() {
    local terraform_address="$1"
    terraform state show "$terraform_address" >/dev/null 2>&1
}

# Function to import a single resource in background
import_resource_async() {
    local terraform_address="$1"
    local azure_id="$2"
    local temp_file="$3"

    if is_in_state "$terraform_address"; then
        echo "SKIP:$terraform_address:already in state" >> "$temp_file"
    else
        if terraform import "$terraform_address" "$azure_id" >/dev/null 2>&1; then
            echo "SUCCESS:$terraform_address:imported" >> "$temp_file"
        else
            echo "SKIP:$terraform_address:doesn't exist" >> "$temp_file"
        fi
    fi
}

# Function to proactively import all possible resources (dynamically discovered)
import_all_resources() {
    echo -e "${BLUE}📥 Dynamic resource discovery and import for HA deployment...${NC}"
    echo ""

    local SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    local RESOURCE_GROUP="rg-ref-arch-iq-ha"

    # Base resources with fixed names
    local critical_resources=(
        "azurerm_resource_group.iq_rg:/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP"
        "azurerm_virtual_network.iq_vnet:/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Network/virtualNetworks/vnet-ref-arch-iq-ha"
        "azurerm_public_ip.app_gw_pip_ha:/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Network/publicIPAddresses/pip-ref-arch-iq-ha"
        "azurerm_network_security_group.public_nsg:/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Network/networkSecurityGroups/nsg-public-ha"
        "azurerm_network_security_group.private_nsg:/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Network/networkSecurityGroups/nsg-private-ha"
        "azurerm_network_security_group.db_nsg:/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Network/networkSecurityGroups/nsg-database-ha"
        "azurerm_application_gateway.iq_app_gw_ha:/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Network/applicationGateways/agw-ref-arch-iq-ha"
        "azurerm_container_app_environment.iq_env_ha:/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.App/managedEnvironments/cae-ref-arch-iq-ha"
        "azurerm_container_app.iq_app_ha:/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.App/containerApps/ca-ref-arch-iq-ha"
        "azurerm_postgresql_flexible_server.iq_db_ha:/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DBforPostgreSQL/flexibleServers/psqlfs-ref-arch-iq-ha"
        "azurerm_log_analytics_workspace.iq_logs_ha:/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.OperationalInsights/workspaces/log-ref-arch-iq-ha"
        "azurerm_private_dns_zone.postgres:/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Network/privateDnsZones/privatelink.postgres.database.azure.com"
    )

    # Dynamically discover storage account (has random suffix)
    local storage_account=$(az storage account list --resource-group "$RESOURCE_GROUP" --query "[?starts_with(name, 'strefarchiqha')].id" -o tsv 2>/dev/null || echo "")
    if [ -n "$storage_account" ]; then
        critical_resources+=("azurerm_storage_account.iq_storage_ha:$storage_account")
    fi

    # Dynamically discover key vault (has random suffix)
    local key_vault=$(az keyvault list --resource-group "$RESOURCE_GROUP" --query "[?starts_with(name, 'kv-iq-ha-')].id" -o tsv 2>/dev/null || echo "")
    if [ -n "$key_vault" ]; then
        critical_resources+=("azurerm_key_vault.iq_kv_ha:$key_vault")
    fi

    # Dynamically discover backup vault if backup is enabled
    local backup_vault=$(az resource list --resource-group "$RESOURCE_GROUP" --resource-type "Microsoft.DataProtection/backupVaults" --query "[0].id" -o tsv 2>/dev/null || echo "")
    if [ -n "$backup_vault" ]; then
        critical_resources+=("azurerm_data_protection_backup_vault.iq_backup_vault[0]:$backup_vault")
    fi

    # Import resources synchronously for reliability
    local imported_count=0
    local skipped_count=0

    echo -e "${YELLOW}🚀 Importing resources synchronously...${NC}"
    echo ""

    for resource in "${critical_resources[@]}"; do
        local terraform_address="${resource%%:*}"
        local azure_id="${resource#*:}"

        # Check if already in state
        if terraform state show "$terraform_address" >/dev/null 2>&1; then
            echo -e "${BLUE}ℹ️  Already in state: $terraform_address${NC}"
            skipped_count=$((skipped_count + 1))
            continue
        fi

        # Attempt import
        echo -e "${YELLOW}📥 Importing: $terraform_address${NC}"
        if terraform import "$terraform_address" "$azure_id" 2>&1 | grep -q "Import successful\|already managed"; then
            echo -e "${GREEN}✅ Imported: $terraform_address${NC}"
            imported_count=$((imported_count + 1))
        else
            echo -e "${BLUE}ℹ️  Skipped (doesn't exist): $terraform_address${NC}"
            skipped_count=$((skipped_count + 1))
        fi
        echo ""
    done

    echo ""
    echo -e "${GREEN}📊 Import Summary: $imported_count imported, $skipped_count skipped${NC}"
    echo ""
}

echo "🚀 Applying Terraform configuration..."
echo "⏱️  This may take 15-20 minutes for HA infrastructure..."

# First, import everything that might exist
import_all_resources

# Regenerate plan after imports (critical!)
echo -e "${BLUE}📋 Regenerating plan after imports...${NC}"
if terraform plan -out=tfplan; then
    echo -e "${GREEN}✅ Plan regenerated${NC}"
    echo ""
else
    echo -e "${RED}❌ Failed to regenerate plan${NC}"
    exit 1
fi

# Apply with auto-approve
terraform apply tfplan

echo ""
echo "✅ Terraform apply completed successfully!"
echo ""

# Show outputs
echo "📋 Deployment Outputs:"
echo "======================"
terraform output

echo ""
echo "🎉 Nexus IQ Server HA deployment completed!"
echo ""
echo "📍 Access Points:"
echo "   🌐 Application Gateway: $(terraform output -raw application_gateway_url)"
echo "   🔗 Container App Direct: $(terraform output -raw container_app_url)"
echo ""
echo "🔍 Next Steps:"
echo "   1. Wait 10-15 minutes for all HA services to fully start"
echo "   2. Monitor replica status in Azure Portal"
echo "   3. Test failover by stopping one replica"
echo "   4. Verify clustering through shared storage"
echo "   5. Default credentials: admin / admin123"
echo ""
echo "📊 HA Status Check:"
echo "   az containerapp show --resource-group $(terraform output -raw resource_group_name) --name ca-ref-arch-iq-ha --query '{replicas:properties.template.scale,status:properties.provisioningState}'"
echo ""
echo "🎯 HA Infrastructure deployed successfully with zone redundancy!"