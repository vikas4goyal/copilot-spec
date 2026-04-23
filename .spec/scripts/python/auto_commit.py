#!/usr/bin/env python3
"""
auto_commit.py — Stage all changes and commit (analogous to auto-commit.ps1).

Usage:
    python auto_commit.py --commit-message "Subject line\n\nBody text"
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

# Allow running directly without installing the package
sys.path.insert(0, str(Path(__file__).parent))
from common import get_repo_root  # noqa: E402


def _run(cmd: list[str], cwd: str) -> tuple[int, str]:
    result = subprocess.run(cmd, capture_output=True, text=True, cwd=cwd)
    return result.returncode, (result.stdout + result.stderr).strip()


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Stage all changes and commit with the supplied message."
    )
    parser.add_argument(
        "--commit-message", "-m",
        required=True,
        help="Commit message (subject + optional body separated by \\n\\n)"
    )
    args = parser.parse_args()
    commit_message: str = args.commit_message

    repo_root = get_repo_root()

    # Require git
    rc, _ = _run(["git", "--version"], repo_root)
    if rc != 0:
        print("[auto-commit] Git not found; skipping commit.", file=sys.stderr)
        sys.exit(0)

    # Require a git repo
    rc, _ = _run(["git", "rev-parse", "--is-inside-work-tree"], repo_root)
    if rc != 0:
        print("[auto-commit] Not a Git repository; skipping commit.", file=sys.stderr)
        sys.exit(0)

    # Nothing to commit?
    rc_diff, _ = _run(["git", "diff", "--quiet", "HEAD"], repo_root)
    rc_cached, _ = _run(["git", "diff", "--cached", "--quiet"], repo_root)
    rc_untracked, untracked = _run(
        ["git", "ls-files", "--others", "--exclude-standard"], repo_root
    )

    if rc_diff == 0 and rc_cached == 0 and not untracked.strip():
        print("[auto-commit] Nothing to commit.")
        sys.exit(0)

    # Stage
    rc, out = _run(["git", "add", "."], repo_root)
    if rc != 0:
        print(f"[auto-commit] git add failed: {out}", file=sys.stderr)
        sys.exit(1)

    # Commit
    rc, out = _run(["git", "commit", "-m", commit_message], repo_root)
    if rc != 0:
        print(f"[auto-commit] git commit failed: {out}", file=sys.stderr)
        sys.exit(1)

    print("[auto-commit] Committed successfully.")


if __name__ == "__main__":
    main()

