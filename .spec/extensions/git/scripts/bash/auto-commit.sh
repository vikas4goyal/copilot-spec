#!/usr/bin/env bash
# Git extension: auto-commit.sh
# Automatically stage and commit all changes using a pre-composed commit message.
# The commit message is passed directly by the caller (e.g., the spec.git.commit agent),
# which analyzes the actual git diff and selects the appropriate conventional-commit prefix.
#
# Usage: auto-commit.sh "<commit_message>"
#   e.g.: auto-commit.sh "feat: implement JWT-based user authentication"

set -e

COMMIT_MESSAGE="${1:-}"
if [ -z "$COMMIT_MESSAGE" ]; then
    echo "Usage: $0 \"<commit_message>\"" >&2
    exit 1
fi

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_find_project_root() {
    local dir="$1"
    while [ "$dir" != "/" ]; do
        if [ -d "$dir/.specify" ] || [ -d "$dir/.spec" ] || [ -d "$dir/.git" ]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

REPO_ROOT=$(_find_project_root "$SCRIPT_DIR") || REPO_ROOT="$(pwd)"
cd "$REPO_ROOT"

# Check if git is available
if ! command -v git >/dev/null 2>&1; then
    echo "[specify] Warning: Git not found; skipped auto-commit" >&2
    exit 0
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "[specify] Warning: Not a Git repository; skipped auto-commit" >&2
    exit 0
fi

# Check if there are changes to commit
if git diff --quiet HEAD 2>/dev/null && git diff --cached --quiet 2>/dev/null && [ -z "$(git ls-files --others --exclude-standard 2>/dev/null)" ]; then
    echo "[specify] No changes to commit" >&2
    exit 0
fi

# Stage and commit using the provided message
_git_out=$(git add . 2>&1) || { echo "[specify] Error: git add failed: $_git_out" >&2; exit 1; }
_git_out=$(git commit -q -m "$COMMIT_MESSAGE" 2>&1) || { echo "[specify] Error: git commit failed: $_git_out" >&2; exit 1; }

echo "✓ Committed: $COMMIT_MESSAGE" >&2
