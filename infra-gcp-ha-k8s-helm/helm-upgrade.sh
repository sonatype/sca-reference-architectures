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

# The migration job is a post-install hook (helm-values.yaml), so this upgrade runs it
# only when the IQ Server image changes, and then only with MIGRATE_DATABASE=yes. The
# migration refuses to start while any IQ Server instance uses the database, so IQ
# Server is scaled to zero first and the job runs as a pre-upgrade hook, which helm
# waits for and fails the upgrade on.
IQ_DEPLOYMENT="nexus-iq-server-ha-iq-server-deployment"
IQ_CONTAINER="nexus-iq-server-ha-iq-server-container"
CURRENT_IMAGE=$(kubectl get deployment "$IQ_DEPLOYMENT" -n nexus-iq \
  -o jsonpath="{.spec.template.spec.containers[?(@.name==\"$IQ_CONTAINER\")].image}" 2>/dev/null || echo "")
NEW_IMAGE=$(helm template nexus-iq-server-ha sonatype/nexus-iq-server-ha \
  --namespace nexus-iq \
  --version "$CHART_VERSION" \
  --values "$TEMP_VALUES_FILE" \
  --show-only templates/iq-server-deployment.yaml 2>/dev/null \
  | sed -n "/name: $IQ_CONTAINER\$/{n;s/^ *image: *//p;}" || true)
if [ -z "$NEW_IMAGE" ]; then
  echo "Error: could not render the IQ Server image from chart $CHART_VERSION"
  exit 1
fi
MIGRATE_ARGS=()
if [ "$CURRENT_IMAGE" != "$NEW_IMAGE" ]; then
  if [ "${MIGRATE_DATABASE:-}" != "yes" ]; then
    echo "Error: the IQ Server image changes from ${CURRENT_IMAGE:-none} to $NEW_IMAGE"
    echo "  A new image needs a database migration, which stops IQ Server for its duration."
    echo "  Back up the database, then re-run with MIGRATE_DATABASE=yes ./helm-upgrade.sh"
    exit 1
  fi
  MIGRATE_ARGS=(--set-string 'iq_server_jobs.migrationJobAnnotations.helm\.sh/hook=pre-upgrade')
  echo "IQ Server image: ${CURRENT_IMAGE:-none} -> $NEW_IMAGE"
  echo "Scaling IQ Server to zero for the database migration..."
  kubectl scale deployment "$IQ_DEPLOYMENT" -n nexus-iq --replicas=0
  kubectl wait --for=delete pod -l name=nexus-iq-server-ha-iq-server -n nexus-iq --timeout=10m 2>/dev/null || true
  # The migration refuses to run within 15 seconds of an IQ Server instance using the database.
  sleep 20
else
  echo "IQ Server image: $NEW_IMAGE, unchanged, so the database migration does not run"
fi

echo ""
echo "Upgrading Nexus IQ Server HA to chart $CHART_VERSION with $REPLICA_COUNT replicas..."
if ! helm upgrade nexus-iq-server-ha sonatype/nexus-iq-server-ha \
  --namespace nexus-iq \
  --version "$CHART_VERSION" \
  --values "$TEMP_VALUES_FILE" \
  "${MIGRATE_ARGS[@]}" \
  --wait \
  --timeout 15m; then
  echo ""
  echo "Error: helm upgrade failed"
  kubectl logs job/nexus-iq-server-ha-migrate-db -n nexus-iq --tail=20 2>/dev/null || true
  if [ ${#MIGRATE_ARGS[@]} -gt 0 ]; then
    echo "IQ Server was scaled to zero for the migration. Once the cause is fixed, start it again:"
    echo "  kubectl scale deployment $IQ_DEPLOYMENT -n nexus-iq --replicas=$REPLICA_COUNT"
  fi
  exit 1
fi

# helm keeps the replica count kubectl scale set, since the chart value did not change,
# and the autoscaler does not act on a deployment at zero, so IQ Server is started here.
if [ ${#MIGRATE_ARGS[@]} -gt 0 ]; then
  kubectl scale deployment "$IQ_DEPLOYMENT" -n nexus-iq --replicas="$REPLICA_COUNT"
  if ! kubectl rollout status deployment/"$IQ_DEPLOYMENT" -n nexus-iq --timeout=15m; then
    echo "Error: IQ Server did not become ready after the database migration"
    exit 1
  fi
fi

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
