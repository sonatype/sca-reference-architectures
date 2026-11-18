#!/bin/bash
# Sets up one OpenSearch node from /etc/opensearch-node/node.env, which Terraform writes through
# cloud-init. The same script runs on Azure and on Google Cloud; OS_CLOUD picks how it reads secrets.
#
#   opensearch-node.sh setup     first boot: data disk, package, certificates, opensearch.yml, start
#   opensearch-node.sh iq-user   creates or updates the user IQ Server signs in as; run on every boot
#                                by opensearch-iq-user.service on the one node that owns it
#
# No secret is passed in instance metadata. Every key, certificate and password is read at boot from
# the cloud's secret store with the node's own identity.
set -euo pipefail

# shellcheck disable=SC1091
. /etc/opensearch-node/node.env

CONF_DIR=/etc/opensearch
DATA_DIR=/var/lib/opensearch

log() { echo "opensearch-node: $*"; }

# Prints one field of a JSON object read from stdin, with no trailing newline.
json_field() {
  python3 -c 'import json, sys; sys.stdout.write(str(json.load(sys.stdin)[sys.argv[1]]))' "$1"
}

access_token() {
  case "$OS_CLOUD" in
    azure)
      curl -sf -H "Metadata: true" \
        "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fvault.azure.net&client_id=$OS_AZURE_CLIENT_ID" |
        json_field access_token
      ;;
    gcp)
      curl -sf -H "Metadata-Flavor: Google" \
        "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token" |
        json_field access_token
      ;;
    *)
      log "REFUSING: unknown OS_CLOUD '$OS_CLOUD'"
      return 1
      ;;
  esac
}

# Prints the value of one secret. Retries for ten minutes, because the identity's access and the
# secret itself can arrive a little after the machine boots.
read_secret() {
  local name=$1 token value attempt
  for attempt in $(seq 1 60); do
    if token=$(access_token) && [ -n "$token" ]; then
      case "$OS_CLOUD" in
        azure)
          if value=$(curl -sf -H "Authorization: Bearer $token" \
            "$OS_AZURE_VAULT_URL/secrets/$name?api-version=7.4" | json_field value); then
            printf '%s' "$value"
            return 0
          fi
          ;;
        gcp)
          if value=$(curl -sf -H "Authorization: Bearer $token" \
            "https://secretmanager.googleapis.com/v1/projects/$OS_GCP_PROJECT/secrets/$name/versions/latest:access" |
            python3 -c 'import base64, json, sys; sys.stdout.write(base64.b64decode(json.load(sys.stdin)["payload"]["data"]).decode())'); then
            printf '%s' "$value"
            return 0
          fi
          ;;
      esac
    fi
    log "secret $name not readable yet, attempt $attempt"
    sleep 10
  done
  log "REFUSING: secret $name was not readable after ten minutes"
  return 1
}

# Azure fallback when the by-lun link is missing: the one whole disk that is not the boot disk,
# has no partitions and holds no file system.
find_blank_disk() {
  local root_disk dev
  root_disk=$(lsblk -npo PKNAME "$(findmnt -no SOURCE /)" | head -1)
  for dev in $(lsblk -dnpo NAME,TYPE | awk '$2 == "disk" { print $1 }'); do
    [ "$dev" = "$root_disk" ] && continue
    [ "$(lsblk -npo NAME "$dev" | wc -l)" -gt 1 ] && continue
    blkid "$dev" >/dev/null 2>&1 && continue
    echo "$dev"
    return 0
  done
  return 1
}

mount_data_disk() {
  local dev="" attempt
  if mountpoint -q "$DATA_DIR"; then
    log "$DATA_DIR already mounted"
    return 0
  fi
  # The disk attachment can finish a minute or two after the machine starts.
  for attempt in $(seq 1 60); do
    if [ -e "$OS_DATA_DISK" ]; then
      dev=$(readlink -f "$OS_DATA_DISK")
      break
    fi
    if [ "$OS_CLOUD" = "azure" ] && dev=$(find_blank_disk); then
      break
    fi
    log "data disk not attached yet, attempt $attempt"
    sleep 5
  done
  if [ -z "$dev" ]; then
    log "REFUSING: no data disk appeared at $OS_DATA_DISK"
    return 1
  fi
  if ! blkid "$dev" >/dev/null 2>&1; then
    mkfs.ext4 -q -F -L osdata "$dev"
  fi
  mkdir -p "$DATA_DIR"
  local uuid
  uuid=$(blkid -s UUID -o value "$dev")
  grep -q " $DATA_DIR " /etc/fstab || echo "UUID=$uuid $DATA_DIR ext4 defaults,nofail 0 2" >>/etc/fstab
  mount "$DATA_DIR"
  mountpoint -q "$DATA_DIR" || {
    log "REFUSING: $DATA_DIR is not mounted"
    return 1
  }
  log "data disk $dev mounted at $DATA_DIR"
}

