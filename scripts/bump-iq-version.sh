#!/usr/bin/env bash
#
# Sets the IQ Server release that every architecture in this repository deploys.
#
# Each architecture pins its version in one place, the default of one variable in its own
# variables.tf, so a root copied out of this repository keeps working on its own:
#
#   infra-aws, infra-aws-ha, infra-azure, infra-azure-ha, infra-gcp, infra-gcp-ha
#       iq_docker_image = "sonatype/nexus-iq-server:<iq-version>"
#   infra-aws-ha-k8s-helm, infra-azure-ha-k8s-helm, infra-gcp-ha-k8s-helm
#       helm_chart_version = "<chart-version>", the nexus-iq-server-ha chart, which sets the image
#
# The chart version is worked out from the IQ Server version the same way Sonatype publishes
# the chart: IQ Server 1.209.2 ships as chart 209.2.0. Before changing anything, the script
# checks that the image is on Docker Hub and that the chart is published with that IQ Server
# version. Running it again with the same version changes nothing.
#
# Usage: scripts/bump-iq-version.sh <iq-version> [--chart-version <version>] [--skip-release-check]
#   --chart-version       use this chart version instead of the one worked out from <iq-version>
#   --skip-release-check  do not check Docker Hub and the Helm repository, for testing only

set -euo pipefail

usage() {
    sed -n '/^# Usage:/,/^$/s/^# \{0,1\}//p' "$0"
    exit "${1:-1}"
}

IQ_VERSION=""
CHART_VERSION=""
CHECK_RELEASE=yes
while [[ $# -gt 0 ]]; do
    case "$1" in
        --chart-version)
            [[ $# -ge 2 ]] || usage
            CHART_VERSION="$2"
            shift 2
            ;;
        --skip-release-check)
            CHECK_RELEASE=no
            shift
            ;;
        -h|--help)
            usage 0
            ;;
        -*)
            echo "Error: unknown option $1" >&2
            usage
            ;;
        *)
            [[ -z "$IQ_VERSION" ]] || usage
            IQ_VERSION="$1"
            shift
            ;;
    esac
done

if [[ ! "$IQ_VERSION" =~ ^1\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "Error: the IQ Server version must look like 1.209.2, got '${IQ_VERSION}'" >&2
    exit 1
fi
CHART_VERSION="${CHART_VERSION:-${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.0}"
if [[ ! "$CHART_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: the chart version must look like 209.2.0, got '${CHART_VERSION}'" >&2
    exit 1
fi
IMAGE="sonatype/nexus-iq-server:${IQ_VERSION}"
CHART=nexus-iq-server-ha

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

if [[ "$CHECK_RELEASE" == yes ]]; then
    if ! curl -fsS -o /dev/null "https://hub.docker.com/v2/repositories/sonatype/nexus-iq-server/tags/${IQ_VERSION}"; then
        echo "Error: ${IMAGE} is not on Docker Hub" >&2
        exit 1
    fi
    if ! curl -fsS -o "$WORK_DIR/index.yaml" https://sonatype.github.io/helm3-charts/index.yaml; then
        echo "Error: could not read the Sonatype Helm repository index" >&2
        exit 1
    fi
    CHART_APP_VERSION=$(awk -v chart="$CHART" -v want="$CHART_VERSION" '
        $0 == "  " chart ":"          { inchart = 1; next }
        inchart && /^  [^ -]/         { inchart = 0 }
        !inchart                      { next }
        /^  - /                       { app = ""; ver = "" }
        /^    appVersion:/            { app = $2 }
        /^    version:/               { ver = $2 }
        ver == want && app != ""      { gsub(/"/, "", app); print app; exit }' "$WORK_DIR/index.yaml")
    if [[ -z "$CHART_APP_VERSION" ]]; then
        echo "Error: chart ${CHART} ${CHART_VERSION} is not in the Sonatype Helm repository" >&2
        exit 1
    fi
    if [[ "$CHART_APP_VERSION" != "$IQ_VERSION" ]]; then
        echo "Error: chart ${CHART} ${CHART_VERSION} carries IQ Server ${CHART_APP_VERSION}, not ${IQ_VERSION}" >&2
        exit 1
    fi
fi

# Writes the variable's default with a new value to stdout. Exits 3 unless the variable's
# block holds exactly one default line, and 4 if an iq_docker_image default is not the
# Sonatype image, so a file that has drifted from the expected shape is never half-edited.
set_default() {
    local file="$1" name="$2" value="$3" endnl=0
    # printf rather than print, so the last line keeps the ending it had, newline or not.
    [[ -z "$(tail -c 1 "$file")" ]] && endnl=1
    awk -v name="$name" -v value="$value" -v endnl="$endnl" '
        index($0, "variable \"" name "\"") == 1      { inblock = 1 }
        inblock && /^[[:space:]]*default[[:space:]]*=/ {
            if (name == "iq_docker_image" && $0 !~ /"sonatype\/nexus-iq-server:[^"]*"/) { bad = 1 }
            if (sub(/"[^"]*"/, "\"" value "\"")) { n++ }
        }
        inblock && /^}/                             { inblock = 0 }
                                                    { printf "%s%s", sep, $0; sep = "\n" }
        END {
            if (endnl && NR > 0) printf "\n"
            if (bad) exit 4
            if (n != 1) exit 3
        }' "$file"
}

ROOTS=()
NEW_FILES=()
for vars in "$REPO_ROOT"/infra-*/variables.tf; do
    root=$(basename "$(dirname "$vars")")
    if grep -q '^variable "helm_chart_version"' "$vars"; then
        name=helm_chart_version
        value="$CHART_VERSION"
    elif grep -q '^variable "iq_docker_image"' "$vars"; then
        name=iq_docker_image
        value="$IMAGE"
    else
        echo "Error: ${root}/variables.tf has neither iq_docker_image nor helm_chart_version" >&2
        exit 1
    fi
    out="$WORK_DIR/${root}.variables.tf"
    if ! set_default "$vars" "$name" "$value" >"$out"; then
        echo "Error: could not find exactly one default for ${name} in ${root}/variables.tf" >&2
        exit 1
    fi
    ROOTS+=("$root")
    NEW_FILES+=("$out")
done

if [[ ${#ROOTS[@]} -eq 0 ]]; then
    echo "Error: no infra-*/variables.tf under ${REPO_ROOT}" >&2
    exit 1
fi

# Every file is checked before any is written.
changed=0
for i in "${!ROOTS[@]}"; do
    target="$REPO_ROOT/${ROOTS[$i]}/variables.tf"
    if cmp -s "${NEW_FILES[$i]}" "$target"; then
        echo "unchanged ${ROOTS[$i]}"
    else
        cat "${NEW_FILES[$i]}" >"$target"
        echo "updated   ${ROOTS[$i]}"
        changed=$((changed + 1))
    fi
done
echo "IQ Server ${IQ_VERSION}, chart ${CHART} ${CHART_VERSION}: ${changed} of ${#ROOTS[@]} architectures changed"
