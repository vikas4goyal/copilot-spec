#!/usr/bin/env bash
# Manage the active spec session state file (.spec/session.json)
#
# Usage:
#   manage-session.sh --action init [--name "oauth2-login"] [--description "..."]
#   manage-session.sh --action get --field name
#   manage-session.sh --action get-multi --fields "name,branch_name,feature_dir"
#   manage-session.sh --action update --field name --value "oauth2-login-google"
#   manage-session.sh --action update-multi --json-patch '{"name":"oauth2-login-google","description":"Implements OAuth2 login with Google."}'
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
FIELDS=""
JSON_PATCH=""
AGENT_NAME=""
ARTIFACT_ID=""
ARTIFACT_FIELD=""
ARTIFACT_VALUE=""
INIT_NAME=""
INIT_DESCRIPTION=""
AS_JSON=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --action)          ACTION="$2";           shift 2 ;;
    --field)           FIELD="$2";            shift 2 ;;
    --fields)          FIELDS="$2";           shift 2 ;;
    --value)           VALUE="$2";            shift 2 ;;
    --json-patch)      JSON_PATCH="$2";       shift 2 ;;
    --agent-name)      AGENT_NAME="$2";       shift 2 ;;
    --artifact-id)     ARTIFACT_ID="$2";      shift 2 ;;
    --artifact-field)  ARTIFACT_FIELD="$2";   shift 2 ;;
    --artifact-value)  ARTIFACT_VALUE="$2";   shift 2 ;;
    --name)            INIT_NAME="$2";        shift 2 ;;
    --description)     INIT_DESCRIPTION="$2"; shift 2 ;;
    --json)            AS_JSON=true;          shift ;;
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
    echo "[session] Session already exists — reusing." >&2

    # Fill missing name/description non-destructively
    local changed=false

    if [[ -n "$INIT_NAME" ]]; then
      local cur_name
      if command -v jq &>/dev/null; then
        cur_name=$(jq -r '.name // empty' "$SESSION_FILE" 2>/dev/null || true)
      else
        cur_name=$(python3 -c "import json; d=json.load(open('$SESSION_FILE')); print(d.get('name') or '')" 2>/dev/null || true)
      fi
      if [[ -z "$cur_name" ]]; then
        local tmp; tmp=$(mktemp)
        if command -v jq &>/dev/null; then
          jq --arg v "$INIT_NAME" '.name=$v' "$SESSION_FILE" > "$tmp" && mv "$tmp" "$SESSION_FILE"
        else
          python3 - "$SESSION_FILE" "name" "$INIT_NAME" <<'PYEOF'
import json, sys; pf, k, v = sys.argv[1:]
with open(pf) as f: s = json.load(f)
s[k] = v
with open(pf, 'w') as f: json.dump(s, f, indent=2)
PYEOF
        fi
        changed=true
      fi
    fi

    if [[ -n "$INIT_DESCRIPTION" ]]; then
      local cur_desc
      if command -v jq &>/dev/null; then
        cur_desc=$(jq -r '.description // empty' "$SESSION_FILE" 2>/dev/null || true)
      else
        cur_desc=$(python3 -c "import json; d=json.load(open('$SESSION_FILE')); print(d.get('description') or '')" 2>/dev/null || true)
      fi
      if [[ -z "$cur_desc" ]]; then
        local tmp; tmp=$(mktemp)
        if command -v jq &>/dev/null; then
          jq --arg v "$INIT_DESCRIPTION" '.description=$v' "$SESSION_FILE" > "$tmp" && mv "$tmp" "$SESSION_FILE"
        else
          python3 - "$SESSION_FILE" "description" "$INIT_DESCRIPTION" <<'PYEOF'
