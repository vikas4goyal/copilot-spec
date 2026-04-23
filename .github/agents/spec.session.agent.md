---
description: Initialize or update the active spec session state file (.spec/session.json). Every spec agent must call this as a pre-requisite to ensure consistent session tracking across a workflow.
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).
Supported actions passed as arguments: `init`, `update`, `add-agent <name>`, `archive`, `read`.
If no action is specified, default to `init`.

## Purpose

The session state file (`.spec/session.json`) is the **single source of truth** for the current active spec workflow. It tracks:

- The active feature branch name and feature number
- The feature directory path
- Which agents have run and when
- Git details (base branch, remote, repository)
- Paths to generated artifacts (spec, plan, tasks)
- Flow status (`active` → `completed`)

There is **always at most one** `.spec/session.json` file. Once a flow is complete, the `spec.release` agent archives it to `.spec/features/<feature-name>/session.json`.

## Pre-Requisite Check (Bootstrap Logic)

**Every spec agent should run this check before any other work:**

1. Check if `.spec/session.json` exists.
2. If **missing**: copy `.spec/templates/session-state-template.json` → `.spec/session.json` and initialize it (the script does this automatically on `init`).
3. If **present**: read it and continue — do not overwrite.

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

The `init` action is idempotent — safe to call on every agent startup. It only creates the file if it does not already exist.

## Updating Session Fields

After completing an action that produces new data (e.g., a branch was created), update the session:

**PowerShell — update a single field:**
```powershell
.spec/scripts/powershell/manage-session.ps1 -Action update -Field "feature.branch_name" -Value "001-my-feature"
```

**PowerShell — update multiple fields atomically:**
```powershell
.spec/scripts/powershell/manage-session.ps1 -Action update-multi -JsonPatch '{"feature":{"branch_name":"001-my-feature","feature_num":"001","feature_dir":"specs/001-my-feature"}}'
```

**Bash equivalents use `--field`/`--value` or `--json-patch` flags:**
```bash
bash .spec/scripts/bash/manage-session.sh --action update --field feature.branch_name --value "001-my-feature"
bash .spec/scripts/bash/manage-session.sh --action update-multi --json-patch '{"feature":{"branch_name":"001-my-feature"}}'
```

## Recording Agent Execution

After the session is initialized, record that the current agent has run:

**PowerShell:**
```powershell
.spec/scripts/powershell/manage-session.ps1 -Action add-agent -AgentName "spec.<agent-name>"
```

**Bash:**
```bash
bash .spec/scripts/bash/manage-session.sh --action add-agent --agent-name "spec.<agent-name>"
```

## Reading Session State

To read the current session and use its data in subsequent steps:

**PowerShell:**
```powershell
$session = Get-Content .spec/session.json -Raw | ConvertFrom-Json
$branchName = $session.feature.branch_name
```

**Bash:**
```bash
branch_name=$(jq -r '.feature.branch_name' .spec/session.json)
```

## Session JSON Schema

The file lives at `.spec/session.json` and follows this structure (see `.spec/templates/session-state-template.json` for the full template):

```json
{
  "_schema": "spec-session/1.0",
  "session": {
    "id": "20260423-143022-AbCd",
    "created_at": "2026-04-23T14:30:22Z",
    "updated_at": "2026-04-23T14:35:10Z",
    "status": "active"
  },
  "feature": {
    "name": "User Authentication",
    "description": "Add OAuth2-based login flow",
    "branch_name": "001-user-auth",
    "feature_num": "001",
    "feature_dir": "specs/001-user-auth"
  },
  "git": {
    "base_branch": "develop",
    "remote_url": "https://github.com/org/repo.git",
    "repository": "/path/to/repo"
  },
  "workflow": {
    "initiated_by": "spec.constitution",
    "agents_run": [
      { "agent": "spec.constitution", "ran_at": "2026-04-23T14:30:22Z" },
      { "agent": "spec.git.feature", "ran_at": "2026-04-23T14:31:00Z" }
    ],
    "current_agent": "spec.git.feature",
    "last_completed_step": "branch-created"
  },
  "paths": {
    "spec_file": "specs/001-user-auth/spec.md",
    "plan_file": "specs/001-user-auth/plan.md",
    "tasks_file": "specs/001-user-auth/tasks.md",
    "checklist_file": "specs/001-user-auth/checklist.md"
  },
  "metadata": {
    "project_name": "MyApp",
    "tags": [],
    "notes": null
  }
}
```

## Key Fields Reference

| Field | Set By | Description |
|---|---|---|
| `session.id` | `spec.session` (init) | Unique ID for this flow |
| `session.status` | `spec.session` / `spec.release` | `active` or `completed` |
| `feature.branch_name` | `spec.git.feature` | Git branch name (e.g. `001-user-auth`) |
| `feature.feature_num` | `spec.git.feature` | Sequential or timestamp prefix |
| `feature.feature_dir` | `spec.git.feature` | Path to the feature specs directory |
| `workflow.initiated_by` | First agent | The agent that started this flow |
| `workflow.agents_run` | Each agent | Audit trail of agents that ran |
| `git.base_branch` | `spec.session` (init) | Branch that was active when flow started |

## Graceful Degradation

- If `.spec/templates/session-state-template.json` is missing, log a warning and continue — do not block the workflow.
- If the script fails, log a warning but do **not** fail the calling agent.

## Output

On successful `init`:
```
[session] Initialized session at .spec/session.json (id: 20260423-143022-AbCd)
```
If session already existed:
```
[session] Session file already exists at .spec/session.json — skipping init.
```
