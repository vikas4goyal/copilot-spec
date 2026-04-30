#!/usr/bin/env python3
"""
bootstrap_session.py — Bootstrap a spec agent: init session, record agent,
check dependencies — in one call (analogous to bootstrap-session.ps1).

Usage:
    python bootstrap_session.py --agent-name spec.plan [--artifact-id plan]

Exit code 1 if deps are unmet.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent


def _run_manage(args: list[str]) -> int:
    """Invoke manage_session.py with provided arguments and return exit code."""
    result = subprocess.run(
        [sys.executable, str(SCRIPT_DIR / "manage_session.py")] + args
    )
    return result.returncode


def main() -> None:
    """Initialize session state, record agent, and optionally validate deps."""
    parser = argparse.ArgumentParser(
        description="Bootstrap a spec agent: init session, record agent, check deps."
    )
    parser.add_argument("--agent-name",  required=True,  help="Agent name, e.g. spec.plan")
    parser.add_argument("--artifact-id", default="",     help="Artifact id for dep check")
    parsed = parser.parse_args()

    # 1. Init session
    return_code = _run_manage(["--action", "init"])
    if return_code != 0:
        sys.exit(1)

    # 2. Record agent
    return_code = _run_manage(["--action", "add-agent", "--agent-name", parsed.agent_name])
    if return_code != 0:
        sys.exit(1)

    # 3. Check deps (if an artifact id was given)
    if parsed.artifact_id:
        return_code = _run_manage(["--action", "check-deps", "--artifact-id", parsed.artifact_id])
        if return_code != 0:
            sys.exit(1)


if __name__ == "__main__":
    main()

