#!/usr/bin/env bash
set -e
# create-new-feature.sh — Create or switch to the feature branch defined in session.json.
# Reads branch_name from session.json. If that branch already exists, appends -v1, -v2, ...
# and updates session.json with the actual name used.

# ─── Argument parsing ────────────────────────────────────────────────────────
JSON_MODE=false
DRY_RUN=false
while [ $# -gt 0 ]; do
    case "$1" in
        --json)     JSON_MODE=true ;;
        --dry-run)  DRY_RUN=true ;;
        --help|-h)
            echo "Usage: $0 [--json] [--dry-run]"
            echo "  --json      Output JSON ({BRANCH_NAME, SPEC_FILE})"
            echo "  --dry-run   Compute names without creating branches or files"
            exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done

# ─── Setup ───────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

REPO_ROOT=$(get_repo_root)
has_git && HAS_GIT=true || HAS_GIT=false
cd "$REPO_ROOT"

SPECS_DIR="$REPO_ROOT/specs"
[ "$DRY_RUN" = true ] || mkdir -p "$SPECS_DIR"

log() { echo "[feature] $*" >&2; }

# ─── Helpers ─────────────────────────────────────────────────────────────────
local_branch_exists() {
    git branch --list "$1" 2>/dev/null | grep -q .
}

remote_branch_exists() {
    git branch -r --list "*/$1" 2>/dev/null | grep -q .
}

get_available_branch_name() {
    local base="$1"
    if ! local_branch_exists "$base" && ! remote_branch_exists "$base"; then
        echo "$base"; return
    fi
    local v=1
    while true; do
        local candidate="${base}-v${v}"
        if ! local_branch_exists "$candidate" && ! remote_branch_exists "$candidate"; then
            echo "$candidate"; return
        fi
        v=$((v + 1))
    done
}

_sync_session() {
    local branch="$1"
    local mgr="$REPO_ROOT/.spec/scripts/bash/manage-session.sh"
    if [ ! -f "$mgr" ]; then
        log "manage-session.sh not found — skipping session update"
        return 0
    fi
    local patch="{\"branch_name\":\"$branch\",\"feature_dir\":\"specs/$branch\"}"
    bash "$mgr" --action update-multi --json-patch "$patch" 2>/dev/null || true
    log "Session updated: branch_name=$branch  feature_dir=specs/$branch"
}

_output() {
    local branch="$1" feat_dir="$2"
    if $JSON_MODE; then
        if command -v jq >/dev/null 2>&1; then
            jq -cn --arg b "$branch" --arg s "$feat_dir/spec.md" '{BRANCH_NAME:$b,SPEC_FILE:$s}'
        else
            printf '{"BRANCH_NAME":"%s","SPEC_FILE":"%s"}\n' "$branch" "$feat_dir/spec.md"
        fi
    else
        echo "BRANCH_NAME: $branch"
        echo "SPEC_FILE:   $feat_dir/spec.md"
    fi
}

# ─── Read session.json ───────────────────────────────────────────────────────
SESSION_FILE="$REPO_ROOT/.spec/session.json"
if [ ! -f "$SESSION_FILE" ]; then
    log "No session.json found — run spec.session init first"; exit 1
fi

if command -v jq >/dev/null 2>&1; then
    SESSION_BRANCH=$(jq -r '.branch_name // empty' "$SESSION_FILE" 2>/dev/null)
elif command -v python3 >/dev/null 2>&1; then
    SESSION_BRANCH=$(python3 -c \
        "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('branch_name',''))" \
        "$SESSION_FILE" 2>/dev/null)
fi

if [ -z "$SESSION_BRANCH" ]; then
    log "session.json has no branch_name — populate it before creating a branch"; exit 1
fi

log "Session branch_name: '$SESSION_BRANCH'"

# Current git branch
CURRENT_BRANCH=""
[ "$HAS_GIT" = true ] && CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
log "Current git branch: '${CURRENT_BRANCH:-none}'"

# Already on the correct branch — nothing to do
if [ -n "$CURRENT_BRANCH" ] && [ "$CURRENT_BRANCH" = "$SESSION_BRANCH" ]; then
    log "Already on session branch '$SESSION_BRANCH' — nothing to do"
    _output "$SESSION_BRANCH" "$SPECS_DIR/$SESSION_BRANCH"
    exit 0
fi

# ─── Find an available branch name ──────────────────────────────────────────
if [ "$HAS_GIT" = true ] && [ "$DRY_RUN" != true ]; then
    git fetch --all --prune >/dev/null 2>&1 || true
    BRANCH_NAME=$(get_available_branch_name "$SESSION_BRANCH")
else
    BRANCH_NAME="$SESSION_BRANCH"
fi

if [ "$BRANCH_NAME" != "$SESSION_BRANCH" ]; then
    log "Branch '$SESSION_BRANCH' exists — using '$BRANCH_NAME'"
fi

FEATURE_DIR="$SPECS_DIR/$BRANCH_NAME"
SPEC_FILE="$FEATURE_DIR/spec.md"

# ─── Create branch and spec dir ─────────────────────────────────────────────
if [ "$DRY_RUN" != true ]; then
    if [ "$HAS_GIT" = true ]; then
        log "Creating git branch '$BRANCH_NAME'..."
        if git checkout -q -b "$BRANCH_NAME" 2>/dev/null; then
            log "Branch '$BRANCH_NAME' created and checked out"
        elif git checkout -q "$BRANCH_NAME" 2>/dev/null; then
            log "Switched to existing branch '$BRANCH_NAME'"
        else
            log "ERROR: Failed to create or checkout '$BRANCH_NAME'"; exit 1
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
            log "Spec file created (empty): $SPEC_FILE"
        fi
    else
        log "Spec file already exists: $SPEC_FILE"
    fi

    _sync_session "$BRANCH_NAME"
else
    log "[dry-run] Would create branch '$BRANCH_NAME' and spec at $SPEC_FILE"
fi

_output "$BRANCH_NAME" "$FEATURE_DIR"