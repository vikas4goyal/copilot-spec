#!/usr/bin/env python3
"""
pre_agent.py — Standardized pre-execution session step for a spec workflow agent
(analogous to pre-agent.ps1).

Steps:
  1. Bootstrap session (init + add-agent + check-deps)
  2. Mark this agent's artifact as in_progress

Usage:
    python pre_agent.py --agent-name spec.plan --artifact-id plan
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent


def _run_manage(args: list[str]) -> int:
    """Run manage_session.py and return its exit code."""
    return subprocess.run(
        [sys.executable, str(SCRIPT_DIR / "manage_session.py")] + args
    ).returncode


def main() -> None:
    """Prepare session state before an agent run and mark artifact in progress."""
    parser = argparse.ArgumentParser(
        description="Standardized pre-execution session step for a spec workflow agent."
    )
    parser.add_argument("--agent-name",  required=True, help="Agent name, e.g. spec.plan")
    parser.add_argument("--artifact-id", default="",    help="Artifact id to mark in_progress")
    parsed = parser.parse_args()

    # 1. Bootstrap session (init + add-agent + check-deps)
    bootstrap_args = [
        sys.executable,
        str(SCRIPT_DIR / "bootstrap_session.py"),
        "--agent-name", parsed.agent_name,
    ]
    if parsed.artifact_id:
        bootstrap_args += ["--artifact-id", parsed.artifact_id]
    return_code = subprocess.run(bootstrap_args).returncode
    if return_code != 0:
        sys.exit(1)

    # 2. Mark artifact in_progress
    if parsed.artifact_id:
        _run_manage([
            "--action", "update-artifact",
            "--artifact-id", parsed.artifact_id,
            "--artifact-field", "status",
            "--artifact-value", "in_progress",
        ])
        # Non-fatal — warn but continue

    suffix = f" (artifact: {parsed.artifact_id})" if parsed.artifact_id else ""
    print(f"[pre-agent] Session ready: {parsed.agent_name}{suffix}")


if __name__ == "__main__":
    main()

