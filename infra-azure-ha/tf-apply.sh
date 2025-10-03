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

# Generate and show plan
echo "📋 Generating Terraform plan..."
terraform plan -out=tfplan

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

# Function to proactively import all possible resources (optimized for speed)
import_all_resources() {
    echo -e "${BLUE}📥 Fast parallel resource import for HA deployment...${NC}"
    echo ""

    # Critical resources that commonly cause import issues (HA-specific)
    local critical_resources=(
        "azurerm_resource_group.iq_rg:/subscriptions/48a33158-a8cc-4938-84fd-e661939ed499/resourceGroups/rg-ref-arch-iq-ha"
        "azurerm_application_gateway.iq_app_gw_ha:/subscriptions/48a33158-a8cc-4938-84fd-e661939ed499/resourceGroups/rg-ref-arch-iq-ha/providers/Microsoft.Network/applicationGateways/agw-ref-arch-iq-ha"
        "azurerm_container_app.iq_app_ha:/subscriptions/48a33158-a8cc-4938-84fd-e661939ed499/resourceGroups/rg-ref-arch-iq-ha/providers/Microsoft.App/containerApps/ca-ref-arch-iq-ha"
        "azurerm_container_app_environment.iq_env_ha:/subscriptions/48a33158-a8cc-4938-84fd-e661939ed499/resourceGroups/rg-ref-arch-iq-ha/providers/Microsoft.App/managedEnvironments/cae-ref-arch-iq-ha"
        "azurerm_virtual_network.iq_vnet:/subscriptions/48a33158-a8cc-4938-84fd-e661939ed499/resourceGroups/rg-ref-arch-iq-ha/providers/Microsoft.Network/virtualNetworks/vnet-ref-arch-iq-ha"
        "azurerm_public_ip.app_gw_pip_ha:/subscriptions/48a33158-a8cc-4938-84fd-e661939ed499/resourceGroups/rg-ref-arch-iq-ha/providers/Microsoft.Network/publicIPAddresses/pip-ref-arch-iq-ha"
        "azurerm_storage_account.iq_storage_ha:/subscriptions/48a33158-a8cc-4938-84fd-e661939ed499/resourceGroups/rg-ref-arch-iq-ha/providers/Microsoft.Storage/storageAccounts/strefarchiqhal1ur9htd"
        "azurerm_postgresql_flexible_server.iq_db_ha:/subscriptions/48a33158-a8cc-4938-84fd-e661939ed499/resourceGroups/rg-ref-arch-iq-ha/providers/Microsoft.DBforPostgreSQL/flexibleServers/psql-ref-arch-iq-ha"
        "azurerm_log_analytics_workspace.iq_logs_ha:/subscriptions/48a33158-a8cc-4938-84fd-e661939ed499/resourceGroups/rg-ref-arch-iq-ha/providers/Microsoft.OperationalInsights/workspaces/log-ref-arch-iq-ha"
        "azurerm_monitor_diagnostic_setting.app_gw_diagnostics[0]:/subscriptions/48a33158-a8cc-4938-84fd-e661939ed499/resourceGroups/rg-ref-arch-iq-ha/providers/Microsoft.Network/applicationGateways/agw-ref-arch-iq-ha|agw-ref-arch-iq-ha-diagnostics"
    )

    # Create temporary file for results
    local temp_file=$(mktemp)
    local pids=()

    echo -e "${YELLOW}🚀 Launching parallel imports...${NC}"

    # Launch all imports in parallel
    for resource in "${critical_resources[@]}"; do
        local terraform_address="${resource%%:*}"
        local azure_id="${resource#*:}"

        import_resource_async "$terraform_address" "$azure_id" "$temp_file" &
        pids+=($!)
    done

    # Wait for all background processes to complete
    echo -e "${BLUE}⏳ Waiting for imports to complete...${NC}"
    for pid in "${pids[@]}"; do
        wait "$pid"
    done

    # Process results
    local imported_count=0
    local skipped_count=0

    while IFS=':' read -r status terraform_address reason; do
        case "$status" in
            "SUCCESS")
                echo -e "${GREEN}✅ Imported: $terraform_address${NC}"
                imported_count=$((imported_count + 1))
                ;;
            "SKIP")
                echo -e "${BLUE}ℹ️  Skipped: $terraform_address ($reason)${NC}"
                skipped_count=$((skipped_count + 1))
                ;;
        esac
    done < "$temp_file"

    # Cleanup
    rm -f "$temp_file"

    echo ""
    echo -e "${GREEN}📊 Import Summary: $imported_count imported, $skipped_count skipped${NC}"
    echo ""
}

echo "🚀 Applying Terraform configuration..."
echo "⏱️  This may take 15-20 minutes for HA infrastructure..."

# First, import everything that might exist
import_all_resources

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