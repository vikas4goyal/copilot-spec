#!/usr/bin/env bash
set -e
# create-new-feature.sh — Bootstrap a new feature: derives branch/folder names,
# creates the git branch and specs/YYYYMMDD-<name>/ directory, and keeps
# session.json in sync — entirely via manage-session.sh (no direct file access).
#
# Naming conventions
#   branch : <name>  →  <name>-YYYYMMDD  →  <name>-YYYYMMDD-2 …
#   folder : YYYYMMDD-<name>  →  YYYYMMDD-<name>-2 …  (date-prefix for dir sorting)
#
# Usage:
#   create-new-feature.sh --name "oauth2-login" --description "Implements OAuth2 login" [--agent-name "spec.specify"] [--json] [--dry-run]

# ─── Argument parsing ────────────────────────────────────────────────────────
JSON_MODE=false
DRY_RUN=false
ARG_NAME=""
ARG_DESCRIPTION=""
ARG_AGENT_NAME=""

while [ $# -gt 0 ]; do
    case "$1" in
        --name)        ARG_NAME="$2";        shift 2 ;;
        --description) ARG_DESCRIPTION="$2"; shift 2 ;;
        --agent-name)  ARG_AGENT_NAME="$2";  shift 2 ;;
        --json)        JSON_MODE=true;        shift ;;
        --dry-run)     DRY_RUN=true;          shift ;;
        --help|-h)
            echo "Usage: $0 --name <slug> --description <desc> [--agent-name <agent>] [--json] [--dry-run]"
            echo "  --name          Feature name slug (e.g. oauth2-login-google)"
            echo "  --description   One-line feature description"
            echo "  --agent-name    Calling agent to record in session (e.g. spec.specify)"
            echo "  --json          Output JSON ({BRANCH_NAME, FEATURE_DIR, SPEC_FILE})"
            echo "  --dry-run       Compute names without creating branches or files"
            exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# ─── Setup ───────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

REPO_ROOT=$(get_repo_root)
has_git && HAS_GIT=true || HAS_GIT=false
cd "$REPO_ROOT"

SPECS_DIR="$REPO_ROOT/specs"
MGR_SH="$REPO_ROOT/.spec/scripts/bash/manage-session.sh"

if [ ! -f "$MGR_SH" ]; then
    echo "[feature] ERROR: manage-session.sh not found at $MGR_SH" >&2; exit 1
fi

[ "$DRY_RUN" = true ] || mkdir -p "$SPECS_DIR"

log() { echo "[feature] $*" >&2; }

# ─── Thin wrapper: call manage-session and propagate errors ──────────────────
mgr() { bash "$MGR_SH" "$@"; }

# ─── Branch / folder naming helpers ──────────────────────────────────────────

get_unique_branch_name() {
    local base="$1"
    local taken="" line n
    if [ "$HAS_GIT" = true ]; then
        while IFS= read -r line; do
            n=$(printf '%s' "$line" | sed 's/^[* ]*//' | sed 's/ .*//')
            [ -n "$n" ] && taken="${taken}${n}"$'\n'
        done < <(git branch --list "${base}*" 2>/dev/null || true)
        while IFS= read -r line; do
            n=$(printf '%s' "$line" | sed 's|.*/||' | sed 's/ .*//')
            [ -n "$n" ] && taken="${taken}${n}"$'\n'
        done < <(git branch -r --list "*/${base}*" 2>/dev/null || true)
    fi
    _bt() { printf '%s' "$taken" | grep -qxF -- "$1" 2>/dev/null; }

    _bt "$base" || { echo "$base"; return; }
    local ds; ds=$(date -u +"%Y%m%d")
    local dc="${base}-${ds}"
    _bt "$dc" || { echo "$dc"; return; }
    local n=2
    while true; do
        local c="${base}-${ds}-${n}"
        _bt "$c" || { echo "$c"; return; }
        n=$((n + 1))
    done
}

get_unique_folder_name() {
    local base="$1"
    local ds; ds=$(date -u +"%Y%m%d")
    local prefix="${ds}-${base}"
    local taken="" d
    for d in "$SPECS_DIR"/${prefix}*/; do
        [ -d "$d" ] || continue
        local n; n=$(basename "$d")
        taken="${taken}${n}"$'\n'
    done
    _ft() { printf '%s' "$taken" | grep -qxF -- "$1" 2>/dev/null; }

    _ft "$prefix" || { echo "$prefix"; return; }
    local n=2
    while true; do
        local c="${prefix}-${n}"
        _ft "$c" || { echo "$c"; return; }
        n=$((n + 1))
    done
}

_output() {
    local branch="$1" feat_dir="$2"
    if $JSON_MODE; then
        if command -v jq >/dev/null 2>&1; then
            jq -cn --arg b "$branch" --arg d "$feat_dir" --arg s "$feat_dir/spec.md" \
               '{BRANCH_NAME:$b,FEATURE_DIR:$d,SPEC_FILE:$s}'
        else
            printf '{"BRANCH_NAME":"%s","FEATURE_DIR":"%s","SPEC_FILE":"%s"}\n' \
                   "$branch" "$feat_dir" "$feat_dir/spec.md"
        fi
    else
        echo "BRANCH_NAME: $branch"
        echo "FEATURE_DIR: $feat_dir"
        echo "SPEC_FILE:   $feat_dir/spec.md"
    fi
}

