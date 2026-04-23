#!/usr/bin/env bash
# Bootstrap a spec agent: init session, record agent, check dependencies — in one call.
# Usage: bootstrap-session.sh --agent-name spec.plan [--artifact-id plan]
# Exit code 1 if deps are unmet (check-deps reported blockers).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANAGE="$SCRIPT_DIR/manage-session.sh"

AGENT_NAME=""
ARTIFACT_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent-name)   AGENT_NAME="$2";   shift 2 ;;
    --artifact-id)  ARTIFACT_ID="$2";  shift 2 ;;
    *) echo "[bootstrap] Unknown argument: $1" >&2; exit 1 ;;
  esac
done

[[ -z "$AGENT_NAME" ]] && { echo "[bootstrap] Error: --agent-name is required" >&2; exit 1; }

bash "$MANAGE" --action init
bash "$MANAGE" --action add-agent --agent-name "$AGENT_NAME"

if [[ -n "$ARTIFACT_ID" ]]; then
  bash "$MANAGE" --action check-deps --artifact-id "$ARTIFACT_ID"
fi
