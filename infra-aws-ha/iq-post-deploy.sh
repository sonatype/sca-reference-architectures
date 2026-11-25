#!/bin/bash
#
# One-time IQ Server settings this architecture needs after a deploy. The apply
# or install script runs it once IQ Server is deployed, and it is safe to run
# again at any time.
#
#   1. Waits until IQ Server answers on its HTTP port.
#   2. With search_engine = "opensearch":
#      - sets the three Nexus One index shard counts to the OpenSearch data node
#        count, so the first index build creates the indices with them;
#      - on the virtual machine architectures, when this configuration built the
#        OpenSearch cluster, waits for the node that creates IQ Server's user;
#      - chooses OpenSearch as the Nexus One search backend, on IQ Server
#        versions that ask for that choice. Older versions answer 404 and are
#        left alone.
#   With search_engine = "builtin" there is nothing to set: there is no OpenSearch, and Nexus One
#   keeps its index in IQ Server's PostgreSQL database, chosen on the Nexus One setup page.
#
# Every setting comes from this directory's Terraform outputs. Each can be
# overridden from the environment:
#   IQ_URL              IQ Server base URL, such as https://iq.example.com
#   SEARCH_ENGINE       opensearch or builtin
#   IQ_ADMIN_PASSWORD   the admin password, once it has been changed from
#                       iq_admin_initial_password
#   OPENSEARCH_DATA_NODE_COUNT
#                       the OpenSearch cluster's data node count
#   IQ_LICENSE_FILE     the license file to install if IQ Server has none yet,
#                       since choosing the search backend needs a license.
#                       Defaults to the iq_license_file output
#   IQ_WAIT_SECONDS     how long to wait for IQ Server to answer, default 1800
#   IQ_GATEWAY_RETRY_SECONDS
#                       how long to keep retrying a request the load balancer
#                       answers with 502, 503 or 504, default 600
#   IQ_CURL_INSECURE=1  skip the TLS certificate check, for a certificate that
#                       does not name the host in IQ_URL
#   OPENSEARCH_READY_WAIT_SECONDS
#                       on the virtual machine architectures, how long to wait
#                       for the OpenSearch node that creates IQ Server's user to
#                       finish, default 1200. 0 skips the wait

set -euo pipefail

cd "$(dirname "$0")"

# How this architecture reaches IQ Server when IQ_URL is not set: a Terraform
# output holding its URL, or a Kubernetes service reached with kubectl
# port-forward.
URL_OUTPUT="application_url"
K8S_NAMESPACE=""
K8S_SERVICE=""
# How to ask the OpenSearch node that creates IQ Server's user whether it has
# finished, when this architecture built the cluster on virtual machines: azure,
# gcp, or empty when there is nothing to wait for.
OPENSEARCH_NODE_CHECK=""
LOCAL_PORT="${IQ_LOCAL_PORT:-18070}"

# IQ Server accepts shard counts from 1 to nexusOneIndexMaxShards, which is 12
# unless raised.
MAX_SHARDS=12

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}• $*${NC}"; }
ok() { echo -e "${GREEN}✅ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $*${NC}"; }
fail() {
    echo -e "${RED}❌ $*${NC}" >&2
    exit 1
}

tf_output() {
    # With no state, `terraform output -raw` prints a warning and exits 0, so ask
    # for JSON first, which fails cleanly when the output does not exist.
    terraform output -json "$1" >/dev/null 2>&1 || return 0
    terraform output -raw "$1" 2>/dev/null || true
}

echo -e "${BLUE}🔧 IQ Server post-deploy settings${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

command -v curl >/dev/null 2>&1 || fail "curl is not installed"
command -v terraform >/dev/null 2>&1 || fail "terraform is not installed"

SEARCH_ENGINE="${SEARCH_ENGINE:-$(tf_output search_engine)}"
case "$SEARCH_ENGINE" in
    opensearch | builtin) ;;
    "") fail "No search_engine output found. Run this from the architecture directory after terraform apply." ;;
    *) fail "search_engine output is '$SEARCH_ENGINE'; expected opensearch or builtin." ;;
esac
info "Search backend: $SEARCH_ENGINE"

