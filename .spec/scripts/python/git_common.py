#!/usr/bin/env python3
"""
git_common.py — Git-specific common functions (analogous to git-common.ps1).
Extracted subset: branch validation and detection logic used by the git extension.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Optional


def test_has_git(repo_root: Optional[str] = None) -> bool:
    """
    Return True only if git is installed AND repo_root is inside a git work tree.
    Handles regular repos (.git directory) and worktrees/submodules (.git file).
    """
    try:
        subprocess.run(["git", "--version"], capture_output=True, check=False)
    except FileNotFoundError:
        return False

    root = repo_root or os.getcwd()
    if not (Path(root) / ".git").exists():
        return False
    try:
        result = subprocess.run(
            ["git", "-C", root, "rev-parse", "--is-inside-work-tree"],
            capture_output=True, text=True
        )
        return result.returncode == 0
    except FileNotFoundError:
        return False


def get_spec_kit_effective_branch_name(branch: str) -> str:
    """
    Strip a remote prefix (e.g. 'origin/feature-x' → 'feature-x').
    For branch names without a slash the input is returned unchanged.
    """
    branch_with_remote_match = re.match(r'^([^/]+)/([^/]+)$', branch)
    return branch_with_remote_match.group(2) if branch_with_remote_match else branch


def test_feature_branch(branch: str, has_git: bool = True) -> bool:
    """
    Validate that *branch* follows feature-branch naming conventions.
    Returns True if valid, False otherwise (prints error to stderr).
    """
    if not has_git:
        print(
            "[specify] Warning: Git repository not detected; skipped branch validation",
            file=sys.stderr
        )
        return True

    original_branch = branch
    branch = get_spec_kit_effective_branch_name(branch)

    # Exclude malformed timestamps (7- or 8-digit date + 6-digit time, no trailing slug)
    malformed = bool(
        re.match(r'^[0-9]{7}-[0-9]{6}-', branch) or
        re.match(r'^(?:\d{7}|\d{8})-\d{6}$', branch)
    )
    is_sequential = bool(re.match(r'^[0-9]{3,}-', branch)) and not malformed
    is_timestamp  = bool(re.match(r'^\d{8}-\d{6}-', branch))

    if not is_sequential and not is_timestamp:
        print(
            f"ERROR: Not on a feature branch. Current branch: {original_branch}",
            file=sys.stderr
        )
        print(
            "Feature branches should be named like: "
            "001-feature-name, 1234-feature-name, or 20260319-143022-feature-name",
            file=sys.stderr
        )
        return False
    return True