import json, sys; pf, k, v = sys.argv[1:]
with open(pf) as f: s = json.load(f)
s[k] = v
with open(pf, 'w') as f: json.dump(s, f, indent=2)
PYEOF
        fi
        changed=true
      fi
    fi

    if [[ "$changed" == true ]]; then
      echo "[session] Applied missing name/description to existing session." >&2
    fi

    cat "$SESSION_FILE"; return 0
  fi

  [[ -f "$TEMPLATE_FILE" ]] || { echo "[session] ERROR: Template not found at $TEMPLATE_FILE" >&2; exit 1; }

  local now id
  now=$(get_now); id=$(new_session_id)

  if command -v jq &>/dev/null; then
    jq --arg id "$id" --arg now "$now" \
       --arg name "${INIT_NAME:-}" --arg desc "${INIT_DESCRIPTION:-}" \
       '.id=$id | .created_at=$now | .updated_at=$now | .status="active" |
        if $name != "" then .name=$name else . end |
        if $desc  != "" then .description=$desc else . end' \
       "$TEMPLATE_FILE" > "$SESSION_FILE"
  else
    python3 - "$TEMPLATE_FILE" "$SESSION_FILE" "$id" "$now" "${INIT_NAME:-}" "${INIT_DESCRIPTION:-}" <<'PYEOF'
import json, sys
tmpl, dest, sid, now, name, desc = sys.argv[1:]
with open(tmpl) as f: s = json.load(f)
s.update(id=sid, created_at=now, updated_at=now, status='active')
if name: s['name'] = name
if desc:  s['description'] = desc
with open(dest, 'w') as f: json.dump(s, f, indent=2)
PYEOF
  fi
  echo "[session] Initialized session at $SESSION_FILE (id: $id)" >&2
  cat "$SESSION_FILE"
}

# ---------------------------------------------------------------------------
# get  — read a single field by dot-notation path (value to stdout)
# ---------------------------------------------------------------------------
get_field() {
  local path="$1"
  if [[ ! -f "$SESSION_FILE" ]]; then
    echo "[session] No active session." >&2; echo ""; return 0
  fi
  if command -v jq &>/dev/null; then
    # Support dot-notation up to two levels; deeper paths uncommon
    jq -r --arg p "$path" '
      ($p | split(".")) as $parts |
      if ($parts | length) == 1 then .[$parts[0]]
      elif ($parts | length) == 2 then .[$parts[0]][$parts[1]]
      else .[$parts[0]][$parts[1]][$parts[2]] end // ""
    ' "$SESSION_FILE" 2>/dev/null || echo ""
  else
    python3 - "$SESSION_FILE" "$path" <<'PYEOF'
import json, sys
pf, path = sys.argv[1:]
with open(pf) as f: s = json.load(f)
parts = path.split('.')
cur = s
for p in parts:
    if cur is None: break
    cur = cur.get(p)
print(cur if cur is not None else "")
PYEOF
  fi
}

