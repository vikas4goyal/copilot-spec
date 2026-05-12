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
- Checks every required dep is present in `artifacts[<id>].status === "complete"` or `"skipped"`.
- If any dep is missing → **stop and error**: `"Run /spec.<dep> first (id: <dep>)"`
- If deps satisfied → runs `pre_agent.ts` which marks artifact `in_progress` and records the agent in `pipeline.agents_run`.

#### `complete` — finish work, mark artifact done

```json
{
  "action": "complete",
  "artifactId": "constitution",
  "summary": "One sentence describing what was produced.",
  "outputPath": ".spec/memory/constitution.md",
  "next": {
    "agent": "spec.specify",
    "prompt": "Context the next agent needs to continue."
  }
}
```

- Runs `post_agent.ts` which:
  - Marks artifact `complete`, increments `revision`, snapshots `based_on`
  - Propagates stale status to downstream artifacts
  - Creates a prompt record in `prompts` map for the next agent
  - Recalculates `pipeline.eligible_agents`, `blocked_agents`, `next_recommended`

#### `skip` — mark artifact intentionally skipped

```json
{ "action": "skip", "artifactId": "constitution" }
```

- Runs `manage_session.ts --action skip-artifact` which sets `artifacts.constitution.status = "skipped"`.
- Skipped artifacts satisfy dependency checks.

#### `archive` — seal the session (used by `spec.release` only)

```json
{ "action": "archive" }
```

- Runs `manage_session.ts --action archive` which moves `session.json` to `.spec/features/<branch_name>/session.json`.

| Field | Required for | Description |
|---|---|---|
| `action` | all | `start` \| `complete` \| `skip` \| `archive` |
| `artifactId` | start, complete, skip | ID from the dependency map |
| `summary` | complete | One-sentence description stored in `artifacts.<id>.summary` |
| `outputPath` | complete (optional) | Where the artifact was written |
| `next.agent` | complete (optional) | Agent name to handoff to, e.g. `spec.specify` |
| `next.prompt` | complete (optional) | Handoff context stored as a prompt record |

## Purpose

`spec.session.manage` is the active-session lifecycle agent. Use it only after the workflow has been initialized.

It owns:
- Agent entry bookkeeping
- Dependency checks for artifacts
- Artifact status transitions (`in_progress`, `complete`, `skipped`, `stale`)
- Artifact metadata updates (`summary`, `outputPath`, `revision`, `based_on`)
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
                                               ↓
                                            release (opt)
```

| id              | command              | required | hard deps           |
|-----------------|----------------------|----------|---------------------|
| `constitution`  | `/spec.constitution` | false    | —                   |
| `specify`       | `/spec.specify`      | true     | —                   |
| `clarify`       | `/spec.clarify`      | false    | specify             |
| `plan`          | `/spec.plan`         | true     | specify             |
| `checklist`     | `/spec.checklist`    | false    | specify             |
| `tasks`         | `/spec.tasks`        | true     | plan                |
| `analyze`       | `/spec.analyze`      | false    | specify, plan, tasks|
| `implement`     | `/spec.implement`    | true     | tasks               |
| `release`       | `/spec.release`      | false    | implement           |

**Artifact statuses:** `pending` | `optional` | `blocked` | `in_progress` | `complete` | `stale` | `skipped` | `failed`

## Wrapper Scripts — How Actions Map to Scripts

Normal agents should use the higher-level wrappers:

| Action | Script invoked |
|--------|----------------|
| `start` | `pre_agent.ts` (checks deps + marks `in_progress`) |
| `complete` | `post_agent.ts` (marks complete + stale propagation + next prompt) |
| `skip` | `manage_session.ts --action skip-artifact` |
| `archive` | `manage_session.ts --action archive` |

### Bootstrap (called inside `start`)

```bash
npm --prefix .spec/scripts run run -- ./pre_agent.ts \
  --agent-name "spec.<agent-name>" \
  --artifact-id "<my-artifact-id>"
```

If dep check fails (exit code 1), **stop and tell the user** what to run first.

### Complete (called inside `complete`)

```bash
npm --prefix .spec/scripts run run -- ./post_agent.ts \
  --artifact-id "<my-artifact-id>" \
  --summary "<one-sentence summary>" \
  --handoff-agent "spec.<next-agent>" \
  --handoff "<prompt for next agent>" \
  [--output-path "<path/to/output/file>"]
```

## Internal Script API

The lower-level `manage_session.ts` script also accepts explicit operations directly:

| `--action` | Description |
|---|---|
| `init` | Create session from template (idempotent) |
| `get` | Read a single dot-path field |
| `get-multi` | Read multiple comma-separated dot-path fields as JSON |
| `update` | Set a single dot-path field |
| `update-multi` | Apply a JSON patch object |
| `read` | Print entire session.json |
| `add-agent` | Append agent to `pipeline.agents_run` |
| `complete-artifact` | Mark artifact complete + recalculate pipeline |
| `update-artifact` | Update one field on an artifact |
| `skip-artifact` | Mark artifact as skipped |
| `check-deps` | Verify artifact deps are met (exit 0 = OK, exit 1 = blocked) |
| `archive` | Move session to `.spec/features/<name>/session.json` |

Run from the repo root:

```bash
npm --prefix .spec/scripts run run -- ./manage_session.ts --action <action> [params]
```

> `manage_session.ts` is a TypeScript + Node.js implementation. It does not require `jq` or any external shell dependencies.

## Agent Lifecycle Pattern

Every artifact-producing agent MUST follow this pattern:

```text
1. Call spec.session.manage  { action: "start", artifactId }
   → pre_agent.ts checks deps and marks artifact in_progress
   → If blocked, STOP and tell user what to run first

