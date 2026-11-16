#!/bin/bash

# Reads the search settings from terraform.tfvars and writes the search: block into a
# Helm values file. Sourced by helm-install.sh and helm-upgrade.sh.

# Reads one scalar from terraform.tfvars, quoted or unquoted, with or without a trailing
# comment. A quoted value runs to its closing quote, so a # inside it is kept, and HCL's
# \" and \\ escapes are undone. An unquoted value loses its trailing comment.
tfvar() {
    local key="$1" file="${2:-terraform.tfvars}" raw

    [[ -f "$file" ]] || return 0

    # Quoted form: escape pairs or any character but a quote or backslash, up to the
    # closing quote.
    raw=$(sed -n -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"((\\\\.|[^\"\\\\])*)\".*\$/\1/p" "$file" | head -n 1)

    if [[ -n "$raw" ]]; then
        # One left-to-right pass, so \\" is a backslash then a quote.
        printf '%s' "$raw" | awk '{
            out = ""
            for (i = 1; i <= length($0); i++) {
                c = substr($0, i, 1)
                if (c == "\\" && i < length($0)) {
                    n = substr($0, i + 1, 1)
                    if (n == "\"" || n == "\\") { out = out n; i++; continue }
                }
                out = out c
            }
            printf "%s", out
        }'
        return 0
    fi

    # Unquoted form, and an empty quoted value, which the pattern above cannot match.
    sed -n -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*(.*)\$/\1/p" "$file" \
        | head -n 1 \
        | sed -E -e 's/[[:space:]]+#.*$//' -e 's/^#.*$//' \
                 -e 's/^[[:space:]]+//' -e 's/[[:space:]]+$//' \
                 -e 's/^""$//'
}

# Loads every search setting, with the defaults the Terraform variables declare.
load_search_vars() {
    SEARCH_ENGINE=$(tfvar search_engine)
    SEARCH_ENGINE=${SEARCH_ENGINE:-lucene}
    OPENSEARCH_ENDPOINT=$(tfvar opensearch_endpoint)
    OPENSEARCH_USERNAME=$(tfvar opensearch_username)
    OPENSEARCH_PASSWORD=$(tfvar opensearch_password)
    OPENSEARCH_PORT=$(tfvar opensearch_port)
    OPENSEARCH_PORT=${OPENSEARCH_PORT:-9200}
    OPENSEARCH_USE_TLS=$(tfvar opensearch_use_tls)
    OPENSEARCH_USE_TLS=${OPENSEARCH_USE_TLS:-true}
    OPENSEARCH_INDEX_REPLICAS=$(tfvar opensearch_index_replicas)
    OPENSEARCH_INDEX_REPLICAS=${OPENSEARCH_INDEX_REPLICAS:-1}
}

# Appends the search: block under iq_server.config to the file named in $1, or nothing
# for Lucene. Credentials are single-quoted YAML scalars with ' doubled.
write_search_block() {
    local values_file="$1"
    local anchor='    clusterDirectory: "/sonatype-work/clm-cluster"'
    local scheme uri user pass

    if [[ "$SEARCH_ENGINE" != "opensearch" ]]; then
        return 0
    fi

    if [[ -z "$OPENSEARCH_ENDPOINT" || -z "$OPENSEARCH_USERNAME" || -z "$OPENSEARCH_PASSWORD" ]]; then
        echo "Error: search_engine is \"opensearch\" but opensearch_endpoint, opensearch_username or opensearch_password is missing from terraform.tfvars" >&2
        return 1
    fi

    if [[ "$OPENSEARCH_USE_TLS" == "false" ]]; then
        scheme="http"
    else
        scheme="https"
    fi

    if [[ "$(grep -c "^${anchor}$" "$values_file")" != "1" ]]; then
        echo "Error: expected exactly one clusterDirectory line under iq_server.config in $values_file" >&2
        return 1
    fi

    if grep -q '^    search:$' "$values_file"; then
        echo "Error: $values_file already carries a search: block" >&2
        return 1
    fi

    uri="$scheme://$OPENSEARCH_ENDPOINT:$OPENSEARCH_PORT"
    user=$(printf '%s' "$OPENSEARCH_USERNAME" | sed "s/'/''/g")
    pass=$(printf '%s' "$OPENSEARCH_PASSWORD" | sed "s/'/''/g")

    # Read from a file descriptor, since awk interprets backslash escapes in -v.
    {
        printf '    search:\n'
        printf '      type: http\n'
        printf '      mode: OPENSEARCH\n'
        printf "      uri: '%s'\n" "$uri"
        printf "      username: '%s'\n" "$user"
        printf "      password: '%s'\n" "$pass"
        printf '    nexusOne:\n'
        printf '      connection:\n'
        printf '        type: http\n'
        printf '        mode: OPENSEARCH\n'
        printf "        uri: '%s'\n" "$uri"
        printf "        username: '%s'\n" "$user"
        printf "        password: '%s'\n" "$pass"
        printf '        nexusOneIndexReplicas: %s\n' "$OPENSEARCH_INDEX_REPLICAS"
    } > "${values_file}.searchblock"

    # awk, since BSD and GNU sed spell appending a line differently.
    awk -v anchor="$anchor" -v blockfile="${values_file}.searchblock" '
        { print }
        $0 == anchor {
            while ((getline line < blockfile) > 0) { print line }
            close(blockfile)
        }
    ' "$values_file" > "${values_file}.search" \
        && mv "${values_file}.search" "$values_file"

    rm -f "${values_file}.searchblock" "${values_file}.search"

    if ! grep -q '^    search:$' "$values_file"; then
        echo "Error: could not write the search: block into $values_file" >&2
        return 1
    fi

    SEARCH_URI="$uri"
    return 0
}
