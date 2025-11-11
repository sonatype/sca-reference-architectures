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
