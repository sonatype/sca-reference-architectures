#!/bin/bash

set -e

echo "============================================="
echo "Nexus IQ Server GKE HA - Helm Upgrade"
echo "============================================="

if [ ! -f "helm-values-runtime.yaml" ]; then
    echo "Error: helm-values-runtime.yaml not found!"
    echo "Please run helm-install.sh first or create the file manually."
    exit 1
fi

echo "Updating Helm repository..."
helm repo update

echo ""
echo "Upgrading Nexus IQ Server HA..."
helm upgrade nexus-iq-server-ha sonatype/nexus-iq-server-ha \
  --namespace nexus-iq \
  --values helm-values-runtime.yaml \
  --wait \
  --timeout 15m

echo ""
echo "============================================="
echo "Helm upgrade complete!"
echo "============================================="

echo ""
echo "Checking deployment status..."
kubectl get pods -n nexus-iq
kubectl get svc -n nexus-iq

echo ""
echo "To view logs:"
echo "  kubectl logs -f -l app.kubernetes.io/name=nexus-iq-server-ha -n nexus-iq"