if [[ "$SEARCH_ENGINE" == "builtin" ]]; then
    ok "search_engine is builtin: there is no OpenSearch to set up here. Choose PostgreSQL on the Nexus One setup page to keep the Nexus One index in IQ Server's PostgreSQL database. Advanced Search uses IQ Server's built-in index"
    exit 0
fi

DATA_NODES="${OPENSEARCH_DATA_NODE_COUNT:-$(tf_output opensearch_data_node_count)}"
if ! [[ "$DATA_NODES" =~ ^[0-9]+$ ]] || [[ "$DATA_NODES" -lt 1 ]]; then
    fail "opensearch_data_node_count output is '$DATA_NODES'; expected a whole number of 1 or more. Set OPENSEARCH_DATA_NODE_COUNT to the OpenSearch cluster's data node count to give it directly."
fi
if [[ "$DATA_NODES" -gt "$MAX_SHARDS" ]]; then
    fail "OpenSearch has $DATA_NODES data nodes, and IQ Server accepts at most $MAX_SHARDS shards per index unless nexusOneIndexMaxShards is raised first."
fi
SHARDS="$DATA_NODES"
info "OpenSearch data nodes: $DATA_NODES, so $SHARDS shard(s) per Nexus One index"

ADMIN_PASSWORD="${IQ_ADMIN_PASSWORD:-$(tf_output iq_admin_initial_password)}"
[[ -n "$ADMIN_PASSWORD" ]] || fail "No admin password: set IQ_ADMIN_PASSWORD, or run terraform apply so the iq_admin_initial_password output exists."

