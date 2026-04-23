#!/usr/bin/env bash
# Manage the active spec session state file (.spec/session.json)
#
# Usage:
#   manage-session.sh --action init
#   manage-session.sh --action update --field feature.branch_name --value "001-my-feature"
#   manage-session.sh --action update-multi --json-patch '{"feature":{"branch_name":"001-x"}}'
#   manage-session.sh --action read
#   manage-session.sh --action add-agent --agent-name "spec.specify"
#   manage-session.sh --action complete-artifact --artifact-id "specify"
#   manage-session.sh --action update-artifact --artifact-id "specify" --artifact-field "summary" --artifact-value "Generated spec for login flow."
#   manage-session.sh --action update-artifact --artifact-id "specify" --artifact-field "handoff" --artifact-value "OAuth2 login, mobile-first, React stack."
#   manage-session.sh --action skip-artifact --artifact-id "clarify"
#   manage-session.sh --action check-deps --artifact-id "plan"
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
ARTIFACT_ID=""
ARTIFACT_FIELD=""
ARTIFACT_VALUE=""
AS_JSON=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --action)          ACTION="$2";         shift 2 ;;
    --field)           FIELD="$2";          shift 2 ;;
    --value)           VALUE="$2";          shift 2 ;;
    --json-patch)      JSON_PATCH="$2";     shift 2 ;;
    --agent-name)      AGENT_NAME="$2";     shift 2 ;;
    --artifact-id)     ARTIFACT_ID="$2";    shift 2 ;;
    --artifact-field)  ARTIFACT_FIELD="$2"; shift 2 ;;
    --artifact-value)  ARTIFACT_VALUE="$2"; shift 2 ;;
    --json)            AS_JSON=true;        shift ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

get_now() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

new_session_id() {
  local ts rand
  ts=$(date -u +"%Y%m%d-%H%M%S")
  rand=$(LC_ALL=C tr -dc 'a-zA-Z' < /dev/urandom | head -c4 2>/dev/null || echo "xxxx")
  echo "${ts}-${rand}"
}

# ---------------------------------------------------------------------------
# init
# ---------------------------------------------------------------------------
initialize_session() {
  if [[ -f "$SESSION_FILE" ]]; then
    echo "[session] Session file already exists at $SESSION_FILE — skipping init." >&2
    cat "$SESSION_FILE"; return 0
  fi
  [[ -f "$TEMPLATE_FILE" ]] || { echo "[session] ERROR: Template not found at $TEMPLATE_FILE" >&2; exit 1; }

  local now id base_branch="" remote_url="" repo=""
  now=$(get_now); id=$(new_session_id)

  if command -v git &>/dev/null && git -C "$REPO_ROOT" rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
    base_branch=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    remote_url=$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || echo "")
    repo=$(git -C "$REPO_ROOT" rev-parse --show-toplevel 2>/dev/null || echo "")
  fi

  if command -v jq &>/dev/null; then
    jq --arg id "$id" --arg now "$now" --arg base "$base_branch" \
       --arg remote "$remote_url" --arg repo_path "$repo" \
      '.session.id=$id | .session.created_at=$now | .session.updated_at=$now |
       .session.status="active" | .git.base_branch=$base |
       .git.remote_url=$remote | .git.repository=$repo_path' \
      "$TEMPLATE_FILE" > "$SESSION_FILE"
  else
    python3 - "$TEMPLATE_FILE" "$SESSION_FILE" "$id" "$now" "$base_branch" "$remote_url" "$repo" <<'PYEOF'
import json, sys
tmpl, dest, sid, now, base, remote, repo = sys.argv[1:]
with open(tmpl) as f: s = json.load(f)
s['session'].update(id=sid, created_at=now, updated_at=now, status='active')
s['git'].update(base_branch=base, remote_url=remote, repository=repo)
with open(dest, 'w') as f: json.dump(s, f, indent=2)
PYEOF
  fi
  echo "[session] Initialized session at $SESSION_FILE (id: $id)"
  cat "$SESSION_FILE"
}