install_opensearch() {
  local admin_password=$1
  export DEBIAN_FRONTEND=noninteractive
  if dpkg -l opensearch 2>/dev/null | grep -q '^ii'; then
    log "opensearch already installed"
    return 0
  fi
  apt-get update -q
  apt-get install -y -q curl gnupg ca-certificates python3
  # The 3.x repository is signed by the release key in opensearch-release.pgp, not opensearch.pgp.
  curl -sfo /tmp/opensearch-release.pgp https://artifacts.opensearch.org/publickeys/opensearch-release.pgp
  gpg --batch --yes --dearmor -o /usr/share/keyrings/opensearch-release-keyring.gpg /tmp/opensearch-release.pgp
  echo "deb [signed-by=/usr/share/keyrings/opensearch-release-keyring.gpg] https://artifacts.opensearch.org/releases/bundle/opensearch/3.x/apt stable main" \
    >/etc/apt/sources.list.d/opensearch-3.x.list
  apt-get update -q
  OPENSEARCH_INITIAL_ADMIN_PASSWORD="$admin_password" apt-get install -y -q "opensearch=$OS_VERSION"
  # Unattended upgrades must not move the version under a running cluster.
  apt-mark hold opensearch
}

# The package ships demo users with published passwords. The security index is created from this
# file on first start, so it holds the admin user alone; IQ Server's user is added later through the
# REST API by the iq-user step.
write_internal_users() {
  local admin_password=$1 hash
  hash=$(OS_ADMIN_PW="$admin_password" OPENSEARCH_JAVA_HOME=/usr/share/opensearch/jdk \
    bash /usr/share/opensearch/plugins/opensearch-security/tools/hash.sh -env OS_ADMIN_PW 2>/dev/null | tail -1)
  case "$hash" in
    # A bcrypt hash starts with a literal $2.
    "\$2"*) ;;
    *)
      log "REFUSING: could not hash the admin password"
      return 1
      ;;
  esac
  cat >"$CONF_DIR/opensearch-security/internal_users.yml" <<USERS
---
_meta:
  type: "internalusers"
  config_version: 2

admin:
  hash: "$hash"
  reserved: true
  backend_roles:
  - "admin"
  description: "OpenSearch admin user"
USERS
  chown opensearch:opensearch "$CONF_DIR/opensearch-security/internal_users.yml"
  chmod 600 "$CONF_DIR/opensearch-security/internal_users.yml"
}

