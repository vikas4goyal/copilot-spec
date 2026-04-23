#!/usr/bin/env python3
"""
check_prerequisites.py — Consolidated prerequisite checking for Spec-Driven
Development workflow (analogous to check-prerequisites.ps1).

Usage:
    python check_prerequisites.py [--json] [--require-tasks] [--include-tasks]
                                   [--paths-only] [--help]
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from common import (  # noqa: E402
    get_feature_paths_env,
    test_feature_branch,
    test_file_exists,
    test_dir_has_files,
)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Consolidated prerequisite checking for Spec-Driven Development workflow.",
        add_help=True,
    )
    parser.add_argument("--json",          action="store_true", help="Output in JSON format")
    parser.add_argument("--require-tasks", action="store_true", help="Require tasks.md to exist")
    parser.add_argument("--include-tasks", action="store_true", help="Include tasks.md in AVAILABLE_DOCS")
    parser.add_argument("--paths-only",    action="store_true", help="Only output path variables (no validation)")
    args = parser.parse_args()

    paths = get_feature_paths_env()

    if not test_feature_branch(paths["CURRENT_BRANCH"], paths["HAS_GIT"]):
        sys.exit(1)

    # Paths-only mode
    if args.paths_only:
        if args.json:
            print(json.dumps({
                "REPO_ROOT":    paths["REPO_ROOT"],
                "BRANCH":       paths["CURRENT_BRANCH"],
                "FEATURE_DIR":  paths["FEATURE_DIR"],
                "FEATURE_SPEC": paths["FEATURE_SPEC"],
                "IMPL_PLAN":    paths["IMPL_PLAN"],
                "TASKS":        paths["TASKS"],
            }, ensure_ascii=False))
        else:
            print(f"REPO_ROOT: {paths['REPO_ROOT']}")
            print(f"BRANCH: {paths['CURRENT_BRANCH']}")
            print(f"FEATURE_DIR: {paths['FEATURE_DIR']}")
            print(f"FEATURE_SPEC: {paths['FEATURE_SPEC']}")
            print(f"IMPL_PLAN: {paths['IMPL_PLAN']}")
            print(f"TASKS: {paths['TASKS']}")
        sys.exit(0)

    # Validate required directories and files
    if not Path(paths["FEATURE_DIR"]).is_dir():
        print(f"ERROR: Feature directory not found: {paths['FEATURE_DIR']}")
        print("Run /spec.specs first to create the feature structure.")
        sys.exit(1)

    if not Path(paths["IMPL_PLAN"]).is_file():
        print(f"ERROR: plan.md not found in {paths['FEATURE_DIR']}")
        print("Run /spec.plan first to create the implementation plan.")
        sys.exit(1)

    if args.require_tasks and not Path(paths["TASKS"]).is_file():
        print(f"ERROR: tasks.md not found in {paths['FEATURE_DIR']}")
        print("Run /spec.tasks first to create the task list.")
        sys.exit(1)

    # Build list of available documents
    docs: list[str] = []
    if Path(paths["RESEARCH"]).is_file():   docs.append("research.md")
    if Path(paths["DATA_MODEL"]).is_file(): docs.append("data-model.md")

    contracts = Path(paths["CONTRACTS_DIR"])
    if contracts.is_dir() and any(f.is_file() for f in contracts.iterdir()):
        docs.append("contracts/")

    if Path(paths["QUICKSTART"]).is_file(): docs.append("quickstart.md")
    if args.include_tasks and Path(paths["TASKS"]).is_file():
        docs.append("tasks.md")

    # Output
    if args.json:
        print(json.dumps({
            "FEATURE_DIR":   paths["FEATURE_DIR"],
            "AVAILABLE_DOCS": docs,
        }, ensure_ascii=False))
    else:
        print(f"FEATURE_DIR:{paths['FEATURE_DIR']}")
        print("AVAILABLE_DOCS:")
        test_file_exists(paths["RESEARCH"],   "research.md")
        test_file_exists(paths["DATA_MODEL"], "data-model.md")
        test_dir_has_files(paths["CONTRACTS_DIR"], "contracts/")
        test_file_exists(paths["QUICKSTART"], "quickstart.md")
        if args.include_tasks:
            test_file_exists(paths["TASKS"], "tasks.md")


if __name__ == "__main__":
    main()

