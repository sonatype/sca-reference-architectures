#!/bin/bash
#
# Renders helm-values.yaml into helm-values-runtime.yaml with the real infrastructure values.
#
# Both helm-install.sh and helm-upgrade.sh call this, so neither of them needs a clear-text values
# file to survive between runs: each run builds its own from the current Terraform outputs and
# removes it on exit. That is what makes a password rotation work on this root. Rotating means
# changing the value in terraform.tfvars and applying, and the next helm-upgrade.sh then renders
# the new value out of the state.
#
# Writes the file named by the single argument, mode 600. The caller owns removing it.

set -e

RED='\033[0;31m'
NC='\033[0m'

TEMP_VALUES_FILE="$1"
VALUES_FILE="${VALUES_FILE:-helm-values.yaml}"

if [[ -z "$TEMP_VALUES_FILE" ]]; then
    echo -e "${RED}❌ Error: render-values.sh needs the output file name as its argument${NC}"
    exit 1
fi

if [[ ! -f "$VALUES_FILE" ]]; then
    echo -e "${RED}❌ Error: $VALUES_FILE not found${NC}"
    exit 1
fi

if [[ ! -f "terraform.tfstate" ]]; then
    echo -e "${RED}❌ Error: Terraform state not found${NC}"
    exit 1
fi

DB_HOST=$(terraform output -raw database_private_ip 2>/dev/null || echo "")
DB_PASSWORD=$(terraform output -raw database_password 2>/dev/null || echo "")
FILESTORE_IP=$(terraform output -raw filestore_ip 2>/dev/null || echo "")
PROJECT_ID=$(terraform output -raw project_id 2>/dev/null || echo "")
WORKLOAD_IDENTITY=$(terraform output -raw workload_identity_email 2>/dev/null || echo "")
INGRESS_IP_NAME=$(terraform output -raw ingress_ip_name 2>/dev/null || echo "")
SEARCH_ENGINE=$(terraform output -raw search_engine 2>/dev/null || echo "lucene")
OPENSEARCH_URI=$(terraform output -raw opensearch_uri 2>/dev/null || echo "")
OPENSEARCH_USERNAME=$(terraform output -raw opensearch_username 2>/dev/null || echo "")
OPENSEARCH_PASSWORD=$(terraform output -raw opensearch_password 2>/dev/null || echo "")
OPENSEARCH_REPLICAS=$(terraform output -raw opensearch_index_replicas 2>/dev/null || echo "0")
OPENSEARCH_CA=$(terraform output -raw opensearch_ca_certificate 2>/dev/null || echo "")

if [[ -z "$FILESTORE_IP" || -z "$DB_HOST" ]]; then
    echo -e "${RED}❌ Error: Missing required infrastructure outputs${NC}"
    exit 1
fi

cp "$VALUES_FILE" "$TEMP_VALUES_FILE"

# The generated file carries the database and OpenSearch passwords in clear text, so it is readable
# only by its owner.
chmod 600 "$TEMP_VALUES_FILE"

sed -i.bak "s|hostname: \"\"|hostname: \"${DB_HOST}\"|g" "$TEMP_VALUES_FILE"
sed -i.bak "s|password: \"\"|password: \"${DB_PASSWORD}\"|g" "$TEMP_VALUES_FILE"
sed -i.bak "s|value: \"\"|value: \"${DB_HOST}\"|g" "$TEMP_VALUES_FILE"
sed -i.bak "s|DB_PASSWORD.*|DB_PASSWORD\n      value: \"${DB_PASSWORD}\"|g" "$TEMP_VALUES_FILE"
sed -i.bak "s|iam.gke.io/gcp-service-account: \"\"|iam.gke.io/gcp-service-account: \"${WORKLOAD_IDENTITY}\"|g" "$TEMP_VALUES_FILE"
sed -i.bak "s|projectId: \"\"|projectId: \"${PROJECT_ID}\"|g" "$TEMP_VALUES_FILE"
sed -i.bak "s|kubernetes.io/ingress.global-static-ip-name: \"\"|kubernetes.io/ingress.global-static-ip-name: \"${INGRESS_IP_NAME}\"|g" "$TEMP_VALUES_FILE"

