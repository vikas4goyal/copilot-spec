---
description: Initialize or update the active spec session state file (.spec/session.json). Every spec agent must call this as a pre-requisite to ensure consistent session tracking across a workflow.
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).
Supported actions passed as arguments: `init`, `update`, `add-agent <name>`, `complete-artifact <id>`, `update-artifact <id> <field> <value>`, `skip-artifact <id>`, `check-deps <id>`, `archive`, `read`.
If no action is specified, default to `init`.

When called with **feature description text** (i.e. arguments that are not a recognized action keyword), treat it as an `init` + context-population call:
1. Run `init` (idempotent — safe if session already exists).
2. Derive a short kebab-case `feature.name` and root `branch_name` from the description (e.g. `"Spring Boot project with strict testing"` → `spring-boot-strict-testing`).
3. Run `add-agent` for the calling agent (if identifiable from context).
4. Populate `feature.description` and `feature.name` in the session using `update-multi`.

## Purpose

The session state file (`.spec/session.json`) is the **single source of truth** for the current active spec workflow. It serves two roles simultaneously:

1. **Session metadata** — feature name, git branch, feature directory, which agents ran, and when.
2. **Artifact pipeline graph** — every command in the workflow is an artifact node with its dependency list, live status, agent summary, and handoff prompt to the next agent.

Together these let any agent answer three questions without human input:
- "What has already been done?" → read `artifacts[*].status` and `artifacts[*].summary`
- "Am I allowed to run yet?" → read `artifacts[<my-id>].missingDeps`
- "What should I tell the next agent?" → write `artifacts[<my-id>].handoff` then call `complete-artifact`

There is **always at most one** `.spec/session.json`. Once a flow is complete the `spec.release` agent archives it to `.spec/features/<feature-name>/session.json`.

---

## Artifact Pipeline — Dependency Map

The `artifacts` array encodes the complete workflow graph:

```
constitution  (independent, optional)
     ↓ (recommended, not required)
specify       ──────────────────────────────── required
     ↓                   ↓              ↓
 clarify (opt)        plan (req)    checklist (opt)
                         ↓
                       tasks ─────────────────────── required
                         ↓                      ↓       
                      analyze (opt)         implement 
                                            (req)    
```

| id              | command                | required | deps               |
|-----------------|------------------------|----------|--------------------|
| `constitution`  | `/spec.constitution`   | false    | —                  |
| `specify`       | `/spec.specify`        | true     | —                  |
| `clarify`       | `/spec.clarify`        | false    | specify            |
| `plan`          | `/spec.plan`           | true     | specify            |
| `checklist`     | `/spec.checklist`      | false    | specify            |
| `tasks`         | `/spec.tasks`          | true     | plan               |
| `analyze`       | `/spec.analyze`        | false    | plan, tasks        |
| `implement`     | `/spec.implement`      | true     | tasks              |

**Artifact statuses:**
- `ready` — dependencies met, can run now
- `pending` — waiting for one or more `missingDeps` to complete
- `in_progress` — currently executing (set manually by agent on start)
- `complete` — finished successfully
- `skipped` — explicitly bypassed (dependents are still unblocked)

---

## Pre-Requisite Bootstrap (every agent must do this first)

```powershell
# 1. Ensure session exists
.spec/scripts/powershell/manage-session.ps1 -Action init

# 2. Record that this agent is running
.spec/scripts/powershell/manage-session.ps1 -Action add-agent -AgentName "spec.<agent-name>"

# 3. Check that prerequisites are met before doing any work
.spec/scripts/powershell/manage-session.ps1 -Action check-deps -ArtifactId "<my-artifact-id>"
```

```bash
bash .spec/scripts/bash/manage-session.sh --action init
bash .spec/scripts/bash/manage-session.sh --action add-agent --agent-name "spec.<agent-name>"
bash .spec/scripts/bash/manage-session.sh --action check-deps --artifact-id "<my-artifact-id>"
```

If `check-deps` reports missing dependencies, **stop and tell the user** what to run first (e.g. "You need to run `/spec.plan` before `/spec.tasks`").

