#!/usr/bin/env python3
"""
detect_remote.py — Detect Git remote URL and parse GitHub owner/repo
(analogous to detect-remote.ps1).

Usage:
    python detect_remote.py [--json]

Exit code 0 always (graceful degradation when no remote).
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path


def _no_remote(reason: str, use_json: bool) -> None:
    """Emit a no-remote response and exit successfully."""
    if use_json:
        print(json.dumps({"has_remote": False, "is_github": False, "reason": reason}))
    else:
        print(f"[specify] {reason}", file=sys.stderr)
    sys.exit(0)


def main() -> None:
    """Detect remote.origin URL and parse GitHub owner/repo when possible."""
    parser = argparse.ArgumentParser(
        description="Detect Git remote URL and parse GitHub owner/repo."
    )
    parser.add_argument("--json", action="store_true", help="Output in JSON format")
    args = parser.parse_args()
    use_json: bool = args.json

    # Check git availability
    try:
        subprocess.run(["git", "--version"], capture_output=True, check=False)
    except FileNotFoundError:
        _no_remote("Git not found; cannot determine remote URL", use_json)

    # Check inside a git repo
    result = subprocess.run(
        ["git", "rev-parse", "--is-inside-work-tree"],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        _no_remote("Not inside a Git repository; cannot determine remote URL", use_json)

    # Get remote URL
    result = subprocess.run(
        ["git", "config", "--get", "remote.origin.url"],
        capture_output=True, text=True
    )
    remote_url = result.stdout.strip()
    if not remote_url:
        _no_remote("No remote.origin configured", use_json)

    is_github = False
    owner = ""
    repo  = ""

    # HTTPS: https://github.com/<owner>/<repo>[.git]
    https_match = re.match(r'^https://github\.com/([^/]+)/([^/]+?)(?:\.git)?$', remote_url)
    if https_match:
        is_github, owner, repo = True, https_match.group(1), https_match.group(2)
    else:
        # SSH: git@github.com:<owner>/<repo>[.git]
        ssh_match = re.match(r'^git@github\.com:([^/]+)/([^/]+?)(?:\.git)?$', remote_url)
        if ssh_match:
            is_github, owner, repo = True, ssh_match.group(1), ssh_match.group(2)

    if use_json:
        print(json.dumps({
            "has_remote": True,
            "is_github":  is_github,
            "remote_url": remote_url,
            "owner":      owner,
            "repo":       repo,
        }, ensure_ascii=False))
    else:
        print(f"Remote URL: {remote_url}")
        if is_github:
            print(f"GitHub repository: {owner}/{repo}")


if __name__ == "__main__":
    main()

