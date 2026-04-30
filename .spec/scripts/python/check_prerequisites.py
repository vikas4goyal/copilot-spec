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
    """Validate feature prerequisites and print available document paths."""
    parser = argparse.ArgumentParser(
        description="Consolidated prerequisite checking for Spec-Driven Development workflow.",
        add_help=True,
    )
    parser.add_argument("--json",          action="store_true", help="Output in JSON format")
    parser.add_argument("--require-tasks", action="store_true", help="Require tasks.md to exist")
    parser.add_argument("--include-tasks", action="store_true", help="Include tasks.md in AVAILABLE_DOCS")
    parser.add_argument("--paths-only",    action="store_true", help="Only output path variables (no validation)")
    args = parser.parse_args()

    feature_paths = get_feature_paths_env()

    if not test_feature_branch(feature_paths["CURRENT_BRANCH"], feature_paths["HAS_GIT"]):
        sys.exit(1)

    # Paths-only mode
    if args.paths_only:
        if args.json:
            print(json.dumps({
                "REPO_ROOT":    feature_paths["REPO_ROOT"],
                "BRANCH":       feature_paths["CURRENT_BRANCH"],
                "FEATURE_DIR":  feature_paths["FEATURE_DIR"],
                "FEATURE_SPEC": feature_paths["FEATURE_SPEC"],
                "IMPL_PLAN":    feature_paths["IMPL_PLAN"],
                "TASKS":        feature_paths["TASKS"],
            }, ensure_ascii=False))
        else:
            print(f"REPO_ROOT: {feature_paths['REPO_ROOT']}")
            print(f"BRANCH: {feature_paths['CURRENT_BRANCH']}")
            print(f"FEATURE_DIR: {feature_paths['FEATURE_DIR']}")
            print(f"FEATURE_SPEC: {feature_paths['FEATURE_SPEC']}")
            print(f"IMPL_PLAN: {feature_paths['IMPL_PLAN']}")
            print(f"TASKS: {feature_paths['TASKS']}")
        sys.exit(0)

    # Validate required directories and files
    if not Path(feature_paths["FEATURE_DIR"]).is_dir():
        print(f"ERROR: Feature directory not found: {feature_paths['FEATURE_DIR']}")
        print("Run /spec.specs first to create the feature structure.")
        sys.exit(1)

    if not Path(feature_paths["IMPL_PLAN"]).is_file():
        print(f"ERROR: plan.md not found in {feature_paths['FEATURE_DIR']}")
        print("Run /spec.plan first to create the implementation plan.")
        sys.exit(1)

    if args.require_tasks and not Path(feature_paths["TASKS"]).is_file():
        print(f"ERROR: tasks.md not found in {feature_paths['FEATURE_DIR']}")
        print("Run /spec.tasks first to create the task list.")
        sys.exit(1)

    # Build list of available documents
    docs: list[str] = []
    if Path(feature_paths["RESEARCH"]).is_file():   docs.append("research.md")
    if Path(feature_paths["DATA_MODEL"]).is_file(): docs.append("data-model.md")

    contracts = Path(feature_paths["CONTRACTS_DIR"])
    if contracts.is_dir() and any(f.is_file() for f in contracts.iterdir()):
        docs.append("contracts/")

    if Path(feature_paths["QUICKSTART"]).is_file(): docs.append("quickstart.md")
    if args.include_tasks and Path(feature_paths["TASKS"]).is_file():
        docs.append("tasks.md")

    # Output
    if args.json:
        print(json.dumps({
            "FEATURE_DIR":   feature_paths["FEATURE_DIR"],
            "AVAILABLE_DOCS": docs,
        }, ensure_ascii=False))
    else:
        print(f"FEATURE_DIR:{feature_paths['FEATURE_DIR']}")
        print("AVAILABLE_DOCS:")
        test_file_exists(feature_paths["RESEARCH"],   "research.md")
        test_file_exists(feature_paths["DATA_MODEL"], "data-model.md")
        test_dir_has_files(feature_paths["CONTRACTS_DIR"], "contracts/")
        test_file_exists(feature_paths["QUICKSTART"], "quickstart.md")
        if args.include_tasks:
            test_file_exists(feature_paths["TASKS"], "tasks.md")


if __name__ == "__main__":
    main()

