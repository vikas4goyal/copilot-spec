#!/usr/bin/env python3
"""
setup_plan.py — Setup implementation plan for a feature
(analogous to setup-plan.ps1).

Usage:
    python setup_plan.py [--json] [--help]
"""

from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from common import get_feature_paths_env, test_feature_branch, resolve_template  # noqa: E402


def main() -> None:
    """Ensure feature plan file exists by copying the configured plan template."""
    parser = argparse.ArgumentParser(description="Setup implementation plan for a feature.")
    parser.add_argument("--json", action="store_true", help="Output results in JSON format")
    args = parser.parse_args()

    feature_paths = get_feature_paths_env()

    if not test_feature_branch(feature_paths["CURRENT_BRANCH"], feature_paths["HAS_GIT"]):
        sys.exit(1)

    # Ensure feature directory exists
    Path(feature_paths["FEATURE_DIR"]).mkdir(parents=True, exist_ok=True)

    # Copy plan template (or create empty file)
    template = resolve_template("plan-template", feature_paths["REPO_ROOT"])
    impl_plan = Path(feature_paths["IMPL_PLAN"])
    if template and Path(template).exists():
        shutil.copy2(template, impl_plan)
        print(f"Copied plan template to {impl_plan}")
    else:
        print("[setup-plan] Warning: Plan template not found", file=sys.stderr)
        impl_plan.touch()

    if args.json:
        print(json.dumps({
            "FEATURE_SPEC": feature_paths["FEATURE_SPEC"],
            "IMPL_PLAN":    feature_paths["IMPL_PLAN"],
            "SPECS_DIR":    feature_paths["FEATURE_DIR"],
            "BRANCH":       feature_paths["CURRENT_BRANCH"],
            "HAS_GIT":      feature_paths["HAS_GIT"],
        }, ensure_ascii=False))
    else:
        print(f"FEATURE_SPEC: {feature_paths['FEATURE_SPEC']}")
        print(f"IMPL_PLAN: {feature_paths['IMPL_PLAN']}")
        print(f"SPECS_DIR: {feature_paths['FEATURE_DIR']}")
        print(f"BRANCH: {feature_paths['CURRENT_BRANCH']}")
        print(f"HAS_GIT: {feature_paths['HAS_GIT']}")


if __name__ == "__main__":
    main()