CURL_CFG="$(mktemp)"
BODY="$(mktemp)"
PF_LOG="$(mktemp)"
PF_PID=""
cleanup() {
    rm -f "$CURL_CFG" "$BODY" "$PF_LOG"
    if [[ -n "$PF_PID" ]]; then
        kill "$PF_PID" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

# The password goes to curl in a config file rather than on the command line,
# where any process listing would show it.
chmod 600 "$CURL_CFG"
ESCAPED_PASSWORD="${ADMIN_PASSWORD//\\/\\\\}"
ESCAPED_PASSWORD="${ESCAPED_PASSWORD//\"/\\\"}"
printf 'user = "admin:%s"\n' "$ESCAPED_PASSWORD" >"$CURL_CFG"

CURL_TLS=()
if [[ "${IQ_CURL_INSECURE:-0}" == "1" ]]; then
    CURL_TLS=(--insecure)
fi

start_port_forward() {
    if [[ -n "$PF_PID" ]] && kill -0 "$PF_PID" >/dev/null 2>&1; then
        return
    fi
    kubectl -n "$K8S_NAMESPACE" port-forward "svc/$K8S_SERVICE" "$LOCAL_PORT:8070" >"$PF_LOG" 2>&1 &
    PF_PID=$!
    sleep 3
}

IQ_URL="${IQ_URL:-}"
USE_PORT_FORWARD=0
if [[ -z "$IQ_URL" && -n "$K8S_SERVICE" ]]; then
    command -v kubectl >/dev/null 2>&1 || fail "kubectl is not installed"
    USE_PORT_FORWARD=1
    IQ_URL="http://127.0.0.1:$LOCAL_PORT"
    info "IQ Server: service $K8S_SERVICE in namespace $K8S_NAMESPACE, through kubectl port-forward on $IQ_URL"
elif [[ -z "$IQ_URL" ]]; then
    IQ_URL="$(tf_output "$URL_OUTPUT")"
    [[ -n "$IQ_URL" ]] || fail "No $URL_OUTPUT output found. Set IQ_URL to IQ Server's address."
    info "IQ Server: $IQ_URL"
else
    info "IQ Server: $IQ_URL"
fi
IQ_URL="${IQ_URL%/}"

IQ_HOST="${IQ_URL#http://}"
IQ_HOST="${IQ_HOST%%[:/]*}"
if [[ "$IQ_URL" == http://* && "$IQ_HOST" != "127.0.0.1" && "$IQ_HOST" != "localhost" ]]; then
    warn "$IQ_URL is plain HTTP, so the admin password crosses the network unencrypted."
    warn "Once TLS is in front of IQ Server, run this with IQ_URL set to its https:// address."
fi

# Sends one request and prints the HTTP status, 000 when nothing answered. The
# response body is left in $BODY.
iq_request() {
    local method="$1" path="$2" data="${3:-}"
    local args=(-s -K "$CURL_CFG" ${CURL_TLS[@]+"${CURL_TLS[@]}"} -o "$BODY" -w '%{http_code}' --max-time 30 -X "$method")
    if [[ -n "$data" ]]; then
        args+=(-H 'Content-Type: application/json' -d "$data")
    fi
    : >"$BODY"
    curl "${args[@]}" "$IQ_URL$path" 2>/dev/null || true
}

# Behind a load balancer, the first IQ Server node to start can answer while another is
# still starting, and a request the load balancer sends to that one gets 502, 503 or 504.
# retry_gateway runs a request command and repeats it on those statuses for up to
# IQ_GATEWAY_RETRY_SECONDS, 600 by default, then prints the last status.
GATEWAY_RETRY_SECONDS="${IQ_GATEWAY_RETRY_SECONDS:-600}"
[[ "$GATEWAY_RETRY_SECONDS" =~ ^[0-9]+$ ]] || fail "IQ_GATEWAY_RETRY_SECONDS must be a whole number of seconds"
retry_gateway() {
    local status deadline=$((SECONDS + GATEWAY_RETRY_SECONDS))
    while true; do
        status="$("$@")"
        case "$status" in
            502 | 503 | 504)
                if [[ $SECONDS -lt $deadline ]]; then
                    echo "  HTTP $status through the load balancer, retrying in 15s" >&2
                    sleep 15
                    continue
                fi
                ;;
        esac
        echo "$status"
        return
    done
}

# Uploads the license file and prints the HTTP status. The response body is left in $BODY.
upload_license() {
    : >"$BODY"
    curl -s -K "$CURL_CFG" ${CURL_TLS[@]+"${CURL_TLS[@]}"} -o "$BODY" -w '%{http_code}' --max-time 60 \
        -F "file=@$IQ_LICENSE_FILE" "$IQ_URL/api/v2/product/license" 2>/dev/null || true
}

SHARD_PROPERTIES=(nexusOneIndexComponentShards nexusOneIndexViolationShards nexusOneIndexVulnerabilityShards)
SHARD_QUERY="/api/v2/config?property=nexusOneIndexComponentShards&property=nexusOneIndexViolationShards&property=nexusOneIndexVulnerabilityShards"

WAIT_SECONDS="${IQ_WAIT_SECONDS:-1800}"
[[ "$WAIT_SECONDS" =~ ^[0-9]+$ ]] || fail "IQ_WAIT_SECONDS must be a whole number of seconds"
DEADLINE=$((SECONDS + WAIT_SECONDS))
LAST_REPORT=0
echo ""
info "Waiting up to ${WAIT_SECONDS}s for IQ Server to answer"
while true; do
    if [[ "$USE_PORT_FORWARD" == "1" ]]; then
        start_port_forward
    fi
    STATUS="$(iq_request GET "$SHARD_QUERY")"
    case "$STATUS" in
        200) break ;;
        401)
            if [[ -z "${IQ_ADMIN_PASSWORD:-}" ]]; then
                fail "IQ Server refused iq_admin_initial_password. IQ Server keeps the admin password it was given on its very first start, so a deployment first started before iq_admin_initial_password existed still has its existing admin password, admin123 unless it was changed. Run again with IQ_ADMIN_PASSWORD set to it."
            fi
            fail "IQ Server refused the admin password. IQ Server keeps the password it was given on its very first start; if it has been changed since, run again with IQ_ADMIN_PASSWORD set to the current one."
            ;;
        403) fail "IQ Server answered 403: the admin user cannot change system configuration." ;;
    esac
    if [[ "$STATUS" == "000" && "$IQ_URL" == https://* && "${IQ_CURL_INSECURE:-0}" != "1" ]]; then
        if curl -s --insecure -o /dev/null --max-time 10 "$IQ_URL/" 2>/dev/null; then
            fail "IQ Server's TLS certificate does not match $IQ_URL. Run again with IQ_URL set to the name the certificate carries, or with IQ_CURL_INSECURE=1."
        fi
    fi
    if [[ $SECONDS -ge $DEADLINE ]]; then
        fail "IQ Server did not answer within ${WAIT_SECONDS}s (last HTTP status $STATUS). Check the IQ Server logs, then run ./iq-post-deploy.sh again."
    fi
    if [[ $((SECONDS - LAST_REPORT)) -ge 60 ]]; then
        echo "  still waiting, HTTP status $STATUS after ${SECONDS}s"
        LAST_REPORT=$SECONDS
    fi
    sleep 15
done
ok "IQ Server is answering"

shard_value() {
    sed -n "s/.*\"$1\" *: *\([0-9][0-9]*\).*/\1/p" "$BODY"
}

ALL_SET=1
for property in "${SHARD_PROPERTIES[@]}"; do
    if [[ "$(shard_value "$property")" != "$SHARDS" ]]; then
        ALL_SET=0
    fi
done

echo ""
if [[ "$ALL_SET" == "1" ]]; then
    ok "Shard counts already $SHARDS"
else
    PAYLOAD="{\"nexusOneIndexComponentShards\":$SHARDS,\"nexusOneIndexViolationShards\":$SHARDS,\"nexusOneIndexVulnerabilityShards\":$SHARDS}"
    STATUS="$(retry_gateway iq_request PUT /api/v2/config "$PAYLOAD")"
    case "$STATUS" in
        200 | 204) ;;
        *) fail "Setting the shard counts answered HTTP $STATUS: $(cat "$BODY")" ;;
    esac
    STATUS="$(retry_gateway iq_request GET "$SHARD_QUERY")"
    [[ "$STATUS" == "200" ]] || fail "Reading the shard counts back answered HTTP $STATUS"
    for property in "${SHARD_PROPERTIES[@]}"; do
        VALUE="$(shard_value "$property")"
        [[ "$VALUE" == "$SHARDS" ]] || fail "$property reads back as '$VALUE', expected $SHARDS"
    done
    ok "Shard counts set to $SHARDS for the component, violation and vulnerability indices"
    info "A shard count applies when an index is created. An index built before this keeps its count until it is rebuilt."
