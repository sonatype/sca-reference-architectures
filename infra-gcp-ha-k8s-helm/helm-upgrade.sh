#!/bin/bash

set -e

VALUES_FILE="helm-values.yaml"
TEMP_VALUES_FILE="helm-values-runtime.yaml"

echo "============================================="
echo "Nexus IQ Server GKE HA - Helm Upgrade"
echo "============================================="

if [ ! -f "$VALUES_FILE" ]; then
    echo "Error: $VALUES_FILE not found!"
    exit 1
fi

if [ ! -f "terraform.tfstate" ]; then
    echo "Error: Terraform state not found!"
    echo "Run terraform apply and helm-install.sh first."
    exit 1
fi

DB_HOST=$(terraform output -raw database_private_ip 2>/dev/null || echo "")
DB_PASSWORD=$(terraform output -raw database_password 2>/dev/null || echo "")
PROJECT_ID=$(terraform output -raw project_id 2>/dev/null || echo "")
WORKLOAD_IDENTITY=$(terraform output -raw workload_identity_email 2>/dev/null || echo "")
INGRESS_IP_NAME=$(terraform output -raw ingress_ip_name 2>/dev/null || echo "")

if [ -z "$DB_HOST" ]; then
    echo "Error: database_private_ip is empty in the Terraform outputs."
    exit 1
fi

# The runtime file holds the database password, so it is removed however the script exits.
trap 'rm -f "$TEMP_VALUES_FILE" "${TEMP_VALUES_FILE}.bak"' EXIT

cp "$VALUES_FILE" "$TEMP_VALUES_FILE"

sed -i.bak "s|hostname: \"\"|hostname: \"${DB_HOST}\"|g" "$TEMP_VALUES_FILE"
sed -i.bak "s|password: \"\"|password: \"${DB_PASSWORD}\"|g" "$TEMP_VALUES_FILE"
sed -i.bak "s|value: \"\"|value: \"${DB_HOST}\"|g" "$TEMP_VALUES_FILE"
sed -i.bak "s|DB_PASSWORD.*|DB_PASSWORD\n      value: \"${DB_PASSWORD}\"|g" "$TEMP_VALUES_FILE"
sed -i.bak "s|iam.gke.io/gcp-service-account: \"\"|iam.gke.io/gcp-service-account: \"${WORKLOAD_IDENTITY}\"|g" "$TEMP_VALUES_FILE"
sed -i.bak "s|projectId: \"\"|projectId: \"${PROJECT_ID}\"|g" "$TEMP_VALUES_FILE"
sed -i.bak "s|kubernetes.io/ingress.global-static-ip-name: \"\"|kubernetes.io/ingress.global-static-ip-name: \"${INGRESS_IP_NAME}\"|g" "$TEMP_VALUES_FILE"

# The capture stops at the digits, so a trailing comment in terraform.tfvars is ignored.
REPLICA_COUNT=$(sed -n 's/^nexus_iq_replica_count *= *\([0-9]*\).*/\1/p' terraform.tfvars)
REPLICA_COUNT=${REPLICA_COUNT:-3}
sed -i.bak "s|^  replicas: [0-9]*|  replicas: ${REPLICA_COUNT}|" "$TEMP_VALUES_FILE"

CHART_VERSION=$(sed -n 's/^helm_chart_version *= *"\([^"]*\)".*/\1/p' terraform.tfvars)
CHART_VERSION=${CHART_VERSION:-195.0.0}

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
