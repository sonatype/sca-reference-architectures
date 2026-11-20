#!/usr/bin/env bash
#
# Guided deploy for the nine reference architectures.
#
# Asks for the cloud, the architecture, the size, the search backend and every
# CHANGE_ME value in the chosen root's terraform.tfvars.example, writes that root's
# terraform.tfvars from the size's values in <root>/examples/<size>.tfvars, then
# runs the root's own scripts: terraform init, plan, apply, and helm-install.sh on
# the Kubernetes roots, which gets <root>/examples/<size>.helm-values.yaml as an
# extra values file. The same answers can come from flags or an answers file.
#
# Runs on the bash 3.2 that macOS ships, and on Linux. Run ./deploy.sh --help.

set -o pipefail

REPO_DIR=$(cd "$(dirname "$0")" && pwd)
PROG=deploy.sh

CLOUD=""
ARCH=""
SIZE=""
SEARCH=""
ANSWERS_FILE=""
AWS_PROFILE_OPT=""
LICENSE_FILE=""
YES=false
PLAN_ONLY=false
DRY_RUN=false
DESTROY=false
FORCE=false
NON_INTERACTIVE=false

WORK=$(mktemp -d "${TMPDIR:-/tmp}/deploy-sh.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT
SETS="$WORK/sets"         # key<TAB>value from --set and the answers file
ANSWERS="$WORK/answers"   # placeholder path<TAB>value
: > "$SETS"
: > "$ANSWERS"
TAB=$(printf '\t')

die() {
    printf '%s: %s\n' "$PROG" "$*" >&2
    exit 1
}

say() {
    printf '%s\n' "$*"
}

usage() {
    cat <<'USAGE'
Usage: ./deploy.sh [options]

Deploys one of the nine reference architectures. With no options it asks every
question. Answers given as options or in an answers file are not asked again.

Selection:
  --cloud aws|azure|gcp
  --architecture single|ha|ha-k8s
  --size xs|s|m|l|xl          only the sizes the architecture publishes
  --search-engine opensearch|builtin

Values:
  --set key=value             a value for terraform.tfvars, repeatable. A key
                              holding CHANGE_ME in terraform.tfvars.example is
                              answered this way; a map entry is map.key, for
                              example common_tags.owner. Any other variable the
                              root declares may be set too.
  --answers-file FILE         key=value lines, the same keys as --set plus cloud,
                              architecture, size, search_engine, aws_profile and
                              license_file. Lines starting with # are skipped.
  --aws-profile NAME          exported as AWS_PROFILE for the root's scripts
  --license-file FILE         IQ Server license file, required. Written into
                              terraform.tfvars as iq_license_file, so every IQ
                              Server node installs it on its first start, and
                              asked for when not given. iq-post-deploy.sh
                              installs it again only if IQ Server has none.

Mode:
  --yes, -y                   no confirmation prompt
  --plan-only                 write terraform.tfvars, run init and the plan, stop
  --dry-run                   print the terraform.tfvars and the commands, write
                              nothing and make no cloud call
  --destroy                   remove the deployment: helm-uninstall.sh first on the
                              Kubernetes roots, then the root's destroy script
  --force                     replace an existing terraform.tfvars (the old one is
                              kept as terraform.tfvars.<time>.bak); with --destroy
                              on GCP, also lets the destroy script turn off
                              deletion protection
  --non-interactive           never prompt; fail if an answer is missing
  -h, --help

An answers file, or input that is not a terminal, also means no prompts: a
missing answer then stops the script with the list of what is missing.

Each run that changes anything logs to deploy-<date>-<time>.log in the root.
USAGE
}

lower() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

# set_put KEY VALUE: one value per key, the last one wins.
set_put() {
    local f="$1" k="$2" v="$3"
    awk -F'\t' -v k="$k" '$1 != k' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    printf '%s\t%s\n' "$k" "$v" >> "$f"
}

# set_get FILE KEY: prints the value, fails when the key is absent.
set_get() {
    awk -F'\t' -v k="$2" '$1 == k { v = substr($0, length(k) + 2); f = 1 } END { if (f) print v; exit !f }' "$1"
}

set_has() {
    awk -F'\t' -v k="$2" '$1 == k { f = 1 } END { exit !f }' "$1"
}

# Set once in main, because stdin is a file inside the loops that prompt.
INTERACTIVE=false

can_prompt() {
    [[ "$INTERACTIVE" == true ]]
}

need_value() {
    [[ $# -ge 2 && -n "$2" ]] || die "$1 needs a value"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --cloud) need_value "$@"; CLOUD=$(lower "$2"); shift 2 ;;
            --cloud=*) CLOUD=$(lower "${1#*=}"); shift ;;
            --architecture|--arch) need_value "$@"; ARCH=$(lower "$2"); shift 2 ;;
            --architecture=*|--arch=*) ARCH=$(lower "${1#*=}"); shift ;;
            --size) need_value "$@"; SIZE=$(lower "$2"); shift 2 ;;
            --size=*) SIZE=$(lower "${1#*=}"); shift ;;
            --search-engine) need_value "$@"; SEARCH=$(lower "$2"); shift 2 ;;
            --search-engine=*) SEARCH=$(lower "${1#*=}"); shift ;;
            --set) need_value "$@"; add_set "$2" cli; shift 2 ;;
            --set=*) add_set "${1#*=}" cli; shift ;;
            --answers-file) need_value "$@"; ANSWERS_FILE="$2"; shift 2 ;;
            --answers-file=*) ANSWERS_FILE="${1#*=}"; shift ;;
            --aws-profile) need_value "$@"; AWS_PROFILE_OPT="$2"; shift 2 ;;
            --aws-profile=*) AWS_PROFILE_OPT="${1#*=}"; shift ;;
            --license-file) need_value "$@"; LICENSE_FILE="$2"; shift 2 ;;
            --license-file=*) LICENSE_FILE="${1#*=}"; shift ;;
            -y|--yes) YES=true; shift ;;
            --plan-only) PLAN_ONLY=true; shift ;;
            --dry-run) DRY_RUN=true; shift ;;
            --destroy) DESTROY=true; shift ;;
            --force) FORCE=true; shift ;;
            --non-interactive) NON_INTERACTIVE=true; shift ;;
            -h|--help) usage; exit 0 ;;
            *) die "unknown option: $1 (see --help)" ;;
        esac
    done
}

