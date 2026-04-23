#!/usr/bin/env bash
# Finalize a spec feature release: push branch + archive session + (optionally) switch to base.
# Usage: release-feature.sh [--stay-on-branch]
# Does NOT commit — assumes the caller (spec.release agent) has already committed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

STAY_ON_BRANCH=false
[[ "${1:-}" == "--stay-on-branch" ]] && STAY_ON_BRANCH=true

REPO_ROOT=$(get_repo_root)
SESSION_FILE="$REPO_ROOT/.spec/session.json"

if [[ ! -f "$SESSION_FILE" ]]; then
  echo "[release] No active session found. Nothing to release."
  exit 0
fi

# Extract branch_name and base_branch from session.json (jq or python3)
read_json() {
  local path="$1"
  if command -v jq &>/dev/null; then
    jq -r "$path // empty" "$SESSION_FILE"
  else
    python3 -c "
import json,sys
d = json.load(open(sys.argv[1]))
parts = sys.argv[2].replace('.','').split('.') if False else '$path'.lstrip('.').split('.')
for p in parts:
    if isinstance(d, dict): d = d.get(p, '')
    else: d = ''
print(d or '')
" "$SESSION_FILE"
  fi
}

BRANCH_NAME=$(read_json '.branch_name')
[[ -z "$BRANCH_NAME" ]] && BRANCH_NAME=$(read_json '.feature.branch_name')
BASE_BRANCH=$(read_json '.git.base_branch')

if [[ -z "$BRANCH_NAME" ]]; then
  echo "[release] Error: could not determine branch_name from session.json" >&2
  exit 1
fi

# Push branch to origin
if command -v git &>/dev/null && git -C "$REPO_ROOT" rev-parse --is-inside-work-tree &>/dev/null; then
  if git -C "$REPO_ROOT" config --get remote.origin.url &>/dev/null; then
    echo "[release] Pushing branch: $BRANCH_NAME"
    if ! git -C "$REPO_ROOT" push origin "$BRANCH_NAME" --set-upstream; then
      echo "[release] Warning: push failed; continuing with archive"
    fi
  else
    echo "[release] No remote 'origin' found — skipping push. Branch is available locally only."
  fi
else
  echo "[release] Git not available — skipping push."
fi

# Archive session
bash "$SCRIPT_DIR/manage-session.sh" --action archive

# Switch to base branch (unless --stay-on-branch)
if ! $STAY_ON_BRANCH && [[ -n "$BASE_BRANCH" && "$BASE_BRANCH" != "$BRANCH_NAME" ]]; then
  if command -v git &>/dev/null && git -C "$REPO_ROOT" rev-parse --is-inside-work-tree &>/dev/null; then
    git -C "$REPO_ROOT" checkout "$BASE_BRANCH" && echo "[release] Switched to base branch: $BASE_BRANCH"
  fi
fi

echo "[release] Done. Branch: $BRANCH_NAME  Base: ${BASE_BRANCH:-<none>}"
