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
    parser = argparse.ArgumentParser(description="Setup implementation plan for a feature.")
    parser.add_argument("--json", action="store_true", help="Output results in JSON format")
    args = parser.parse_args()

    paths = get_feature_paths_env()

    if not test_feature_branch(paths["CURRENT_BRANCH"], paths["HAS_GIT"]):
        sys.exit(1)

    # Ensure feature directory exists
    Path(paths["FEATURE_DIR"]).mkdir(parents=True, exist_ok=True)

    # Copy plan template (or create empty file)
    template = resolve_template("plan-template", paths["REPO_ROOT"])
    impl_plan = Path(paths["IMPL_PLAN"])
    if template and Path(template).exists():
        shutil.copy2(template, impl_plan)
        print(f"Copied plan template to {impl_plan}")
    else:
        print("[setup-plan] Warning: Plan template not found", file=sys.stderr)
        impl_plan.touch()

    if args.json:
        print(json.dumps({
            "FEATURE_SPEC": paths["FEATURE_SPEC"],
            "IMPL_PLAN":    paths["IMPL_PLAN"],
            "SPECS_DIR":    paths["FEATURE_DIR"],
            "BRANCH":       paths["CURRENT_BRANCH"],
            "HAS_GIT":      paths["HAS_GIT"],
        }, ensure_ascii=False))
    else:
        print(f"FEATURE_SPEC: {paths['FEATURE_SPEC']}")
        print(f"IMPL_PLAN: {paths['IMPL_PLAN']}")
        print(f"SPECS_DIR: {paths['FEATURE_DIR']}")
        print(f"BRANCH: {paths['CURRENT_BRANCH']}")
        print(f"HAS_GIT: {paths['HAS_GIT']}")


if __name__ == "__main__":
    main()