# ---------------------------------------------------------------------------
# update (dot-notation field)
# ---------------------------------------------------------------------------
update_field() {
  local field="$1" value="$2" now
  now=$(get_now)
  [[ -f "$SESSION_FILE" ]] || initialize_session > /dev/null

  if command -v jq &>/dev/null; then
    local tmp; tmp=$(mktemp)
    # Support two-level dot paths (e.g. feature.name)
    jq --arg f "$field" --arg v "$value" --arg now "$now" '
      . as $root |
      ($f | split(".")) as $parts |
      if ($parts | length) == 2
      then .[$parts[0]][$parts[1]] = $v
      else .[$parts[0]] = $v end |
      .session.updated_at = $now
    ' "$SESSION_FILE" > "$tmp" && mv "$tmp" "$SESSION_FILE"
  else
    python3 - "$SESSION_FILE" "$field" "$value" "$now" <<'PYEOF'
import json, sys
pf, field_path, value, now = sys.argv[1:]
with open(pf) as f: s = json.load(f)
parts = field_path.split('.')
obj = s
for p in parts[:-1]: obj = obj[p]
obj[parts[-1]] = value
s['session']['updated_at'] = now
with open(pf, 'w') as f: json.dump(s, f, indent=2)
PYEOF
  fi
  echo "[session] Updated $field"
}

# ---------------------------------------------------------------------------
# add-agent
# ---------------------------------------------------------------------------
add_agent() {
  local agent="$1" now
  now=$(get_now)
  [[ -f "$SESSION_FILE" ]] || initialize_session > /dev/null

  if command -v jq &>/dev/null; then
    local tmp entry
    entry=$(jq -n --arg a "$agent" --arg t "$now" '{"agent":$a,"ran_at":$t}')
    tmp=$(mktemp)
    jq --argjson entry "$entry" --arg a "$agent" --arg now "$now" \
      '.pipeline.agents_run += [$entry] | .pipeline.current_agent=$a | .session.updated_at=$now' \
      "$SESSION_FILE" > "$tmp" && mv "$tmp" "$SESSION_FILE"
  else
    python3 - "$SESSION_FILE" "$agent" "$now" <<'PYEOF'
import json, sys
pf, agent, now = sys.argv[1:]
with open(pf) as f: s = json.load(f)
s['pipeline']['agents_run'].append({'agent': agent, 'ran_at': now})
s['pipeline']['current_agent'] = agent
s['session']['updated_at'] = now
with open(pf, 'w') as f: json.dump(s, f, indent=2)
PYEOF
  fi
  echo "[session] Recorded agent '$agent' in session."
}