2. [do work — read spec.md, plan.md, tasks.md, etc.]

3. Call spec.session.manage  { action: "complete", artifactId, summary, outputPath, next }
   → post_agent.ts marks complete, increments revision, propagates stale, creates next prompt
```

## Session JSON Schema (`spec-session/2.0`)

`pipeline` is recalculated on every `complete-artifact` or `skip-artifact`. The `artifacts` map is keyed by artifact ID, not an array.

```json
{
  "_schema": "spec-session/2.0",
  "id": "20260502-143022-AbCd",
  "name": "modern-register-ui",
  "description": "Redesign the registration UI with OAuth2 and mobile-first layout",
  "branch_name": "20260502-modern-register-ui",
  "feature_dir": ".spec/specs/20260502-modern-register-ui",
  "schemaName": "spec-driven",
  "status": "active",
  "isComplete": false,
  "pipeline": {
    "current_agent": "spec.specify",
    "last_completed": "constitution",
    "eligible_agents": ["/spec.constitution", "/spec.specify", "/spec.clarify"],
    "blocked_agents": {
      "/spec.plan": "Requires spec.md to exist in the feature directory",
      "/spec.tasks": "Requires /spec.plan to be complete first"
    },
    "next_recommended": "/spec.specify",
    "next_prompt_id": "prompt_001",
    "next_prompt": "Constitution v1.2.0 ratified. Reflect principles in spec requirements.",
    "agents_run": [
      { "agent": "spec.session.init", "ran_at": "2026-05-02T14:30:22Z" },
      { "agent": "spec.constitution", "ran_at": "2026-05-02T14:44:00Z" }
    ],
    "transition_history": [],
    "warnings": [],
    "rework_counts": {},
    "max_rework_per_artifact": 3
  },
  "artifacts": {
    "constitution": {
      "status": "complete",
      "required": false,
      "revision": 1,
      "outputPath": ".spec/memory/constitution.md",
      "based_on": {},
      "summary": "Constitution amended to v1.2.0: added Observability principle.",
      "started_at": "2026-05-02T14:44:00Z",
      "completed_at": "2026-05-02T14:50:00Z",
      "history": [{ "revision": 1, "status": "complete", "summary": "...", "based_on": {}, "completed_at": "2026-05-02T14:50:00Z" }]
    },
    "specify": {
      "status": "in_progress",
      "required": true,
      "revision": 0,
      "outputPath": null,
      "based_on": {},
      "summary": null,
      "started_at": "2026-05-02T14:51:00Z",
      "completed_at": null,
      "history": []
    },
    "plan": {
      "status": "blocked",
      "required": true,
      "revision": 0,
      "outputPath": null,
      "based_on": { "specify": 0 },
      "summary": null,
      "started_at": null,
      "completed_at": null,
      "history": []
    }
  },
  "prompts": {
    "prompt_001": {
      "id": "prompt_001",
      "target_agent": "spec.specify",
      "command": "/spec.specify",
      "prompt": "Constitution v1.2.0 ratified. Reflect principles in spec requirements.",
      "status": "recommended",
      "created_at": "2026-05-02T14:50:00Z"
    }
  }
}
```

## Key Fields Reference

| Field | Set By | Description |
|---|---|---|
| `pipeline.current_agent` | `pre_agent.ts` | Agent that is currently in_progress |
| `pipeline.last_completed` | `post_agent.ts` | Most recently completed artifact ID |
| `pipeline.eligible_agents` | `post_agent.ts` | Commands currently unblocked |
| `pipeline.blocked_agents` | `post_agent.ts` | Commands blocked with reason strings |
| `pipeline.next_recommended` | `post_agent.ts` | Suggested next command to run |
| `pipeline.next_prompt_id` | `post_agent.ts` | ID of the recommended prompt record |
| `pipeline.next_prompt` | `post_agent.ts` | Text of the recommended prompt |
| `pipeline.agents_run` | `pre_agent.ts` | Full history of agent runs |
| `pipeline.rework_counts` | `pre_agent.ts` | How many times each artifact was re-run |
| `artifacts.<id>.status` | `pre_agent.ts` / `post_agent.ts` | Current status of the artifact |
| `artifacts.<id>.revision` | `post_agent.ts` | Increments on each `complete` with changes |
| `artifacts.<id>.based_on` | `post_agent.ts` | Revision snapshot of soft-deps at completion time |
| `artifacts.<id>.summary` | `post_agent.ts` | What this artifact produced |
| `artifacts.<id>.history` | `post_agent.ts` | Full revision history entries |
| `prompts.<id>` | `post_agent.ts` | Prompt records for next-agent handoff |

## Reading Context from Completed Artifacts

```typescript
import * as fs from "node:fs";

const session = JSON.parse(fs.readFileSync(".spec/session.json", "utf-8"));
const specify = session.artifacts.specify;
const plan = session.artifacts.plan;

// Read summaries from completed artifacts
const specSummary = specify?.summary;

// Read next recommended prompt
const nextPrompt = session.pipeline.next_recommended;
const nextPromptText = session.pipeline.next_prompt;

// Check if artifact is complete
const planDone = plan?.status === "complete" || plan?.status === "skipped";
```

## Output Examples

```text
[session] Initialized session at .spec/session.json (id: 20260502-143022-AbCd)
[session] Session already exists — reusing.
[pre-agent] ✓ spec.plan is eligible and marked in_progress.
[post-agent] ✓ plan marked complete (revision 1).
[session] Artifact 'plan' marked complete. Next: /spec.tasks
[session] 'tasks' is blocked: plan is stale — run /spec.plan first to refresh the plan
```