fi

echo ""
# On the virtual machine architectures, one OpenSearch node creates the user IQ Server
# signs in as once the cluster has formed, which can finish after the apply does. Wait
# for that node to report the user ready before choosing OpenSearch. There is nothing
# to wait for when the cluster was brought rather than built here.
OS_NODE=""
if [[ -n "$OPENSEARCH_NODE_CHECK" ]]; then
    OS_NODE="$(tf_output opensearch_bootstrap_node)"
fi
OS_READY_WAIT_SECONDS="${OPENSEARCH_READY_WAIT_SECONDS:-1200}"
[[ "$OS_READY_WAIT_SECONDS" =~ ^[0-9]+$ ]] || fail "OPENSEARCH_READY_WAIT_SECONDS must be a whole number of seconds"
if [[ -n "$OS_NODE" && "$OS_READY_WAIT_SECONDS" -gt 0 ]]; then
    case "$OPENSEARCH_NODE_CHECK" in
        azure)
            command -v az >/dev/null 2>&1 || fail "az is not installed, and it is needed to check OpenSearch node $OS_NODE. Set OPENSEARCH_READY_WAIT_SECONDS=0 to skip the check."
            OS_GROUP="$(tf_output resource_group_name)"
            [[ -n "$OS_GROUP" ]] || fail "No resource_group_name output found"
            OS_CHECK_HINT="the opensearch-iq-user.service journal on VM $OS_NODE, for example with: az vm run-command invoke --resource-group $OS_GROUP --name $OS_NODE --command-id RunShellScript --scripts 'journalctl -u opensearch-iq-user.service --no-pager | tail -50'"
            ;;
        gcp)
            command -v gcloud >/dev/null 2>&1 || fail "gcloud is not installed, and it is needed to check OpenSearch node $OS_NODE. Set OPENSEARCH_READY_WAIT_SECONDS=0 to skip the check."
            OS_ZONE="$(tf_output opensearch_bootstrap_zone)"
            OS_PROJECT="$(tf_output project_id)"
            [[ -n "$OS_ZONE" && -n "$OS_PROJECT" ]] || fail "No opensearch_bootstrap_zone or project_id output found"
            OS_CHECK_HINT="the opensearch-iq-user.service journal on instance $OS_NODE in zone $OS_ZONE"
            ;;
        *) fail "Unknown OPENSEARCH_NODE_CHECK '$OPENSEARCH_NODE_CHECK'" ;;
    esac

    # Succeeds once the node reports the user ready: on Azure, the IQ_USER_READY line in
    # the user service's journal; on GCP, the guest attribute it writes after that line.
    opensearch_user_ready() {
        case "$OPENSEARCH_NODE_CHECK" in
            azure)
                az vm run-command invoke --resource-group "$OS_GROUP" --name "$OS_NODE" --command-id RunShellScript \
                    --scripts "if journalctl -u opensearch-iq-user.service --no-pager 2>/dev/null | grep -q IQ_USER_READY; then echo user-is-ready; fi" \
                    --query 'value[0].message' -o tsv 2>/dev/null | grep -qx 'user-is-ready'
                ;;
            gcp)
                [[ "$(gcloud compute instances get-guest-attributes "$OS_NODE" --zone "$OS_ZONE" --project "$OS_PROJECT" \
                    --query-path=opensearch/iq-user-ready --format='value(value)' 2>/dev/null)" == "ready" ]]
                ;;
        esac
    }

    info "Waiting up to ${OS_READY_WAIT_SECONDS}s for OpenSearch node $OS_NODE to create the IQ Server user"
    OS_DEADLINE=$((SECONDS + OS_READY_WAIT_SECONDS))
    until opensearch_user_ready; do
        if [[ $SECONDS -ge $OS_DEADLINE ]]; then
            fail "OpenSearch node $OS_NODE did not report the IQ Server user ready within ${OS_READY_WAIT_SECONDS}s. Read $OS_CHECK_HINT, then run ./iq-post-deploy.sh again."
        fi
        echo "  not ready yet after ${SECONDS}s, checking again in 30s"
        sleep 30
    done
    ok "OpenSearch node $OS_NODE has created the IQ Server user"
    echo ""
