#!/usr/bin/env bash
# Git extension: initialize-repo.sh
# Initialize a Git repository with an initial commit.
# Customizable — replace this script to add .gitignore templates,
# default branch config, git-flow, LFS, signing, etc.

set -e

log() {
    echo "[spec] $1" >&2
}

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log "Script directory resolved to: $SCRIPT_DIR"

# Find project root
_find_project_root() {
    local dir="$1"
    log "Searching for project root from: $dir"
    while [ "$dir" != "/" ]; do
        log "Inspecting directory for project markers: $dir"
        if [ -d "$dir/.spec" ] || [ -d "$dir/.git" ]; then
            log "Found project marker in: $dir"
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    log "Reached filesystem root without finding a project marker"
    return 1
}

if REPO_ROOT=$(_find_project_root "$SCRIPT_DIR"); then
    log "Using discovered project root: $REPO_ROOT"
else
    REPO_ROOT="$(pwd)"
    log "Project root not found from script path; falling back to current working directory: $REPO_ROOT"
fi
cd "$REPO_ROOT"
log "Changed working directory to: $REPO_ROOT"

# Read commit message from extension config, fall back to default
COMMIT_MSG="[Spec] Initial commit"
#_config_file="$REPO_ROOT/.spec/git-config.yml"
#if [ -f "$_config_file" ]; then
#    log "Found git config file: $_config_file"
#    _msg=$(grep '^init_commit_message:' "$_config_file" 2>/dev/null | sed 's/^init_commit_message:[[:space:]]*//' | sed 's/^["'\'']//' | sed 's/["'\'']*$//')
#    if [ -n "$_msg" ]; then
#        COMMIT_MSG="$_msg"
#        log "Using init commit message from config"
#    else
#        if grep -q '^init_commit_message:' "$_config_file" 2>/dev/null; then
#            log "Config init commit message was empty; using default message"
#        else
#            log "Config file did not define init_commit_message; using default message"
#        fi
#    fi
#else
#    log "Git config file not found; using default commit message"
#fi
log "Final commit message: $COMMIT_MSG"

# Check if git is available
if ! command -v git >/dev/null 2>&1; then
    log "Git executable not found; exiting without initializing repository"
    echo "[spec] Warning: Git not found; skipped repository initialization" >&2
    exit 0
fi
log "Git executable found"

# Check if already a git repo
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    log "Repository already initialized; exiting early"
    echo "[spec] Git repository already initialized; skipping" >&2
    exit 0
fi
log "Current directory is not an initialized Git repository"

# Initialize
log "Running: git init -q"
_git_out=$(git init -q 2>&1) || { echo "[spec] Error: git init failed: $_git_out" >&2; exit 1; }
log "git init completed successfully"
log "Running: git add ."
_git_out=$(git add . 2>&1) || { echo "[spec] Error: git add failed: $_git_out" >&2; exit 1; }
log "git add completed successfully"
log "Running: git commit --allow-empty -q -m <message>"
_git_out=$(git commit --allow-empty -q -m "$COMMIT_MSG" 2>&1) || { echo "[spec] Error: git commit failed: $_git_out" >&2; exit 1; }
log "git commit completed successfully"

log "Repository initialization flow completed"
echo "✓ Git repository initialized" >&2
