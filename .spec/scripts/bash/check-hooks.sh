#!/usr/bin/env bash
# Read .spec/extensions.yml and output formatted hook prompts for a given event.
# Usage: check-hooks.sh --event before_plan
# Outputs ready-to-display markdown blocks; silent if no hooks / no file / no YAML parser.
# Hooks with non-empty `condition` are skipped (left to the HookExecutor).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

EVENT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --event) EVENT="$2"; shift 2 ;;
    *) echo "[check-hooks] Unknown argument: $1" >&2; exit 1 ;;
  esac
done

[[ -z "$EVENT" ]] && { echo "[check-hooks] Error: --event required" >&2; exit 1; }

REPO_ROOT=$(get_repo_root)
EXT_FILE="$REPO_ROOT/.spec/extensions.yml"

[[ -f "$EXT_FILE" ]] || exit 0
command -v python3 &>/dev/null || exit 0

python3 - "$EXT_FILE" "$EVENT" <<'PYEOF'
import sys
try:
    import yaml
except ImportError:
    sys.exit(0)

ext_file, event = sys.argv[1], sys.argv[2]
try:
    with open(ext_file) as f:
        data = yaml.safe_load(f) or {}
except Exception:
    sys.exit(0)

hooks = (data.get("hooks") or {}).get(event) or []
if not hooks:
    sys.exit(0)

parts = []
for hook in hooks:
    if not isinstance(hook, dict):
        continue
    if hook.get("enabled") is False:
        continue
    if hook.get("condition"):  # non-empty → leave to HookExecutor
        continue
    ext      = hook.get("extension", "<unknown>")
    cmd      = hook.get("command", "<unknown>")
    desc     = hook.get("description", "")
    prompt   = hook.get("prompt", "")
    optional = bool(hook.get("optional", False))

    parts.append("## Extension Hooks\n")
    if optional:
        parts.append(f"**Optional Pre-Hook**: {ext}")
        parts.append(f"Command: `/{cmd}`")
        parts.append(f"Description: {desc}\n")
        parts.append(f"Prompt: {prompt}")
        parts.append(f"To execute: `/{cmd}`")
    else:
        parts.append(f"**Automatic Pre-Hook**: {ext}")
        parts.append(f"Executing: `/{cmd}`")
        parts.append(f"EXECUTE_COMMAND: {cmd}\n")
        parts.append("Wait for the result of the hook command before proceeding.")
    parts.append("")

if parts:
    print("\n".join(parts))
PYEOF
