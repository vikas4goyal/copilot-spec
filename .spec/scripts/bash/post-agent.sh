#!/usr/bin/env bash
# Standardized post-execution for any spec workflow agent:
#   1. Write artifact summary (what was produced)
#   2. Write artifact handoff (prompt/context for the next agent)
#   3. Mark artifact complete (cascades unblocking of downstream artifacts)
#
# Usage: post-agent.sh --artifact-id plan --summary "..." --handoff "..."
#
# NOTE: Does NOT auto-commit. The calling agent must invoke the
#       spec.git.commit sub-agent separately — commit messages need AI.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANAGE="$SCRIPT_DIR/manage-session.sh"

ARTIFACT_ID=""
SUMMARY=""
HANDOFF=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --artifact-id) ARTIFACT_ID="$2"; shift 2 ;;
    --summary)     SUMMARY="$2";     shift 2 ;;
    --handoff)     HANDOFF="$2";     shift 2 ;;
    *) echo "[post-agent] Unknown argument: $1" >&2; exit 1 ;;
  esac
done

[[ -z "$ARTIFACT_ID" ]] && { echo "[post-agent] Error: --artifact-id required" >&2; exit 1; }

if [[ -n "$SUMMARY" ]]; then
  bash "$MANAGE" --action update-artifact \
    --artifact-id "$ARTIFACT_ID" \
    --artifact-field summary \
    --artifact-value "$SUMMARY"
fi

if [[ -n "$HANDOFF" ]]; then
  bash "$MANAGE" --action update-artifact \
    --artifact-id "$ARTIFACT_ID" \
    --artifact-field handoff \
    --artifact-value "$HANDOFF"
fi

bash "$MANAGE" --action complete-artifact --artifact-id "$ARTIFACT_ID"
