#!/bin/bash

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
echo "Attempting terraform destroy..."

if terraform destroy; then
    echo ""
    echo "============================================"
    echo "✅ Infrastructure destroyed successfully"
    echo "============================================"
else
    echo ""
    echo "⚠️  Terraform destroy encountered errors"
    echo ""
    echo "This usually happens when:"
    echo "1. Deployment failed mid-way"
    echo "2. Resources exist outside Terraform state"
    echo "3. Service connections are still in use"
    echo ""
    read -p "Would you like to run the force cleanup script? (yes/no): " FORCE_CLEANUP
    
    if [ "$FORCE_CLEANUP" == "yes" ]; then
        echo ""
        echo "Running force cleanup..."
        ./force-cleanup.sh
    else
        echo ""
        echo "To manually clean up, you can:"
        echo "1. Run: ./force-cleanup.sh"
        echo "2. Check: CLEANUP_INSTRUCTIONS.md"
        echo ""
        exit 1
    fi
fi
