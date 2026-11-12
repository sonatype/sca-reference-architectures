#!/bin/bash

set -e

echo "============================================="
echo "Nexus IQ Server GKE HA - Helm Upgrade"
echo "============================================="

TEMP_VALUES_FILE="helm-values-runtime.yaml"

# Rendered fresh from Terraform outputs, since the values file holding the passwords is
# removed after each run; this is how a rotated password reaches the release.
trap 'rm -f "$TEMP_VALUES_FILE" "$TEMP_VALUES_FILE.bak" "$TEMP_VALUES_FILE.new"' EXIT INT TERM

echo "Rendering values from the current Terraform outputs..."
./render-values.sh "$TEMP_VALUES_FILE"

# The capture stops at the digits, so a trailing comment in terraform.tfvars is ignored.
REPLICA_COUNT=$(sed -n 's/^nexus_iq_replica_count *= *\([0-9]*\).*/\1/p' terraform.tfvars)
REPLICA_COUNT=${REPLICA_COUNT:-3}
sed -i.bak "s|^  replicas: [0-9]*|  replicas: ${REPLICA_COUNT}|" "$TEMP_VALUES_FILE"

# A CHANGE_ME from terraform.tfvars, such as the database password, stops the upgrade here.
if grep -v '^[[:space:]]*#' "$TEMP_VALUES_FILE" | grep -q "CHANGE_ME"; then
  echo "Error: $TEMP_VALUES_FILE still has CHANGE_ME placeholders"
  grep -n "CHANGE_ME" "$TEMP_VALUES_FILE" | grep -v '^[0-9]*:[[:space:]]*#' || true
  exit 1
fi

# Unset in terraform.tfvars, keep the chart version the release already runs.
CHART_VERSION=$(sed -n 's/^helm_chart_version *= *"\([^"]*\)".*/\1/p' terraform.tfvars)
if [ -z "$CHART_VERSION" ]; then
  CHART_VERSION=$(helm list -n nexus-iq -f '^nexus-iq-server-ha$' -o json | sed -n 's/.*"chart":"nexus-iq-server-ha-\([^"]*\)".*/\1/p')
fi
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
