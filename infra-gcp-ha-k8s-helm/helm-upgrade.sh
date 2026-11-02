#!/bin/bash

set -e

echo "============================================="
echo "Nexus IQ Server GKE HA - Helm Upgrade"
echo "============================================="

TEMP_VALUES_FILE="helm-values-runtime.yaml"

# The values file is rendered here rather than reused from an earlier helm-install.sh run. It holds
# the database and OpenSearch passwords in clear text, so both scripts remove it on exit, and a
# rotation would otherwise have nothing to upgrade from: changing the password in terraform.tfvars
# and applying puts the new value in the state, and this render is what carries it into the release.
trap 'rm -f "$TEMP_VALUES_FILE" "$TEMP_VALUES_FILE.bak" "$TEMP_VALUES_FILE.new"' EXIT INT TERM

echo "Rendering values from the current Terraform outputs..."
./render-values.sh "$TEMP_VALUES_FILE"

echo "Updating Helm repository..."
helm repo update

echo ""
echo "Upgrading Nexus IQ Server HA..."
helm upgrade nexus-iq-server-ha sonatype/nexus-iq-server-ha \
  --namespace nexus-iq \
  --values "$TEMP_VALUES_FILE" \
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
