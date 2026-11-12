#!/bin/bash

set -e

echo "=========================================="
echo "Nexus IQ Server GKE HA - Terraform Plan"
echo "=========================================="

if [ ! -f "terraform.tfvars" ]; then
    echo "Error: terraform.tfvars not found!"
    echo "Please create terraform.tfvars from terraform.tfvars.example"
    exit 1
fi

# Stop on any CHANGE_ME placeholder left in a setting. Commented lines are skipped.
if grep -v '^[[:space:]]*#' terraform.tfvars | grep -q "CHANGE_ME"; then
    echo "Error: terraform.tfvars still has CHANGE_ME placeholders:"
    grep -n "CHANGE_ME" terraform.tfvars | grep -v '^[0-9]*:[[:space:]]*#' || true
    exit 1
fi

echo "Initializing Terraform..."
terraform init

echo ""
echo "Creating Terraform plan..."
PLAN_FILE="tfplan-$(date +%Y%m%d-%H%M%S)"
terraform plan -out="${PLAN_FILE}"

echo ""
echo "=========================================="
echo "Plan saved to: ${PLAN_FILE}"
echo "To apply: terraform apply ${PLAN_FILE}"
echo "=========================================="