---

## Execution

Run the appropriate script from the repo root:

**PowerShell:**
```
.spec/scripts/powershell/manage-session.ps1 -Action init
```

**Bash:**
```
bash .spec/scripts/bash/manage-session.sh --action init
```

The `init` action is idempotent — safe to call on every agent startup.

### Branch Creation (part of session init)

After `init`, create the feature branch from `session.json`'s `branch_name`. The script reads the branch name directly from session — no description or slug generation needed. If the branch already exists (locally or remotely), it automatically appends `-v1`, `-v2`, etc. and updates `session.json` with the actual name used.

**PowerShell:**
```powershell
.spec/scripts/powershell/create-new-feature.ps1 -Json
```

**Bash:**
```bash
bash .spec/scripts/bash/create-new-feature.sh --json
```

The script will:
1. Read `branch_name` from `session.json` — exits with an error if not set
2. If already on that branch, exit immediately (nothing to do)
3. Try to create the branch; if it exists, try `branch_name-v1`, `branch_name-v2`, ...
4. Update `session.json` with the actual `branch_name` and `feature_dir` used
5. Create the `specs/<branch_name>/` directory and seed `spec.md` from the template

---

## Script Reference

### `init`
Creates `.spec/session.json` from the template with a new session ID and detected git context. No-op if file already exists.

### `read`
Prints the current session JSON to stdout.

### `add-agent` — record agent execution
```powershell
.spec/scripts/powershell/manage-session.ps1 -Action add-agent -AgentName "spec.plan"
```
```bash
bash .spec/scripts/bash/manage-session.sh --action add-agent --agent-name "spec.plan"
```
Appends to `pipeline.agents_run` and sets `pipeline.current_agent`.

### `update` — set a single session field
```powershell
.spec/scripts/powershell/manage-session.ps1 -Action update -Field "branch_name" -Value "001-my-feature"
```
```bash
bash .spec/scripts/bash/manage-session.sh --action update --field branch_name --value "001-my-feature"
```

### `update-multi` — set multiple session fields atomically
```powershell
.spec/scripts/powershell/manage-session.ps1 -Action update-multi -JsonPatch '{"name":"modern-register-ui","branch_name":"001-modern-register-ui","feature_num":"001","feature_dir":"specs/001-modern-register-ui"}'
```
```bash
bash .spec/scripts/bash/manage-session.sh --action update-multi --json-patch '{"name":"modern-register-ui","branch_name":"001-modern-register-ui"}'
```

### `update-artifact` — write summary or handoff (call before `complete-artifact`)

**Write what this agent produced** (other agents read this as context):
```powershell
.spec/scripts/powershell/manage-session.ps1 -Action update-artifact `
  -ArtifactId "specify" `
  -ArtifactField "summary" `
  -ArtifactValue "Defined registration UI spec. 3 user flows, 12 requirements. OAuth2 provider TBD."
```

**Write the handoff prompt for the next agent** (becomes `pipeline.next_prompt` after `complete-artifact`):
```powershell
.spec/scripts/powershell/manage-session.ps1 -Action update-artifact `
  -ArtifactId "specify" `
  -ArtifactField "handoff" `
  -ArtifactValue "Building a modern registration UI. OAuth2 login, email/password fallback, mobile-first. Tech stack: React + TypeScript + Node.js. Key constraint: must integrate with existing auth-service API."
```

```bash
bash .spec/scripts/bash/manage-session.sh --action update-artifact \
  --artifact-id "specify" --artifact-field "summary" \
  --artifact-value "Defined registration UI spec. OAuth2 required, mobile-first."
bash .spec/scripts/bash/manage-session.sh --action update-artifact \
  --artifact-id "specify" --artifact-field "handoff" \
  --artifact-value "React + TypeScript, OAuth2, mobile-first registration flow."
```

Valid `--artifact-field` values: `summary`, `handoff`, `status`, `outputPath`.

