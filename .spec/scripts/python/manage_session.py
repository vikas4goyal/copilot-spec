#!/usr/bin/env python3
"""
manage_session.py — Manage the active spec session state file (.spec/session.json).
Analogous to manage-session.ps1.

Usage examples:
    python manage_session.py --action init [--name "oauth2-login"] [--description "..."]
    python manage_session.py --action get --field name
    python manage_session.py --action get-multi --fields "name,branch_name,feature_dir"
    python manage_session.py --action update --field name --value "oauth2-login-google"
    python manage_session.py --action update-multi --json-patch '{"name":"oauth2","description":"..."}'
    python manage_session.py --action read
    python manage_session.py --action add-agent --agent-name "spec.specify"
    python manage_session.py --action complete-artifact --artifact-id "specify"
    python manage_session.py --action update-artifact --artifact-id "specify" --artifact-field "summary" --artifact-value "..."
    python manage_session.py --action skip-artifact --artifact-id "clarify"
    python manage_session.py --action check-deps --artifact-id "plan"
    python manage_session.py --action archive
"""

from __future__ import annotations

import argparse
import json
import os
import random
import re
import string
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

sys.path.insert(0, str(Path(__file__).parent))
from common import get_repo_root  # noqa: E402

VALID_ACTIONS = [
    "init", "get", "get-multi", "update", "update-multi", "read",
    "add-agent", "archive", "complete-artifact", "update-artifact",
    "skip-artifact", "check-deps",
]

VALID_ARTIFACT_FIELDS = ["summary", "handoff", "status", "outputPath"]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _new_session_id() -> str:
    ts   = datetime.now().strftime("%Y%m%d-%H%M%S")
    rand = "".join(random.choices(string.ascii_letters, k=4))
    return f"{ts}-{rand}"


def _read_session(session_file: Path) -> dict:
    return json.loads(session_file.read_text(encoding="utf-8"))


def _save_session(session: dict, session_file: Path) -> None:
    session["updated_at"] = _now_iso()
    session_file.write_text(
        json.dumps(session, indent=2, ensure_ascii=False),
        encoding="utf-8"
    )


def _get_by_dot(obj: Any, path: str) -> Any:
    """Traverse a nested dict/object using dot-notation path."""
    for part in path.split("."):
        if obj is None:
            return None
        if isinstance(obj, dict):
            obj = obj.get(part)
        else:
            obj = getattr(obj, part, None)
    return obj


def _set_by_dot(obj: dict, path: str, value: Any) -> None:
    """Set a value on a nested dict using dot-notation path."""
    parts = path.split(".")
    for part in parts[:-1]:
        if isinstance(obj, dict):
            obj = obj.setdefault(part, {})
        else:
            obj = obj[part]
    if isinstance(obj, dict):
        obj[parts[-1]] = value
    else:
        obj[parts[-1]] = value


def _merge_patch(target: dict, patch: dict) -> None:
    """Recursively merge *patch* into *target* (analogous to Merge-JsonPatch)."""
    for key, value in patch.items():
        if isinstance(value, dict) and isinstance(target.get(key), dict):
            _merge_patch(target[key], value)
        else:
            target[key] = value


def _update_pipeline_next(session: dict) -> None:
    """Recalculate pipeline.next_recommended after any artifact status change."""
    completed_id = (session.get("pipeline") or {}).get("last_completed")
    artifacts    = session.get("artifacts", [])

    # First: required, ready, not just completed
    next_art = next(
        (a for a in artifacts
         if a.get("status") == "ready" and a.get("required") and a.get("id") != completed_id),
        None
    )
    # Fallback: any ready artifact
    if next_art is None:
        next_art = next(
            (a for a in artifacts
             if a.get("status") == "ready" and a.get("id") != completed_id),
            None
        )

    pipeline = session.setdefault("pipeline", {})
    pipeline["next_recommended"] = next_art.get("command") if next_art else None


# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

