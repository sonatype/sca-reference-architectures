#!/bin/bash

set -e

# Extra Helm values files, applied after helm-values.yaml so their settings win.
# ../deploy.sh passes the size file this way, examples/<size>.helm-values.yaml.
EXTRA_VALUES_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--values)
            if [[ $# -lt 2 || ! -f "$2" ]]; then
                echo "Error: $1 needs an existing values file" >&2
                exit 1
            fi
            EXTRA_VALUES_ARGS+=(--values "$2")
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [-f|--values FILE]...  extra values files, applied after helm-values.yaml"
            exit 0
            ;;
        *)
            echo "Error: unknown option $1 (see $0 --help)" >&2
            exit 1
            ;;
    esac
done

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
REPLICA_COUNT=${REPLICA_COUNT:-2}
sed -i.bak "s|^  replicas: [0-9]*|  replicas: ${REPLICA_COUNT}|" "$TEMP_VALUES_FILE"

# A CHANGE_ME from terraform.tfvars, such as the database password, stops the upgrade here.
if grep -v '^[[:space:]]*#' "$TEMP_VALUES_FILE" | grep -q "CHANGE_ME"; then
  echo "Error: $TEMP_VALUES_FILE still has CHANGE_ME placeholders"
  grep -n "CHANGE_ME" "$TEMP_VALUES_FILE" | grep -v '^[0-9]*:[[:space:]]*#' || true
  exit 1
fi

# terraform.tfvars wins when it sets helm_chart_version, otherwise the pin in variables.tf.
CHART_VERSION=$(sed -n 's/^helm_chart_version *= *"\([^"]*\)".*/\1/p' terraform.tfvars)
if [ -z "$CHART_VERSION" ]; then
  CHART_VERSION=$(awk '/^variable "helm_chart_version"/ {f=1} f && /^[[:space:]]*default[[:space:]]*=/ {split($0, q, "\""); print q[2]; exit}' variables.tf)
fi
if [ -z "$CHART_VERSION" ]; then
  echo "Error: no helm_chart_version in terraform.tfvars or variables.tf"
  exit 1
fi

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
  ${EXTRA_VALUES_ARGS[@]+"${EXTRA_VALUES_ARGS[@]}"} \
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
  # Through helm, on the release's installed chart. Helm 4 applies server-side, so a
  # kubectl scale would own the replica count and fail the upgrade below.
  PREVIOUS_REVISION=$(helm list -n nexus-iq -f '^nexus-iq-server-ha$' -o json | sed -n 's/.*"revision":"\{0,1\}\([0-9]*\).*/\1/p')
  CURRENT_CHART_VERSION=$(helm list -n nexus-iq -f '^nexus-iq-server-ha$' -o json | sed -n 's/.*"chart":"nexus-iq-server-ha-\([^"]*\)".*/\1/p')
  if ! helm upgrade nexus-iq-server-ha sonatype/nexus-iq-server-ha \
    --namespace nexus-iq \
    --version "$CURRENT_CHART_VERSION" \
    --reuse-values \
    --set iq_server.replicas=0 \
    --set hpa.enabled=false \
    --wait \
    --timeout 10m; then
    echo "Error: scaling IQ Server to zero failed, so the migration did not start"
    exit 1
  fi
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
  ${EXTRA_VALUES_ARGS[@]+"${EXTRA_VALUES_ARGS[@]}"} \
  "${MIGRATE_ARGS[@]}" \
  --wait \
  --timeout 15m; then
  echo ""
  echo "Error: helm upgrade failed"
  kubectl logs job/nexus-iq-server-ha-migrate-db -n nexus-iq --tail=20 2>/dev/null || true
  if [ ${#MIGRATE_ARGS[@]} -gt 0 ]; then
    echo "IQ Server was scaled to zero for the migration. Once the cause is fixed, start the previous version again:"
    echo "  helm rollback nexus-iq-server-ha $PREVIOUS_REVISION -n nexus-iq"
  fi
  exit 1
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
