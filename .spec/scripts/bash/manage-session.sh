#!/usr/bin/env bash
# Manage the active spec session state file (.spec/session.json)
# Usage:
#   manage-session.sh --action init
#   manage-session.sh --action update --field feature.branch_name --value "001-my-feature"
#   manage-session.sh --action update-multi --json-patch '{"feature":{"branch_name":"001-x"}}'
#   manage-session.sh --action read
#   manage-session.sh --action add-agent --agent-name "spec.constitution"
#   manage-session.sh --action archive

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

REPO_ROOT="$(get_repo_root)"
SESSION_FILE="$REPO_ROOT/.spec/session.json"
TEMPLATE_FILE="$REPO_ROOT/.spec/templates/session-state-template.json"

ACTION=""
FIELD=""
VALUE=""
JSON_PATCH=""
AGENT_NAME=""
AS_JSON=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --action)    ACTION="$2";     shift 2 ;;
    --field)     FIELD="$2";      shift 2 ;;
    --value)     VALUE="$2";      shift 2 ;;
    --json-patch) JSON_PATCH="$2"; shift 2 ;;
    --agent-name) AGENT_NAME="$2"; shift 2 ;;
    --json)      AS_JSON=true;    shift ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

get_now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

new_session_id() {
  local ts rand
  ts=$(date -u +"%Y%m%d-%H%M%S")
  rand=$(LC_ALL=C tr -dc 'a-zA-Z' < /dev/urandom | head -c4 2>/dev/null || echo "xxxx")
  echo "${ts}-${rand}"
}

initialize_session() {
  if [[ -f "$SESSION_FILE" ]]; then
    echo "[session] Session file already exists at $SESSION_FILE — skipping init." >&2
    cat "$SESSION_FILE"
    return 0
  fi

  if [[ ! -f "$TEMPLATE_FILE" ]]; then
    echo "[session] ERROR: Template not found at $TEMPLATE_FILE" >&2
    exit 1
  fi

  local now id base_branch remote_url repo
  now=$(get_now)
  id=$(new_session_id)

  base_branch=""
  remote_url=""
  repo=""
  if command -v git &>/dev/null && git -C "$REPO_ROOT" rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
    base_branch=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    remote_url=$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || echo "")
    repo=$(git -C "$REPO_ROOT" rev-parse --show-toplevel 2>/dev/null || echo "")
  fi

  # Use jq if available, otherwise use Python
  if command -v jq &>/dev/null; then
    jq \
      --arg id "$id" \
      --arg now "$now" \
      --arg base "$base_branch" \
      --arg remote "$remote_url" \
      --arg repo_path "$repo" \
      '.session.id = $id |
       .session.created_at = $now |
       .session.updated_at = $now |
       .session.status = "active" |
       .git.base_branch = $base |
       .git.remote_url = $remote |
       .git.repository = $repo_path' \
      "$TEMPLATE_FILE" > "$SESSION_FILE"
  else
    python3 - "$TEMPLATE_FILE" "$SESSION_FILE" "$id" "$now" "$base_branch" "$remote_url" "$repo" <<'PYEOF'
import json, sys
tmpl, dest, sid, now, base, remote, repo = sys.argv[1:]
with open(tmpl) as f:
    s = json.load(f)
s['session']['id'] = sid
s['session']['created_at'] = now
s['session']['updated_at'] = now
s['session']['status'] = 'active'
s['git']['base_branch'] = base
s['git']['remote_url'] = remote
s['git']['repository'] = repo
with open(dest, 'w') as f:
    json.dump(s, f, indent=2)
PYEOF
  fi

  echo "[session] Initialized session at $SESSION_FILE (id: $id)"
  cat "$SESSION_FILE"
}

update_field() {
  local field="$1" value="$2" now
  now=$(get_now)
  [[ -f "$SESSION_FILE" ]] || initialize_session > /dev/null

  if command -v jq &>/dev/null; then
    local tmp
    tmp=$(mktemp)
    jq --arg f "$field" --arg v "$value" --arg now "$now" \
      'reduce ($f | split(".")) as $k (.; if length > 0 then .[$k[0]][$k[1]] = $v else . end) | .session.updated_at = $now' \
      "$SESSION_FILE" > "$tmp" && mv "$tmp" "$SESSION_FILE"
  else
    python3 - "$SESSION_FILE" "$field" "$value" "$now" <<'PYEOF'
import json, sys
path_file, field_path, value, now = sys.argv[1:]
with open(path_file) as f:
    s = json.load(f)
parts = field_path.split('.')
obj = s
for part in parts[:-1]:
    obj = obj[part]
obj[parts[-1]] = value
s['session']['updated_at'] = now
with open(path_file, 'w') as f:
    json.dump(s, f, indent=2)
PYEOF
  fi
  echo "[session] Updated $field"
}

