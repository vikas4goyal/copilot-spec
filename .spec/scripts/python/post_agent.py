#!/usr/bin/env python3
"""
post_agent.py — Standardized post-execution for any spec workflow agent
(analogous to post-agent.ps1).

Steps:
  1. Write artifact summary
  2. Write artifact handoff
  3. Mark artifact complete

NOTE: Does NOT auto-commit. The calling agent must invoke auto_commit.py
      separately — commit messages need AI.

Usage:
    python post_agent.py --artifact-id plan --summary "..." --handoff "..."
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent


def _run_manage(args: list[str]) -> int:
    return subprocess.run(
        [sys.executable, str(SCRIPT_DIR / "manage_session.py")] + args
    ).returncode


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Standardized post-execution session step for a spec workflow agent."
    )
    parser.add_argument("--artifact-id", required=True, help="Artifact id to finalize")
    parser.add_argument("--summary",     default="",    help="What was produced")
    parser.add_argument("--handoff",     default="",    help="Context/prompt for next agent")
    parsed = parser.parse_args()

    if parsed.summary:
        _run_manage([
            "--action", "update-artifact",
            "--artifact-id",    parsed.artifact_id,
            "--artifact-field", "summary",
            "--artifact-value", parsed.summary,
        ])

    if parsed.handoff:
        _run_manage([
            "--action", "update-artifact",
            "--artifact-id",    parsed.artifact_id,
            "--artifact-field", "handoff",
            "--artifact-value", parsed.handoff,
        ])

    rc = _run_manage(["--action", "complete-artifact", "--artifact-id", parsed.artifact_id])
    if rc != 0:
        sys.exit(rc)


if __name__ == "__main__":
    main()