# ---------------------------------------------------------------------------
# get-multi  — read multiple fields by comma-separated paths (JSON to stdout)
# ---------------------------------------------------------------------------
get_multi() {
  local paths="$1"
  if [[ ! -f "$SESSION_FILE" ]]; then
    echo "[session] No active session." >&2; echo "{}"; return 0
  fi
  if command -v jq &>/dev/null; then
    # Build a jq expression that extracts each path into a named key
    local jq_expr="{" first=true
    IFS=',' read -ra path_arr <<< "$paths"
    for raw_path in "${path_arr[@]}"; do
      local p; p=$(echo "$raw_path" | tr -d ' ')
      [[ "$first" == true ]] && first=false || jq_expr+=","
      # Quote the key; support up to 2-level dot-path
      local parts_count; parts_count=$(echo "$p" | tr -cd '.' | wc -c)
      if [[ "$parts_count" -eq 0 ]]; then
        jq_expr+="\"${p}\": (.${p} // null)"
      elif [[ "$parts_count" -eq 1 ]]; then
        local p1 p2; p1=${p%%.*}; p2=${p#*.}
        jq_expr+="\"${p}\": (.${p1}.${p2} // null)"
      else
        jq_expr+="\"${p}\": null"
      fi
    done
    jq_expr+="}"
    jq "$jq_expr" "$SESSION_FILE" 2>/dev/null || echo "{}"
  else
    python3 - "$SESSION_FILE" "$paths" <<'PYEOF'
import json, sys
pf, paths_str = sys.argv[1:]
with open(pf) as f: s = json.load(f)
result = {}
for raw in paths_str.split(','):
    path = raw.strip()
    parts = path.split('.')
    cur = s
    for p in parts:
        if not isinstance(cur, dict): cur = None; break
        cur = cur.get(p)
    result[path] = cur
print(json.dumps(result))
PYEOF
  fi
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
    # Support two-level dot paths (e.g. pipeline.current_agent)
    jq --arg f "$field" --arg v "$value" --arg now "$now" '
      . as $root |
      ($f | split(".")) as $parts |
      if ($parts | length) == 2
      then .[$parts[0]][$parts[1]] = $v
      else .[$parts[0]] = $v end |
      .updated_at = $now
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
s['updated_at'] = now
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
      '.pipeline.agents_run += [$entry] | .pipeline.current_agent=$a | .updated_at=$now' \
      "$SESSION_FILE" > "$tmp" && mv "$tmp" "$SESSION_FILE"
  else
    python3 - "$SESSION_FILE" "$agent" "$now" <<'PYEOF'
import json, sys
pf, agent, now = sys.argv[1:]
with open(pf) as f: s = json.load(f)
s['pipeline']['agents_run'].append({'agent': agent, 'ran_at': now})
s['pipeline']['current_agent'] = agent
s['updated_at'] = now
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
       .updated_at = $now
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
s['updated_at'] = now
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
      .updated_at = $now
    ' "$SESSION_FILE" > "$tmp" && mv "$tmp" "$SESSION_FILE"
  else
    python3 - "$SESSION_FILE" "$id" "$field" "$value" "$now" <<'PYEOF'
import json, sys
pf, art_id, field, value, now = sys.argv[1:]
with open(pf) as f: s = json.load(f)
for a in s['artifacts']:
    if a['id'] == art_id: a[field] = value; break
s['updated_at'] = now
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
       .updated_at = $now
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
s['updated_at'] = now
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
    feature_name=$(jq -r '.branch_name // .name // .id // empty' "$SESSION_FILE")
  else
    feature_name=$(python3 -c "import json; d=json.load(open('$SESSION_FILE')); print(d.get('branch_name') or d.get('name') or d.get('id') or '')")
  fi

  safe_name="${feature_name//[^a-zA-Z0-9\-_.]/-}"
  archive_dir="$REPO_ROOT/.spec/features/$safe_name"
  mkdir -p "$archive_dir"

  if command -v jq &>/dev/null; then
    local tmp; tmp=$(mktemp)
    jq --arg now "$now" '.status="completed" | .updated_at=$now' \
      "$SESSION_FILE" > "$tmp" && mv "$tmp" "$SESSION_FILE"
  else
    python3 - "$SESSION_FILE" "$now" <<'PYEOF'
import json, sys
pf, now = sys.argv[1:]
with open(pf) as f: s = json.load(f)
s['status'] = 'completed'
s['updated_at'] = now
with open(pf, 'w') as f: json.dump(s, f, indent=2)
PYEOF
  fi

  mv "$SESSION_FILE" "$archive_dir/session.json"
  echo "[session] Archived session to $archive_dir/session.json"
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
case "$ACTION" in
  init)              initialize_session ;;
  get)
    [[ -z "$FIELD" && -z "$FIELDS" ]] && { echo "--field (or --fields) required" >&2; exit 1; }
    get_field "${FIELD:-$FIELDS}" ;;
  get-multi)
    [[ -z "$FIELDS" ]] && { echo "--fields required" >&2; exit 1; }
    get_multi "$FIELDS" ;;
  update)
    [[ -z "$FIELD" ]] && { echo "--field required" >&2; exit 1; }
    update_field "$FIELD" "$VALUE" ;;
  update-multi)
    [[ -z "$JSON_PATCH" ]] && { echo "--json-patch required" >&2; exit 1; }
    [[ -f "$SESSION_FILE" ]] || initialize_session > /dev/null
    if command -v jq &>/dev/null; then
      tmp=$(mktemp); now=$(get_now)
      jq --argjson patch "$JSON_PATCH" --arg now "$now" \
        '. * $patch | .updated_at=$now' "$SESSION_FILE" > "$tmp" && mv "$tmp" "$SESSION_FILE"
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
s['updated_at'] = now
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
