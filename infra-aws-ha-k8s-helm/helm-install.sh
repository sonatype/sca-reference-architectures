#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

NAMESPACE="nexus-iq"
HELM_RELEASE_NAME="nexus-iq-server-ha"
HELM_CHART_REPO="https://sonatype.github.io/helm3-charts"
HELM_CHART_NAME="nexus-iq-server-ha"
VALUES_FILE="helm-values.yaml"
AWS_PROFILE="admin@iq-sandbox"

echo -e "${BLUE}🚀 Nexus IQ Server HA on EKS - Helm Installation${NC}"
echo "===================================================="
echo ""

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}❌ Error: kubectl not found${NC}"
    exit 1
fi

if ! command -v helm &> /dev/null; then
    echo -e "${RED}❌ Error: helm not found${NC}"
    exit 1
fi

KUBECTL_PREFIX=""
TERRAFORM_PREFIX=""
HELM_PREFIX=""
if command -v aws-vault >/dev/null 2>&1; then
    KUBECTL_PREFIX="aws-vault exec $AWS_PROFILE --"
    TERRAFORM_PREFIX="aws-vault exec $AWS_PROFILE --"
    HELM_PREFIX="aws-vault exec $AWS_PROFILE --"
fi

if ! $KUBECTL_PREFIX kubectl cluster-info >/dev/null 2>&1; then
    KUBECTL_COMMAND=$($TERRAFORM_PREFIX terraform output -raw kubectl_config_command 2>/dev/null || echo "")

    if [[ -n "$KUBECTL_COMMAND" ]]; then
        if command -v aws-vault >/dev/null 2>&1; then
            aws-vault exec "$AWS_PROFILE" -- $KUBECTL_COMMAND >/dev/null 2>&1
        else
            $KUBECTL_COMMAND >/dev/null 2>&1
        fi
    else
        AWS_REGION="us-east-1"
        CLUSTER_NAME="nexus-iq-ha"

        if command -v aws-vault >/dev/null 2>&1; then
            aws-vault exec "$AWS_PROFILE" -- aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME" >/dev/null 2>&1
        else
            aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME" >/dev/null 2>&1
        fi
    fi

    sleep 2
    if ! $KUBECTL_PREFIX kubectl cluster-info >/dev/null 2>&1; then
        echo -e "${RED}❌ Error: Cannot connect to Kubernetes cluster${NC}"
        exit 1
    fi
fi

if [[ ! -f "$VALUES_FILE" ]]; then
    echo -e "${RED}❌ Error: $VALUES_FILE not found${NC}"
    exit 1
fi

if [[ ! -f "terraform.tfstate" ]]; then
    echo -e "${RED}❌ Error: Terraform state not found${NC}"
    exit 1
fi

echo -e "${BLUE}📊 Retrieving Infrastructure Details${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

DB_ENDPOINT=$($TERRAFORM_PREFIX terraform output -raw rds_cluster_endpoint 2>/dev/null || echo "")
EFS_ID=$($TERRAFORM_PREFIX terraform output -raw efs_id 2>/dev/null || echo "")
EFS_DATA_ACCESS_POINT=$($TERRAFORM_PREFIX terraform output -raw efs_data_access_point_id 2>/dev/null || echo "")
EFS_LOGS_ACCESS_POINT=$($TERRAFORM_PREFIX terraform output -raw efs_logs_access_point_id 2>/dev/null || echo "")
AWS_REGION=$($TERRAFORM_PREFIX terraform output -raw aws_region 2>/dev/null || echo "us-east-1")
CLUSTER_NAME=$($TERRAFORM_PREFIX terraform output -raw cluster_name 2>/dev/null || echo "")

echo "• Database: $DB_ENDPOINT"
echo "• EFS: $EFS_ID"
echo "• Region: $AWS_REGION"
echo "• Cluster: $CLUSTER_NAME"
echo ""

if [[ -z "$EFS_ID" || -z "$EFS_DATA_ACCESS_POINT" ]]; then
    echo -e "${RED}❌ Error: Missing required infrastructure outputs${NC}"
    exit 1
fi

echo -e "${BLUE}💾 Configuring Storage${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━"

$KUBECTL_PREFIX kubectl delete pv nexus-iq-data-pv nexus-iq-logs-pv iq-server-pv --ignore-not-found=true >/dev/null 2>&1 || true
$KUBECTL_PREFIX kubectl get pv -o name 2>/dev/null | grep -E "(nexus|iq)" | xargs -r $KUBECTL_PREFIX kubectl delete --ignore-not-found=true >/dev/null 2>&1 || true
$KUBECTL_PREFIX kubectl delete storageclass efs-sc --ignore-not-found=true >/dev/null 2>&1 || true

