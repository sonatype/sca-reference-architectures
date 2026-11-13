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

# Credentials come from the standard AWS chain: the named profile in AWS_PROFILE,
# such as an IAM Identity Center profile, or credentials already in the environment.
if [[ -z "$AWS_PROFILE" && -z "$AWS_ACCESS_KEY_ID" ]]; then
    echo -e "${RED}❌ Error: AWS_PROFILE environment variable is not set${NC}"
    echo ""
    echo "Please set your AWS profile name:"
    echo "  export AWS_PROFILE=your-profile-name"
    echo ""
    echo "Or run with inline variable:"
    echo "  AWS_PROFILE=your-profile-name ./helm-install.sh"
    echo ""
    exit 1
fi

if ! command -v aws &> /dev/null; then
    echo -e "${RED}❌ Error: aws not found${NC}"
    exit 1
fi

if ! aws sts get-caller-identity --region "${AWS_REGION:-us-east-1}" >/dev/null 2>&1; then
    echo -e "${RED}❌ Error: no valid AWS credentials${NC}"
    echo ""
    echo "The credentials are missing or have expired. For an IAM Identity Center"
    echo "profile, sign in again:"
    echo "  aws sso login --profile ${AWS_PROFILE:-your-profile-name}"
    echo ""
    exit 1
fi

if ! kubectl cluster-info >/dev/null 2>&1; then
    KUBECTL_COMMAND=$(terraform output -raw kubectl_config_command 2>/dev/null || echo "")

    if [[ -n "$KUBECTL_COMMAND" ]]; then
        $KUBECTL_COMMAND >/dev/null 2>&1
    else
        # Without Terraform outputs, the cluster name and region come from terraform.tfvars,
        # falling back to the variables.tf defaults Terraform itself uses.
        AWS_REGION=$(sed -n 's/^aws_region *= *"\([^"]*\)".*/\1/p' terraform.tfvars 2>/dev/null || true)
        AWS_REGION=${AWS_REGION:-us-east-1}
        CLUSTER_NAME=$(sed -n 's/^cluster_name *= *"\([^"]*\)".*/\1/p' terraform.tfvars 2>/dev/null || true)
        CLUSTER_NAME=${CLUSTER_NAME:-nexus-iq-ha}

        aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME" >/dev/null 2>&1
    fi

    sleep 2
    if ! kubectl cluster-info >/dev/null 2>&1; then
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

DB_ENDPOINT=$(terraform output -raw rds_cluster_endpoint 2>/dev/null || echo "")
EFS_ID=$(terraform output -raw efs_id 2>/dev/null || echo "")
EFS_DATA_ACCESS_POINT=$(terraform output -raw efs_data_access_point_id 2>/dev/null || echo "")
EFS_LOGS_ACCESS_POINT=$(terraform output -raw efs_logs_access_point_id 2>/dev/null || echo "")
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "us-east-1")
CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "")
LOG_GROUP=$(terraform output -raw cloudwatch_log_group 2>/dev/null || echo "")

echo "• Database: $DB_ENDPOINT"
echo "• EFS: $EFS_ID"
echo "• Region: $AWS_REGION"
echo "• Cluster: $CLUSTER_NAME"
echo "• Log group: $LOG_GROUP"
echo ""

if [[ -z "$EFS_ID" || -z "$EFS_DATA_ACCESS_POINT" || -z "$CLUSTER_NAME" || -z "$LOG_GROUP" ]]; then
    echo -e "${RED}❌ Error: Missing required infrastructure outputs${NC}"
    echo "   efs_id, efs_data_access_point_id, cluster_name and cloudwatch_log_group must all be set."
    echo "   Run ./tf-apply.sh in this directory first."
    exit 1
fi

echo -e "${BLUE}💾 Configuring Storage${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━"

kubectl delete pv nexus-iq-data-pv nexus-iq-logs-pv iq-server-pv --ignore-not-found=true >/dev/null 2>&1 || true
kubectl get pv -o name 2>/dev/null | grep -E "(nexus|iq)" | xargs -r kubectl delete --ignore-not-found=true >/dev/null 2>&1 || true
kubectl delete storageclass efs-sc --ignore-not-found=true >/dev/null 2>&1 || true

sleep 3

sed -e "s/\${EFS_ID}/$EFS_ID/g" efs-storageclass.yaml | kubectl apply -f - >/dev/null 2>&1

kubectl apply -f nexus-iq-namespace.yaml >/dev/null 2>&1

timeout=30
elapsed=0
while ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; do
    if [ $elapsed -ge $timeout ]; then
        echo -e "${RED}❌ Error: Namespace creation failed${NC}"
        exit 1
    fi
    sleep 2
    elapsed=$((elapsed + 2))
