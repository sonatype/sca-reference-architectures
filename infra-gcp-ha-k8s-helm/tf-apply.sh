#!/bin/bash

set -e

echo "==========================================="
echo "Nexus IQ Server GKE HA - Terraform Apply"
echo "==========================================="

if [ ! -f "terraform.tfvars" ]; then
    echo "Error: terraform.tfvars not found!"
    echo "Please create terraform.tfvars from terraform.tfvars.example"
    exit 1
fi

echo "Initializing Terraform..."
terraform init

echo ""
echo "Planning infrastructure deployment..."
terraform plan

echo ""
read -p "Do you want to proceed with deployment? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Deployment cancelled."
    exit 0
fi

echo ""
echo "Applying Terraform configuration..."
terraform apply -auto-approve

echo ""
echo "==========================================="
echo "Infrastructure deployment complete!"
echo "==========================================="

echo ""
echo "Configuring kubectl..."
CLUSTER_NAME=$(terraform output -raw gke_cluster_name)
REGION=$(terraform output -raw region)
PROJECT_ID=$(terraform output -raw project_id)

gcloud container clusters get-credentials "${CLUSTER_NAME}" --region "${REGION}" --project "${PROJECT_ID}"

echo ""
echo "Next steps:"
echo "1. Review the outputs: terraform output"
echo "2. Deploy Nexus IQ Server: ./helm-install.sh"
echo "==========================================="