# add_set "key=value" cli|file. A value from the command line beats one from the file.
add_set() {
    local pair="$1" src="$2" k v
    [[ "$pair" == *=* ]] || die "--set needs key=value, got: $pair"
    k="${pair%%=*}"
    v="${pair#*=}"
    k=$(printf '%s' "$k" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [[ "$k" =~ ^[A-Za-z_][A-Za-z0-9_-]*(\.[A-Za-z0-9_-]+)?$ ]] || die "not a valid key: $k"
    if [[ "$src" == file ]] && set_has "$SETS" "$k"; then
        return 0
    fi
    set_put "$SETS" "$k" "$v"
}

load_answers_file() {
    [[ -n "$ANSWERS_FILE" ]] || return 0
    [[ -f "$ANSWERS_FILE" ]] || die "answers file not found: $ANSWERS_FILE"
    local line k v n=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        n=$((n + 1))
        line=$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        [[ -z "$line" || "$line" == \#* ]] && continue
        [[ "$line" == *=* ]] || die "$ANSWERS_FILE line $n is not key=value"
        k="${line%%=*}"
        v="${line#*=}"
        k=$(printf '%s' "$k" | sed 's/[[:space:]]*$//')
        v=$(printf '%s' "$v" | sed 's/^[[:space:]]*//')
        # One pair of surrounding quotes is taken off, so key="a b" works.
        if [[ "$v" =~ ^\"(.*)\"$ || "$v" =~ ^\'(.*)\'$ ]]; then
            v="${BASH_REMATCH[1]}"
        fi
        case "$k" in
            cloud) [[ -n "$CLOUD" ]] || CLOUD=$(lower "$v") ;;
            architecture) [[ -n "$ARCH" ]] || ARCH=$(lower "$v") ;;
            size) [[ -n "$SIZE" ]] || SIZE=$(lower "$v") ;;
            search_engine) [[ -n "$SEARCH" ]] || SEARCH=$(lower "$v") ;;
            aws_profile) [[ -n "$AWS_PROFILE_OPT" ]] || AWS_PROFILE_OPT="$v" ;;
            license_file) [[ -n "$LICENSE_FILE" ]] || LICENSE_FILE="$v" ;;
            *) add_set "$k=$v" file ;;
        esac
    done < "$ANSWERS_FILE"
}

# choose VAR "question" option...: a numbered menu, or fail when prompting is off.
choose() {
    local var="$1" question="$2" flag="$3"
    shift 3
    local options=("$@") i reply
    if ! can_prompt; then
        die "no answer for $question: pass $flag (one of: ${options[*]})"
    fi
    while true; do
        say "" >&2
        say "$question" >&2
        for ((i = 0; i < ${#options[@]}; i++)); do
            printf '  %d) %s\n' $((i + 1)) "${options[$i]}" >&2
        done
        printf 'Choose 1-%d: ' "${#options[@]}" >&2
        IFS= read -r reply || die "no answer for $question"
        if [[ "$reply" =~ ^[0-9]+$ ]] && ((reply >= 1 && reply <= ${#options[@]})); then
            printf -v "$var" '%s' "${options[$((reply - 1))]}"
            return 0
        fi
        for ((i = 0; i < ${#options[@]}; i++)); do
            if [[ "$(lower "$reply")" == "${options[$i]}" ]]; then
                printf -v "$var" '%s' "${options[$i]}"
                return 0
            fi
        done
        say "Not one of the choices." >&2
    done
}

in_list() {
    local want="$1" x
    shift
    for x in "$@"; do
        [[ "$x" == "$want" ]] && return 0
    done
    return 1
}

# ---------------------------------------------------------------------------
# The nine roots and their scripts
# ---------------------------------------------------------------------------

root_dir_name() {
    case "$1-$2" in
        aws-single) echo infra-aws ;;
        aws-ha) echo infra-aws-ha ;;
        aws-ha-k8s) echo infra-aws-ha-k8s-helm ;;
        azure-single) echo infra-azure ;;
        azure-ha) echo infra-azure-ha ;;
        azure-ha-k8s) echo infra-azure-ha-k8s-helm ;;
        gcp-single) echo infra-gcp ;;
        gcp-ha) echo infra-gcp-ha ;;
        gcp-ha-k8s) echo infra-gcp-ha-k8s-helm ;;
        *) return 1 ;;
    esac
}

is_k8s() {
    [[ "$ARCH" == ha-k8s ]]
}

# The commands, as the strings printed by --dry-run and run from the root directory.
plan_cmd() {
    case "$ROOT_NAME" in
        infra-gcp) echo "bash ./gcp-plan.sh" ;;
        infra-gcp-ha) echo "bash ./gcp-ha-plan.sh" ;;
        *) echo "bash ./tf-plan.sh" ;;
    esac
}

# deploy.sh has already asked for confirmation, so the GCP scripts get theirs skipped.
apply_cmd() {
    case "$ROOT_NAME" in
        infra-gcp) echo "bash ./gcp-apply.sh --auto-approve" ;;
        infra-gcp-ha) echo "bash ./gcp-ha-apply.sh --auto-approve" ;;
        *) echo "bash ./tf-apply.sh" ;;
    esac
}

destroy_cmd() {
    local force=""
    [[ "$FORCE" == true ]] && force=" --force"
    case "$ROOT_NAME" in
        infra-gcp) echo "bash ./destroy.sh --yes$force" ;;
        infra-gcp-ha) echo "bash ./gcp-ha-destroy.sh --yes$force" ;;
        infra-aws*) echo "bash ./tf-destroy.sh --delete-opensearch-domain" ;;
        *) echo "bash ./tf-destroy.sh" ;;
    esac
}

# The GKE uninstall script asks two questions: remove the release, delete the namespace.
uninstall_cmd() {
    case "$ROOT_NAME" in
        infra-gcp-ha-k8s-helm) printf '%s\n' "printf 'yes\\nyes\\n' | bash ./helm-uninstall.sh" ;;
        *) echo "bash ./helm-uninstall.sh" ;;
    esac
}

