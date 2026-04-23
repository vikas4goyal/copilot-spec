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

**Artifact statuses:** `ready` | `pending` | `in_progress` | `complete` | `skipped`

---

## Pre-Requisite Bootstrap (every agent must do this first)

Use the bootstrap script — one call handles init + add-agent + check-deps:

**PowerShell:**
```powershell
.spec/scripts/powershell/bootstrap-session.ps1 -AgentName "spec.<agent-name>" -ArtifactId "<my-artifact-id>"
```

**Bash:**
```bash
bash .spec/scripts/bash/bootstrap-session.sh --agent-name "spec.<agent-name>" --artifact-id "<my-artifact-id>"
```

If `check-deps` reports missing dependencies, **stop and tell the user** what to run first.

---

## Execution

Run the appropriate script from the repo root:

**PowerShell:** `.spec/scripts/powershell/manage-session.ps1 -Action <action> [params]`

**Bash:** `bash .spec/scripts/bash/manage-session.sh --action <action> [params]`

The `init` action is idempotent — safe to call on every agent startup.

### Branch Creation (part of session init)

After `init`, create the feature branch by running:

**PowerShell:**
```powershell
.spec/scripts/powershell/create-new-feature.ps1 -Json
```

**Bash:**
```bash
bash .spec/scripts/bash/create-new-feature.sh --json
```

The script reads `branch_name` from `session.json`, resolves any name conflicts (`-v1`, `-v2`…), creates the branch, updates `session.json`, and seeds the spec directory.

---

## Agent Lifecycle Pattern

Every spec agent follows this exact pattern:

```
1. bootstrap-session  → init + add-agent + check-deps (one script call)
2. [do work]
3. update-artifact <id> summary "<what was produced>"
4. update-artifact <id> handoff "<context for the next agent>"
5. complete-artifact <id>  → cascades unblocking + sets pipeline.next_recommended
```

Read context from previously completed artifacts before starting:
```powershell
$session     = Get-Content .spec/session.json -Raw | ConvertFrom-Json
$specSummary = ($session.artifacts | Where-Object { $_.id -eq 'specify' }).summary
$handoff     = $session.pipeline.next_prompt
```
```bash
spec_summary=$(jq -r '.artifacts[] | select(.id=="specify") | .summary' .spec/session.json)
handoff=$(jq -r '.pipeline.next_prompt // empty' .spec/session.json)
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
  "isComplete": false,
  "status": "active",
  "pipeline": {
    "current_agent": "spec.plan",
    "last_completed": "specify",
    "next_recommended": "/spec.plan",
    "next_prompt": "Building a modern registration UI. OAuth2 login, mobile-first. React + TypeScript.",
    "agents_run": [{ "agent": "spec.specify", "ran_at": "2026-04-23T14:30:22Z" }]
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
      "summary": "3 user flows, 12 functional requirements. OAuth2 + email/password auth.",
      "handoff": "React + TypeScript, OAuth2, mobile-first. Must integrate with auth-service.",
      "completedAt": "2026-04-23T14:44:00Z"
    },
    {
      "id": "plan",
      "status": "ready",
      "required": true,
      "deps": ["specify"],
      "missingDeps": []
    }
  ]
}
```

---

## Key Fields

| Field | Set By | Description |
|---|---|---|
| `name` | `update-multi` | Feature name (kebab-case) |
| `branch_name` | `update-multi` | Active branch; used for archiving |
| `status` | `init` / `archive` | `active` while in progress, `completed` after archive |
| `pipeline.next_recommended` | auto (`complete-artifact`) | Next command to run |
| `pipeline.next_prompt` | auto (from `artifact.handoff`) | Context prompt for the next agent |
| `artifacts[].status` | agents / scripts | `ready` \| `pending` \| `in_progress` \| `complete` \| `skipped` |
| `artifacts[].summary` | completing agent | What this step produced |
| `artifacts[].handoff` | completing agent | Prompt/context to pass to the next agent |
| `artifacts[].missingDeps` | auto (`complete-artifact`) | Empty = can run |

## Graceful Degradation

- If `.spec/templates/session-state-template.json` is missing, log a warning and continue.
- If the script fails, log a warning but do **not** fail the calling agent.
- If `check-deps` finds blockers, surface them clearly — do not silently run.

## Output

```
[session] Initialized session at .spec/session.json (id: 20260423-143022-AbCd)
[session] Artifact 'specify' marked complete. Next: /spec.plan
[session] 'tasks' is blocked. Missing dependencies:
  → Run /spec.plan first  (id: plan)
```