done

if ! kubectl apply -f nexus-iq-pvc.yaml >/dev/null 2>&1; then
    echo -e "${RED}❌ Error: PVC creation failed${NC}"
    exit 1
fi

sleep 2
timeout=60
elapsed=0
while true; do
    PVC_STATUS=$(kubectl get pvc iq-server-pvc -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")

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

if ! kubectl get secret nexus-iq-license -n "$NAMESPACE" >/dev/null 2>&1; then
    kubectl create secret generic nexus-iq-license \
        --from-literal=license_lic="sample-license-content" \
        -n "$NAMESPACE" >/dev/null 2>&1
fi

echo -e "${GREEN}✅ Storage configured${NC}"
echo ""

echo -e "${BLUE}📦 Preparing Helm Chart${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━"

if helm repo list 2>/dev/null | grep -q sonatype; then
    helm repo update >/dev/null 2>&1
else
    helm repo add sonatype "$HELM_CHART_REPO" >/dev/null 2>&1
    helm repo update >/dev/null 2>&1
fi

DB_NAME=$(terraform output -raw rds_cluster_database_name 2>/dev/null || echo "nexusiq")
DB_PORT=$(terraform output -raw rds_cluster_port 2>/dev/null || echo "5432")
SECRET_NAME=$(terraform output -raw secrets_manager_secret_name 2>/dev/null || echo "")

if [[ -n "$SECRET_NAME" && "$SECRET_NAME" != "null" ]]; then
    if command -v timeout >/dev/null 2>&1; then
        SECRET_JSON=$(timeout 30s aws secretsmanager get-secret-value \
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

FLUENTD_IRSA_ROLE_ARN=$(terraform output -raw fluentd_irsa_role_arn 2>/dev/null || echo "")
# sed rather than cut, which keeps a trailing comment. The default is on its own line because
# `|| echo` after a pipe sees only the last command's status.
REPLICA_COUNT=$(sed -n 's/^nexus_iq_replica_count *= *\([0-9]*\).*/\1/p' terraform.tfvars)
REPLICA_COUNT=${REPLICA_COUNT:-3}
SEARCH_ENGINE=$(terraform output -raw search_engine 2>/dev/null || echo "lucene")
OPENSEARCH_ENDPOINT=$(terraform output -raw opensearch_domain_endpoint 2>/dev/null || echo "")
OPENSEARCH_REPLICAS=$(terraform output -raw opensearch_index_replicas 2>/dev/null || echo "0")

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
    -e "s/^  replicas: [0-9]*/  replicas: $REPLICA_COUNT/" \
    -e "s|CLOUDWATCH_LOG_GROUP_PLACEHOLDER|$LOG_GROUP|g" \
    "$TEMP_VALUES_FILE"

# Fill in or delete the search: block between its markers, after the database
# substitutions above so their patterns cannot touch it.
if [[ "$SEARCH_ENGINE" == "opensearch" ]]; then
    if [[ -z "$OPENSEARCH_ENDPOINT" ]]; then
        echo -e "${RED}❌ Error: search_engine is 'opensearch' but no domain endpoint was found${NC}"
        echo "   Run terraform apply with search_engine = \"opensearch\" and check it created the domain."
        echo "   Set opensearch_domain_endpoint only to use a domain you already run."
        rm -f "$TEMP_VALUES_FILE" "${TEMP_VALUES_FILE}.bak"
        exit 1
    fi
    sed -i.bak2 \
        -e "s|OPENSEARCH_DOMAIN_PLACEHOLDER|$OPENSEARCH_ENDPOINT|" \
        -e "s|OPENSEARCH_REGION_PLACEHOLDER|$AWS_REGION|" \
        -e "s|OPENSEARCH_REPLICAS_PLACEHOLDER|$OPENSEARCH_REPLICAS|" \
        "$TEMP_VALUES_FILE"
    # The unanchored role-arn substitution above also gave nexus-iq-sa the Fluentd
    # role; point that service account at the OpenSearch role instead.
    IQ_IRSA_ROLE_ARN=$(terraform output -raw iq_server_irsa_role_arn 2>/dev/null || echo "")
    if [[ -z "$IQ_IRSA_ROLE_ARN" ]]; then
        echo -e "${RED}❌ Error: no iq_server_irsa_role_arn output found${NC}"
        echo "   Re-run terraform apply with search_engine = \"opensearch\" set."
        rm -f "$TEMP_VALUES_FILE" "${TEMP_VALUES_FILE}.bak" "${TEMP_VALUES_FILE}.bak2"
        exit 1
    fi
    sed -i.bak3 \
        -e "/^serviceAccount:/,/^[a-z]/s|^\( \{4\}\)eks.amazonaws.com/role-arn: \".*\"|\1eks.amazonaws.com/role-arn: \"$IQ_IRSA_ROLE_ARN\"|" \
        "$TEMP_VALUES_FILE"
    rm -f "${TEMP_VALUES_FILE}.bak3"
    echo "• Search backend: OpenSearch at $OPENSEARCH_ENDPOINT, $OPENSEARCH_REPLICAS replica(s)"
else
    sed -i.bak2 \
        -e "/# BEGIN search backend/,/# END search backend/d" \
        "$TEMP_VALUES_FILE"
    echo "• Search backend: Lucene, built into IQ Server"
fi
rm -f "${TEMP_VALUES_FILE}.bak2"

if grep -q "_PLACEHOLDER" "$TEMP_VALUES_FILE"; then
    echo -e "${RED}❌ Error: a placeholder was left unsubstituted in $TEMP_VALUES_FILE${NC}"
    grep -n "_PLACEHOLDER" "$TEMP_VALUES_FILE"
    rm -f "$TEMP_VALUES_FILE" "${TEMP_VALUES_FILE}.bak"
    exit 1
fi

sed -i '' \
    -e "/name: DB_HOSTNAME/{n;s/value: \"\"/value: \"$DB_ENDPOINT\"/;}" \
    -e "/name: DB_PASSWORD/{n;s/value: \"\"/value: \"$DB_PASSWORD\"/;}" \
    -e "/name: DB_USERNAME/{n;s/value: \"nexusiq\"/value: \"$DB_USERNAME\"/;}" \
    -e "/name: DB_NAME/{n;s/value: \"nexusiq\"/value: \"$DB_NAME\"/;}" \
    -e "/name: DB_PORT/{n;s/value: \"5432\"/value: \"$DB_PORT\"/;}" \
    "$TEMP_VALUES_FILE"

# A CHANGE_ME from terraform.tfvars, such as the database password, stops the install here.
if grep -v '^[[:space:]]*#' "$TEMP_VALUES_FILE" | grep -q "CHANGE_ME"; then
    echo -e "${RED}❌ Error: $TEMP_VALUES_FILE still has CHANGE_ME placeholders${NC}"
    grep -n "CHANGE_ME" "$TEMP_VALUES_FILE" | grep -v '^[0-9]*:[[:space:]]*#' || true
    rm -f "$TEMP_VALUES_FILE" "${TEMP_VALUES_FILE}.bak"
    exit 1
fi

if helm list -n "$NAMESPACE" 2>/dev/null | grep -q "$HELM_RELEASE_NAME"; then
    echo -e "${YELLOW}⚠️  Helm release already exists - use ./helm-upgrade.sh${NC}"
    rm -f "$TEMP_VALUES_FILE" "${TEMP_VALUES_FILE}.bak"
    exit 1
fi

if ! kubectl get storageclass efs-sc >/dev/null 2>&1; then
    echo -e "${RED}❌ Error: StorageClass 'efs-sc' missing${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Helm chart configured${NC}"
echo ""

CHART_VERSION=$(sed -n 's/^helm_chart_version *= *"\([^"]*\)".*/\1/p' terraform.tfvars)
CHART_VERSION=${CHART_VERSION:-201.0.0}

echo -e "${BLUE}🚀 Installing Helm Release${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "This may take 10-15 minutes..."
echo ""

if helm install "$HELM_RELEASE_NAME" sonatype/nexus-iq-server-ha \
    --namespace "$NAMESPACE" \
    --create-namespace \
    --version "$CHART_VERSION" \
    --values "$TEMP_VALUES_FILE" \
    --timeout 10m; then

    rm -f "$TEMP_VALUES_FILE" "${TEMP_VALUES_FILE}.bak"

    kubectl wait --for=condition=ready pod -l name=nexus-iq-server-ha-iq-server -n "$NAMESPACE" --timeout=5m >/dev/null 2>&1 || true

    ALB_ADDRESS=""
    ALB_TIMEOUT=120
    ALB_ELAPSED=0
    while [[ -z "$ALB_ADDRESS" ]] && [ $ALB_ELAPSED -lt $ALB_TIMEOUT ]; do
        ALB_ADDRESS=$(kubectl get ingress -n "$NAMESPACE" -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
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

    kubectl get pods -n "$NAMESPACE"
    echo ""

    kubectl get svc -n "$NAMESPACE"
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

    kubectl get pods -n "$NAMESPACE" 2>/dev/null || true
    echo ""

    kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' 2>/dev/null | tail -10 || true
    echo ""

    rm -f "$TEMP_VALUES_FILE" "${TEMP_VALUES_FILE}.bak"
    exit 1
fi
