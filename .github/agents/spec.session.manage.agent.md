---
description: Manage an existing spec workflow session (.spec/session.json): bootstrap agent entry, update artifact state, complete or skip steps, and archive the session when the flow ends.
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

`$ARGUMENTS` **MUST** be a JSON object when called by another agent. Parse it and use the fields to drive execution.

### Caller JSON Payload Schema

Three actions cover the full agent lifecycle. Every agent calls `start` before doing work and `complete` (or `skip`) when done.

#### `start` — register as running, check deps

```json
{ "action": "start", "artifactId": "constitution" }
```

- Looks up `artifactId` in the dependency map.
- Checks every required dep is present in `pipeline.completed` **or** `pipeline.skipped`.
- If any dep is missing → **stop and error**: `"Run /spec.<dep> first (id: <dep>)"`
- If deps satisfied → push `artifactId` onto `pipeline.running`.

#### `complete` — finish work, pop from running

```json
{
  "action": "complete",
  "artifactId": "constitution",
  "summary": "One sentence describing what was produced.",
  "next": {
    "agent": "spec.specify",
    "prompt": "Context the next agent needs to continue."
  }
}
```

- Remove `artifactId` from `pipeline.running`.
- Add `artifactId` to `pipeline.completed`.
- Append `{ id, summary, completedAt }` to `artifacts[]`.
- If `next` provided → write it to `pipeline.next`.

#### `skip` — mark artifact intentionally skipped

```json
{ "action": "skip", "artifactId": "constitution" }
```

- Add `artifactId` to `pipeline.skipped`. Skipped artifacts satisfy dependency checks.

#### `archive` — seal the session (used by `spec.release` only)

```json
{ "action": "archive" }
```

- Set `status: "archived"` on the session root.

| Field | Required for | Description |
|---|---|---|
| `action` | all | `start` \| `complete` \| `skip` \| `archive` |
| `artifactId` | start, complete, skip | ID from the dependency map |
| `summary` | complete | One-sentence description stored in `artifacts[].summary` |
| `next.agent` | complete (optional) | Agent name to suggest next, e.g. `spec.specify` |
| `next.prompt` | complete (optional) | Handoff context stored in `pipeline.next` |

## Purpose

`spec.session.manage` is the active-session lifecycle agent. Use it only after the workflow has been initialized.

It owns:
- Agent entry bookkeeping
- Dependency checks for artifacts
- Artifact status transitions (`in_progress`, `complete`, `skipped`)
- Artifact metadata updates (`summary`, `handoff`, `outputPath`)
- Session archival at release time

Do **not** use this agent to start a brand new flow. Use `spec.session.init` first.

## Artifact Pipeline — Dependency Map

```text
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

| id              | command              | required | deps           |
|-----------------|----------------------|----------|----------------|
| `constitution`  | `/spec.constitution` | false    | —              |
| `specify`       | `/spec.specify`      | true     | —              |
| `clarify`       | `/spec.clarify`      | false    | specify        |
| `plan`          | `/spec.plan`         | true     | specify        |
| `checklist`     | `/spec.checklist`    | false    | specify        |
| `tasks`         | `/spec.tasks`        | true     | plan           |
| `analyze`       | `/spec.analyze`      | false    | plan, tasks    |
| `implement`     | `/spec.implement`    | true     | tasks          |

**Artifact statuses:** `ready` | `pending` | `in_progress` | `complete` | `skipped`

## Wrapper Scripts

Normal agents should use the wrappers instead of assembling low-level steps manually:

- `bootstrap-session` → `init` + `add-agent` + `check-deps`
- `pre-agent` → `bootstrap-session` + mark artifact `in_progress`
- `post-agent` → update `summary` + `handoff` + `complete-artifact`

### Bootstrap

**PowerShell:**
```powershell
.spec/scripts/powershell/bootstrap-session.ps1 -AgentName "spec.<agent-name>" -ArtifactId "<my-artifact-id>"
```

**Bash:**
```bash
bash .spec/scripts/bash/bootstrap-session.sh --agent-name "spec.<agent-name>" --artifact-id "<my-artifact-id>"
```

If `check-deps` reports missing dependencies, **stop and tell the user** what to run first.

## Internal Script API

The session-management scripts expose explicit operations:

`update`, `update-multi`, `read`, `add-agent`, `complete-artifact`, `update-artifact`, `skip-artifact`, `check-deps`, `archive`

These remain explicit because `session.json` stores state but does not infer intent such as "this artifact is finished" or "this optional step was intentionally skipped".

Run from the repo root:

**PowerShell:** `.spec/scripts/powershell/manage-session.ps1 -Action <action> [params]`

**Bash:** `bash .spec/scripts/bash/manage-session.sh --action <action> [params]`

### Bash Requirement

`manage-session.sh` is a Bash + `jq` implementation. It should not shell out to Python for JSON mutation. If `jq` is unavailable, the script must fail clearly instead of silently switching runtimes.

## Agent Lifecycle Pattern

Every artifact-producing agent MUST follow this pattern:

```text
1. Call spec.session.manage  { action: "start", artifactId }          ← push to running, check deps
2. [do work]
3. Call spec.session.manage  { action: "complete", artifactId,         ← pop from running, push to completed
                               summary, next }