fi

# IQ Server installs the license iq_license_file names on its first start. This script
# installs it only when IQ Server still has none, which choosing the backend reports
# as 402.
if [[ -z "${IQ_LICENSE_FILE:-}" ]]; then
    IQ_LICENSE_FILE="$(terraform output -raw iq_license_file 2>/dev/null || true)"
fi
STATUS="$(retry_gateway iq_request PUT /api/v2/search/advanced/index/backend '{"backend":"OPENSEARCH"}')"
if [[ "$STATUS" == "402" && -n "${IQ_LICENSE_FILE:-}" ]]; then
    [[ -f "$IQ_LICENSE_FILE" ]] || fail "The license file $IQ_LICENSE_FILE does not exist"
    warn "IQ Server has no license yet, so installing it from $IQ_LICENSE_FILE"
    LICENSE_STATUS="$(retry_gateway upload_license)"
    case "$LICENSE_STATUS" in
        200 | 204) ok "License installed from $IQ_LICENSE_FILE" ;;
        *) fail "Installing the license answered HTTP $LICENSE_STATUS: $(cat "$BODY")" ;;
    esac
    STATUS="$(retry_gateway iq_request PUT /api/v2/search/advanced/index/backend '{"backend":"OPENSEARCH"}')"
fi
case "$STATUS" in
    200)
        ok "Nexus One search backend set to OpenSearch"
        ;;
    409)
        if grep -q "OPENSEARCH" "$BODY"; then
            ok "Nexus One search backend already OpenSearch"
        else
            fail "A different Nexus One search backend is already chosen, and the choice cannot be changed: $(cat "$BODY")"
        fi
        ;;
    402)
        warn "IQ Server has no license yet, and choosing the Nexus One search backend needs one."
        warn "Set iq_license_file in terraform.tfvars and apply, or run ./iq-post-deploy.sh again with IQ_LICENSE_FILE set to the license file."
        echo ""
        ok "Post-deploy settings complete, apart from the search backend choice above"
        exit 0
        ;;
    404 | 405)
        ok "This IQ Server version does not ask for a search backend choice; nothing to set"
        ;;
    *)
        fail "Choosing the Nexus One search backend answered HTTP $STATUS: $(cat "$BODY")"
        ;;
esac

echo ""
ok "Post-deploy settings complete"