def initialize_session(
    session_file: Path,
    template_file: Path,
    name: Optional[str] = None,
    description: Optional[str] = None,
) -> dict:
    if not session_file.exists():
        if not template_file.exists():
            print(
                f"[session] Template not found at {template_file}. Cannot initialize session.",
                file=sys.stderr
            )
            sys.exit(1)
        session = json.loads(template_file.read_text(encoding="utf-8"))
        now = _now_iso()
        session["id"]         = _new_session_id()
        session["created_at"] = now
        session["updated_at"] = now
        session["status"]     = "active"
        if name:        session["name"]        = name
        if description: session["description"] = description
        session_file.write_text(
            json.dumps(session, indent=2, ensure_ascii=False),
            encoding="utf-8"
        )
        print(f"[session] Initialized session at {session_file} (id: {session['id']})")
        return session

    # Reuse existing — fill missing name/description non-destructively
    print("[session] Session already exists — reusing.")
    session = _read_session(session_file)
    changed = False
    if name        and not session.get("name"):
        session["name"]        = name;        changed = True
    if description and not session.get("description"):
        session["description"] = description; changed = True
    if changed:
        _save_session(session, session_file)
        print("[session] Applied missing name/description to existing session.")
    return session


def get_field_value(session_file: Path, field_path: str) -> None:
    if not session_file.exists():
        print("[session] No active session.", file=sys.stderr)
        return
    session = _read_session(session_file)
    value   = _get_by_dot(session, field_path)
    print("" if value is None else str(value))


def get_multi_values(session_file: Path, field_paths: str) -> None:
    if not session_file.exists():
        print("[session] No active session.", file=sys.stderr)
        print("{}")
        return
    session = _read_session(session_file)
    result  = {}
    for raw_path in field_paths.split(","):
        path         = raw_path.strip()
        result[path] = _get_by_dot(session, path)
    print(json.dumps(result, ensure_ascii=False))


def update_session_field(
    session_file: Path,
    template_file: Path,
    field_path: str,
    value: Any,
) -> dict:
    if not session_file.exists():
        initialize_session(session_file, template_file)
    session = _read_session(session_file)
    _set_by_dot(session, field_path, value)
    _save_session(session, session_file)
    print(f"[session] Updated {field_path}")
    return session


def add_agent_to_session(
    session_file: Path,
    template_file: Path,
    agent: str,
) -> dict:
    if not session_file.exists():
        initialize_session(session_file, template_file)
    session = _read_session(session_file)
    now     = _now_iso()
    entry   = {"agent": agent, "ran_at": now}
    pipeline = session.setdefault("pipeline", {})
    pipeline.setdefault("agents_run", []).append(entry)
    pipeline["current_agent"] = agent
    _save_session(session, session_file)
    print(f"[session] Recorded agent '{agent}' in session.")
    return session


def complete_artifact(session_file: Path, artifact_id: str) -> dict:
    if not session_file.exists():
        print("[session] No active session. Run 'init' first.", file=sys.stderr)
        sys.exit(1)
    session   = _read_session(session_file)
    artifacts = session.get("artifacts", [])
    artifact  = next((a for a in artifacts if a.get("id") == artifact_id), None)
    if artifact is None:
        print(f"[session] Artifact '{artifact_id}' not found in session.", file=sys.stderr)
        sys.exit(1)

    now = _now_iso()
    artifact["status"]      = "complete"
    artifact["completedAt"] = now
    handoff = artifact.get("handoff")

    # Cascade: remove artifact_id from missingDeps of every other artifact
    for a in artifacts:
        missing = a.get("missingDeps", [])
        if artifact_id in missing:
            missing.remove(artifact_id)
            a["missingDeps"] = missing
            if len(missing) == 0 and a.get("status") == "pending":
                a["status"] = "ready"

    pipeline = session.setdefault("pipeline", {})
    pipeline["last_completed"]  = artifact_id
    pipeline["current_agent"]   = None
    if handoff:
        pipeline["next_prompt"] = handoff

    _update_pipeline_next(session)

    required_pending = [
        a for a in artifacts
        if a.get("required") and a.get("status") not in ("complete", "skipped")
    ]
    session["isComplete"] = len(required_pending) == 0

    _save_session(session, session_file)
    print(f"[session] Artifact '{artifact_id}' marked complete. Next: {pipeline.get('next_recommended')}")
    return session