# ─── Session bootstrap ────────────────────────────────────────────────────────

if [ "$DRY_RUN" != true ]; then
    # Step 1: Init — creates session from template (or reuses existing).
    #         Passes name/description so they are written on creation, or filled
    #         in non-destructively if the session already exists but has blanks.
    INIT_ARGS=(--action init)
    [ -n "$ARG_NAME" ]        && INIT_ARGS+=(--name "$ARG_NAME")
    [ -n "$ARG_DESCRIPTION" ] && INIT_ARGS+=(--description "$ARG_DESCRIPTION")
    mgr "${INIT_ARGS[@]}" > /dev/null
fi

# Step 2: Read current session values via manage-session (stdout = JSON)
BASE_NAME=""
SESS_BRANCH=""
SESS_FDIR=""

SESS_JSON=$(mgr --action get-multi --fields "name,branch_name,feature_dir" 2>/dev/null || true)

if [ -n "$SESS_JSON" ]; then
    if command -v jq >/dev/null 2>&1; then
        BASE_NAME=$(echo "$SESS_JSON"   | jq -r '.name          // empty' 2>/dev/null || true)
        SESS_BRANCH=$(echo "$SESS_JSON" | jq -r '.branch_name   // empty' 2>/dev/null || true)
        SESS_FDIR=$(echo "$SESS_JSON"   | jq -r '.feature_dir   // empty' 2>/dev/null || true)
    elif command -v python3 >/dev/null 2>&1; then
        BASE_NAME=$(echo "$SESS_JSON"   | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('name','') or '')")
        SESS_BRANCH=$(echo "$SESS_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('branch_name','') or '')")
        SESS_FDIR=$(echo "$SESS_JSON"   | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('feature_dir','') or '')")
    fi
fi

# In dry-run (no session created), still honour the --name param
[ -z "$BASE_NAME" ] && BASE_NAME="$ARG_NAME"

if [ -z "$BASE_NAME" ]; then
    if [ "$DRY_RUN" = true ]; then
        log "ERROR: No active session and --name not provided. Pass --name <slug> for dry-run."
    else
        log "ERROR: Feature name is not set. Pass --name <slug> to provide one."
    fi
    exit 1
fi
log "Session name: '$BASE_NAME'"

# Current git branch
CURRENT_BRANCH=""
[ "$HAS_GIT" = true ] && CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
log "Current git branch: '${CURRENT_BRANCH:-none}'"

# ── Idempotency / consistency check ──────────────────────────────────────────
if [ -n "$SESS_BRANCH" ] && [ -n "$SESS_FDIR" ]; then
    EXISTING_DIR="$REPO_ROOT/$SESS_FDIR"

    if [ "$CURRENT_BRANCH" = "$SESS_BRANCH" ] && [ -d "$EXISTING_DIR" ]; then
        log "Already on branch '$SESS_BRANCH' with feature dir '$SESS_FDIR' — nothing to do"
        _output "$SESS_BRANCH" "$EXISTING_DIR"
        exit 0
    fi

    if [ "$CURRENT_BRANCH" != "$SESS_BRANCH" ]; then
        log "ERROR: Session expects branch '$SESS_BRANCH' but the current git branch is '${CURRENT_BRANCH:-none}'."
        log "       Switch to the correct branch  →  git checkout $SESS_BRANCH"
        log "       Or release the current feature first  →  /spec.release"
        exit 1
    fi
    # branch matches but folder is missing — fall through and re-create
fi

# ─── Fetch remote refs so branch availability check is accurate ──────────────
if [ "$HAS_GIT" = true ] && [ "$DRY_RUN" != true ]; then
    git fetch --all --prune >/dev/null 2>&1 || true
fi

# ─── Resolve unique branch name and folder name ───────────────────────────────
BRANCH_NAME=$(get_unique_branch_name "$BASE_NAME")
FOLDER_NAME=$(get_unique_folder_name "$BASE_NAME")

[ "$BRANCH_NAME" != "$BASE_NAME" ] && log "Branch '$BASE_NAME' taken — using '$BRANCH_NAME'"
log "Folder name: $FOLDER_NAME"

FEATURE_DIR="$SPECS_DIR/$FOLDER_NAME"
SPEC_FILE="$FEATURE_DIR/spec.md"

# ─── Create branch and spec dir ──────────────────────────────────────────────
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

    # ── Write branch_name and feature_dir back to session ────────────────────
    PATCH="{\"branch_name\":\"${BRANCH_NAME}\",\"feature_dir\":\"specs/${FOLDER_NAME}\"}"
    mgr --action update-multi --json-patch "$PATCH" > /dev/null

    # ── Record calling agent (if provided) ───────────────────────────────────
    if [ -n "$ARG_AGENT_NAME" ]; then
        mgr --action add-agent --agent-name "$ARG_AGENT_NAME" > /dev/null
    fi

    log "Session updated: branch_name=${BRANCH_NAME}  feature_dir=specs/${FOLDER_NAME}"
else
    log "[dry-run] branch_name  → $BRANCH_NAME"
    log "[dry-run] feature_dir  → specs/$FOLDER_NAME"
    log "[dry-run] Would create session.json (if needed), branch and spec dir"
fi

_output "$BRANCH_NAME" "$FEATURE_DIR"
