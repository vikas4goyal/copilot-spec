#!/usr/bin/env bash
set -e
# create-new-feature.sh — Resolves unique branch and folder names from session 'name',
# creates the git branch and specs/YYYYMMDD-<name>/ directory, then writes branch_name
# and feature_dir back to session.json.
#
# Naming conventions
#   branch : <name>  →  <name>-YYYYMMDD  →  <name>-YYYYMMDD-2 …
#   folder : YYYYMMDD-<name>  →  YYYYMMDD-<name>-2 …  (date-prefix for dir sorting)

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

get_unique_branch_name() {
    local base="$1"

    # Collect all existing branch names starting with $base ONCE
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

    # 1. Clean base name — preferred; keeps branch list readable
    _bt "$base" || { echo "$base"; return; }
    # 2. Date suffix — clearly shows when the duplicate was created
    local ds; ds=$(date -u +"%Y%m%d")
    local dc="${base}-${ds}"
    _bt "$dc" || { echo "$dc"; return; }
    # 3. Same-day counter
    local n=2
    while true; do
        local c="${base}-${ds}-${n}"
        _bt "$c" || { echo "$c"; return; }
        n=$((n + 1))
    done
}

get_unique_folder_name() {
    local base="$1"
    # Folders are ALWAYS date-prefixed (YYYYMMDD-<name>) so ls specs/ sorts
    # chronologically. Collect only dirs sharing today's date prefix (once).
    local ds; ds=$(date -u +"%Y%m%d")
    local prefix="${ds}-${base}"

    local taken="" d
    for d in "$SPECS_DIR"/${prefix}*/; do
        [ -d "$d" ] || continue
        local n; n=$(basename "$d")
        taken="${taken}${n}"$'\n'
    done

    _ft() { printf '%s' "$taken" | grep -qxF -- "$1" 2>/dev/null; }

    # 1. Base date-prefixed name
    _ft "$prefix" || { echo "$prefix"; return; }
    # 2. Counter suffix
    local n=2
    while true; do
        local c="${prefix}-${n}"
        _ft "$c" || { echo "$c"; return; }
        n=$((n + 1))
    done
}

_sync_session() {
    local branch_name="$1" folder_name="$2"
    local mgr="$REPO_ROOT/.spec/scripts/bash/manage-session.sh"
    if [ ! -f "$mgr" ]; then
        log "manage-session.sh not found — skipping session update"
        return 0
    fi
    local patch="{\"branch_name\":\"${branch_name}\",\"feature_dir\":\"specs/${folder_name}\"}"
    bash "$mgr" --action update-multi --json-patch "$patch" 2>/dev/null || true
    log "Session updated: branch_name=${branch_name}  feature_dir=specs/${folder_name}"
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

# ─── Read session.json ───────────────────────────────────────────────────────
SESSION_FILE="$REPO_ROOT/.spec/session.json"
if [ ! -f "$SESSION_FILE" ]; then
    log "No session.json found — run spec.session init first"; exit 1
fi

if command -v jq >/dev/null 2>&1; then
    BASE_NAME=$(jq -r '.name // empty' "$SESSION_FILE" 2>/dev/null)
elif command -v python3 >/dev/null 2>&1; then
    BASE_NAME=$(python3 -c \
        "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('name',''))" \
        "$SESSION_FILE" 2>/dev/null)
fi

if [ -z "$BASE_NAME" ]; then
    log "session.json has no name — populate it before creating a feature"; exit 1
fi
log "Session name: '$BASE_NAME'"

# Current git branch
CURRENT_BRANCH=""
[ "$HAS_GIT" = true ] && CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
log "Current git branch: '${CURRENT_BRANCH:-none}'"

# ── Early-exit: session already resolved and environment matches ─────────────
if command -v jq >/dev/null 2>&1; then
    SESS_BRANCH=$(jq -r '.branch_name // empty' "$SESSION_FILE" 2>/dev/null)
    SESS_FDIR=$(jq -r '.feature_dir // empty'   "$SESSION_FILE" 2>/dev/null)
fi
if [ -n "$SESS_BRANCH" ] && [ -n "$SESS_FDIR" ]; then
    EXISTING_DIR="$REPO_ROOT/$SESS_FDIR"
    if [ "$CURRENT_BRANCH" = "$SESS_BRANCH" ] && [ -d "$EXISTING_DIR" ]; then
        log "Already on branch '$SESS_BRANCH' with feature dir '$SESS_FDIR' — nothing to do"
        _output "$SESS_BRANCH" "$EXISTING_DIR"
        exit 0
    fi
fi

# ─── Fetch remote refs so branch availability check is accurate ─────────────
if [ "$HAS_GIT" = true ] && [ "$DRY_RUN" != true ]; then
    git fetch --all --prune >/dev/null 2>&1 || true
fi

# ─── Resolve unique branch name and unique folder name (independent) ─────────
BRANCH_NAME=$(get_unique_branch_name "$BASE_NAME")
FOLDER_NAME=$(get_unique_folder_name "$BASE_NAME")

[ "$BRANCH_NAME" != "$BASE_NAME" ] && log "Branch '$BASE_NAME' taken — using '$BRANCH_NAME'"
log "Folder name: $FOLDER_NAME"

FEATURE_DIR="$SPECS_DIR/$FOLDER_NAME"
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

    _sync_session "$BRANCH_NAME" "$FOLDER_NAME"
else
    log "[dry-run] branch_name  → $BRANCH_NAME"
    log "[dry-run] feature_dir  → specs/$FOLDER_NAME"
    log "[dry-run] Would create branch and spec dir, then update session"
fi

_output "$BRANCH_NAME" "$FEATURE_DIR"

