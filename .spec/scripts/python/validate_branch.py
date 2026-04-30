#!/usr/bin/env python3
"""
validate_branch.py — Validate current git branch follows feature branch naming
conventions (analogous to validate-branch.ps1).

Patterns:
  sequential : 001-feature-name, 1234-feature-name  (3+ leading digits)
  timestamp  : 20260319-143022-feature-name

Usage:
    python validate_branch.py [--json]

Exit codes:
    0 = valid feature branch
    1 = invalid / not a feature branch
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path


def _no_branch(reason: str, use_json: bool) -> None:
    """Emit a graceful skip response and exit with code 0."""
    if use_json:
        print(json.dumps({"valid": False, "reason": reason}))
    else:
        print(f"[specify] {reason}", file=sys.stderr)
    sys.exit(0)   # graceful exit (exit 0 matches PS behaviour)


def main() -> None:
    """Validate feature branch naming and report matching spec directory."""
    parser = argparse.ArgumentParser(
        description="Validate current git branch follows feature branch naming conventions."
    )
    parser.add_argument("--json", action="store_true", help="Output in JSON format")
    args = parser.parse_args()
    use_json: bool = args.json

    # Resolve branch name
    branch: str | None = None
    git_available = True
    try:
        subprocess.run(["git", "--version"], capture_output=True, check=False)
    except FileNotFoundError:
        git_available = False

    if not git_available:
        branch = os.environ.get("SPECIFY_FEATURE", "").strip() or None
        if not branch:
            _no_branch(
                "Git not found and SPECIFY_FEATURE not set; skipped branch validation",
                use_json
            )
    else:
        result = subprocess.run(
            ["git", "rev-parse", "--is-inside-work-tree"],
            capture_output=True, text=True
        )
        if result.returncode != 0:
            branch = os.environ.get("SPECIFY_FEATURE", "").strip() or None
            if not branch:
                _no_branch("Not inside a Git repository; skipped branch validation", use_json)
        else:
            result2 = subprocess.run(
                ["git", "rev-parse", "--abbrev-ref", "HEAD"],
                capture_output=True, text=True
            )
            branch = result2.stdout.strip() or None

    if not branch:
        _no_branch("Could not determine branch name", use_json)

    sequential_re = r'^[0-9]{3,}-'
    timestamp_re  = r'^[0-9]{8}-[0-9]{6}-'

    prefix = ""
    if re.match(sequential_re, branch):
        sequential_prefix_match = re.match(r'^[0-9]{3,}', branch)
        prefix = sequential_prefix_match.group(0) if sequential_prefix_match else ""
    elif re.match(timestamp_re, branch):
        timestamp_prefix_match = re.match(r'^[0-9]{8}-[0-9]{6}', branch)
        prefix = timestamp_prefix_match.group(0) if timestamp_prefix_match else ""
    else:
        if use_json:
            print(json.dumps({
                "valid":  False,
                "branch": branch,
                "reason": "not-a-feature-branch",
            }))
        else:
            print(f"[FAIL] Not on a feature branch. Current branch: {branch}")
            print(
                "Feature branches must be named like: "
                "001-feature-name or 20260319-143022-feature-name"
            )
        sys.exit(1)

    # Find spec directory
    script_dir = Path(__file__).parent
    repo_root  = script_dir.parents[2]         # .spec/scripts/python → repo root
    specs_dir  = repo_root / "specs"
    spec_dir   = ""
    if specs_dir.is_dir():
        match = next(
            (d for d in specs_dir.iterdir() if d.is_dir() and d.name.startswith(f"{prefix}-")),
            None
        )
        if match:
            spec_dir = str(match)

    if use_json:
        print(json.dumps({
            "valid":    True,
            "branch":   branch,
            "prefix":   prefix,
            "spec_dir": spec_dir,
        }))
    else:
        print(f"[OK] On feature branch: {branch}")
        if spec_dir:
            print(f"[OK] Spec directory found: {spec_dir}")
        else:
            print(f"[WARN] No spec directory found for prefix {prefix}")


if __name__ == "__main__":
    main()