if [[ "$SEARCH_ENGINE" == "opensearch" ]]; then
    if [[ -z "$OPENSEARCH_URI" || -z "$OPENSEARCH_USERNAME" || -z "$OPENSEARCH_PASSWORD" ]]; then
        echo -e "${RED}❌ Error: search_engine is \"opensearch\" but the endpoint, user name or password is empty${NC}"
        exit 1
    fi
    sed -i.bak "s|OPENSEARCH_URI_PLACEHOLDER|${OPENSEARCH_URI}|g" "$TEMP_VALUES_FILE"
    sed -i.bak "s|OPENSEARCH_REPLICAS_PLACEHOLDER|${OPENSEARCH_REPLICAS}|g" "$TEMP_VALUES_FILE"

    # The user name and the password are both written as single-quoted YAML scalars, with an
    # embedded single quote written twice, and both are substituted with awk rather than sed. A sed
    # replacement reads \ and & specially and ends at the | delimiter, so a value containing any of
    # those three is mangled with no error, and an unquoted scalar containing ": " " #" or a
    # leading indicator character breaks the YAML. awk reads each value out of the environment, so
    # nothing in it is read as a pattern or as an escape.
    OPENSEARCH_USERNAME_YAML="'$(printf '%s' "$OPENSEARCH_USERNAME" | sed "s/'/''/g")'"
    OPENSEARCH_PASSWORD_YAML="'$(printf '%s' "$OPENSEARCH_PASSWORD" | sed "s/'/''/g")'"
    export OPENSEARCH_USERNAME_YAML OPENSEARCH_PASSWORD_YAML
    awk '
      BEGIN {
        user = ENVIRON["OPENSEARCH_USERNAME_YAML"]
        pass = ENVIRON["OPENSEARCH_PASSWORD_YAML"]
      }
      /^[[:space:]]*username: OPENSEARCH_USERNAME_PLACEHOLDER[[:space:]]*$/ {
        match($0, /^[[:space:]]*/)
        print substr($0, 1, RLENGTH) "username: " user
        next
      }
      /^[[:space:]]*password: OPENSEARCH_PASSWORD_PLACEHOLDER[[:space:]]*$/ {
        match($0, /^[[:space:]]*/)
        print substr($0, 1, RLENGTH) "password: " pass
        next
      }
      { print }
    ' "$TEMP_VALUES_FILE" > "${TEMP_VALUES_FILE}.new"
    mv "${TEMP_VALUES_FILE}.new" "$TEMP_VALUES_FILE"
    unset OPENSEARCH_USERNAME_YAML OPENSEARCH_PASSWORD_YAML
    chmod 600 "$TEMP_VALUES_FILE"
else
    # Remove the whole search block, markers and all, so the deployment uses the built-in index.
    sed -i.bak "/# search-block-begin/,/# search-block-end/d" "$TEMP_VALUES_FILE"
fi

# A private certificate authority for the cluster reaches the pods as the Kubernetes Secret
# nexus-iq-opensearch-ca, which the pods read through an environment variable. The chart version
# this root pins mounts no extra volumes into the IQ Server pod. Without an authority, the blocks
# between the opensearch-ca markers are deleted, so the pods run the image's own start command.
if [[ "$SEARCH_ENGINE" == "opensearch" && -n "$OPENSEARCH_CA" ]]; then
    kubectl create secret generic nexus-iq-opensearch-ca \
        --from-literal=ca.pem="$OPENSEARCH_CA" \
        -n "${NAMESPACE:-nexus-iq}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
else
    sed -i.bak "/# opensearch-ca-begin/,/# opensearch-ca-end/d" "$TEMP_VALUES_FILE"
fi

# A placeholder left behind means a substitution did not run, and Nexus IQ Server would read the
# literal text as a host name or a password.
if grep -q "OPENSEARCH_.*_PLACEHOLDER" "$TEMP_VALUES_FILE"; then
    echo -e "${RED}❌ Error: a search placeholder survived substitution in ${TEMP_VALUES_FILE}${NC}"
    exit 1
fi

rm -f "${TEMP_VALUES_FILE}.bak"
