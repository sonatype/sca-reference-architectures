#!/bin/bash

set -e

echo "==============================================="
echo "Nexus IQ Server GKE HA - Helm Uninstall"
echo "==============================================="

echo ""
read -p "This will remove the Nexus IQ Server deployment. Continue? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Uninstall cancelled."
    exit 0
fi

echo ""
echo "Uninstalling Nexus IQ Server HA..."
helm uninstall nexus-iq-server-ha --namespace nexus-iq || true

echo ""
echo "Removing PersistentVolumeClaim..."
kubectl delete pvc nexus-iq-pvc -n nexus-iq || true

echo ""
echo "Removing PersistentVolume..."
kubectl delete pv nexus-iq-filestore-pv || true

echo ""
read -p "Do you want to delete the namespace? (yes/no): " DELETE_NS
if [ "$DELETE_NS" == "yes" ]; then
    echo "Deleting namespace..."
    kubectl delete namespace nexus-iq || true
fi

echo ""
echo "==============================================="
echo "Helm uninstall complete!"
echo "==============================================="
echo ""
echo "Note: Filestore data has not been deleted."
echo "To destroy all infrastructure: ./tf-destroy.sh"
