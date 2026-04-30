#!/usr/bin/env python3
"""
common.py — Common utility functions analogous to common.ps1 / common.sh.
Import this module from other scripts: from common import get_repo_root, ...
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Optional


# ---------------------------------------------------------------------------
# Repository root detection
# ---------------------------------------------------------------------------

def find_specify_root(start_dir: Optional[str] = None) -> Optional[str]:
    """Search upward for a .specs directory (spec-kit's primary marker)."""
    current = Path(start_dir).resolve() if start_dir else Path.cwd().resolve()
    while True:
        if (current / ".specs").is_dir():
            return str(current)
        parent = current.parent
        if parent == current:
            return None
        current = parent


def get_repo_root() -> str:
    """
    Return the repository root, prioritising .specs over git.
    Falls back to the script location (../../..) for non-git repos.
    """
    # 1. .specs directory marker
    specify_root = find_specify_root()
    if specify_root:
        return specify_root

    # 2. git fallback
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True, text=True
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except FileNotFoundError:
        pass

    # 3. Relative to this script: scripts/python → repo root is ../../../
    return str(Path(__file__).resolve().parents[3])


# ---------------------------------------------------------------------------
# Git helpers
# ---------------------------------------------------------------------------

def has_git_command() -> bool:
    """Return True if the git executable is available on PATH."""
    try:
        subprocess.run(["git", "--version"], capture_output=True)
        return True
    except FileNotFoundError:
        return False


def test_has_git(repo_root: Optional[str] = None) -> bool:
    """
    Return True only if git is installed AND the repo_root is inside a git
    work tree.  Handles regular repos, worktrees, and submodules (.git file).
    """
    if not has_git_command():
        return False
    root = repo_root or get_repo_root()
    git_path = Path(root) / ".git"
    if not git_path.exists():
        return False
    try:
        result = subprocess.run(
            ["git", "-C", root, "rev-parse", "--is-inside-work-tree"],
            capture_output=True, text=True
        )
        return result.returncode == 0
    except FileNotFoundError:
        return False


def get_current_branch(repo_root: Optional[str] = None) -> str:
    """
    Return the current git branch name (or logical feature name for non-git repos).
    Priority:
      1. SPECIFY_FEATURE env var
      2. git rev-parse (if available)
      3. Latest feature directory (timestamp- or sequential-prefixed)
      4. 'main'
    """
    # 1. Env override
    env_branch = os.environ.get("SPECIFY_FEATURE", "").strip()
    if env_branch:
        return env_branch

    root = repo_root or get_repo_root()

    # 2. git
    if test_has_git(root):
        try:
            result = subprocess.run(
                ["git", "-C", root, "rev-parse", "--abbrev-ref", "HEAD"],
                capture_output=True, text=True
            )
            if result.returncode == 0:
                return result.stdout.strip()
        except FileNotFoundError:
            pass

    # 3. Latest feature directory
    specs_dir = Path(root) / "specs"
    if specs_dir.is_dir():
        latest_feature = ""
        highest_seq = 0
        latest_ts = ""
        for feature_path in specs_dir.iterdir():
            if not feature_path.is_dir():
                continue
            feature_name = feature_path.name
            timestamp_match = re.match(r'^(\d{8}-\d{6})-', feature_name)
            sequence_match = re.match(r'^(\d{3,})-', feature_name)
            if timestamp_match:
                timestamp_prefix = timestamp_match.group(1)
                if timestamp_prefix > latest_ts:
                    latest_ts = timestamp_prefix
                    latest_feature = feature_name
            elif sequence_match and not latest_ts:
                sequence_number = int(sequence_match.group(1))
                if sequence_number > highest_seq:
                    highest_seq = sequence_number
                    latest_feature = feature_name
        if latest_feature:
            return latest_feature

    return "main"


# ---------------------------------------------------------------------------
# Branch validation
# ---------------------------------------------------------------------------

def test_feature_branch(branch: str, has_git: bool = True) -> bool:
    """
    Validate that *branch* follows feature-branch naming conventions.
    Returns True if valid, False otherwise (prints error to stdout).
    """
    if not has_git:
        print(
            "[specify] Warning: Git repository not detected; skipped branch validation",
            file=sys.stderr
        )
        return True

    # Exclude malformed timestamps (7- or 8-digit date + 6-digit time with no slug)
    malformed = bool(
        re.match(r'^[0-9]{7}-[0-9]{6}-', branch) or
        re.match(r'^(?:\d{7}|\d{8})-\d{6}$', branch)
    )
    is_sequential = bool(re.match(r'^[0-9]{3,}-', branch)) and not malformed
    is_timestamp  = bool(re.match(r'^\d{8}-\d{6}-', branch))

    if not is_sequential and not is_timestamp:
        print(f"ERROR: Not on a feature branch. Current branch: {branch}")
        print(
            "Feature branches should be named like: "
            "001-feature-name, 1234-feature-name, or 20260319-143022-feature-name"
        )
        return False
    return True


# ---------------------------------------------------------------------------
# Feature path helpers
# ---------------------------------------------------------------------------

def get_feature_dir(repo_root: str, branch: str) -> str:
    """Return the default feature directory path for a given branch name."""
    return str(Path(repo_root) / "specs" / branch)


def get_feature_paths_env() -> dict:
    """
    Return a dict with all canonical feature path variables.
    Mirrors the PSCustomObject returned by Get-FeaturePathsEnv in common.ps1.
    """
    repo_root      = get_repo_root()
    current_branch = get_current_branch(repo_root)
    has_git_val    = test_has_git(repo_root)

    # Resolve feature directory — priority:
    #   1. SPECIFY_FEATURE_DIRECTORY env var
    #   2. .specs/feature.json  "feature_directory" key
    #   3. specs/<branch> (legacy fallback)
    feature_json_path = Path(repo_root) / ".specs" / "feature.json"
    feature_dir: Optional[str] = None

    env_feat_dir = os.environ.get("SPECIFY_FEATURE_DIRECTORY", "").strip()
    if env_feat_dir:
        feature_dir = (
            env_feat_dir if Path(env_feat_dir).is_absolute()
            else str(Path(repo_root) / env_feat_dir)
        )
    elif feature_json_path.exists():
        try:
            feature_config = json.loads(feature_json_path.read_text(encoding="utf-8"))
            feature_directory_value = feature_config.get("feature_directory", "")
            if feature_directory_value:
                feature_dir = (
                    feature_directory_value
                    if Path(feature_directory_value).is_absolute()
                    else str(Path(repo_root) / feature_directory_value)
                )
        except Exception:
            pass

    if feature_dir is None:
        feature_dir = get_feature_dir(repo_root, current_branch)

    feature_path = Path(feature_dir)
    return {
        "REPO_ROOT":      repo_root,
        "CURRENT_BRANCH": current_branch,
        "HAS_GIT":        has_git_val,
        "FEATURE_DIR":    str(feature_path),
        "FEATURE_SPEC":   str(feature_path / "spec.md"),
        "IMPL_PLAN":      str(feature_path / "plan.md"),
        "TASKS":          str(feature_path / "tasks.md"),
        "RESEARCH":       str(feature_path / "research.md"),
        "DATA_MODEL":     str(feature_path / "data-model.md"),
        "QUICKSTART":     str(feature_path / "quickstart.md"),
        "CONTRACTS_DIR":  str(feature_path / "contracts"),
    }


# ---------------------------------------------------------------------------
# File / directory existence reporters
# ---------------------------------------------------------------------------

def test_file_exists(path: str, description: str) -> bool:
    """Print a status line and return whether a file exists at *path*."""
    if Path(path).is_file():
        print(f"  [OK] {description}")
        return True
    print(f"  [FAIL] {description}")
    return False


def test_dir_has_files(path: str, description: str) -> bool:
    """Print a status line and return whether a directory contains files."""
    directory_path = Path(path)
    if directory_path.is_dir() and any(entry.is_file() for entry in directory_path.iterdir()):
        print(f"  [OK] {description}")
        return True
    print(f"  [FAIL] {description}")
    return False


# ---------------------------------------------------------------------------
# Template resolution
# ---------------------------------------------------------------------------

def resolve_template(template_name: str, repo_root: str) -> Optional[str]:
    """
    Resolve a template name to a file path using the priority stack:
      1. .specs/templates/overrides/
      2. .specs/presets/<preset-id>/templates/  (sorted by priority from .registry)
      3. .specs/extensions/<ext-id>/templates/
      4. .specs/templates/  (core)
    Returns the absolute path string, or None if not found.
    """
    base = Path(repo_root) / ".specs" / "templates"

    # Priority 1: Project overrides
    override = base / "overrides" / f"{template_name}.md"
    if override.exists():
        return str(override)

    # Priority 2: Installed presets sorted by priority
    presets_dir = Path(repo_root) / ".specs" / "presets"
    if presets_dir.is_dir():
        sorted_presets: list[str] = []
        registry_file = presets_dir / ".registry"
        if registry_file.exists():
            try:
                registry_data = json.loads(registry_file.read_text(encoding="utf-8"))
                presets = registry_data.get("presets", {})
                sorted_presets = sorted(
                    presets.keys(),
                    key=lambda k: presets[k].get("priority", 10) if isinstance(presets[k], dict) else 10,
                )
            except Exception:
                sorted_presets = []

        if not sorted_presets:
            sorted_presets = sorted(
                d.name for d in presets_dir.iterdir()
                if d.is_dir() and not d.name.startswith(".")
            )

        for preset_id in sorted_presets:
            candidate = presets_dir / preset_id / "templates" / f"{template_name}.md"
            if candidate.exists():
                return str(candidate)

    # Priority 3: Extension-provided templates
    ext_dir = Path(repo_root) / ".specs" / "extensions"
    if ext_dir.is_dir():
        for ext in sorted(
            (d for d in ext_dir.iterdir() if d.is_dir() and not d.name.startswith(".")),
            key=lambda d: d.name,
        ):
            candidate = ext / "templates" / f"{template_name}.md"
            if candidate.exists():
                return str(candidate)

    # Priority 4: Core templates
    core = base / f"{template_name}.md"
    if core.exists():
        return str(core)

    return None