# ---------------------------------------------------------------------------
# complete-artifact  — marks done, cascades status, updates pipeline
# ---------------------------------------------------------------------------
complete_artifact() {
  local id="$1" now
  now=$(get_now)
  [[ -f "$SESSION_FILE" ]] || { echo "[session] No active session." >&2; exit 1; }

  if command -v jq &>/dev/null; then
    local tmp
    tmp=$(mktemp)
    # Step 1: mark complete + cascade missingDeps
    jq --arg id "$id" --arg now "$now" '
      # complete the target artifact
      (.artifacts[] | select(.id == $id)) |= (.status = "complete" | .completedAt = $now) |
      # cascade: remove $id from every artifact missingDeps; unblock if now empty
      (.artifacts[] | select(.missingDeps | (. != null and contains([$id])))) |=
        (.missingDeps -= [$id] |
         if (.missingDeps | length) == 0 and .status == "pending" then .status = "ready" else . end) |
      .pipeline.last_completed = $id |
      .pipeline.current_agent  = null |
      .isComplete = ([.artifacts[] | select(.required == true) |
                      select(.status != "complete" and .status != "skipped")] | length == 0) |
      .session.updated_at = $now
    ' "$SESSION_FILE" > "$tmp" && mv "$tmp" "$SESSION_FILE"

    # Step 2: propagate handoff → next_prompt
    local handoff
    handoff=$(jq -r --arg id "$id" '.artifacts[] | select(.id==$id) | .handoff // empty' "$SESSION_FILE")
    # Step 3: compute next_recommended
    local next_cmd
    next_cmd=$(jq -r --arg id "$id" '
      first(.artifacts[] | select(.status=="ready" and .required==true and .id!=$id) | .command) // empty
    ' "$SESSION_FILE" 2>/dev/null || true)
    [[ -z "$next_cmd" ]] && next_cmd=$(jq -r --arg id "$id" '
      first(.artifacts[] | select(.status=="ready" and .id!=$id) | .command) // empty
    ' "$SESSION_FILE" 2>/dev/null || true)

    tmp=$(mktemp)
    jq --arg next "$next_cmd" --arg prompt "$handoff" '
      .pipeline.next_recommended = (if $next   != "" then $next   else null end) |
      .pipeline.next_prompt      = (if $prompt != "" then $prompt else null end)
    ' "$SESSION_FILE" > "$tmp" && mv "$tmp" "$SESSION_FILE"
  else
    python3 - "$SESSION_FILE" "$id" "$now" <<'PYEOF'
import json, sys
pf, art_id, now = sys.argv[1:]
with open(pf) as f: s = json.load(f)

handoff = None
for a in s['artifacts']:
    if a['id'] == art_id:
        a['status'] = 'complete'; a['completedAt'] = now
        handoff = a.get('handoff')
        break

for a in s['artifacts']:
    md = a.get('missingDeps', [])
    if art_id in md:
        md = [d for d in md if d != art_id]
        a['missingDeps'] = md
        if len(md) == 0 and a['status'] == 'pending':
            a['status'] = 'ready'

s['pipeline']['last_completed'] = art_id
s['pipeline']['current_agent']  = None
if handoff: s['pipeline']['next_prompt'] = handoff

nxt = next((a for a in s['artifacts'] if a['status']=='ready' and a.get('required') and a['id']!=art_id), None) \
   or next((a for a in s['artifacts'] if a['status']=='ready' and a['id']!=art_id), None)
s['pipeline']['next_recommended'] = nxt['command'] if nxt else None

req_pending = [a for a in s['artifacts'] if a.get('required') and a['status'] not in ('complete','skipped')]
s['isComplete'] = len(req_pending) == 0
if s['feature'].get('name'): s['changeName'] = s['feature']['name']
s['session']['updated_at'] = now
with open(pf, 'w') as f: json.dump(s, f, indent=2)
PYEOF
  fi

  local next_rec
  next_rec=$(jq -r '.pipeline.next_recommended // "none"' "$SESSION_FILE" 2>/dev/null || echo "none")
  echo "[session] Artifact '$id' marked complete. Next: $next_rec"
}

# ---------------------------------------------------------------------------
# update-artifact  — set summary, handoff, status, or outputPath
# ---------------------------------------------------------------------------
update_artifact() {
  local id="$1" field="$2" value="$3" now
  now=$(get_now)
  [[ -f "$SESSION_FILE" ]] || { echo "[session] No active session." >&2; exit 1; }

  if command -v jq &>/dev/null; then
    local tmp; tmp=$(mktemp)
    jq --arg id "$id" --arg f "$field" --arg v "$value" --arg now "$now" '
      (.artifacts[] | select(.id==$id)) |= (.[$f] = $v) |
      .session.updated_at = $now
    ' "$SESSION_FILE" > "$tmp" && mv "$tmp" "$SESSION_FILE"
  else
    python3 - "$SESSION_FILE" "$id" "$field" "$value" "$now" <<'PYEOF'
import json, sys
pf, art_id, field, value, now = sys.argv[1:]
with open(pf) as f: s = json.load(f)
for a in s['artifacts']:
    if a['id'] == art_id: a[field] = value; break
s['session']['updated_at'] = now
with open(pf, 'w') as f: json.dump(s, f, indent=2)
PYEOF
  fi
  echo "[session] Artifact '$id'.$field updated."
}

# ---------------------------------------------------------------------------
# skip-artifact  — marks skipped, cascades just like complete
# ---------------------------------------------------------------------------
skip_artifact() {
  local id="$1" now
  now=$(get_now)
  [[ -f "$SESSION_FILE" ]] || { echo "[session] No active session." >&2; exit 1; }

  if command -v jq &>/dev/null; then
    local tmp; tmp=$(mktemp)
    jq --arg id "$id" --arg now "$now" '
      (.artifacts[] | select(.id == $id)) |= (.status = "skipped" | .completedAt = $now) |
      (.artifacts[] | select(.missingDeps | (. != null and contains([$id])))) |=
        (.missingDeps -= [$id] |
         if (.missingDeps | length) == 0 and .status == "pending" then .status = "ready" else . end) |
      .pipeline.last_completed = $id |
      .isComplete = ([.artifacts[] | select(.required==true) |
                      select(.status!="complete" and .status!="skipped")] | length == 0) |
      .session.updated_at = $now
    ' "$SESSION_FILE" > "$tmp" && mv "$tmp" "$SESSION_FILE"

    local next_cmd
    next_cmd=$(jq -r --arg id "$id" \
      'first(.artifacts[] | select(.status=="ready" and .id!=$id) | .command) // empty' \
      "$SESSION_FILE" 2>/dev/null || true)
    tmp=$(mktemp)
    jq --arg next "$next_cmd" \
      '.pipeline.next_recommended = (if $next != "" then $next else null end)' \
      "$SESSION_FILE" > "$tmp" && mv "$tmp" "$SESSION_FILE"
  else
    python3 - "$SESSION_FILE" "$id" "$now" <<'PYEOF'
import json, sys
pf, art_id, now = sys.argv[1:]
with open(pf) as f: s = json.load(f)
for a in s['artifacts']:
    if a['id'] == art_id: a['status'] = 'skipped'; a['completedAt'] = now; break
for a in s['artifacts']:
    md = a.get('missingDeps', [])
    if art_id in md:
        md = [d for d in md if d != art_id]; a['missingDeps'] = md
        if len(md) == 0 and a['status'] == 'pending': a['status'] = 'ready'
s['pipeline']['last_completed'] = art_id
nxt = next((a for a in s['artifacts'] if a['status']=='ready' and a['id']!=art_id), None)
s['pipeline']['next_recommended'] = nxt['command'] if nxt else None
req_pending = [a for a in s['artifacts'] if a.get('required') and a['status'] not in ('complete','skipped')]
s['isComplete'] = len(req_pending) == 0
s['session']['updated_at'] = now
with open(pf, 'w') as f: json.dump(s, f, indent=2)
PYEOF
  fi
  echo "[session] Artifact '$id' skipped."
}

# ---------------------------------------------------------------------------
# check-deps  — report whether an artifact can run
# ---------------------------------------------------------------------------
check_deps() {
  local id="$1"
  [[ -f "$SESSION_FILE" ]] || { echo "[session] No active session." >&2; exit 1; }

  if command -v jq &>/dev/null; then
    local missing count
    missing=$(jq -r --arg id "$id" '.artifacts[] | select(.id==$id) | .missingDeps[]?' "$SESSION_FILE" 2>/dev/null || true)
    if [[ -z "$missing" ]]; then
      echo "[session] '$id' is ready — all dependencies met."
    else
      echo "[session] '$id' is blocked. Missing dependencies:"
      while IFS= read -r dep; do
        local depCmd
        depCmd=$(jq -r --arg dep "$dep" '.artifacts[] | select(.id==$dep) | .command' "$SESSION_FILE" 2>/dev/null || echo "$dep")
        echo "  → Run $depCmd first  (id: $dep)"
      done <<< "$missing"
    fi
  else
    python3 - "$SESSION_FILE" "$id" <<'PYEOF'
import json, sys
pf, art_id = sys.argv[1:]
with open(pf) as f: s = json.load(f)
art = next((a for a in s['artifacts'] if a['id']==art_id), None)
if not art: print(f"[session] Artifact '{art_id}' not found."); sys.exit(1)
missing = art.get('missingDeps', [])
if not missing:
    print(f"[session] '{art_id}' is ready — all dependencies met.")
else:
    print(f"[session] '{art_id}' is blocked. Missing dependencies:")
    cmd_map = {a['id']: a['command'] for a in s['artifacts']}
    for dep in missing: print(f"  → Run {cmd_map.get(dep, dep)} first  (id: {dep})")
PYEOF
  fi
}

# ---------------------------------------------------------------------------
# archive
# ---------------------------------------------------------------------------
archive_session() {
  [[ -f "$SESSION_FILE" ]] || { echo "[session] WARNING: No active session found." >&2; return 0; }
  local feature_name safe_name archive_dir now
  now=$(get_now)

  if command -v jq &>/dev/null; then
    feature_name=$(jq -r '.feature.branch_name // empty' "$SESSION_FILE")
    [[ -z "$feature_name" ]] && feature_name=$(jq -r '.session.id' "$SESSION_FILE")
  else
    feature_name=$(python3 -c "import json; d=json.load(open('$SESSION_FILE')); print(d['feature'].get('branch_name') or d['session']['id'])")
  fi

  safe_name="${feature_name//[^a-zA-Z0-9\-_.]/-}"
  archive_dir="$REPO_ROOT/.spec/features/$safe_name"
  mkdir -p "$archive_dir"

  if command -v jq &>/dev/null; then
    local tmp; tmp=$(mktemp)
    jq --arg now "$now" '.session.status="completed" | .session.updated_at=$now' \
      "$SESSION_FILE" > "$tmp" && mv "$tmp" "$SESSION_FILE"
  fi

  mv "$SESSION_FILE" "$archive_dir/session.json"
  echo "[session] Archived session to $archive_dir/session.json"
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
case "$ACTION" in
  init)              initialize_session ;;
  update)
    [[ -z "$FIELD" ]] && { echo "--field required" >&2; exit 1; }
    update_field "$FIELD" "$VALUE" ;;
  update-multi)
    [[ -z "$JSON_PATCH" ]] && { echo "--json-patch required" >&2; exit 1; }
    [[ -f "$SESSION_FILE" ]] || initialize_session > /dev/null
    if command -v jq &>/dev/null; then
      tmp=$(mktemp); now=$(get_now)
      jq --argjson patch "$JSON_PATCH" --arg now "$now" \
        '. * $patch | .session.updated_at=$now' "$SESSION_FILE" > "$tmp" && mv "$tmp" "$SESSION_FILE"
    else
      python3 - "$SESSION_FILE" "$JSON_PATCH" "$( get_now )" <<'PYEOF'
