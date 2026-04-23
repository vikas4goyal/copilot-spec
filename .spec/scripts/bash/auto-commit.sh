#!/usr/bin/env bash
# auto-commit.sh
# Stage all changes and commit with the message supplied by the caller (spec.git.commit agent).
#
# Usage: auto-commit.sh "<subject line>\n\n<body>"

set -e

COMMIT_MESSAGE="${1:-}"
if [ -z "$COMMIT_MESSAGE" ]; then
    echo "[auto-commit] Error: commit message is required." >&2
    exit 1
fi

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_find_project_root() {
    local dir="$1"
    while [ "$dir" != "/" ]; do
        if [ -d "$dir/.spec" ] || [ -d "$dir/.git" ]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

REPO_ROOT=$(_find_project_root "$SCRIPT_DIR") || REPO_ROOT="$(pwd)"
cd "$REPO_ROOT"

# Require git
if ! command -v git >/dev/null 2>&1; then
    echo "[auto-commit] Git not found; skipping commit." >&2
    exit 0
fi

# Require a git repo
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "[auto-commit] Not a Git repository; skipping commit." >&2
    exit 0
fi

# Nothing to commit?
if git diff --quiet HEAD 2>/dev/null \
   && git diff --cached --quiet 2>/dev/null \
   && [ -z "$(git ls-files --others --exclude-standard 2>/dev/null)" ]; then
    echo "[auto-commit] Nothing to commit." >&2
    exit 0
fi

# Stage and commit
git add . || { echo "[auto-commit] Error: git add failed." >&2; exit 1; }
git commit -m "$COMMIT_MESSAGE" || { echo "[auto-commit] Error: git commit failed." >&2; exit 1; }

echo "[auto-commit] Committed successfully." >&2