# Sizes this root publishes: one examples/<size>.tfvars per size.
available_sizes() {
    local s
    for s in xs s m l xl; do
        [[ -f "$ROOT_DIR/examples/$s.tfvars" ]] && printf '%s\n' "$s"
    done | paste -sd ' ' -
}

# ---------------------------------------------------------------------------
# Reading the root's .tf files: the declared variable names and their simple validation rules
# ---------------------------------------------------------------------------

# Writes name<TAB>sensitive<TAB>min length<TAB>max length<TAB>allowed values.
parse_variables() {
    awk '
        function emit() {
            if (name != "") print name "\t" sens "\t" minl "\t" maxl "\t" en
        }
        FNR == 1 { emit(); name = "" }
        /^variable "/ {
            emit()
            name = $2
            gsub(/"/, "", name)
            sens = 0; minl = ""; maxl = ""; en = ""
            next
        }
        name != "" {
            line = $0
            if (line ~ /^[ \t]*sensitive[ \t]*=[ \t]*true/) sens = 1
            p = "length\\(var\\." name "\\)[ \t]*>=[ \t]*[0-9]+"
            if (match(line, p)) { s = substr(line, RSTART, RLENGTH); sub(/.*>=[ \t]*/, "", s); minl = s }
            p = "length\\(var\\." name "\\)[ \t]*<=[ \t]*[0-9]+"
            if (match(line, p)) { s = substr(line, RSTART, RLENGTH); sub(/.*<=[ \t]*/, "", s); maxl = s }
            p = "contains\\(\\[[^]]*\\],[ \t]*var\\." name "\\)"
            if (match(line, p)) {
                s = substr(line, RSTART, RLENGTH)
                sub(/^contains\(\[/, "", s)
                sub(/\],.*/, "", s)
                if (s ~ /^[ \t]*"/) { gsub(/[" \t]/, "", s); en = s }
            }
        }
        END { emit() }
    ' "$ROOT_DIR"/*.tf > "$WORK/vars.tsv"
}

var_declared() {
    awk -F'\t' -v k="$1" '$1 == k { f = 1 } END { exit !f }' "$WORK/vars.tsv"
}

# var_rule NAME FIELD: FIELD 2 sensitive, 3 min length, 4 max length, 5 allowed values.
var_rule() {
    awk -F'\t' -v k="$1" -v f="$2" '$1 == k { print $f }' "$WORK/vars.tsv"
}

# ---------------------------------------------------------------------------
# Editing terraform.tfvars text with awk. Every pass tracks nesting depth, so a
# key inside a map is read as map.key and a multi-line value is skipped whole.
# ---------------------------------------------------------------------------

