#!/usr/bin/env python3
"""
initialize_repo.py — Initialize a Git repository with an initial commit
(analogous to initialize-repo.ps1).

Customizable: extend this script to add .gitignore templates, default branch
config, git-flow, LFS, signing, etc.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path


def _log(msg: str) -> None:
    print(f"[initialize-repo] {msg}")


def find_project_root(start_dir: str) -> str | None:
    """Search upward for .spec or .git to locate the project root."""
    _log(f"Searching for project root from: {start_dir}")
    current = Path(start_dir).resolve()
    while True:
        _log(f"Inspecting directory for project markers: {current}")
        for marker in (".spec", ".git"):
            if (current / marker).exists():
                _log(f"Found project marker '{marker}' in: {current}")
                return str(current)
        parent = current.parent
        if parent == current:
            _log("Reached filesystem root without finding a project marker")
            return None
        current = parent


def _run(cmd: list[str], cwd: str) -> tuple[int, str]:
    result = subprocess.run(cmd, capture_output=True, text=True, cwd=cwd)
    return result.returncode, (result.stdout + result.stderr).strip()


def main() -> None:
    script_dir = Path(__file__).parent

    repo_root = find_project_root(str(script_dir))
    if not repo_root:
        _log("Project root not found from script path; falling back to current working directory")
        import os
        repo_root = os.getcwd()
    else:
        _log(f"Using discovered project root: {repo_root}")

    _log(f"Changed working directory to: {repo_root}")

    commit_msg = "[Spec] Initial commit"
    _log(f"Final commit message: {commit_msg}")

    # Check git availability
    try:
        subprocess.run(["git", "--version"], capture_output=True, check=False)
    except FileNotFoundError:
        _log("Git executable not found; exiting without initializing repository")
        print("[spec] Warning: Git not found; skipped repository initialization", file=sys.stderr)
        sys.exit(0)

    _log("Git executable found")

    # Check if already a git repo
    rc, _ = _run(["git", "rev-parse", "--is-inside-work-tree"], repo_root)
    if rc == 0:
        _log("Repository already initialized; exiting early")
        print("[spec] Git repository already initialized; skipping", file=sys.stderr)
        sys.exit(0)
    _log("Current directory is not an initialized Git repository")

    # Initialize
    rc, out = _run(["git", "init", "-q"], repo_root)
    if rc != 0:
        _log("Repository initialization failed; exiting with error")
        print(f"[spec] Error: git init failed: {out}", file=sys.stderr)
        sys.exit(1)
    _log("git init completed successfully")

    rc, out = _run(["git", "add", "."], repo_root)
    if rc != 0:
        _log("Repository initialization failed; exiting with error")
        print(f"[spec] Error: git add failed: {out}", file=sys.stderr)
        sys.exit(1)
    _log("git add completed successfully")

    rc, out = _run(["git", "commit", "--allow-empty", "-q", "-m", commit_msg], repo_root)
    if rc != 0:
        _log("Repository initialization failed; exiting with error")
        print(f"[spec] Error: git commit failed: {out}", file=sys.stderr)
        sys.exit(1)
    _log("git commit completed successfully")

    _log("Repository initialization flow completed")
    print("[OK] Git repository initialized")


if __name__ == "__main__":
    main()

