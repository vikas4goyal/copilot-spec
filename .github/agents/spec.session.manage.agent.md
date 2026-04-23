---
description: Manage an existing spec workflow session (.spec/session.json): bootstrap agent entry, update artifact state, complete or skip steps, and archive the session when the flow ends.
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

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

Every artifact-producing agent should follow this pattern:

```text
1. pre-agent   → bootstrap session + mark artifact in_progress
2. [do work]
3. [optional] manage-session update/update-multi for extra session metadata
4. post-agent  → write summary + handoff + complete-artifact
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

## Session JSON Schema (v2.0)

```json
{
  "_schema": "spec-session/2.0",
  "id": "20260423-143022-AbCd",
  "name": "modern-register-ui",
  "description": "Redesign the registration UI with OAuth2 and mobile-first layout",
  "branch_name": "modern-register-ui",
  "feature_dir": "specs/20260423-modern-register-ui",
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
      "outputPath": "specs/20260423-modern-register-ui/spec.md",
      "status": "complete",
      "required": true,
      "deps": [],
      "missingDeps": [],
      "summary": "3 user flows, 12 functional requirements. OAuth2 + email/password auth.",
      "handoff": "React + TypeScript, OAuth2, mobile-first. Must integrate with auth-service.",
      "completedAt": "2026-04-23T14:44:00Z"
    }
  ]
}
```

## Key Fields

| Field | Set By | Description |
|---|---|---|
| `pipeline.current_agent` | `add-agent` / wrappers | Agent currently running |
| `pipeline.next_recommended` | auto (`complete-artifact`) | Next command to run |
| `pipeline.next_prompt` | auto (`artifact.handoff`) | Context prompt for the next agent |
| `artifacts[].status` | wrappers / scripts | `ready` \| `pending` \| `in_progress` \| `complete` \| `skipped` |
| `artifacts[].summary` | completing agent | What this step produced |
| `artifacts[].handoff` | completing agent | Context to pass to the next agent |
| `artifacts[].missingDeps` | auto (`complete-artifact`) | Empty means the artifact can run |

## Output

```text
[session] Recorded agent 'spec.plan' in session.
[session] 'tasks' is blocked. Missing dependencies:
  → Run /spec.plan first  (id: plan)
[session] Artifact 'plan' marked complete. Next: /spec.tasks
```