AWK_LIB='
function strip(s) {
    gsub(/"([^"\\]|\\.)*"/, "\"\"", s)
    sub(/#.*/, "", s)
    return s
}
function delta(s,   o, c) {
    s = strip(s)
    o = gsub(/[{[]/, "&", s)
    c = gsub(/[]}]/, "&", s)
    return o - c
}
function keyof(s,   k) {
    if (match(s, /^[ \t]*"?[A-Za-z0-9_.-]+"?[ \t]*=/)) {
        k = substr(s, RSTART, RLENGTH)
        gsub(/[ \t"=]/, "", k)
        return k
    }
    return ""
}
function iscomment(s) {
    return s ~ /^[ \t]*#/
}
'

# overlay BASE OVERLAY HEADER: each "key = value" line in OVERLAY replaces that
# top-level setting in BASE, or is added at the end under HEADER when BASE has no
# live line for it.
overlay() {
    awk -v OVL="$2" -v HDR="$3" "$AWK_LIB"'
        BEGIN {
            n = 0
            while ((getline l < OVL) > 0) {
                if (iscomment(l)) continue
                k = keyof(l)
                if (k == "") continue
                if (!(k in val)) order[++n] = k
                val[k] = l
            }
        }
        {
            if (skip) { depth += delta($0); if (depth <= 0) { skip = 0; depth = 0 } ; next }
            if (iscomment($0)) { print; next }
            k = keyof($0)
            d = delta($0)
            if (depth == 0 && k != "" && (k in val)) {
                print val[k]
                done[k] = 1
                if (d > 0) { skip = 1; depth = d }
                next
            }
            depth += d
            print
        }
        END {
            first = 1
            for (i = 1; i <= n; i++) {
                k = order[i]
                if (k in done) continue
                if (first) { print ""; print HDR; first = 0 }
                print val[k]
            }
        }
    ' "$1"
}

# scan_placeholders FILE: one line per live CHANGE_ME: path, placeholder, hint.
scan_placeholders() {
    awk "$AWK_LIB"'
        {
            if (iscomment($0)) next
            k = keyof($0)
            if (depth == 0 && k != "") top = k
            path = (depth == 0) ? k : ((k != "") ? top "." k : top)
            if (index($0, "CHANGE_ME") && match($0, /"[^"]*CHANGE_ME[^"]*"/)) {
                ph = substr($0, RSTART + 1, RLENGTH - 2)
                rest = substr($0, RSTART + RLENGTH)
                hint = ""
                if (match(rest, /#.*/)) { hint = substr(rest, RSTART + 1); sub(/^[ \t]+/, "", hint) }
                if (!(path in seen)) print path "\t" ph "\t" hint
                seen[path] = 1
            }
            depth += delta($0)
        }
    ' "$1"
}

# fill_placeholders FILE ANSWERS: each answered CHANGE_ME string becomes the answer.
fill_placeholders() {
    awk -v ANS="$2" "$AWK_LIB"'
        function repl(s, a, b,   out, i) {
            out = ""
            while ((i = index(s, a)) > 0) { out = out substr(s, 1, i - 1) b; s = substr(s, i + length(a)) }
            return out s
        }
        BEGIN {
            while ((getline l < ANS) > 0) {
                t = index(l, "\t")
                if (t) ans[substr(l, 1, t - 1)] = substr(l, t + 1)
            }
        }
        {
            if (iscomment($0)) { print; next }
            k = keyof($0)
            if (depth == 0 && k != "") top = k
            path = (depth == 0) ? k : ((k != "") ? top "." k : top)
            line = $0
            if ((path in ans) && match(line, /"[^"]*CHANGE_ME[^"]*"/)) {
                v = repl(repl(ans[path], "${", "$${"), "%{", "%%{")
                line = substr(line, 1, RSTART - 1) "\"" v "\"" substr(line, RSTART + RLENGTH)
            }
            depth += delta($0)
            print line
        }
    ' "$1"
}

# mask FILE: secret values shown as ********, for the screen and the log.
mask() {
    awk "$AWK_LIB"'
        {
            if (iscomment($0)) { print; next }
            k = keyof($0)
            line = $0
            if (tolower(k) ~ /password|secret|token/ && match(line, /"[^"]*"/))
                line = substr(line, 1, RSTART - 1) "\"********\"" substr(line, RSTART + RLENGTH)
            print line
        }
    ' "$1"
}

# live_value FILE KEY: the right-hand side of a live top-level setting.
live_value() {
    awk -v K="$2" "$AWK_LIB"'
        {
            if (iscomment($0)) next
            k = keyof($0)
            if (depth == 0 && k == K) { v = $0; sub(/^[^=]*=[ \t]*/, "", v); print v; exit }
            depth += delta($0)
        }
    ' "$1"
}

# hcl_value KEY VALUE BASE: VALUE as HCL, quoted when the example holds a string there.
hcl_value() {
    local key="$1" value="$2" base="$3" current
    current=$(live_value "$base" "$key")
    if [[ "$value" =~ ^\" || "$value" =~ ^\[ || "$value" =~ ^\{ ]]; then
        printf '%s' "$value"
    elif [[ -n "$current" && "$current" != \"* ]]; then
        printf '%s' "$value"
    elif [[ -z "$current" && "$value" =~ ^(-?[0-9]+(\.[0-9]+)?|true|false|null)$ ]]; then
        printf '%s' "$value"
    else
        printf '"%s"' "$(printf '%s' "$value" | sed 's/\\/\\\\/g; s/"/\\"/g')"
    fi
}

# ---------------------------------------------------------------------------
# Helm values for the Kubernetes roots: examples/<size>.helm-values.yaml holds
# scalar settings by YAML path, each written into the root's helm-values.yaml.
# ---------------------------------------------------------------------------

AWK_YAML='
function yamlpath(line,   ind, k) {
    if (line ~ /^[ \t]*#/ || line ~ /^[ \t]*-/ || line ~ /^[ \t]*$/) return ""
    if (!match(line, /^ *[A-Za-z0-9_.-]+:/)) return ""
    ind = match(line, /[^ ]/) - 1
    k = line
    sub(/^ */, "", k)
    sub(/:.*/, "", k)
    while (sp > 0 && sind[sp] >= ind) sp--
    sp++
    sind[sp] = ind
    skey[sp] = k
    p = skey[1]
    for (i = 2; i <= sp; i++) p = p "." skey[i]
    return p
}
function yamlvalue(line,   v) {
    v = line
    sub(/^ *[A-Za-z0-9_.-]+:[ \t]*/, "", v)
    return v
}
'

# helm_patch VALUES SIZEFILE: prints VALUES with every scalar in SIZEFILE applied,
# and fails naming any path that VALUES does not have.
helm_patch() {
    awk -v SZ="$2" "$AWK_YAML"'
        BEGIN {
            sp = 0
            while ((getline l < SZ) > 0) {
                p = yamlpath(l)
                if (p == "") continue
                v = yamlvalue(l)
                if (v == "") continue
                want[p] = v
                order[++n] = p
            }
            sp = 0
        }
        {
            p = yamlpath($0)
            if (p != "" && (p in want)) {
                pre = $0
                sub(/:.*/, ":", pre)
                print pre " " want[p]
                found[p] = 1
                next
            }
            print
        }
        END {
            bad = 0
            for (i = 1; i <= n; i++) if (!(order[i] in found)) { print "missing path: " order[i] > "/dev/stderr"; bad = 1 }
            exit bad
        }
    ' "$1"
}

# ---------------------------------------------------------------------------
# Answers: prompting and validation
# ---------------------------------------------------------------------------

is_secret() {
    [[ "$(lower "${1##*.}")" =~ password|secret|token ]]
}

# validate PATH VALUE: prints why VALUE is refused, or nothing.
validate() {
    local path="$1" value="$2" name="${1%%.*}" minl maxl en
    if [[ -z "$value" ]]; then echo "is empty"; return; fi
    if [[ "$value" == *CHANGE_ME* ]]; then echo "still holds CHANGE_ME"; return; fi
    if [[ "$value" == *\"* || "$value" == *\\* ]]; then echo "may not contain a double quote or a backslash"; return; fi
    if [[ "$path" == "$name" ]]; then
        minl=$(var_rule "$name" 3)
        maxl=$(var_rule "$name" 4)
        en=$(var_rule "$name" 5)
    fi
    if is_secret "$path"; then
        if [[ "$(lower "$path")" == *password* ]] && [[ -z "$minl" || "$minl" -lt 12 ]]; then minl=12; fi
        if printf '%s' "$value" | LC_ALL=C grep -q '[^A-Za-z0-9!#%*+,.:;=?^_~-]'; then
            echo "may use only letters, digits and ! # % * + , - . : ; = ? ^ _ ~ (the database services refuse some other symbols, and the install scripts pass it through sed)"
            return
        fi
    fi
    if [[ -n "$minl" && ${#value} -lt $minl ]]; then echo "needs at least $minl characters"; return; fi
    if [[ -n "$maxl" && ${#value} -gt $maxl ]]; then echo "may have at most $maxl characters"; return; fi
    # shellcheck disable=SC2046
    if [[ -n "$en" ]] && ! in_list "$value" $(printf '%s' "$en" | tr ',' ' '); then
        echo "must be one of: $(printf '%s' "$en" | tr ',' ' ')"
        return
    fi
    case "$path" in
        *cidr*)
            if ! printf '%s' "$value" | grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}/[0-9]{1,2}$'; then
                echo "must be an address range such as 203.0.113.0/24"
            fi
            ;;
        gcp_project_id)
            if ! printf '%s' "$value" | grep -Eq '^[a-z][a-z0-9-]{4,28}[a-z0-9]$'; then
                echo "must be a GCP project ID: 6 to 30 lowercase letters, digits and hyphens"
            fi
            ;;
        iq_license_file)
            # shellcheck disable=SC2088
            case "$value" in "~/"*) value="$HOME/${value#\~/}" ;; esac
            [[ -f "$value" ]] || echo "names no file: $value"
            ;;
    esac
}

# ask_placeholder PATH PLACEHOLDER HINT: prompts until the answer passes validate.
ask_placeholder() {
    local path="$1" ph="$2" hint="$3" v v2 why label
    label="$path"
    [[ -n "$hint" ]] && label="$label ($hint)"
    while true; do
        if is_secret "$path"; then
            printf '%s: ' "$label" >&2
            IFS= read -rs v || die "no answer for $path"
            printf '\n' >&2
            printf 'Again, to confirm: ' >&2
            IFS= read -rs v2 || die "no answer for $path"
            printf '\n' >&2
            if [[ "$v" != "$v2" ]]; then say "The two entries differ." >&2; continue; fi
        else
            printf '%s, in place of %s: ' "$label" "$ph" >&2
            IFS= read -r v || die "no answer for $path"
        fi
        why=$(validate "$path" "$v")
        if [[ -z "$why" ]]; then
            set_put "$ANSWERS" "$path" "$v"
            return 0
        fi
        say "$path $why." >&2
    done
}

# ---------------------------------------------------------------------------
# Selection
# ---------------------------------------------------------------------------

select_root() {
    if [[ -z "$CLOUD" ]]; then choose CLOUD "Which cloud?" --cloud aws azure gcp; fi
    in_list "$CLOUD" aws azure gcp || die "unknown cloud: $CLOUD (aws, azure or gcp)"
    case "$ARCH" in k8s|kubernetes|ha-kubernetes) ARCH=ha-k8s ;; single-instance) ARCH=single ;; esac
    if [[ -z "$ARCH" ]]; then
        choose ARCH "Which architecture? single is one IQ Server node, ha is several behind a load balancer, ha-k8s runs IQ Server on Kubernetes with Helm" --architecture single ha ha-k8s
    fi
    in_list "$ARCH" single ha ha-k8s || die "unknown architecture: $ARCH (single, ha or ha-k8s)"
    ROOT_NAME=$(root_dir_name "$CLOUD" "$ARCH")
    ROOT_DIR="$REPO_DIR/$ROOT_NAME"
    [[ -f "$ROOT_DIR/terraform.tfvars.example" ]] || die "$ROOT_NAME/terraform.tfvars.example not found"
    parse_variables
}

select_size_and_search() {
    local sizes enums
    sizes=$(available_sizes)
    [[ -n "$sizes" ]] || die "$ROOT_NAME/examples has no size files"
    if [[ -z "$SIZE" ]]; then
        # shellcheck disable=SC2086
        choose SIZE "Which size? $ROOT_NAME publishes: $sizes" --size $sizes
    fi
    # shellcheck disable=SC2086
    in_list "$SIZE" $sizes || die "$ROOT_NAME publishes sizes $sizes, not $SIZE"
    enums=$(var_rule search_engine 5 | tr ',' ' ')
    [[ -n "$enums" ]] || enums="opensearch builtin"
    # opensearch first, then the others in the order the variable lists them.
    # shellcheck disable=SC2086
    if in_list opensearch $enums; then
        enums="opensearch $(printf '%s\n' $enums | grep -vx opensearch | paste -sd ' ' -)"
    fi
    if [[ -z "$SEARCH" ]]; then
        # shellcheck disable=SC2086
        choose SEARCH "Which search backend? opensearch creates an OpenSearch cluster for Advanced Search and the Nexus One index; builtin creates none, so Advanced Search uses IQ Server's built-in index and Nexus One (IQ Server 1.210 and later) can keep its index in IQ Server's PostgreSQL database" --search-engine $enums
    fi
    # shellcheck disable=SC2086
    in_list "$SEARCH" $enums || die "search engine must be one of: $enums"
}

# ---------------------------------------------------------------------------
# Building terraform.tfvars
# ---------------------------------------------------------------------------

build_tfvars() {
    local example="$ROOT_DIR/terraform.tfvars.example" sizefile="$ROOT_DIR/examples/$SIZE.tfvars"
    local k v line why missing="" upsize
    upsize=$(printf '%s' "$SIZE" | tr '[:lower:]' '[:upper:]')

    # Every setting in the size file must be one the root declares.
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# || ! "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*= ]] && continue
        k="${BASH_REMATCH[1]}"
        var_declared "$k" || die "$ROOT_NAME/examples/$SIZE.tfvars sets $k, which no $ROOT_NAME/*.tf file declares"
    done < "$sizefile"

    # Stage 1: the example with the size's settings and the search backend.
    { grep -v '^[[:space:]]*#' "$sizefile"; printf 'search_engine = "%s"\n' "$SEARCH"; } > "$WORK/ovl1"
    overlay "$example" "$WORK/ovl1" "# Size $upsize settings, from examples/$SIZE.tfvars" > "$WORK/stage1" || die "could not build terraform.tfvars"
    scan_placeholders "$WORK/stage1" > "$WORK/ph1"

    # Stage 2: --set values. A CHANGE_ME key is an answer; anything else replaces a setting.
    : > "$WORK/ovl2"
    while IFS="$TAB" read -r k v; do
        [[ -z "$k" ]] && continue
        if set_has "$WORK/ph1" "$k"; then
            why=$(validate "$k" "$v")
            [[ -z "$why" ]] || die "$k $why"
            set_put "$ANSWERS" "$k" "$v"
        elif [[ "$k" == *.* ]]; then
            die "$k is not a CHANGE_ME entry in $ROOT_NAME/terraform.tfvars.example, and only those map entries can be set"
        elif [[ "$k" == search_engine ]]; then
            die "set the search backend with --search-engine or search_engine in the answers file"
        else
            var_declared "$k" || die "$k is not a variable declared in $ROOT_NAME"
            if [[ ! "$v" =~ ^[\[\{\"] ]]; then
                why=$(validate "$k" "$v")
                [[ -z "$why" ]] || die "$k $why"
            fi
            printf '%s = %s\n' "$k" "$(hcl_value "$k" "$v" "$WORK/stage1")" >> "$WORK/ovl2"
        fi
    done < "$SETS"
    # --license-file, or license_file in the answers file, answers iq_license_file.
    if [[ -n "$LICENSE_FILE" ]] && set_has "$WORK/ph1" iq_license_file && ! set_has "$ANSWERS" iq_license_file; then
        set_put "$ANSWERS" iq_license_file "$LICENSE_FILE"
    fi
    overlay "$WORK/stage1" "$WORK/ovl2" "# Set with deploy.sh --set" > "$WORK/stage2" || die "could not build terraform.tfvars"
    scan_placeholders "$WORK/stage2" > "$WORK/ph2"

    # Stage 3: the remaining CHANGE_ME values, asked for or reported missing.
    while IFS="$TAB" read -r k v line; do
        [[ -z "$k" ]] && continue
        set_has "$ANSWERS" "$k" && continue
        if can_prompt; then
            ask_placeholder "$k" "$v" "$line" < /dev/tty
        else
            missing="$missing  --set $k=...\n"
        fi
    done < "$WORK/ph2"
    if [[ -n "$missing" ]]; then
        printf '%s: these CHANGE_ME values have no answer:\n' "$PROG" >&2
        printf '%b' "$missing" >&2
        exit 1
    fi
    # The license path as an absolute path, since Terraform reads it from the root directory,
    # and as LICENSE_FILE, so iq-post-deploy.sh can install it again if IQ Server has none.
    if set_has "$ANSWERS" iq_license_file; then
        LICENSE_FILE=$(set_get "$ANSWERS" iq_license_file)
        resolve_license
        set_put "$ANSWERS" iq_license_file "$LICENSE_FILE"
    fi
    fill_placeholders "$WORK/stage2" "$ANSWERS" > "$WORK/tfvars" || die "could not build terraform.tfvars"
    if [[ -n "$(scan_placeholders "$WORK/tfvars")" ]]; then
        die "terraform.tfvars would still hold CHANGE_ME: $(scan_placeholders "$WORK/tfvars" | cut -f1 | tr '\n' ' ')"
    fi
}

build_helm_values() {
    local sizefile="$ROOT_DIR/examples/$SIZE.helm-values.yaml"
    HELM_SIZE_FILE=""
    is_k8s || return 0
    [[ -f "$sizefile" ]] || return 0
    # Only a check: every setting the size file changes must exist in helm-values.yaml.
    # helm-install.sh gets the size file as an extra values file, so helm-values.yaml
    # itself is never edited.
    helm_patch "$ROOT_DIR/helm-values.yaml" "$sizefile" > "$WORK/helm-values.yaml" ||
        die "$ROOT_NAME/helm-values.yaml lacks a setting that examples/$SIZE.helm-values.yaml changes"
    HELM_SIZE_FILE="$sizefile"
}

# resolve_license: makes LICENSE_FILE absolute, since the root's scripts run from the root.
resolve_license() {
    [[ -n "$LICENSE_FILE" ]] || return 0
    # shellcheck disable=SC2088
    case "$LICENSE_FILE" in "~/"*) LICENSE_FILE="$HOME/${LICENSE_FILE#\~/}" ;; esac
    [[ -f "$LICENSE_FILE" ]] || die "license file not found: $LICENSE_FILE"
    LICENSE_FILE="$(cd "$(dirname "$LICENSE_FILE")" && pwd)/$(basename "$LICENSE_FILE")"
}

# ---------------------------------------------------------------------------
# Running the root's scripts
# ---------------------------------------------------------------------------

start_log() {
    LOG="$ROOT_DIR/deploy-$(date +%Y%m%d-%H%M%S).log"
    : > "$LOG" || die "cannot write $LOG"
    exec > >(tee -a "$LOG") 2>&1
    say "Log: $LOG"
}

# run_step COMMAND: runs it from the root directory, streaming its output.
# A plan script may run terraform plan -detailed-exitcode, which exits 2 when the
# plan has changes. That is the normal result before an apply, so on the plan step
# 2 means continue and only 1 or above 2 is a failure.
run_step() {
    local cmd="$1" rc f
    say ""
    say "==> $ROOT_NAME: $cmd"
    # Terraform state holds the admin password and the license, so the steps run under
    # umask 077 and any state already there is made private first.
    for f in "$ROOT_DIR"/terraform.tfstate*; do
        if [[ -e "$f" ]]; then chmod 600 "$f"; fi
    done
    if can_prompt; then
        (cd "$ROOT_DIR" && umask 077 && eval "$cmd") < /dev/tty
    else
        (cd "$ROOT_DIR" && umask 077 && eval "$cmd") < /dev/null
    fi
    rc=$?
    if [[ $rc -eq 2 && "$cmd" == "$(plan_cmd)" ]]; then
        say "$PROG: the plan has changes to apply (exit code 2), continuing."
        rc=0
    fi
    if [[ $rc -ne 0 ]]; then
        say ""
        say "$PROG: '$cmd' failed with exit code $rc in $ROOT_NAME. The log is $LOG."
        capacity_hint
        exit "$rc"
    fi
}

# capacity_hint: when the failure was the cloud having no capacity for a machine type in a
# zone, names the setting that moves the deployment to a zone or size that has it. The
# fallback changes where nodes run, so it is printed for a person to choose, not applied.
capacity_hint() {
    local sizes="" errlines="" alt="" node_alt="" os_alt="" tfvars="$ROOT_DIR/terraform.tfvars"
    [[ -n "${LOG:-}" && -f "$LOG" ]] || return 0
    if grep -q "ZONE_RESOURCE_POOL_EXHAUSTED\|does not have enough resources available to fulfill the request" "$LOG"; then
        say ""
        say "GCP has no stock of a machine type in a zone. Run again with --force and one of:"
        say "  --set 'opensearch_zones=[\"<zone with stock>\"]'   an OpenSearch zone that has the type, one zone is enough"
        say "  --set opensearch_data_instance_type=c4-standard-2   an x86 C4 type with as many vCPUs, if no zone has it"
        if [[ "$ROOT_NAME" != infra-gcp-ha-k8s-helm ]]; then
            say "  (with a C4 type also set opensearch_data_heap_gb to half its memory, 3 for c4-standard-2)"
        fi
        say "Creating a throwaway VM of the type in each zone shows which zones have it."
    elif grep -q "ZonalAllocationFailed\|SkuNotAvailable\|AllocationFailed" "$LOG"; then
        # Only the error's own lines, since the rest of the log names every size in terraform.tfvars.
        # The sizes Azure suggests instead are not the one that failed, so they are shown apart.
        errlines=$(grep "ZonalAllocationFailed\|SkuNotAvailable\|AllocationFailed\|Allocation failed" "$LOG")
        sizes=$(printf '%s\n' "$errlines" | sed "s/alternative sizes '[^']*'//g" | grep -o "Standard_[A-Za-z0-9_]*" | sort -u | paste -sd ' ' -)
        alt=$(printf '%s\n' "$errlines" | grep -o "alternative sizes '[^']*' ([^)]*)" | head -n 1)
        # The IQ Server node fallback is the deployed size's own VM size from the AMD series, which has
        # the same vCPUs and memory: Standard_D16ps_v6 becomes Standard_D16as_v6. The OpenSearch nodes
        # run Arm only, so their fallback is the previous Arm series: Standard_D2ps_v6 becomes
        # Standard_D2ps_v5, Standard_D2pls_v6 Standard_D2pls_v5.
        [[ -f "$tfvars" ]] || tfvars="$ROOT_DIR/examples/${SIZE:-m}.tfvars"
        node_alt=$(sed -n 's/^node_instance_type *= *"\(Standard_[A-Za-z0-9]*\)p\(l\{0,1\}\)s_v6".*/\1a\2s_v6/p' "$tfvars" 2>/dev/null | head -n 1)
        os_alt=$(sed -n 's/^opensearch_data_instance_type *= *"\(Standard_[A-Za-z0-9]*p[a-z]*\)_v6".*/\1_v5/p' "$tfvars" 2>/dev/null | head -n 1)
        say ""
        say "Azure has no capacity for a VM size in a zone${sizes:+ ($sizes)}."
        [[ -n "$alt" ]] && say "Azure's error suggests $alt."
        say "Run again with --force and one of:"
        case "$ROOT_NAME" in
            infra-azure-ha-k8s-helm)
                say "  --set 'node_pool_zones=[\"2\",\"3\"]'   the IQ Server node pool in the zones that have capacity"
                say "  --set node_instance_type=${node_alt:-<type>}   the same vCPUs and memory from another series"
                say "  --set opensearch_data_instance_type=${os_alt:-<type>}   for an OpenSearch size, the same vCPUs and memory from the previous Arm series"
                say "A node pool that failed this way can exist in Azure and not in Terraform state; delete it with"
                say "az aks nodepool delete before the retry, or the retry fails with 'already exists'."
                ;;
            *)
                say "  --set 'opensearch_zones=[\"2\",\"3\"]'   the OpenSearch nodes in the zones that have capacity"
                say "  --set opensearch_data_instance_type=${os_alt:-<type>}   the same vCPUs and memory from the previous Arm series"
                ;;
        esac
    elif grep -q "InsufficientInstanceCapacity\|InsufficientCapacity" "$LOG"; then
        say ""
        say "AWS has no capacity for an instance type in a zone. Retrying in a few minutes usually works;"
        say "otherwise run again with --force and a type with the same vCPUs and memory:"
        if [[ "$ROOT_NAME" == infra-aws-ha-k8s-helm ]]; then
            say "  --set node_instance_type=<type>   for the EKS worker nodes"
        fi
        say "  --set opensearch_instance_type=<type>.search   for the OpenSearch data nodes"
    fi
}

cloud_env() {
    local region project
    if [[ -n "$AWS_PROFILE_OPT" ]]; then
        export AWS_PROFILE="$AWS_PROFILE_OPT"
    fi
    if [[ "$CLOUD" == aws && -z "${AWS_REGION:-}" ]]; then
        region=$(sed -n 's/^aws_region[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$1" | head -n 1)
        [[ -n "$region" ]] && export AWS_REGION="$region"
    fi
    # The GCP scripts ask gcloud for the project, so point gcloud at the one in terraform.tfvars.
    if [[ "$CLOUD" == gcp && -z "${CLOUDSDK_CORE_PROJECT:-}" ]]; then
        project=$(sed -n 's/^gcp_project_id[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$1" | head -n 1)
        [[ -n "$project" ]] && export CLOUDSDK_CORE_PROJECT="$project"
    fi
}

check_tools() {
    local t missing=""
    for t in "$@"; do
        command -v "$t" >/dev/null 2>&1 || missing="$missing $t"
    done
    [[ -z "$missing" ]] || die "not installed:$missing"
}

cloud_tools() {
    local tools="terraform jq"
    case "$CLOUD" in
        aws) tools="$tools aws" ;;
        azure) tools="$tools az" ;;
        gcp) tools="$tools gcloud" ;;
    esac
    is_k8s && tools="$tools kubectl helm"
    # shellcheck disable=SC2086
    check_tools $tools
    if [[ "$CLOUD" == aws && -z "${AWS_PROFILE:-}" && -z "${AWS_ACCESS_KEY_ID:-}" ]]; then
        die "the AWS scripts need credentials: pass --aws-profile NAME, or export AWS_PROFILE"
    fi
}

# iq-post-deploy.sh sets the Nexus One shard counts and the search backend. The
# root's apply or helm-install.sh script runs it; deploy.sh runs it only for a root
# whose own scripts do not, so it never runs twice.
post_deploy_cmd() {
    [[ -f "$ROOT_DIR/iq-post-deploy.sh" ]] || return 0
    if grep -qs 'iq-post-deploy\.sh' "$ROOT_DIR"/*apply*.sh "$ROOT_DIR"/helm-install.sh; then
        return 0
    fi
    echo "bash ./iq-post-deploy.sh"
}

print_access() {
    local out url="" pw
    for out in application_url nexus_iq_url load_balancer_url application_gateway_url; do
        url=$(cd "$ROOT_DIR" && terraform output -raw "$out" 2>/dev/null) || url=""
        [[ "$url" == http* ]] && break
        url=""
    done
    if [[ -z "$url" ]] && is_k8s; then
        url=$(kubectl get ingress -n nexus-iq -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null) || url=""
        [[ -n "$url" ]] && url="http://$url"
    fi
    say ""
    say "IQ Server: ${url:-run terraform output in $ROOT_NAME for the address}"
    pw=$(live_value "$ROOT_DIR/terraform.tfvars" iq_admin_initial_password)
    if [[ -n "$pw" ]]; then
        say "Sign in as admin with the iq_admin_initial_password value from $ROOT_NAME/terraform.tfvars."
    else
        say "Sign in as admin with IQ Server's default admin password, and change it at once."
    fi
    say "IQ Server takes several minutes to start after the deploy finishes."
}

confirm() {
    local question="$1" word="$2" reply
    [[ "$YES" == true ]] && return 0
    # Asks on the terminal even when the answers come from a file, so only --yes or
    # --non-interactive skips the question.
    if [[ "$NON_INTERACTIVE" == true ]]; then
        die "confirmation needed and --non-interactive is set: pass --yes"
    fi
    if ! { : < /dev/tty; } 2>/dev/null; then
        die "confirmation needed and there is no terminal to ask on: pass --yes"
    fi
    printf '%s Type %s to continue: ' "$question" "$word" >&2
    IFS= read -r reply < /dev/tty || die "canceled"
    [[ "$reply" == "$word" ]] || die "canceled"
}

# ---------------------------------------------------------------------------
# Deploy and destroy
# ---------------------------------------------------------------------------

do_deploy() {
    local target="$ROOT_DIR/terraform.tfvars" stamp cmds="" c post region
    select_size_and_search
    resolve_license
    build_tfvars
    build_helm_values

    cmds="terraform init -input=false"
    cmds="$cmds
$(plan_cmd)"
    if [[ "$PLAN_ONLY" != true ]]; then
        cmds="$cmds
$(apply_cmd)"
        if is_k8s; then
            if [[ -n "$HELM_SIZE_FILE" ]]; then
                cmds="$cmds
bash ./helm-install.sh --values examples/$SIZE.helm-values.yaml"
            else
                cmds="$cmds
bash ./helm-install.sh"
            fi
        fi
        post=$(post_deploy_cmd)
        if [[ -n "$post" ]]; then
            cmds="$cmds
$post"
        fi
    fi

    say ""
    say "Deployment: $ROOT_NAME, size $SIZE, search backend $SEARCH"
    if [[ "$DRY_RUN" == true ]]; then
        if [[ -f "$target" && "$FORCE" != true ]]; then
            say "Note: $ROOT_NAME/terraform.tfvars exists, so a real run stops there unless --force is given."
        fi
        say ""
        say "--- $ROOT_NAME/terraform.tfvars that would be written (secrets masked) ---"
        mask "$WORK/tfvars"
        if [[ -n "$HELM_SIZE_FILE" ]]; then
            say ""
            say "--- Helm values: $ROOT_NAME/helm-values.yaml, then examples/$SIZE.helm-values.yaml ---"
            grep -v '^[[:space:]]*#' "$HELM_SIZE_FILE"
        fi
        if [[ -n "$LICENSE_FILE" ]]; then
            say ""
            say "License file (iq_license_file): $LICENSE_FILE"
        fi
        say ""
        say "--- commands that would run in $ROOT_NAME ---"
        say "$cmds"
        return 0
    fi

    if [[ -f "$target" && "$FORCE" != true ]]; then
        die "$ROOT_NAME/terraform.tfvars exists. Pass --force to replace it (the old one is kept as a .bak file)."
    fi
    cloud_env "$WORK/tfvars"
    cloud_tools
    if [[ "$PLAN_ONLY" != true ]]; then
        region=$(live_value "$WORK/tfvars" "${CLOUD}_region" | sed 's/^"\([^"]*\)".*/\1/')
        say "Region: ${region:-the default in $ROOT_NAME/variables.tf}. To change it, run again with --set ${CLOUD}_region=<region>."
        confirm "This creates the $ROOT_NAME deployment at size $SIZE in your $CLOUD account." yes
    fi

    start_log
    stamp=$(date +%Y%m%d-%H%M%S)
    if [[ -f "$target" ]]; then
        mv "$target" "$target.$stamp.bak" || die "cannot back up $target"
        say "Kept the previous terraform.tfvars as terraform.tfvars.$stamp.bak"
    fi
    (umask 077 && cp "$WORK/tfvars" "$target") || die "cannot write $target"
    say "Wrote $ROOT_NAME/terraform.tfvars for size $SIZE (secrets masked here):"
    mask "$target"
    if [[ -n "$LICENSE_FILE" ]]; then
        export IQ_LICENSE_FILE="$LICENSE_FILE"
        say "IQ Server installs the license from $LICENSE_FILE on its first start; iq-post-deploy.sh installs it if IQ Server has none"
    fi

    while IFS= read -r c <&3; do
        [[ -n "$c" ]] && run_step "$c"
    done 3<<EOF
$cmds
EOF

    if [[ "$PLAN_ONLY" == true ]]; then
        say ""
        say "Plan only: nothing was created. Run ./deploy.sh again without --plan-only, with --force, to deploy."
        return 0
    fi
    print_access
}

do_destroy() {
    local target="$ROOT_DIR/terraform.tfvars" cmds="" c
    [[ -f "$target" ]] || die "$ROOT_NAME/terraform.tfvars not found, so there is no deployment here to destroy"
    if is_k8s; then
        cmds="$(uninstall_cmd)
"
    fi
    cmds="$cmds$(destroy_cmd)"

    say ""
    say "Destroy: $ROOT_NAME"
    if [[ "$DRY_RUN" == true ]]; then
        say "--- commands that would run in $ROOT_NAME ---"
        say "$cmds"
        return 0
    fi
    cloud_env "$target"
    cloud_tools
    confirm "This deletes every resource the $ROOT_NAME deployment created, its database and stored data included." destroy
    INTERACTIVE=false
    start_log
    while IFS= read -r c <&3; do
        [[ -n "$c" ]] && run_step "$c"
    done 3<<EOF
$cmds
EOF
    say ""
    say "$ROOT_NAME destroyed. terraform.tfvars is left in place."
}

main() {
    parse_args "$@"
    if [[ -t 0 && -z "$ANSWERS_FILE" && "$NON_INTERACTIVE" != true ]]; then
        INTERACTIVE=true
    fi
    load_answers_file
    select_root
    if [[ "$DESTROY" == true ]]; then
        do_destroy
    else
        do_deploy
    fi
}

main "$@"