```

If a dep check fails on `start`, **stop immediately** and tell the user which agent to run first.

Read context from previously completed artifacts before starting work:

```powershell
$session     = Get-Content .spec/session.json -Raw | ConvertFrom-Json
$specSummary = ($session.artifacts | Where-Object { $_.id -eq 'specify' }).summary
$nextPrompt  = $session.pipeline.next.prompt
```

```bash
spec_summary=$(jq -r '.artifacts[] | select(.id=="specify") | .summary' .spec/session.json)
next_prompt=$(jq -r '.pipeline.next.prompt // empty' .spec/session.json)
```

## Session JSON Schema (v3.0)

`pipeline.running` is a **stack** — agents push themselves on `start` and pop themselves on `complete`. An agent invoked by another agent while it is running will appear deeper in the stack.

```json
{
  "_schema": "spec-session/3.0",
  "id": "20260423-143022-AbCd",
  "name": "modern-register-ui",
  "description": "Redesign the registration UI with OAuth2 and mobile-first layout",
  "branch_name": "modern-register-ui",
  "feature_dir": "specs/20260423-modern-register-ui",
  "status": "active",
  "pipeline": {
    "running": ["specify", "constitution"],
    "completed": [],
    "skipped": [],
    "next": {
      "agent": "spec.specify",
      "prompt": "Constitution v1.2.0 ratified. Reflect principles in spec requirements."
    }
  },
  "artifacts": [
    {
      "id": "constitution",
      "summary": "Constitution amended to v1.2.0: added Observability principle.",
      "completedAt": "2026-04-23T14:44:00Z"
    }
  ]
}
```

> **Example stack reading**: `running: ["specify", "constitution"]` means `specify` is the outer agent; it called `constitution` which is currently executing. When `constitution` completes it pops off, leaving `running: ["specify"]`.

## Key Fields

| Field | Set By | Description |
|---|---|---|
| `pipeline.running` | `start` action | Stack of artifact IDs currently executing (last = innermost) |
| `pipeline.completed` | `complete` action | Ordered list of artifact IDs that finished successfully |
| `pipeline.skipped` | `skip` action | Artifact IDs intentionally skipped (count as satisfied deps) |
| `pipeline.next` | `complete` action (`next` field) | Suggested next agent + prompt for the user |
| `artifacts[].id` | `complete` action | Artifact identifier |
| `artifacts[].summary` | `complete` action | What this step produced |
| `artifacts[].completedAt` | `complete` action | ISO-8601 timestamp |

## Output

```text
[session] Recorded agent 'spec.plan' in session.
[session] 'tasks' is blocked. Missing dependencies:
  → Run /spec.plan first  (id: plan)
[session] Artifact 'plan' marked complete. Next: /spec.tasks
```