sleep 3

sed -e "s/\${EFS_ID}/$EFS_ID/g" efs-storageclass.yaml | $KUBECTL_PREFIX kubectl apply -f - >/dev/null 2>&1

$KUBECTL_PREFIX kubectl apply -f nexus-iq-namespace.yaml >/dev/null 2>&1

timeout=30
elapsed=0
while ! $KUBECTL_PREFIX kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; do
    if [ $elapsed -ge $timeout ]; then
        echo -e "${RED}❌ Error: Namespace creation failed${NC}"
        exit 1
    fi
    sleep 2
    elapsed=$((elapsed + 2))
done

if ! $KUBECTL_PREFIX kubectl apply -f nexus-iq-pvc.yaml >/dev/null 2>&1; then
    echo -e "${RED}❌ Error: PVC creation failed${NC}"
    exit 1
fi

sleep 2
timeout=60
elapsed=0
while true; do
    PVC_STATUS=$($KUBECTL_PREFIX kubectl get pvc iq-server-pvc -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")

    if [[ "$PVC_STATUS" == "Bound" ]]; then
        break
    elif [[ "$PVC_STATUS" == "NotFound" && $elapsed -eq 0 ]]; then
        echo -e "${RED}❌ Error: PVC not found${NC}"
        exit 1
    elif [ $elapsed -ge $timeout ]; then
        echo -e "${RED}❌ Error: PVC binding timeout${NC}"
        exit 1
    fi

    sleep 5
    elapsed=$((elapsed + 5))
done

if ! $KUBECTL_PREFIX kubectl get secret nexus-iq-license -n "$NAMESPACE" >/dev/null 2>&1; then
    $KUBECTL_PREFIX kubectl create secret generic nexus-iq-license \
        --from-literal=license_lic="sample-license-content" \
        -n "$NAMESPACE" >/dev/null 2>&1
fi

echo -e "${GREEN}✅ Storage configured${NC}"
echo ""

echo -e "${BLUE}📦 Preparing Helm Chart${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━"

if $HELM_PREFIX helm repo list 2>/dev/null | grep -q sonatype; then
    $HELM_PREFIX helm repo update >/dev/null 2>&1
else
    $HELM_PREFIX helm repo add sonatype "$HELM_CHART_REPO" >/dev/null 2>&1
    $HELM_PREFIX helm repo update >/dev/null 2>&1
fi

DB_NAME=$($TERRAFORM_PREFIX terraform output -raw rds_cluster_database_name 2>/dev/null || echo "nexusiq")
DB_PORT=$($TERRAFORM_PREFIX terraform output -raw rds_cluster_port 2>/dev/null || echo "5432")
SECRET_NAME=$($TERRAFORM_PREFIX terraform output -raw secrets_manager_secret_name 2>/dev/null || echo "")

if [[ -n "$SECRET_NAME" && "$SECRET_NAME" != "null" ]]; then
    if command -v timeout >/dev/null 2>&1; then
        if command -v aws-vault >/dev/null 2>&1; then
            SECRET_JSON=$(timeout 30s aws-vault exec "$AWS_PROFILE" -- aws secretsmanager get-secret-value \
                --secret-id "$SECRET_NAME" \
                --query 'SecretString' \
                --output text \
                --region "$AWS_REGION" 2>/dev/null || echo "")
        else
            SECRET_JSON=$(timeout 30s aws secretsmanager get-secret-value \
                --secret-id "$SECRET_NAME" \
                --query 'SecretString' \
                --output text \
                --region "$AWS_REGION" 2>/dev/null || echo "")
        fi
    else
        if command -v aws-vault >/dev/null 2>&1; then
            SECRET_JSON=$(aws-vault exec "$AWS_PROFILE" -- aws secretsmanager get-secret-value \
                --secret-id "$SECRET_NAME" \
                --query 'SecretString' \
                --output text \
                --region "$AWS_REGION" 2>/dev/null || echo "")
        else
            SECRET_JSON=$(aws secretsmanager get-secret-value \
                --secret-id "$SECRET_NAME" \
                --query 'SecretString' \
                --output text \
                --region "$AWS_REGION" 2>/dev/null || echo "")
        fi
    fi

    if [[ -n "$SECRET_JSON" ]]; then
        DB_USERNAME=$(echo "$SECRET_JSON" | jq -r '.username' 2>/dev/null || echo "")
        DB_PASSWORD=$(echo "$SECRET_JSON" | jq -r '.password' 2>/dev/null || echo "")

        if [[ -z "$DB_USERNAME" || -z "$DB_PASSWORD" ]]; then
            DB_USERNAME=$(grep '^database_username' terraform.tfvars | cut -d'"' -f2)
            DB_PASSWORD=$(grep '^database_password' terraform.tfvars | cut -d'"' -f2)
        fi
    else
        DB_USERNAME=$(grep '^database_username' terraform.tfvars | cut -d'"' -f2)
        DB_PASSWORD=$(grep '^database_password' terraform.tfvars | cut -d'"' -f2)
    fi
else
    DB_USERNAME=$(grep '^database_username' terraform.tfvars | cut -d'"' -f2)
    DB_PASSWORD=$(grep '^database_password' terraform.tfvars | cut -d'"' -f2)
fi

FLUENTD_IRSA_ROLE_ARN=$($TERRAFORM_PREFIX terraform output -raw fluentd_irsa_role_arn 2>/dev/null || echo "")
REPLICA_COUNT=$(grep '^nexus_iq_replica_count' terraform.tfvars | cut -d'=' -f2 | tr -d ' ' 2>/dev/null || echo "3")

TEMP_VALUES_FILE="helm-values-runtime.yaml"
cp "$VALUES_FILE" "$TEMP_VALUES_FILE"

sed -i.bak \
    -e "s/hostname: \"\"/hostname: \"$DB_ENDPOINT\"/" \
    -e "s/password: \"\"/password: \"$DB_PASSWORD\"/" \
    -e "s/username: \"nexusiq\"/username: \"$DB_USERNAME\"/" \
    -e "s/name: \"nexusiq\"/name: \"$DB_NAME\"/" \
    -e "s/port: 5432/port: $DB_PORT/" \
    -e "s/region: \"us-east-1\"/region: \"$AWS_REGION\"/" \
    -e "s|eks.amazonaws.com/role-arn: \"\"|eks.amazonaws.com/role-arn: \"$FLUENTD_IRSA_ROLE_ARN\"|g" \
    -e "s/replicaCount: [0-9]*/replicaCount: $REPLICA_COUNT/" \
    "$TEMP_VALUES_FILE"

sed -i '' \
    -e "/name: DB_HOSTNAME/{n;s/value: \"\"/value: \"$DB_ENDPOINT\"/;}" \
    -e "/name: DB_PASSWORD/{n;s/value: \"\"/value: \"$DB_PASSWORD\"/;}" \
    -e "/name: DB_USERNAME/{n;s/value: \"nexusiq\"/value: \"$DB_USERNAME\"/;}" \
    -e "/name: DB_NAME/{n;s/value: \"nexusiq\"/value: \"$DB_NAME\"/;}" \
    -e "/name: DB_PORT/{n;s/value: \"5432\"/value: \"$DB_PORT\"/;}" \
    "$TEMP_VALUES_FILE"

if $HELM_PREFIX helm list -n "$NAMESPACE" 2>/dev/null | grep -q "$HELM_RELEASE_NAME"; then
    echo -e "${YELLOW}⚠️  Helm release already exists - use ./helm-upgrade.sh${NC}"
    rm -f "$TEMP_VALUES_FILE" "${TEMP_VALUES_FILE}.bak"
    exit 1
fi

if ! $KUBECTL_PREFIX kubectl get storageclass efs-sc >/dev/null 2>&1; then
    echo -e "${RED}❌ Error: StorageClass 'efs-sc' missing${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Helm chart configured${NC}"
echo ""

CHART_VERSION=$(grep '^helm_chart_version' terraform.tfvars | cut -d'"' -f2)

echo -e "${BLUE}🚀 Installing Helm Release${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "This may take 10-15 minutes..."
echo ""

if $HELM_PREFIX helm install "$HELM_RELEASE_NAME" sonatype/nexus-iq-server-ha \
    --namespace "$NAMESPACE" \
    --create-namespace \
    --version "$CHART_VERSION" \
    --values "$TEMP_VALUES_FILE" \
    --timeout 10m; then

    rm -f "$TEMP_VALUES_FILE" "${TEMP_VALUES_FILE}.bak"

    RDS_SG_ID=$($TERRAFORM_PREFIX terraform output -raw rds_security_group_id 2>/dev/null || echo "")
    if [[ -n "$RDS_SG_ID" && "$RDS_SG_ID" != "null" ]]; then
        timeout=120
        elapsed=0
        EKS_NODE_SG=""
        while [[ -z "$EKS_NODE_SG" ]] && [ $elapsed -lt $timeout ]; do
            EKS_NODE_SG=$(aws-vault exec "$AWS_PROFILE" -- aws ec2 describe-instances \
                --filters "Name=tag:eks:cluster-name,Values=$CLUSTER_NAME" "Name=instance-state-name,Values=running" \
                --query 'Reservations[].Instances[0].SecurityGroups[].GroupId' \
                --output text 2>/dev/null | awk '{print $1}')

            if [[ -z "$EKS_NODE_SG" ]]; then
                sleep 10
                elapsed=$((elapsed + 10))
            fi
        done

        if [[ -n "$EKS_NODE_SG" ]]; then
            EXISTING_RULE=$(aws-vault exec "$AWS_PROFILE" -- aws ec2 describe-security-groups \
                --group-ids "$RDS_SG_ID" \
                --query "SecurityGroups[0].IpPermissions[?FromPort==\`5432\` && ToPort==\`5432\`].UserIdGroupPairs[?GroupId==\`$EKS_NODE_SG\`]" \
                --output text 2>/dev/null || echo "")

            if [[ -z "$EXISTING_RULE" ]]; then
                aws-vault exec "$AWS_PROFILE" -- aws ec2 authorize-security-group-ingress \
                    --group-id "$RDS_SG_ID" \
                    --protocol tcp --port 5432 \
                    --source-group "$EKS_NODE_SG" >/dev/null 2>&1 || true
            fi
        fi
    fi

    if $KUBECTL_PREFIX kubectl get pods -l app.kubernetes.io/name=nexus-iq-server-ha -n "$NAMESPACE" 2>/dev/null | grep -q "nexus"; then
        $KUBECTL_PREFIX kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=nexus-iq-server-ha -n "$NAMESPACE" --timeout=300s >/dev/null 2>&1 || true
    elif $KUBECTL_PREFIX kubectl get pods -l app=nexus-iq-server-ha -n "$NAMESPACE" 2>/dev/null | grep -q "nexus"; then
        $KUBECTL_PREFIX kubectl wait --for=condition=ready pod -l app=nexus-iq-server-ha -n "$NAMESPACE" --timeout=300s >/dev/null 2>&1 || true
    else
        sleep 30
    fi

    ALB_ADDRESS=""
    ALB_TIMEOUT=120
    ALB_ELAPSED=0
    while [[ -z "$ALB_ADDRESS" ]] && [ $ALB_ELAPSED -lt $ALB_TIMEOUT ]; do
        ALB_ADDRESS=$($KUBECTL_PREFIX kubectl get ingress -n "$NAMESPACE" -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
        if [[ -z "$ALB_ADDRESS" ]]; then
            sleep 5
            ALB_ELAPSED=$((ALB_ELAPSED + 5))
        fi
    done

    echo ""
    echo -e "${GREEN}✅ Installation Completed Successfully${NC}"
    echo ""

    echo -e "${BLUE}📊 Deployment Summary${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━"

    $KUBECTL_PREFIX kubectl get pods -n "$NAMESPACE"
    echo ""

    $KUBECTL_PREFIX kubectl get svc -n "$NAMESPACE"
    echo ""

    if [[ -n "$ALB_ADDRESS" ]]; then
        echo "• Application URL: http://$ALB_ADDRESS"
        echo ""
    fi

    echo -e "${BLUE}🎯 Next Steps${NC}"
    echo "━━━━━━━━━━━━"
    echo "1. Access IQ Server (default credentials: admin / admin123)"
    echo "2. Monitor pods: kubectl get pods -n $NAMESPACE -w"
    echo ""

else
    echo ""
    echo -e "${RED}❌ Installation Failed${NC}"

    echo ""
    echo -e "${BLUE}📋 Troubleshooting${NC}"
    echo "━━━━━━━━━━━━━━━━━━"

    $KUBECTL_PREFIX kubectl get pods -n "$NAMESPACE" 2>/dev/null || true
    echo ""

    $KUBECTL_PREFIX kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' 2>/dev/null | tail -10 || true
    echo ""

    rm -f "$TEMP_VALUES_FILE" "${TEMP_VALUES_FILE}.bak"
    exit 1
fi
