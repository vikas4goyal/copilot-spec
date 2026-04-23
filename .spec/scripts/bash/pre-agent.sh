#!/usr/bin/env bash
# Standardized pre-execution session step for a spec workflow agent:
#   1. Bootstrap session (init + add-agent + check-deps)
#   2. Mark this agent's artifact as in_progress
#
# Call order inside the agent:
#   1. spec.git.initialize sub-agent  (ensures repo exists)
#   2. spec.git.commit    sub-agent  (commits any pending pre-agent work)
#   3. pre-agent.sh       (THIS)     (marks the session step started)
#
# Usage: pre-agent.sh --agent-name spec.plan --artifact-id plan
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

AGENT_NAME=""
ARTIFACT_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent-name)  AGENT_NAME="$2";  shift 2 ;;
    --artifact-id) ARTIFACT_ID="$2"; shift 2 ;;
    *) echo "[pre-agent] Unknown argument: $1" >&2; exit 1 ;;
  esac
done

[[ -z "$AGENT_NAME" ]] && { echo "[pre-agent] Error: --agent-name required" >&2; exit 1; }

# 1. Bootstrap session (init + add-agent + check-deps)
if [[ -n "$ARTIFACT_ID" ]]; then
  bash "$SCRIPT_DIR/bootstrap-session.sh" --agent-name "$AGENT_NAME" --artifact-id "$ARTIFACT_ID"
else
  bash "$SCRIPT_DIR/bootstrap-session.sh" --agent-name "$AGENT_NAME"
fi

# 2. Mark artifact in_progress
if [[ -n "$ARTIFACT_ID" ]]; then
  bash "$SCRIPT_DIR/manage-session.sh" \
    --action update-artifact \
    --artifact-id "$ARTIFACT_ID" \
    --artifact-field status \
    --artifact-value in_progress
fi

echo "[pre-agent] Session ready: $AGENT_NAME${ARTIFACT_ID:+ (artifact: $ARTIFACT_ID)}"
