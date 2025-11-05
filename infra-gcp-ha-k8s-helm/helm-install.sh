#!/bin/bash

set -e

echo "=============================================="
echo "Nexus IQ Server GKE HA - Helm Installation"
echo "=============================================="

echo "Fetching Terraform outputs..."
DB_HOST=$(terraform output -raw database_private_ip)
DB_PASSWORD=$(terraform output -raw database_username)
FILESTORE_IP=$(terraform output -raw filestore_ip)
PROJECT_ID=$(terraform output -raw project_id)
REGION=$(terraform output -raw region)
WORKLOAD_IDENTITY=$(terraform output -raw workload_identity_email)
FLUENTD_IDENTITY=$(terraform output -raw fluentd_workload_identity_email)
INGRESS_IP_NAME=$(terraform output -raw ingress_ip)

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
  --wait \
  --timeout 15m

echo ""
echo "=============================================="
echo "Helm installation complete!"
echo "=============================================="

echo ""
echo "Checking deployment status..."
kubectl get pods -n nexus-iq
kubectl get svc -n nexus-iq
kubectl get ingress -n nexus-iq

echo ""
echo "To view logs:"
echo "  kubectl logs -f -l app.kubernetes.io/name=nexus-iq-server-ha -n nexus-iq"
echo ""
echo "To check Cloud Logging:"
echo "  gcloud logging read 'resource.type=\"k8s_container\" AND resource.labels.namespace_name=\"nexus-iq\"' --limit=50"
echo ""
echo "=============================================="