import json, sys
pf, patch_str, now = sys.argv[1:]
patch = json.loads(patch_str)
with open(pf) as f: s = json.load(f)
def deep_merge(base, overlay):
    for k, v in overlay.items():
        if isinstance(v, dict) and isinstance(base.get(k), dict): deep_merge(base[k], v)
        else: base[k] = v
deep_merge(s, patch)
s['session']['updated_at'] = now
with open(pf, 'w') as f: json.dump(s, f, indent=2)
PYEOF
    fi
    echo "[session] Applied JSON patch to session." ;;
  read)
    [[ -f "$SESSION_FILE" ]] && cat "$SESSION_FILE" || echo "[session] No active session." ;;
  add-agent)
    [[ -z "$AGENT_NAME" ]] && { echo "--agent-name required" >&2; exit 1; }
    add_agent "$AGENT_NAME" ;;
  complete-artifact)
    [[ -z "$ARTIFACT_ID" ]] && { echo "--artifact-id required" >&2; exit 1; }
    complete_artifact "$ARTIFACT_ID" ;;
  update-artifact)
    [[ -z "$ARTIFACT_ID" ]]    && { echo "--artifact-id required" >&2;    exit 1; }
    [[ -z "$ARTIFACT_FIELD" ]] && { echo "--artifact-field required" >&2; exit 1; }
    update_artifact "$ARTIFACT_ID" "$ARTIFACT_FIELD" "$ARTIFACT_VALUE" ;;
  skip-artifact)
    [[ -z "$ARTIFACT_ID" ]] && { echo "--artifact-id required" >&2; exit 1; }
    skip_artifact "$ARTIFACT_ID" ;;
  check-deps)
    [[ -z "$ARTIFACT_ID" ]] && { echo "--artifact-id required" >&2; exit 1; }
    check_deps "$ARTIFACT_ID" ;;
  archive)
    archive_session ;;
  *)
    echo "Unknown action: $ACTION" >&2
    echo "Valid: init | update | update-multi | read | add-agent | archive | complete-artifact | update-artifact | skip-artifact | check-deps" >&2
    exit 1 ;;
esac
