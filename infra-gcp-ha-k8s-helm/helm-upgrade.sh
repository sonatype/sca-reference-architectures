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

# The capture stops at the digits, so a trailing comment in terraform.tfvars is ignored.
REPLICA_COUNT=$(sed -n 's/^nexus_iq_replica_count *= *\([0-9]*\).*/\1/p' terraform.tfvars)
REPLICA_COUNT=${REPLICA_COUNT:-3}
sed -i.bak "s|^  replicas: [0-9]*|  replicas: ${REPLICA_COUNT}|" "$TEMP_VALUES_FILE"

CHART_VERSION=$(sed -n 's/^helm_chart_version *= *"\([^"]*\)".*/\1/p' terraform.tfvars)
CHART_VERSION=${CHART_VERSION:-201.0.0}

echo "Updating Helm repository..."
helm repo update

echo ""
echo "Upgrading Nexus IQ Server HA to chart $CHART_VERSION with $REPLICA_COUNT replicas..."
helm upgrade nexus-iq-server-ha sonatype/nexus-iq-server-ha \
  --namespace nexus-iq \
  --version "$CHART_VERSION" \
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
