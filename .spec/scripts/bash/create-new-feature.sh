#!/usr/bin/env bash
set -e

# ─── Argument parsing ────────────────────────────────────────────────────────
JSON_MODE=false
DRY_RUN=false
SHORT_NAME=""
USE_TIMESTAMP=false
ARGS=()
i=1
while [ $i -le $# ]; do
    arg="${!i}"
    case "$arg" in
        --json)       JSON_MODE=true ;;
        --dry-run)    DRY_RUN=true ;;
        --timestamp)  USE_TIMESTAMP=true ;;
        --short-name)
            i=$((i+1))
            [ $i -le $# ] || { echo "Error: --short-name requires a value" >&2; exit 1; }
            SHORT_NAME="${!i}"
            ;;
        --help|-h)
            echo "Usage: $0 [--json] [--dry-run] [--timestamp] [--short-name <name>] <feature_description>"
            echo "  --json           Output JSON ({BRANCH_NAME, SPEC_FILE, FEATURE_NUM})"
            echo "  --dry-run        Compute names without creating branches or files"
            echo "  --timestamp      Use YYYYMMDD-HHMMSS prefix instead of sequential numbering"
            echo "  --short-name     Override the generated slug (2-4 words, kebab-case)"
            exit 0 ;;
        *)  ARGS+=("$arg") ;;
    esac
    i=$((i+1))
done

FEATURE_DESCRIPTION=$(echo "${ARGS[*]}" | xargs)
if [ -z "$FEATURE_DESCRIPTION" ]; then
    echo "Error: feature description is required" >&2; exit 1
fi

# ─── Setup ───────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

REPO_ROOT=$(get_repo_root)
has_git && HAS_GIT=true || HAS_GIT=false
cd "$REPO_ROOT"

SPECS_DIR="$REPO_ROOT/specs"
[ "$DRY_RUN" = true ] || mkdir -p "$SPECS_DIR"

# ─── Helpers ─────────────────────────────────────────────────────────────────
log() { echo "[feature] $*" >&2; }

clean_branch_name() {
    echo "$1" | tr '[:upper:]' '[:lower:]' \
        | sed 's/[^a-z0-9]/-/g; s/-\+/-/g; s/^-//; s/-$//'
}

