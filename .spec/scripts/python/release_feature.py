#!/usr/bin/env python3
"""
release_feature.py — Finalize a spec feature release: push branch + archive
session + (optionally) switch to base branch (analogous to release-feature.ps1).

Does NOT commit — assumes the caller (spec.release agent) has already committed.

Usage:
    python release_feature.py [--stay-on-branch]
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))


def _run(cmd: list[str], cwd: str) -> tuple[int, str]:
    result = subprocess.run(cmd, capture_output=True, text=True, cwd=cwd)
    return result.returncode, (result.stdout + result.stderr).strip()


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Finalize a spec feature release."
    )
    parser.add_argument(
        "--stay-on-branch",
        action="store_true",
        help="Do not switch to the base branch after releasing"
    )
    args = parser.parse_args()

    script_dir   = Path(__file__).parent
    repo_root    = str(script_dir.parents[2])  # .spec/scripts/python → repo root
    session_file = Path(repo_root) / ".spec" / "session.json"

    if not session_file.exists():
        print("[release] No active session found. Nothing to release.", file=sys.stderr)
        sys.exit(0)

    session = json.loads(session_file.read_text(encoding="utf-8"))

    # Resolve branch_name (support both flat and nested layouts)
    branch_name = session.get("branch_name")
    if not branch_name:
        branch_name = (session.get("feature") or {}).get("branch_name")

    base_branch = (session.get("git") or {}).get("base_branch")

    if not branch_name:
        print("[release] Could not determine branch_name from session.json", file=sys.stderr)
        sys.exit(1)

    # Check git
    has_git = False
    try:
        subprocess.run(["git", "--version"], capture_output=True, check=False)
        rc, _ = _run(["git", "-C", repo_root, "rev-parse", "--is-inside-work-tree"], repo_root)
        has_git = (rc == 0)
    except FileNotFoundError:
        pass

    # Push to origin
    if has_git:
        rc, remote_url = _run(["git", "-C", repo_root, "config", "--get", "remote.origin.url"], repo_root)
        if rc == 0 and remote_url.strip():
            print(f"[release] Pushing branch: {branch_name}")
            rc, out = _run(
                ["git", "-C", repo_root, "push", "origin", branch_name, "--set-upstream"],
                repo_root
            )
            if rc != 0:
                print(f"[release] Push failed; continuing with archive. ({out})", file=sys.stderr)
        else:
            print("[release] No remote 'origin' found — skipping push. Branch is available locally only.")
    else:
        print("[release] Git not available — skipping push.")

    # Archive session
    rc = subprocess.run(
        [sys.executable, str(script_dir / "manage_session.py"), "--action", "archive"]
    ).returncode
    if rc != 0:
        print("[release] Warning: archive step returned non-zero.", file=sys.stderr)

    # Switch to base branch
    if (
        not args.stay_on_branch
        and base_branch
        and base_branch != branch_name
        and has_git
    ):
        rc, _ = _run(["git", "-C", repo_root, "checkout", base_branch], repo_root)
        if rc == 0:
            print(f"[release] Switched to base branch: {base_branch}")

    base_display = base_branch or "<none>"
    print(f"[release] Done. Branch: {branch_name}  Base: {base_display}")


if __name__ == "__main__":
    main()

