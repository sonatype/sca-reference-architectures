#!/bin/bash

# Terraform apply script for Nexus IQ Server High Availability deployment on Azure
# This script applies the HA infrastructure with automatic import handling and validation

set -e

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

echo "🚀 Applying Terraform configuration..."
echo "⏱️  This may take 15-20 minutes for HA infrastructure..."

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