def update_artifact(
    session_file: Path,
    artifact_id: str,
    field: str,
    field_value: str,
) -> dict:
    if not session_file.exists():
        print("[session] No active session. Run 'init' first.", file=sys.stderr)
        sys.exit(1)
    if field not in VALID_ARTIFACT_FIELDS:
        print(
            f"[session] Invalid ArtifactField '{field}'. Valid: {', '.join(VALID_ARTIFACT_FIELDS)}",
            file=sys.stderr
        )
        sys.exit(1)
    session  = _read_session(session_file)
    artifact = next((a for a in session.get("artifacts", []) if a.get("id") == artifact_id), None)
    if artifact is None:
        print(f"[session] Artifact '{artifact_id}' not found.", file=sys.stderr)
        sys.exit(1)
    artifact[field] = field_value
    _save_session(session, session_file)
    print(f"[session] Artifact '{artifact_id}'.{field} updated.")
    return session


def skip_artifact(session_file: Path, artifact_id: str) -> dict:
    if not session_file.exists():
        print("[session] No active session. Run 'init' first.", file=sys.stderr)
        sys.exit(1)
    session   = _read_session(session_file)
    artifacts = session.get("artifacts", [])
    artifact  = next((a for a in artifacts if a.get("id") == artifact_id), None)
    if artifact is None:
        print(f"[session] Artifact '{artifact_id}' not found.", file=sys.stderr)
        sys.exit(1)
    if artifact.get("required"):
        print(
            f"[session] Artifact '{artifact_id}' is marked required. "
            "Skipping it may break downstream steps.",
            file=sys.stderr
        )

    now = _now_iso()
    artifact["status"]      = "skipped"
    artifact["completedAt"] = now

    for a in artifacts:
        missing = a.get("missingDeps", [])
        if artifact_id in missing:
            missing.remove(artifact_id)
            a["missingDeps"] = missing
            if len(missing) == 0 and a.get("status") == "pending":
                a["status"] = "ready"

    pipeline = session.setdefault("pipeline", {})
    pipeline["last_completed"] = artifact_id
    _update_pipeline_next(session)

    required_pending = [
        a for a in artifacts
        if a.get("required") and a.get("status") not in ("complete", "skipped")
    ]
    session["isComplete"] = len(required_pending) == 0

    _save_session(session, session_file)
    print(f"[session] Artifact '{artifact_id}' skipped. Next: {pipeline.get('next_recommended')}")
    return session


def check_artifact_deps(session_file: Path, artifact_id: str) -> bool:
    if not session_file.exists():
        print("[session] No active session.", file=sys.stderr)
        sys.exit(1)
    session  = _read_session(session_file)
    artifact = next((a for a in session.get("artifacts", []) if a.get("id") == artifact_id), None)
    if artifact is None:
        print(f"[session] Artifact '{artifact_id}' not found.", file=sys.stderr)
        sys.exit(1)

    missing = artifact.get("missingDeps", [])
    if not missing:
        print(f"[session] '{artifact_id}' is ready - all dependencies met.")
        return True

    print(f"[session] '{artifact_id}' is blocked. Missing dependencies:", file=sys.stderr)
    for dep in missing:
        dep_art = next((a for a in session.get("artifacts", []) if a.get("id") == dep), None)
        cmd     = dep_art.get("command", dep) if dep_art else dep
        print(f"  → Run {cmd} first  (id: {dep})", file=sys.stderr)
    return False


def archive_session(session_file: Path, repo_root: str) -> None:
    if not session_file.exists():
        print(f"[session] No active session file found at {session_file}", file=sys.stderr)
        return
    session      = _read_session(session_file)
    feature_name = session.get("branch_name") or session.get("name") or session.get("id", "unknown")
    safe_name    = re.sub(r'[^a-zA-Z0-9\-_.]', '-', feature_name)
    archive_dir  = Path(repo_root) / ".spec" / "features" / safe_name
    archive_dir.mkdir(parents=True, exist_ok=True)

    session["status"]     = "completed"
    session["updated_at"] = _now_iso()
    session_file.write_text(
        json.dumps(session, indent=2, ensure_ascii=False),
        encoding="utf-8"
    )

    dest = archive_dir / "session.json"
    session_file.rename(dest)
    print(f"[session] Archived session to {dest}")