### `complete-artifact` — mark done, cascade unblocking, set next step
Call this **after** writing summary and handoff. It:
1. Sets `artifacts[id].status = "complete"` and stamps `completedAt`
2. Removes `id` from `missingDeps` of every downstream artifact; sets them `ready` when unblocked
3. Copies `handoff` → `pipeline.next_prompt`
4. Computes `pipeline.next_recommended` (first ready required artifact, else first ready artifact)
5. Recalculates `isComplete`

```powershell
.spec/scripts/powershell/manage-session.ps1 -Action complete-artifact -ArtifactId "specify"
```
```bash
bash .spec/scripts/bash/manage-session.sh --action complete-artifact --artifact-id "specify"
```

### `skip-artifact` — bypass an optional step
Marks the artifact `skipped` and cascades the same unblocking as `complete-artifact`. Warns if the artifact is `required`.
```powershell
.spec/scripts/powershell/manage-session.ps1 -Action skip-artifact -ArtifactId "clarify"
```
```bash
bash .spec/scripts/bash/manage-session.sh --action skip-artifact --artifact-id "clarify"
```

### `check-deps` — verify prerequisites before running
```powershell
.spec/scripts/powershell/manage-session.ps1 -Action check-deps -ArtifactId "tasks"
```
```bash
bash .spec/scripts/bash/manage-session.sh --action check-deps --artifact-id "tasks"
```
Output if blocked:
```
[session] 'tasks' is blocked. Missing dependencies:
  → Run /spec.plan first  (id: plan)
```

### `archive`
Marks the session `completed` and moves `.spec/session.json` to `.spec/features/<branch-name>/session.json`.

---

## Agent Lifecycle Pattern

Every spec agent follows this exact pattern:

```
1. init          → ensure session exists
2. add-agent     → record this agent started
3. check-deps    → verify prerequisites; abort with guidance if blocked
4. [do work]
5. update-artifact <id> summary "<what was produced>"
6. update-artifact <id> handoff "<context for the next agent>"
7. complete-artifact <id>   → cascades unblocking + sets pipeline.next_recommended
```

Agents should also read context from previously completed artifacts before starting:
```powershell
$session = Get-Content .spec/session.json -Raw | ConvertFrom-Json

# Read what specify produced
$specSummary = ($session.artifacts | Where-Object { $_.id -eq 'specify' }).summary

# Read handoff from the previous step
$handoff = $session.pipeline.next_prompt
```
```bash
spec_summary=$(jq -r '.artifacts[] | select(.id=="specify") | .summary' .spec/session.json)
handoff=$(jq -r '.pipeline.next_prompt // empty' .spec/session.json)
```

---

## Reading Session State

```powershell
$session = Get-Content .spec/session.json -Raw | ConvertFrom-Json

# Root identity fields
$session.id                            # session ID
$session.name                          # feature name
$session.branch_name                   # active branch (e.g. "001-modern-register-ui")
$session.description                   # feature description
$session.feature_dir                   # e.g. "specs/001-modern-register-ui"
$session.status                        # active / completed
$session.pipeline.next_recommended     # e.g. "/spec.plan"
$session.pipeline.next_prompt          # handoff prompt from last completed agent
$session.isComplete                    # true when all required artifacts are done

# Find a specific artifact
$planArtifact = $session.artifacts | Where-Object { $_.id -eq 'plan' }
$planArtifact.status                   # ready / pending / complete / skipped
$planArtifact.missingDeps              # [] when ready
$planArtifact.summary                  # what spec.plan produced
```
```bash
jq -r '.name'                          .spec/session.json
jq -r '.branch_name'                   .spec/session.json
jq -r '.pipeline.next_recommended'     .spec/session.json
jq -r '.pipeline.next_prompt'          .spec/session.json
jq -r '.isComplete'                    .spec/session.json
jq -r '.artifacts[] | select(.id=="plan") | .status'   .spec/session.json
jq -r '.artifacts[] | select(.id=="plan") | .summary'  .spec/session.json
```

---

## Session JSON Schema (v2.0)

