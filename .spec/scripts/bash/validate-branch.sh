#!/usr/bin/env bash
# Validate current git branch follows feature branch naming conventions.
# Patterns: sequential (001-name) or timestamp (20260319-143022-name).
# Usage: validate-branch.sh [--json]
# Exit code 0 = valid feature branch, 1 = invalid/not a feature branch.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

JSON=false
[[ "${1:-}" == "--json" ]] && JSON=true

warn() {
  if $JSON; then
    echo "{\"valid\":false,\"reason\":\"$1\"}"
  else
    echo "[specify] Warning: $1"
  fi
}

# Check git
if ! command -v git &>/dev/null; then
  BRANCH="${SPECIFY_FEATURE:-}"
  if [[ -z "$BRANCH" ]]; then
    warn "Git not found and SPECIFY_FEATURE not set; skipped branch validation"
    exit 0
  fi
else
  if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    BRANCH="${SPECIFY_FEATURE:-}"
    if [[ -z "$BRANCH" ]]; then
      warn "Not inside a Git repository; skipped branch validation"
      exit 0
    fi
  else
    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "${SPECIFY_FEATURE:-}")
  fi
fi

SEQUENTIAL_RE='^[0-9]{3,}-'
TIMESTAMP_RE='^[0-9]{8}-[0-9]{6}-'

if [[ "$BRANCH" =~ $SEQUENTIAL_RE ]]; then
  PREFIX=$(echo "$BRANCH" | grep -oE '^[0-9]{3,}')
elif [[ "$BRANCH" =~ $TIMESTAMP_RE ]]; then
  PREFIX=$(echo "$BRANCH" | grep -oE '^[0-9]{8}-[0-9]{6}')
else
  if $JSON; then
    echo "{\"valid\":false,\"branch\":\"$BRANCH\",\"reason\":\"not-a-feature-branch\"}"
  else
    echo "[FAIL] Not on a feature branch. Current branch: $BRANCH"
    echo "Feature branches must be named like: 001-feature-name or 20260319-143022-feature-name"
  fi
  exit 1
fi

REPO_ROOT=$(get_repo_root)
SPEC_DIR=$(find "$REPO_ROOT/specs" -maxdepth 1 -type d -name "${PREFIX}-*" 2>/dev/null | head -1 || true)

if $JSON; then
  echo "{\"valid\":true,\"branch\":\"$BRANCH\",\"prefix\":\"$PREFIX\",\"spec_dir\":\"${SPEC_DIR:-}\"}"
else
  echo "[OK] On feature branch: $BRANCH"
  if [[ -n "$SPEC_DIR" ]]; then
    echo "[OK] Spec directory found: $SPEC_DIR"
  else
    echo "[WARN] No spec directory found for prefix $PREFIX"
  fi
fi