install_certificates() {
  install -d -o opensearch -g opensearch -m 750 "$CONF_DIR"
  read_secret "$OS_SECRET_CA_CERT" >"$CONF_DIR/root-ca.pem"
  read_secret "$OS_SECRET_NODE_CERT" >"$CONF_DIR/esnode.pem"
  read_secret "$OS_SECRET_NODE_KEY" >"$CONF_DIR/esnode-key.pem"
  if [ -n "$OS_SECRET_ADMIN_CERT" ]; then
    read_secret "$OS_SECRET_ADMIN_CERT" >"$CONF_DIR/admin.pem"
    read_secret "$OS_SECRET_ADMIN_KEY" >"$CONF_DIR/admin-key.pem"
  fi
  rm -f "$CONF_DIR"/kirk.pem "$CONF_DIR"/kirk-key.pem "$CONF_DIR"/esnode-demo*.pem
  chown opensearch:opensearch "$CONF_DIR"/*.pem
  chmod 600 "$CONF_DIR"/*.pem
  local f
  for f in root-ca esnode esnode-key; do
    [ -s "$CONF_DIR/$f.pem" ] || {
      log "REFUSING: $f.pem is empty"
      return 1
    }
  done
  log "certificates installed"
}

# Turns "a,b,c" into "\"a\", \"b\", \"c\"" for a YAML flow list.
yaml_list() {
  printf '%s' "$1" | awk -F, '{ for (i = 1; i <= NF; i++) printf "%s\"%s\"", (i > 1 ? ", " : ""), $i }'
}

write_config() {
  local roles discovery awareness=""
  roles=$(yaml_list "$OS_NODE_ROLES")
  if [ "$OS_SINGLE_NODE" = "true" ]; then
    discovery="discovery.type: single-node"
  else
    discovery="discovery.seed_hosts: [ $(yaml_list "$OS_SEED_HOSTS") ]
cluster.initial_cluster_manager_nodes: [ $(yaml_list "$OS_MANAGER_NODES") ]"
    awareness="cluster.routing.allocation.awareness.attributes: zone"
    # Forcing the zone values is right only when the nodes really sit in three zones.
    if [ -n "$OS_FORCE_ZONES" ]; then
      awareness="$awareness
cluster.routing.allocation.awareness.force.zone.values: $OS_FORCE_ZONES"
    fi
  fi

  cat >"$CONF_DIR/opensearch.yml" <<YML
cluster.name: $OS_CLUSTER_NAME
node.name: $OS_NODE_NAME
node.roles: [ $roles ]
node.attr.zone: "$OS_NODE_ZONE"

network.host: 0.0.0.0
http.port: 9200
transport.port: 9300

path.data: $DATA_DIR
path.logs: /var/log/opensearch

$discovery
$awareness

bootstrap.memory_lock: true

plugins.security.ssl.transport.pemcert_filepath: esnode.pem
plugins.security.ssl.transport.pemkey_filepath: esnode-key.pem
plugins.security.ssl.transport.pemtrustedcas_filepath: root-ca.pem
plugins.security.ssl.transport.enforce_hostname_verification: false
plugins.security.ssl.http.enabled: true
plugins.security.ssl.http.pemcert_filepath: esnode.pem
plugins.security.ssl.http.pemkey_filepath: esnode-key.pem
plugins.security.ssl.http.pemtrustedcas_filepath: root-ca.pem
plugins.security.allow_default_init_securityindex: true
plugins.security.authcz.admin_dn:
  - '$OS_ADMIN_DN'
plugins.security.nodes_dn:
  - '$OS_NODES_DN'
plugins.security.audit.type: internal_opensearch
plugins.security.enable_snapshot_restore_privilege: true
plugins.security.check_snapshot_restore_write_privileges: true
plugins.security.restapi.roles_enabled: ["all_access", "security_rest_api_access"]
YML
  chown opensearch:opensearch "$CONF_DIR/opensearch.yml"

  install -d -o opensearch -g opensearch "$CONF_DIR/jvm.options.d"
  printf -- '-Xms%sm\n-Xmx%sm\n' "$OS_HEAP_MB" "$OS_HEAP_MB" >"$CONF_DIR/jvm.options.d/heap.options"
  chown opensearch:opensearch "$CONF_DIR/jvm.options.d/heap.options"
}

tune_host() {
  echo "vm.max_map_count=262144" >/etc/sysctl.d/99-opensearch.conf
  sysctl -q -p /etc/sysctl.d/99-opensearch.conf
  swapoff -a || true
  mkdir -p /etc/systemd/system/opensearch.service.d
  printf '[Service]\nLimitMEMLOCK=infinity\nLimitNOFILE=65536\n' >/etc/systemd/system/opensearch.service.d/override.conf
}

install_iq_user_unit() {
  cat >/etc/systemd/system/opensearch-iq-user.service <<UNIT
[Unit]
Description=Create or update the OpenSearch user IQ Server signs in as
After=opensearch.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/opensearch-node.sh iq-user
TimeoutStartSec=45min

[Install]
WantedBy=multi-user.target
UNIT
  systemctl daemon-reload
  systemctl enable opensearch-iq-user.service
  systemctl start --no-block opensearch-iq-user.service
}

setup() {
  log "setting up $OS_NODE_NAME, roles $OS_NODE_ROLES, zone $OS_NODE_ZONE, heap ${OS_HEAP_MB}m"
  if [ "$OS_HAS_DATA" = "true" ]; then
    mount_data_disk
  else
    mkdir -p "$DATA_DIR"
  fi
  local admin_password
  admin_password=$(read_secret "$OS_SECRET_ADMIN_PASSWORD")
  install_opensearch "$admin_password"
  write_internal_users "$admin_password"
  unset admin_password
  chown -R opensearch:opensearch "$DATA_DIR"
  tune_host
  install_certificates
  write_config
  systemctl daemon-reload
  systemctl enable opensearch
  systemctl restart opensearch
  local attempt
  for attempt in $(seq 1 60); do
    systemctl is-active --quiet opensearch && break
    sleep 5
  done
  systemctl is-active --quiet opensearch || {
    log "REFUSING: opensearch did not start"
    return 1
  }
  if [ "$OS_BOOTSTRAP_IQ_USER" = "true" ]; then
    install_iq_user_unit
  fi
  log "NODE_READY $OS_NODE_NAME"
}

# Escapes a value for a curl config file string.
curl_quote() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

iq_user() {
  local url code attempt body
  # Not local: the EXIT trap runs after this function returns.
  work=$(mktemp -d /run/opensearch-iq-user.XXXXXX)
  chmod 700 "$work"
  trap 'rm -rf "$work"' EXIT
  url="https://$OS_NODE_IP:9200"

  read_secret "$OS_SECRET_ADMIN_PASSWORD" >"$work/admin-password"
  read_secret "$OS_SECRET_IQ_PASSWORD" >"$work/iq-password"
  printf 'user = "admin:%s"\n' "$(curl_quote "$(cat "$work/admin-password")")" >"$work/admin.cfg"
  printf 'user = "%s:%s"\n' "$(curl_quote "$OS_IQ_USERNAME")" "$(curl_quote "$(cat "$work/iq-password")")" >"$work/iq.cfg"
  python3 - "$work/iq-password" "$work/user.json" <<'PY'
import json, sys
password = open(sys.argv[1]).read()
json.dump({"password": password, "backend_roles": ["iq_index_manager"],
           "description": "The user Sonatype IQ Server signs in as"}, open(sys.argv[2], "w"))
PY
  chmod 600 "$work"/*

  local api=(curl -s --cacert "$CONF_DIR/root-ca.pem" -K "$work/admin.cfg")
  local secadmin_run=false
  for attempt in $(seq 1 180); do
    code=$("${api[@]}" -o "$work/health" -w '%{http_code}' "$url/_cluster/health?wait_for_status=yellow&timeout=10s" || true)
    [ "$code" = "200" ] && break
    body=$(cat "$work/health" 2>/dev/null || true)
    # The security index is normally created from the files on first start. If the cluster formed
    # without it, apply the files once with the admin certificate. Nothing has been created through
    # the REST API yet in that state, so the files overwrite nothing.
    if [ "$secadmin_run" = "false" ] && [ "$attempt" -ge 30 ] && [ -s "$CONF_DIR/admin.pem" ] &&
      printf '%s' "$body" | grep -qi "not initialized"; then
      log "security index not initialized, applying the security configuration once"
      OPENSEARCH_JAVA_HOME=/usr/share/opensearch/jdk bash /usr/share/opensearch/plugins/opensearch-security/tools/securityadmin.sh \
        -cd "$CONF_DIR/opensearch-security" -icl -nhnv -h "$OS_NODE_IP" \
        -cacert "$CONF_DIR/root-ca.pem" -cert "$CONF_DIR/admin.pem" -key "$CONF_DIR/admin-key.pem" || true
      secadmin_run=true
    fi
    log "cluster not answering yet (HTTP $code), attempt $attempt"
    sleep 10
  done
  [ "$code" = "200" ] || {
    log "REFUSING: cluster health never answered 200"
    return 1
  }

  local put=("${api[@]}" -o /dev/null -w '%{http_code}' -X PUT -H 'Content-Type: application/json')

  # IQ Server creates the Advanced Search index with no replica setting, so it takes the cluster
  # default of 1, which one data node cannot place. Only the persistent cluster setting changes
  # that default; the same key in opensearch.yml has no effect.
  if [ "$OS_SINGLE_NODE" = "true" ]; then
    code=$("${put[@]}" "$url/_cluster/settings" -d '{"persistent":{"cluster.default_number_of_replicas":0}}')
    log "cluster.default_number_of_replicas 0: HTTP $code"
    [ "$code" = "200" ] || return 1
  fi

  code=$("${put[@]}" "$url/_plugins/_security/api/roles/iq_index_manager" \
    -d '{"cluster_permissions":["cluster_composite_ops","cluster_monitor","cluster:monitor/*","indices:data/read/scroll*","cluster:admin/opensearch/ql/datasources/read"],"index_permissions":[{"index_patterns":["*"],"allowed_actions":["indices_all"]}]}')
  log "role iq_index_manager: HTTP $code"
  case "$code" in 200 | 201) ;; *) return 1 ;; esac

  code=$("${put[@]}" "$url/_plugins/_security/api/internalusers/$OS_IQ_USERNAME" --data "@$work/user.json")
  log "user $OS_IQ_USERNAME: HTTP $code"
  case "$code" in 200 | 201) ;; *) return 1 ;; esac

  python3 -c 'import json, sys; print(json.dumps({"backend_roles": ["iq_index_manager"], "users": [sys.argv[1]]}))' \
    "$OS_IQ_USERNAME" >"$work/mapping.json"
  code=$("${put[@]}" "$url/_plugins/_security/api/rolesmapping/iq_index_manager" --data "@$work/mapping.json")
  log "role mapping iq_index_manager: HTTP $code"
  case "$code" in 200 | 201) ;; *) return 1 ;; esac

  code=$(curl -s --cacert "$CONF_DIR/root-ca.pem" -K "$work/iq.cfg" -o /dev/null -w '%{http_code}' "$url/_cluster/health")
  log "$OS_IQ_USERNAME reads cluster health: HTTP $code"
  [ "$code" = "200" ] || return 1
  log "IQ_USER_READY $OS_IQ_USERNAME"
}

case "${1:-}" in
  setup) setup 2>&1 | tee -a /var/log/opensearch-node-setup.log ;;
  iq-user) iq_user ;;
  *)
    echo "usage: $0 setup|iq-user" >&2
    exit 2
    ;;
esac
