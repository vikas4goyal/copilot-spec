#!/usr/bin/env python3
"""
create_new_feature.py — Bootstrap a new feature: derives branch/folder names,
creates the git branch and specs/YYYYMMDD-<name>/ directory, and keeps
session.json in sync (analogous to create-new-feature.ps1).

Naming conventions
  branch  : <name>  →  <name>-YYYYMMDD  →  <name>-YYYYMMDD-2 …
  folder  : YYYYMMDD-<name>  →  YYYYMMDD-<name>-2 …  (date-prefix for dir sorting)

Usage:
    python create_new_feature.py --name "oauth2-login" --description "Implements OAuth2 login"
                                  [--agent-name "spec.specify"] [--json] [--dry-run]
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from common import get_repo_root, test_has_git, resolve_template  # noqa: E402

SCRIPT_DIR = Path(__file__).parent


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _run_manage(args: list[str], capture: bool = False):
    """Run manage_session.py and return (returncode, stdout)."""
    cmd = [sys.executable, str(SCRIPT_DIR / "manage_session.py")] + args
    if capture:
        result = subprocess.run(cmd, capture_output=True, text=True)
        return result.returncode, result.stdout.strip()
    rc = subprocess.run(cmd).returncode
    return rc, ""


def _log(msg: str) -> None:
    print(f"[feature] {msg}")


def _git_run(args: list[str], repo_root: str, capture: bool = False):
    cmd = ["git", "-C", repo_root] + args
    if capture:
        result = subprocess.run(cmd, capture_output=True, text=True)
        return result.returncode, result.stdout.strip()
    rc = subprocess.run(cmd, capture_output=True).returncode
    return rc, ""


# ---------------------------------------------------------------------------
# Unique name generators
# ---------------------------------------------------------------------------

def get_unique_branch_name(base: str, repo_root: str, has_git: bool) -> str:
    taken: set[str] = set()
    if has_git:
        rc, out = _git_run(["branch", "--list", f"{base}*"], repo_root, capture=True)
        if rc == 0:
            for line in out.splitlines():
                taken.add(line.strip().lstrip("*").strip())
        rc, out = _git_run(["branch", "-r", "--list", f"*/{base}*"], repo_root, capture=True)
        if rc == 0:
            for line in out.splitlines():
                taken.add(line.strip().split("/")[-1])

    if base not in taken:
        return base
    ds = datetime.now().strftime("%Y%m%d")
    dc = f"{base}-{ds}"
    if dc not in taken:
        return dc
    n = 2
    while True:
        c = f"{base}-{ds}-{n}"
        if c not in taken:
            return c
        n += 1


def get_unique_folder_name(base: str, specs_dir: Path) -> str:
    ds     = datetime.now().strftime("%Y%m%d")
    prefix = f"{ds}-{base}"
    taken: set[str] = set()
    if specs_dir.is_dir():
        for d in specs_dir.iterdir():
            if d.is_dir() and d.name.startswith(prefix):
                taken.add(d.name)
    if prefix not in taken:
        return prefix
    n = 2
    while True:
        c = f"{prefix}-{n}"
        if c not in taken:
            return c
        n += 1


# ---------------------------------------------------------------------------
# Output helper
# ---------------------------------------------------------------------------

def write_result(branch: str, feat_dir: str, use_json: bool) -> None:
    if use_json:
        print(json.dumps({
            "BRANCH_NAME": branch,
            "FEATURE_DIR": feat_dir,
            "SPEC_FILE":   f"{feat_dir}/spec.md",
        }, ensure_ascii=False))
    else:
        print(f"BRANCH_NAME: {branch}")
        print(f"FEATURE_DIR: {feat_dir}")
        print(f"SPEC_FILE:   {feat_dir}/spec.md")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Bootstrap a new feature branch and spec directory."
    )
    parser.add_argument("--name",        default="", help="Feature name slug (e.g. oauth2-login-google)")
    parser.add_argument("--description", default="", help="One-line feature description")
    parser.add_argument("--agent-name",  default="", help="Calling agent to record in session")
    parser.add_argument("--json",        action="store_true", help="Output JSON")
    parser.add_argument("--dry-run",     action="store_true", help="Compute names without creating anything")
    args = parser.parse_args()

    repo_root  = get_repo_root()
    has_git    = test_has_git(repo_root)
    specs_dir  = Path(repo_root) / "specs"

    if not args.dry_run:
        specs_dir.mkdir(parents=True, exist_ok=True)

    # ── Session bootstrap ────────────────────────────────────────────────────
    if not args.dry_run:
        init_args = ["--action", "init"]
        if args.name:        init_args += ["--name",        args.name]
        if args.description: init_args += ["--description", args.description]
        rc, _ = _run_manage(init_args)
        if rc != 0:
            sys.exit(rc)

    # Read current session values
    base_name     = ""
    sess_branch   = ""
    sess_feat_dir = ""

    rc, raw = _run_manage(["--action", "get-multi", "--fields", "name,branch_name,feature_dir"], capture=True)
    if rc == 0 and raw:
        try:
            sess_data     = json.loads(raw)
            base_name     = sess_data.get("name", "") or ""
            sess_branch   = sess_data.get("branch_name", "") or ""
            sess_feat_dir = sess_data.get("feature_dir", "") or ""
        except Exception:
            pass

    if not base_name:
        base_name = args.name
    if not base_name:
        msg = (
            "ERROR: No active session and --name not provided. Pass --name <slug> for dry-run."
            if args.dry_run else
            "ERROR: Feature name is not set. Pass --name <slug> to provide one."
        )
        _log(msg)
        sys.exit(1)

    _log(f"Session name: {base_name}")

    # Current git branch
    current_branch = ""
    if has_git:
        rc, cb = _git_run(["rev-parse", "--abbrev-ref", "HEAD"], repo_root, capture=True)
        if rc == 0:
            current_branch = cb
    _log(f"Current git branch: {current_branch or 'none'}")

    # ── Idempotency check ────────────────────────────────────────────────────
    if sess_branch and sess_feat_dir:
        existing_dir = Path(repo_root) / sess_feat_dir if not Path(sess_feat_dir).is_absolute() else Path(sess_feat_dir)
        if current_branch == sess_branch and existing_dir.is_dir():
            _log(f"Already on branch '{sess_branch}' with feature dir '{sess_feat_dir}' — nothing to do")
            write_result(sess_branch, str(existing_dir), args.json)
            sys.exit(0)
        if current_branch and current_branch != sess_branch:
            _log(f"ERROR: Session expects branch '{sess_branch}' but current git branch is '{current_branch}'.")
            _log(f"       Switch to the correct branch  →  git checkout {sess_branch}")
            _log("       Or release the current feature first  →  /spec.release")
            sys.exit(1)

    # Fetch remote refs
    if has_git and not args.dry_run:
        subprocess.run(["git", "-C", repo_root, "fetch", "--all", "--prune"],
                       capture_output=True)

    # ── Resolve unique names ─────────────────────────────────────────────────
    branch_name = get_unique_branch_name(base_name, repo_root, has_git)
    folder_name = get_unique_folder_name(base_name, specs_dir)

    if branch_name != base_name:
        _log(f"Branch '{base_name}' taken — using '{branch_name}'")
    _log(f"Folder name: {folder_name}")

    feature_dir = specs_dir / folder_name
    spec_file   = feature_dir / "spec.md"

    # ── Create branch and spec dir ───────────────────────────────────────────
    if not args.dry_run:
        if has_git:
            _log(f"Creating git branch '{branch_name}'...")
            rc, _ = _git_run(["checkout", "-q", "-b", branch_name], repo_root)
            if rc != 0:
                rc2, _ = _git_run(["checkout", "-q", branch_name], repo_root)
                if rc2 != 0:
                    _log(f"ERROR: Failed to create or checkout '{branch_name}'")
                    sys.exit(1)
                _log(f"Switched to existing branch '{branch_name}'")
            else:
                _log(f"Branch '{branch_name}' created and checked out")
        else:
            _log("No git repo — skipping branch creation")

        feature_dir.mkdir(parents=True, exist_ok=True)

        if not spec_file.exists():
            tmpl = resolve_template("spec-template", repo_root)
            if tmpl and Path(tmpl).exists():
                import shutil
                shutil.copy2(tmpl, spec_file)
                _log(f"Spec file created from template: {spec_file}")
            else:
                spec_file.touch()
                _log(f"Spec file created (empty): {spec_file}")
        else:
            _log(f"Spec file already exists: {spec_file}")

        # Write branch_name and feature_dir back to session
        patch = json.dumps({
            "branch_name": branch_name,
            "feature_dir": f"specs/{folder_name}",
        })
        rc, _ = _run_manage(["--action", "update-multi", "--json-patch", patch])
        if rc != 0:
            sys.exit(rc)

        if args.agent_name:
            rc, _ = _run_manage(["--action", "add-agent", "--agent-name", args.agent_name])
            if rc != 0:
                sys.exit(rc)

        _log(f"Session updated: branch_name={branch_name}  feature_dir=specs/{folder_name}")
    else:
        _log(f"[dry-run] branch_name  → {branch_name}")
        _log(f"[dry-run] feature_dir  → specs/{folder_name}")
        _log("[dry-run] Would create session.json (if needed), branch and spec dir")

    write_result(branch_name, str(feature_dir), args.json)


if __name__ == "__main__":
    main()

