#!/bin/bash

set -e

echo "=============================================="
echo "Nexus IQ Server GKE HA - Helm Installation"
echo "=============================================="

echo "Fetching Terraform outputs..."
DB_HOST=$(terraform output -raw database_private_ip)
DB_PASSWORD=$(terraform output -raw database_password)
FILESTORE_IP=$(terraform output -raw filestore_ip)
PROJECT_ID=$(terraform output -raw project_id)
REGION=$(terraform output -raw region)
WORKLOAD_IDENTITY=$(terraform output -raw workload_identity_email)
FLUENTD_IDENTITY=$(terraform output -raw fluentd_workload_identity_email)
INGRESS_IP_NAME=$(terraform output -raw ingress_ip_name)

echo ""
echo "Creating Kubernetes namespace..."
kubectl apply -f nexus-iq-namespace.yaml

echo ""
echo "Creating Filestore PersistentVolume..."
sed "s/FILESTORE_IP_PLACEHOLDER/${FILESTORE_IP}/g" filestore-pv.yaml | kubectl apply -f -

echo ""
echo "Creating Filestore PersistentVolumeClaim..."
kubectl apply -f filestore-pvc.yaml

echo ""
echo "Creating license secret..."
if kubectl get secret nexus-iq-license -n nexus-iq >/dev/null 2>&1; then
    echo "  ✅ License secret already exists"
else
    echo "  Creating placeholder license secret..."
    if kubectl create secret generic nexus-iq-license \
        --from-literal=license_lic="sample-license-content" \
        -n nexus-iq; then
        echo "  ✅ License secret created"
        echo "  ⚠️  Remember to update with your actual license:"
        echo "    kubectl create secret generic nexus-iq-license --from-file=license_lic=path/to/your/license.lic -n nexus-iq --dry-run=client -o yaml | kubectl replace -f -"
    else
        echo "  ❌ Failed to create license secret"
        exit 1
    fi
fi

echo ""
echo "Creating runtime Helm values..."
cp helm-values.yaml helm-values-runtime.yaml

sed -i.bak "s|hostname: \"\"|hostname: \"${DB_HOST}\"|g" helm-values-runtime.yaml
sed -i.bak "s|password: \"\"|password: \"${DB_PASSWORD}\"|g" helm-values-runtime.yaml
sed -i.bak "s|value: \"\"|value: \"${DB_HOST}\"|g" helm-values-runtime.yaml
sed -i.bak "s|DB_PASSWORD.*|DB_PASSWORD\n      value: \"${DB_PASSWORD}\"|g" helm-values-runtime.yaml
sed -i.bak "s|iam.gke.io/gcp-service-account: \"\"|iam.gke.io/gcp-service-account: \"${WORKLOAD_IDENTITY}\"|g" helm-values-runtime.yaml
sed -i.bak "s|projectId: \"\"|projectId: \"${PROJECT_ID}\"|g" helm-values-runtime.yaml
sed -i.bak "s|kubernetes.io/ingress.global-static-ip-name: \"\"|kubernetes.io/ingress.global-static-ip-name: \"${INGRESS_IP_NAME}\"|g" helm-values-runtime.yaml

rm helm-values-runtime.yaml.bak

echo ""
echo "Adding Sonatype Helm repository..."
helm repo add sonatype https://sonatype.github.io/helm3-charts/
helm repo update

echo ""
echo "Installing Nexus IQ Server HA..."
helm install nexus-iq-server-ha sonatype/nexus-iq-server-ha \
  --namespace nexus-iq \
  --values helm-values-runtime.yaml \
  --timeout 10m

echo ""
echo "Creating BackendConfig for health checks..."
kubectl apply -f backend-config.yaml

echo ""
echo "Annotating application service with BackendConfig..."
kubectl annotate service nexus-iq-server-ha-iq-server-application-service \
  cloud.google.com/backend-config='{"default": "nexus-iq-backendconfig"}' \
  -n nexus-iq

echo ""
echo "Creating Ingress..."
sed "s/INGRESS_IP_NAME_PLACEHOLDER/${INGRESS_IP_NAME}/g" ingress.yaml | kubectl apply -f -

echo ""
echo "Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod -l name=nexus-iq-server-ha-iq-server -n nexus-iq --timeout=5m || echo "Pods may still be starting..."

echo ""
echo "=============================================="
echo "Helm installation complete!"
echo "=============================================="

echo ""
echo "Checking deployment status..."
kubectl get pods -n nexus-iq
kubectl get svc -n nexus-iq
echo ""
echo "Ingress (may take 5-10 minutes for IP assignment and backend health checks):"
kubectl get ingress -n nexus-iq

echo ""
echo "Next Steps:"
echo "=============================================="
echo ""
echo "1. Update the license secret with your actual HA-enabled license:"
echo "   kubectl create secret generic nexus-iq-license --from-file=license_lic=path/to/your/license.lic -n nexus-iq --dry-run=client -o yaml | kubectl replace -f -"
echo ""
echo "2. View logs:"
echo "   kubectl logs -f -l app.kubernetes.io/name=nexus-iq-server-ha -n nexus-iq"
echo ""
echo "3. Check Cloud Logging:"
echo "   gcloud logging read 'resource.type=\"k8s_container\" AND resource.labels.namespace_name=\"nexus-iq\"' --limit=50"
echo ""
echo "4. Access Nexus IQ Server:"
echo "   Check ingress status: kubectl get ingress -n nexus-iq"
echo "   Once ADDRESS is assigned, access at: http://<INGRESS-IP>"
echo ""
echo "   Note: GCE Ingress provisioning takes 5-10 minutes for:"
echo "   - Load balancer creation"
echo "   - Backend health checks to pass"
echo "   - SSL certificate provisioning (if enabled)"
echo ""
echo "⚠️  Note: HA clustering requires an HA-enabled license."
echo "   Update with: kubectl create secret generic nexus-iq-license --from-file=license_lic=path/to/license.lic -n nexus-iq --dry-run=client -o yaml | kubectl replace -f -"
echo ""
echo "=============================================="