```json
{
  "_schema": "spec-session/2.0",
  "id": "20260423-143022-AbCd",
  "name": "modern-register-ui",
  "description": "Redesign the registration UI with OAuth2 and mobile-first layout",
  "branch_name": "001-modern-register-ui",
  "feature_num": "001",
  "feature_dir": "specs/001-modern-register-ui",
  "schemaName": "spec-driven",
  "isComplete": false,
  "applyRequires": ["tasks"],
  "created_at": "2026-04-23T14:30:22Z",
  "updated_at": "2026-04-23T14:45:10Z",
  "status": "active",

  "pipeline": {
    "current_agent": "spec.plan",
    "last_completed": "specify",
    "next_recommended": "/spec.plan",
    "next_prompt": "Building a modern registration UI. OAuth2 login, email/password fallback, mobile-first. React + TypeScript + Node.js. Must integrate with existing auth-service API.",
    "agents_run": [
      { "agent": "spec.specify", "ran_at": "2026-04-23T14:30:22Z" }
    ]
  },

  "artifacts": [
    {
      "id": "specify",
      "command": "/spec.specify",
      "label": "Feature Specification",
      "outputPath": "specs/001-modern-register-ui/spec.md",
      "status": "complete",
      "required": true,
      "deps": [],
      "missingDeps": [],
      "summary": "Defined registration UI spec. 3 user flows, 12 functional requirements. OAuth2 + email/password auth.",
      "handoff": "React + TypeScript, OAuth2, mobile-first registration flow. Must integrate with auth-service.",
      "completedAt": "2026-04-23T14:44:00Z"
    },
    {
      "id": "plan",
      "command": "/spec.plan",
      "label": "Technical Implementation Plan",
      "outputPath": "specs/001-modern-register-ui/plan.md",
      "status": "ready",
      "required": true,
      "deps": ["specify"],
      "missingDeps": [],
      "summary": null,
      "handoff": null,
      "completedAt": null
    }
  ]
}
```

---

## Key Fields Reference

| Field | Set By | Description |
|---|---|---|
| `id` | `init` | Unique session ID (timestamp + random suffix) |
| `name` | `spec.session` / `update-multi` | Feature name — derived from arguments or user input |
| `description` | `spec.session` / `update-multi` | Full feature description |
| `branch_name` | `spec.session` / `update-multi` | Active branch — derived from args or git; used for archiving |
| `feature_num` | `update-multi` | Sequential feature number (e.g. `"001"`) |
| `feature_dir` | `update-multi` | Relative path to the feature's spec folder |
| `status` | `init` / `archive` | `active` while in progress, `completed` after archive |
| `created_at` | `init` | ISO timestamp when session was created |
| `updated_at` | auto (every save) | ISO timestamp of last write |
| `isComplete` | auto (complete-artifact) | `true` when all required artifacts are done/skipped |
| `applyRequires` | template | Artifact IDs that must be complete before `/spec.implement` |
| `pipeline.next_recommended` | auto (complete-artifact) | Next command to run |
| `pipeline.next_prompt` | auto (from artifact.handoff) | Context prompt written by the last agent for the next one |
| `pipeline.agents_run` | add-agent | Audit trail of every agent that ran |
| `artifacts[].status` | agents / scripts | `ready` \| `pending` \| `in_progress` \| `complete` \| `skipped` |
| `artifacts[].summary` | completing agent | What this step produced (read by downstream agents) |
| `artifacts[].handoff` | completing agent | Prompt/context to pass to the next agent |
| `artifacts[].missingDeps` | auto (complete-artifact) | Deps not yet met; empty = can run |

## Graceful Degradation

- If `.spec/templates/session-state-template.json` is missing, log a warning and continue.
- If the script fails, log a warning but do **not** fail the calling agent.
- If `check-deps` finds blockers, surface them clearly — do not silently run.

## Output

On successful `init`:
```
[session] Initialized session at .spec/session.json (id: 20260423-143022-AbCd)
```
On `complete-artifact`:
```
[session] Artifact 'specify' marked complete. Next: /spec.plan
```
On `check-deps` (blocked):
```
[session] 'tasks' is blocked. Missing dependencies:
  → Run /spec.plan first  (id: plan)
```