# ---------------------------------------------------------------------------
# CLI entrypoint
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Manage the active spec session state file (.spec/session.json)."
    )
    parser.add_argument("--action", required=True, choices=VALID_ACTIONS)
    parser.add_argument("--name",           default="")
    parser.add_argument("--description",    default="")
    parser.add_argument("--field",          default="")
    parser.add_argument("--fields",         default="")
    parser.add_argument("--value",          default="")
    parser.add_argument("--json-patch",     default="")
    parser.add_argument("--agent-name",     default="")
    parser.add_argument("--artifact-id",    default="")
    parser.add_argument("--artifact-field", default="")
    parser.add_argument("--artifact-value", default="")
    parser.add_argument("--json",           action="store_true")
    args = parser.parse_args()

    repo_root     = get_repo_root()
    session_file  = Path(repo_root) / ".spec" / "session.json"
    template_file = Path(repo_root) / ".spec" / "templates" / "session-state-template.json"

    action = args.action

    if action == "init":
        result = initialize_session(
            session_file, template_file, args.name or None, args.description or None
        )
        if args.json:
            print(json.dumps(result, indent=2, ensure_ascii=False))

    elif action == "get":
        field = args.field or args.fields
        if not field:
            print("-field (or --fields) is required for 'get'", file=sys.stderr)
            sys.exit(1)
        get_field_value(session_file, field)

    elif action == "get-multi":
        if not args.fields:
            print("--fields is required for 'get-multi'", file=sys.stderr)
            sys.exit(1)
        get_multi_values(session_file, args.fields)

    elif action == "update":
        if not args.field:
            print("--field is required for 'update'", file=sys.stderr)
            sys.exit(1)
        result = update_session_field(session_file, template_file, args.field, args.value)
        if args.json:
            print(json.dumps(result, indent=2, ensure_ascii=False))

    elif action == "update-multi":
        if not args.json_patch:
            print("--json-patch is required for 'update-multi'", file=sys.stderr)
            sys.exit(1)
        if not session_file.exists():
            initialize_session(session_file, template_file)
        session = _read_session(session_file)
        patch   = json.loads(args.json_patch)
        _merge_patch(session, patch)
        _save_session(session, session_file)
        print("[session] Applied JSON patch to session.")
        if args.json:
            print(json.dumps(session, indent=2, ensure_ascii=False))

    elif action == "read":
        if not session_file.exists():
            print("[session] No active session file.", file=sys.stderr)
        else:
            print(session_file.read_text(encoding="utf-8"))

    elif action == "add-agent":
        if not args.agent_name:
            print("--agent-name is required for 'add-agent'", file=sys.stderr)
            sys.exit(1)
        result = add_agent_to_session(session_file, template_file, args.agent_name)
        if args.json:
            print(json.dumps(result, indent=2, ensure_ascii=False))

    elif action == "complete-artifact":
        if not args.artifact_id:
            print("--artifact-id is required for 'complete-artifact'", file=sys.stderr)
            sys.exit(1)
        result = complete_artifact(session_file, args.artifact_id)
        if args.json:
            print(json.dumps(result, indent=2, ensure_ascii=False))

    elif action == "update-artifact":
        if not args.artifact_id:
            print("--artifact-id is required for 'update-artifact'", file=sys.stderr)
            sys.exit(1)
        if not args.artifact_field:
            print("--artifact-field is required for 'update-artifact'", file=sys.stderr)
            sys.exit(1)
        result = update_artifact(
            session_file, args.artifact_id, args.artifact_field, args.artifact_value
        )
        if args.json:
            print(json.dumps(result, indent=2, ensure_ascii=False))

    elif action == "skip-artifact":
        if not args.artifact_id:
            print("--artifact-id is required for 'skip-artifact'", file=sys.stderr)
            sys.exit(1)
        result = skip_artifact(session_file, args.artifact_id)
        if args.json:
            print(json.dumps(result, indent=2, ensure_ascii=False))

    elif action == "check-deps":
        if not args.artifact_id:
            print("--artifact-id is required for 'check-deps'", file=sys.stderr)
            sys.exit(1)
        ok = check_artifact_deps(session_file, args.artifact_id)
        if not ok:
            sys.exit(1)

    elif action == "archive":
        archive_session(session_file, repo_root)


if __name__ == "__main__":
    main()