add_agent() {
  local agent="$1" now
  now=$(get_now)
  [[ -f "$SESSION_FILE" ]] || initialize_session > /dev/null

  if command -v jq &>/dev/null; then
    local tmp entry
    entry=$(jq -n --arg a "$agent" --arg t "$now" '{"agent":$a,"ran_at":$t}')
    tmp=$(mktemp)
    jq --argjson entry "$entry" --arg a "$agent" --arg now "$now" \
      '.workflow.agents_run += [$entry] | .workflow.current_agent = $a | .session.updated_at = $now' \
      "$SESSION_FILE" > "$tmp" && mv "$tmp" "$SESSION_FILE"
  else
    python3 - "$SESSION_FILE" "$agent" "$now" <<'PYEOF'
import json, sys
path_file, agent, now = sys.argv[1:]
with open(path_file) as f:
    s = json.load(f)
s['workflow']['agents_run'].append({'agent': agent, 'ran_at': now})
s['workflow']['current_agent'] = agent
s['session']['updated_at'] = now
with open(path_file, 'w') as f:
    json.dump(s, f, indent=2)
PYEOF
  fi
  echo "[session] Recorded agent '$agent' in session."
}

archive_session() {
  if [[ ! -f "$SESSION_FILE" ]]; then
    echo "[session] WARNING: No active session file found at $SESSION_FILE" >&2
    return 0
  fi

  local feature_name safe_name archive_dir now
  now=$(get_now)

  if command -v jq &>/dev/null; then
    feature_name=$(jq -r '.feature.branch_name // empty' "$SESSION_FILE")
    [[ -z "$feature_name" ]] && feature_name=$(jq -r '.session.id' "$SESSION_FILE")
  else
    feature_name=$(python3 -c "import json,sys; d=json.load(open('$SESSION_FILE')); print(d['feature'].get('branch_name') or d['session']['id'])")
  fi

  safe_name="${feature_name//[^a-zA-Z0-9\-_.]/-}"
  archive_dir="$REPO_ROOT/.spec/features/$safe_name"
  mkdir -p "$archive_dir"

  # Mark completed
  if command -v jq &>/dev/null; then
    local tmp
    tmp=$(mktemp)
    jq --arg now "$now" '.session.status = "completed" | .session.updated_at = $now' \
      "$SESSION_FILE" > "$tmp" && mv "$tmp" "$SESSION_FILE"
  fi

  mv "$SESSION_FILE" "$archive_dir/session.json"
  echo "[session] Archived session to $archive_dir/session.json"
}

case "$ACTION" in
  init)         initialize_session ;;
  update)       [[ -z "$FIELD" ]] && { echo "--field required" >&2; exit 1; }; update_field "$FIELD" "$VALUE" ;;
  update-multi) [[ -z "$JSON_PATCH" ]] && { echo "--json-patch required" >&2; exit 1; }
                [[ -f "$SESSION_FILE" ]] || initialize_session > /dev/null
                if command -v jq &>/dev/null; then
                  tmp=$(mktemp)
                  now=$(get_now)
                  jq --argjson patch "$JSON_PATCH" --arg now "$now" \
                    '. * $patch | .session.updated_at = $now' "$SESSION_FILE" > "$tmp" && mv "$tmp" "$SESSION_FILE"
                else
                  python3 - "$SESSION_FILE" <<PYEOF
import json, sys
patch = $JSON_PATCH
with open('$SESSION_FILE') as f:
    s = json.load(f)
def deep_merge(base, overlay):
    for k, v in overlay.items():
        if isinstance(v, dict) and isinstance(base.get(k), dict):
            deep_merge(base[k], v)
        else:
            base[k] = v
deep_merge(s, patch)
s['session']['updated_at'] = '$(get_now)'
with open('$SESSION_FILE', 'w') as f:
    json.dump(s, f, indent=2)
PYEOF
                fi
                echo "[session] Applied JSON patch to session." ;;
  read)         [[ -f "$SESSION_FILE" ]] && cat "$SESSION_FILE" || echo "[session] No active session." ;;
  add-agent)    [[ -z "$AGENT_NAME" ]] && { echo "--agent-name required" >&2; exit 1; }; add_agent "$AGENT_NAME" ;;
  archive)      archive_session ;;
  *)            echo "Unknown action: $ACTION. Use: init | update | update-multi | read | add-agent | archive" >&2; exit 1 ;;
esac