generate_branch_name() {
    local desc="$1"
    local stop="^(i|a|an|the|to|for|of|in|on|at|by|with|from|is|are|was|were|be|been|being|have|has|had|do|does|did|will|would|should|could|can|may|might|must|shall|this|that|these|those|my|your|our|their|want|need|add|get|set)$"
    local words=()
    for word in $(echo "$desc" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/ /g'); do
        [ -z "$word" ] && continue
        echo "$word" | grep -qiE "$stop" && continue
        if [ ${#word} -ge 3 ]; then
            words+=("$word")
        elif echo "$desc" | grep -q "\b${word^^}\b" 2>/dev/null; then
            words+=("$word")
        fi
    done
    if [ ${#words[@]} -gt 0 ]; then
        local max=3; [ ${#words[@]} -eq 4 ] && max=4
        local result="" n=0
        for w in "${words[@]}"; do
            [ $n -ge $max ] && break
            [ -n "$result" ] && result="$result-"
            result="$result$w"; n=$((n+1))
        done
        echo "$result"
    else
        clean_branch_name "$desc" | tr '-' '\n' | grep -v '^$' | head -3 | tr '\n' '-' | sed 's/-$//'
    fi
}

get_highest_from_specs() {
    local highest=0
    if [ -d "$SPECS_DIR" ]; then
        for dir in "$SPECS_DIR"/*/; do
            [ -d "$dir" ] || continue
            local name; name=$(basename "$dir")
            if echo "$name" | grep -Eq '^[0-9]{3,}-' && ! echo "$name" | grep -Eq '^[0-9]{8}-[0-9]{6}-'; then
                local num; num=$((10#$(echo "$name" | grep -Eo '^[0-9]+')))
                [ "$num" -gt "$highest" ] && highest=$num
            fi
        done
    fi
    echo "$highest"
}

get_next_branch_number() {
    local highest_branch=0
    if [ "$HAS_GIT" = true ]; then
        log "Fetching remote branches to find next number..."
        git fetch --all --prune >/dev/null 2>&1 || true
        while IFS= read -r name; do
            [ -z "$name" ] && continue
            if echo "$name" | grep -Eq '^[0-9]{3,}-' && ! echo "$name" | grep -Eq '^[0-9]{8}-[0-9]{6}-'; then
                local num; num=$((10#$(echo "$name" | grep -Eo '^[0-9]+')))
                [ "$num" -gt "$highest_branch" ] && highest_branch=$num
            fi
        done < <(git branch -a 2>/dev/null | sed 's/^[* ]*//; s|^remotes/[^/]*/||' | sort -u)
    fi
    local highest_spec; highest_spec=$(get_highest_from_specs)
    local max=$highest_branch
    [ "$highest_spec" -gt "$max" ] && max=$highest_spec
    log "Highest existing number: $max → next: $((max+1))"
    echo $((max + 1))
}

_sync_session() {
    local branch="$1" feat_num="$2"
    local mgr="$REPO_ROOT/.spec/scripts/bash/manage-session.sh"
    if [ ! -f "$mgr" ]; then
        log "manage-session.sh not found — skipping session sync"
        return 0
    fi
    local patch="{\"branch_name\":\"$branch\",\"feature_num\":\"$feat_num\",\"feature_dir\":\"specs/$branch\"}"
    bash "$mgr" --action update-multi --json-patch "$patch" 2>/dev/null || true
    bash "$mgr" --action add-agent --agent-name "spec.git.feature" 2>/dev/null || true
    log "Session synced: branch_name=$branch  feature_num=$feat_num  feature_dir=specs/$branch"
}

_feature_num_from_branch() {
    local name="$1"
    if [[ "$name" =~ ^([0-9]{8}-[0-9]{6}|[0-9]{3,})- ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo "$name"
    fi
}

_output() {
    local branch="$1" feat_num="$2" feat_dir="$3"
    if $JSON_MODE; then
        if command -v jq >/dev/null 2>&1; then
            jq -cn --arg b "$branch" --arg s "$feat_dir/spec.md" --arg n "$feat_num" \
                '{BRANCH_NAME:$b,SPEC_FILE:$s,FEATURE_NUM:$n}'
        else
            printf '{"BRANCH_NAME":"%s","SPEC_FILE":"%s","FEATURE_NUM":"%s"}\n' \
                "$(json_escape "$branch")" "$(json_escape "$feat_dir/spec.md")" "$(json_escape "$feat_num")"
        fi
    else
        echo "BRANCH_NAME: $branch"
        echo "SPEC_FILE:   $feat_dir/spec.md"
        echo "FEATURE_NUM: $feat_num"
    fi
}

# ─── Session-first ───────────────────────────────────────────────────────────
_session_file="$REPO_ROOT/.spec/session.json"
_session_branch=""
if [ -f "$_session_file" ]; then
    if command -v jq >/dev/null 2>&1; then
        _session_branch=$(jq -r '.branch_name // empty' "$_session_file" 2>/dev/null)
    elif command -v python3 >/dev/null 2>&1; then
        _session_branch=$(python3 -c \
            "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('branch_name',''))" \
            "$_session_file" 2>/dev/null)
    fi
    log "Session found: branch_name='$_session_branch'"
else
    log "No session.json found — will generate new branch"
fi

_current_branch=""
[ "$HAS_GIT" = true ] && _current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
log "Current git branch: '${_current_branch:-none}'"

# Already on the correct branch — nothing to do
if [ -n "$_session_branch" ] && [ "$_current_branch" = "$_session_branch" ]; then
    log "Already on session branch '$_session_branch' — nothing to do"
    _fn=$(_feature_num_from_branch "$_session_branch")
    _output "$_session_branch" "$_fn" "$SPECS_DIR/$_session_branch"
    exit 0
fi

# Session has a branch but we are not on it — create or checkout
if [ -n "$_session_branch" ] && [ "$_current_branch" != "$_session_branch" ]; then
    log "Session branch '$_session_branch' set; current is '${_current_branch:-none}' — switching"
    if [ "$HAS_GIT" = true ] && [ "$DRY_RUN" != true ]; then
        git checkout -b "$_session_branch" 2>/dev/null \
            || git checkout "$_session_branch" 2>/dev/null \
            || { log "ERROR: Failed to create or checkout '$_session_branch'"; exit 1; }
        log "Switched to branch '$_session_branch'"
    elif [ "$DRY_RUN" = true ]; then
        log "[dry-run] Would checkout/create branch '$_session_branch'"
    fi
    _fn=$(_feature_num_from_branch "$_session_branch")
    if [ "$DRY_RUN" != true ]; then
        mkdir -p "$SPECS_DIR/$_session_branch"
        _sync_session "$_session_branch" "$_fn"
    fi
    _output "$_session_branch" "$_fn" "$SPECS_DIR/$_session_branch"
    exit 0
fi

# ─── No session branch — generate new ────────────────────────────────────────
log "No branch_name in session — generating new branch from description"

if [ -n "$SHORT_NAME" ]; then
    BRANCH_SUFFIX=$(clean_branch_name "$SHORT_NAME")
    log "Using provided short name: '$BRANCH_SUFFIX'"
else
    BRANCH_SUFFIX=$(generate_branch_name "$FEATURE_DESCRIPTION")
    log "Generated slug from description: '$BRANCH_SUFFIX'"
fi

if [ "$USE_TIMESTAMP" = true ]; then
    FEATURE_NUM=$(date +%Y%m%d-%H%M%S)
    log "Using timestamp prefix: $FEATURE_NUM"
else
    BRANCH_NUMBER=$(get_next_branch_number)
    FEATURE_NUM=$(printf "%03d" "$((10#$BRANCH_NUMBER))")
    log "Using sequential prefix: $FEATURE_NUM"
fi

BRANCH_NAME="${FEATURE_NUM}-${BRANCH_SUFFIX}"

# Truncate if over GitHub's 244-byte limit
if [ ${#BRANCH_NAME} -gt 244 ]; then
    MAX_SUFFIX=$(( 244 - ${#FEATURE_NUM} - 1 ))
    BRANCH_SUFFIX=$(echo "$BRANCH_SUFFIX" | cut -c1-$MAX_SUFFIX | sed 's/-$//')
    log "WARNING: Branch name too long — truncated suffix to '$BRANCH_SUFFIX'"
    BRANCH_NAME="${FEATURE_NUM}-${BRANCH_SUFFIX}"
fi

log "New branch name: '$BRANCH_NAME'"

FEATURE_DIR="$SPECS_DIR/$BRANCH_NAME"
SPEC_FILE="$FEATURE_DIR/spec.md"

if [ "$DRY_RUN" != true ]; then
    if [ "$HAS_GIT" = true ]; then
        log "Creating git branch '$BRANCH_NAME'..."
        if ! git checkout -q -b "$BRANCH_NAME" 2>/dev/null; then
            if git branch --list "$BRANCH_NAME" | grep -q .; then
                log "Branch '$BRANCH_NAME' already exists — switching to it"
                git checkout -q "$BRANCH_NAME" || { log "ERROR: Failed to switch to '$BRANCH_NAME'"; exit 1; }
            else
                log "ERROR: Failed to create branch '$BRANCH_NAME'"
                exit 1
            fi
        else
            log "Branch '$BRANCH_NAME' created and checked out"
        fi
    else
        log "No git repo — skipping branch creation"
    fi

    mkdir -p "$FEATURE_DIR"
    if [ ! -f "$SPEC_FILE" ]; then
        TEMPLATE=$(resolve_template "spec-template" "$REPO_ROOT") || true
        if [ -n "$TEMPLATE" ] && [ -f "$TEMPLATE" ]; then
            cp "$TEMPLATE" "$SPEC_FILE"
            log "Spec file created from template: $SPEC_FILE"
        else
            touch "$SPEC_FILE"
            log "Spec file created (empty — template not found): $SPEC_FILE"
        fi
    else
        log "Spec file already exists: $SPEC_FILE"
    fi

    _sync_session "$BRANCH_NAME" "$FEATURE_NUM"
    printf '# To persist in your shell: export SPECIFY_FEATURE=%q\n' "$BRANCH_NAME" >&2
else
    log "[dry-run] Would create branch '$BRANCH_NAME' and spec at $SPEC_FILE"
fi

_output "$BRANCH_NAME" "$FEATURE_NUM" "$FEATURE_DIR"
