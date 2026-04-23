#!/usr/bin/env bash
# Detect Git remote URL and parse GitHub owner/repo.
# Usage: detect-remote.sh [--json]
# Exit code 0 always (graceful degradation when no remote).
set -euo pipefail

JSON=false
[[ "${1:-}" == "--json" ]] && JSON=true

no_remote() {
  local reason="$1"
  if $JSON; then
    echo "{\"has_remote\":false,\"is_github\":false,\"reason\":\"$reason\"}"
  else
    echo "[specify] Warning: $reason"
  fi
  exit 0
}

command -v git &>/dev/null || no_remote "Git not found; cannot determine remote URL"
git rev-parse --is-inside-work-tree &>/dev/null || no_remote "Not inside a Git repository; cannot determine remote URL"

REMOTE_URL=$(git config --get remote.origin.url 2>/dev/null || true)
[[ -z "$REMOTE_URL" ]] && no_remote "No remote.origin configured"

# Parse HTTPS: https://github.com/<owner>/<repo>.git
# Parse SSH:   git@github.com:<owner>/<repo>.git
IS_GITHUB=false
OWNER=""
REPO=""

if [[ "$REMOTE_URL" =~ ^https://github\.com/([^/]+)/([^/]+?)(\.git)?$ ]]; then
  IS_GITHUB=true
  OWNER="${BASH_REMATCH[1]}"
  REPO="${BASH_REMATCH[2]}"
elif [[ "$REMOTE_URL" =~ ^git@github\.com:([^/]+)/([^/]+?)(\.git)?$ ]]; then
  IS_GITHUB=true
  OWNER="${BASH_REMATCH[1]}"
  REPO="${BASH_REMATCH[2]}"
fi

if $JSON; then
  echo "{\"has_remote\":true,\"is_github\":$IS_GITHUB,\"remote_url\":\"$REMOTE_URL\",\"owner\":\"$OWNER\",\"repo\":\"$REPO\"}"
else
  echo "Remote URL: $REMOTE_URL"
  if $IS_GITHUB; then
    echo "GitHub repository: $OWNER/$REPO"
  fi
fi
