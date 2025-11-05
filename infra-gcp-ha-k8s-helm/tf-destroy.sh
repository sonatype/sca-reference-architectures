#!/bin/bash

set -e

echo "============================================"
echo "Nexus IQ Server GKE HA - Terraform Destroy"
echo "============================================"

echo ""
echo "WARNING: This will destroy ALL infrastructure including:"
echo "  - GKE Cluster"
echo "  - Cloud SQL Database (all data will be lost)"
echo "  - Filestore (all data will be lost)"
echo "  - VPC and networking"
echo "  - All other resources"
echo ""
read -p "Are you absolutely sure? Type 'YES' to confirm: " CONFIRM

if [ "$CONFIRM" != "YES" ]; then
    echo "Destruction cancelled."
    exit 0
fi

echo ""
echo "Destroying infrastructure..."
terraform destroy

echo ""
echo "============================================"
echo "Infrastructure destroyed successfully"
echo "============================================"
