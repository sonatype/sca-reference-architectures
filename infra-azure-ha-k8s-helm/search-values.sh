#!/bin/bash

# Reads the search settings out of terraform.tfvars and writes the search:
# block into a Helm values file. Sourced by both helm-install.sh and
# helm-upgrade.sh, so an upgrade cannot rebuild the values file without the
# block and silently put IQ Server back on Lucene.

# Reads one scalar from terraform.tfvars. Terraform accepts a quoted and an
# unquoted form for every type, and allows a trailing # comment on either, so
# neither cut -d'"' nor tr -d ' ' reads both: the first turns
# `opensearch_port = 9200 # prod` into nothing useful and the second turns it
# into 9200#prod, while `opensearch_use_tls = "false"` reaches a test for the
# string false carrying its quotes.
#
# A quoted value is taken up to its closing quote, so a # inside it is part of
# the value rather than a comment. HCL's two escapes inside a quoted string,
# \" and \\, are then undone, which is what lets a password hold a quote or a
# backslash. An unquoted value has any trailing comment and whitespace removed.
tfvar() {
    local key="$1" file="${2:-terraform.tfvars}" raw

    [[ -f "$file" ]] || return 0

    # The quoted form. The pattern consumes an escape pair or any character
    # that is neither a quote nor a backslash, so it stops at the real closing
    # quote and ignores everything after it.
    raw=$(sed -n -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"((\\\\.|[^\"\\\\])*)\".*\$/\1/p" "$file" | head -n 1)

    if [[ -n "$raw" ]]; then
        # Undo HCL's \" and \\ in one left-to-right pass, so a \\" in the file
        # is a backslash followed by a quote rather than an escaped quote.
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

    # The unquoted form, and an empty quoted value, which the pattern above
    # cannot tell apart from no match.
    sed -n -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*(.*)\$/\1/p" "$file" \
        | head -n 1 \
        | sed -E -e 's/[[:space:]]+#.*$//' -e 's/^#.*$//' \
                 -e 's/^[[:space:]]+//' -e 's/[[:space:]]+$//' \
                 -e 's/^""$//'
}

# Loads every search setting into the environment, with the same defaults the
# matching Terraform variables declare.
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
    OPENSEARCH_INDEX_REPLICAS=${OPENSEARCH_INDEX_REPLICAS:-0}
}

# Appends the search: block to the values file named in $1, under
# iq_server.config. Returns 0 and writes nothing when the engine is Lucene.
#
# The password never passes through a sed pattern, an awk -v assignment or a
# template, so no character in it can change the file's structure. It is
# written as a single-quoted YAML scalar, which is literal: a |, &, \ or # is
# only that character. The one character YAML gives meaning to inside single
# quotes is ' itself, which doubles, and that doubling is the only
# substitution, with a fixed pattern, a fixed replacement, and the value
# arriving on standard input rather than as part of the command.
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

    # The block is read from a file descriptor rather than passed to awk as a
    # -v assignment, because awk interprets a backslash escape in -v.
    {
        printf '    search:\n'
        printf '      type: http\n'
        printf '      mode: OPENSEARCH\n'
        printf "      uri: '%s'\n" "$uri"
        printf "      username: '%s'\n" "$user"
        printf "      password: '%s'\n" "$pass"
        printf '      nexusOneIndexReplicas: %s\n' "$OPENSEARCH_INDEX_REPLICAS"
    } > "${values_file}.searchblock"

    # awk rather than sed, because appending a line is spelled differently by
    # BSD and GNU sed and this script runs on both.
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
