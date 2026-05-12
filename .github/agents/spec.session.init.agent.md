---
description: Initialize the active spec workflow session (.spec/session.json) for a new or resumed feature flow. Entry-point agents should call this before creating feature artifacts.
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Purpose

`spec.session.init` is the feature-flow bootstrap agent. It is responsible for:

- Deriving a branch-compatible `name` slug from the caller's input
- Rephrasing the raw input into a clean `description`
- Calling `create-new-feature` with those values — which handles **everything** else:
  - Creates `.spec/session.json` from the template (if it does not exist yet)
  - Reuses and validates the active session if one already exists
  - Creates the git branch and `.spec/specs/YYYYMMDD-<name>/` directory
  - Writes `branch_name` and `feature_dir` back to `session.json`

> **Session field roles:**
> | Field | Set by | Example |
> |---|---|---|
> | `name` | This agent (passed to script) | `oauth2-login` |
> | `description` | This agent (passed to script) | `"Implements OAuth2 login…"` |
> | `branch_name` | `create-new-feature` | `20260430-oauth2-login` |
> | `feature_dir` | `create-new-feature` | `.spec/specs/20260430-oauth2-login` |
>
> Both `branch_name` and `feature_dir` are always date-prefixed (`YYYYMMDD-<slug>`), keeping `.spec/specs/` listings chronological and branches easy to identify.

This agent is idempotent:
- If a session already exists **and** the current git branch matches `branch_name` **and** the feature folder exists → the script skips all creation steps and outputs the existing values.
- If a session exists but the current git branch does **not** match `branch_name` → the script exits with a clear error directing the user to switch branches or run `/spec.release`.

Use `spec.session.manage` for artifact-state updates after the flow has started.

## Execution

### Step 1 — Derive `name` and `description`

When the caller provides a feature description you **must**:

1. **Derive `name`** — Generate a short, lowercase, hyphen-separated slug valid as a git branch name.
   - Strip special characters, replace whitespace with hyphens, lowercase everything.
   - Keep it concise: 3–6 meaningful words, max 50 characters.
   - Examples: `"Add OAuth2 login with Google"` → `oauth2-login-google`; `"Fix pagination on user dashboard"` → `fix-pagination-user-dashboard`

2. **Rephrase `description`** — Rewrite the caller's raw input into one clear, concise sentence in present tense.
   - Example: `"i want oauth login so users can sign in with google"` → `"Implements OAuth2 login flow allowing users to authenticate with their Google account."`

### Step 2 — Run `create-new-feature`

Pass `name`, `description`, and the calling agent name directly to the script. It will create the session, branch, and folder in one step.

```bash
npm --prefix .spec/scripts run run -- ./create_new_feature.ts \
  --name "<slug>" \
  --description "<rephrased-desc>" \
  --agent-name "spec.<calling-agent>" \
  --json
```

That is the complete execution — no separate `manage-session` calls are needed.

## Typical Callers

- `spec.constitution`
- `spec.specify`
- Any entry-point workflow that may begin a new feature

## Output

After `create-new-feature` runs, `session.json` is created using the **`spec-session/2.0`** schema:

```json
{
  "_schema": "spec-session/2.0",
  "id": "20260502-143022-AbCd",
  "name": "oauth2-login",
  "description": "Implements OAuth2 login flow allowing users to authenticate with their Google account.",
  "branch_name": "20260502-oauth2-login",
  "feature_dir": ".spec/specs/20260502-oauth2-login",
  "schemaName": "spec-driven",
  "status": "active",
  "isComplete": false,
  "pipeline": {
    "current_agent": "spec.session.init",
    "last_completed": null,
    "eligible_agents": ["/spec.constitution", "/spec.specify"],
    "blocked_agents": {
      "/spec.plan": "Requires /spec.specify to be complete first",
      "/spec.tasks": "Requires /spec.plan to be complete first"
    },
    "next_recommended": "/spec.specify",
    "next_prompt_id": null,
    "next_prompt": "Define the feature requirements and user stories.",
    "agents_run": [{ "agent": "spec.session.init", "ran_at": "2026-05-02T14:30:22Z" }],
    "transition_history": [],
    "warnings": [],
    "rework_counts": {},
    "max_rework_per_artifact": 3
  },
  "artifacts": {
    "constitution": { "status": "optional", "required": false, "revision": 0, "outputPath": ".spec/memory/constitution.md", "based_on": {}, "summary": null, "started_at": null, "completed_at": null },
    "specify":      { "status": "pending",  "required": true,  "revision": 0, "outputPath": null, "based_on": {}, "summary": null, "started_at": null, "completed_at": null },
    "clarify":      { "status": "optional", "required": false, "revision": 0, "outputPath": null, "based_on": { "specify": 0 }, "summary": null, "started_at": null, "completed_at": null },
    "plan":         { "status": "blocked",  "required": true,  "revision": 0, "outputPath": null, "based_on": { "specify": 0 }, "summary": null, "started_at": null, "completed_at": null },
    "checklist":    { "status": "optional", "required": false, "revision": 0, "outputPath": null, "based_on": { "specify": 0, "plan": 0 }, "summary": null, "started_at": null, "completed_at": null },
    "tasks":        { "status": "blocked",  "required": true,  "revision": 0, "outputPath": null, "based_on": { "plan": 0 }, "summary": null, "started_at": null, "completed_at": null },
    "analyze":      { "status": "optional", "required": false, "revision": 0, "outputPath": null, "based_on": { "specify": 0, "plan": 0, "tasks": 0 }, "summary": null, "started_at": null, "completed_at": null },
    "implement":    { "status": "blocked",  "required": true,  "revision": 0, "outputPath": null, "based_on": { "tasks": 0 }, "summary": null, "started_at": null, "completed_at": null },
    "release":      { "status": "blocked",  "required": false, "revision": 0, "outputPath": null, "based_on": { "implement": 0 }, "summary": null, "started_at": null, "completed_at": null }
  },
  "prompts": {}
}
```

### Artifact Status Reference

| Status | Meaning |
|--------|---------|
| `pending` | Not yet started, no hard-dep blockers |
| `optional` | Can run any time, not required for completion |
| `blocked` | Hard dependencies not yet met |
| `in_progress` | Currently running (set by `pre_agent.ts`) |
| `complete` | Done; revision incremented |
| `stale` | Done but an upstream it based_on has since changed |
| `skipped` | Intentionally bypassed; counts as satisfied for dep checks |

### Console output:
```text
[feature] Session name: oauth2-login
[feature] Current git branch: none
[feature] Branch '20260502-oauth2-login' created and checked out
[feature] Spec file created from template: .spec/specs/20260502-oauth2-login/spec.md
[feature] Session updated: branch_name=20260502-oauth2-login  feature_dir=.spec/specs/20260502-oauth2-login
BRANCH_NAME: 20260502-oauth2-login
FEATURE_DIR: .../spec/specs/20260502-oauth2-login
SPEC_FILE:   .../spec/specs/20260502-oauth2-login/spec.md
```

### Resume / idempotent output

```text
[feature] Session name: oauth2-login
[feature] Current git branch: 20260502-oauth2-login
[feature] Already on branch '20260502-oauth2-login' with feature dir '.spec/specs/20260502-oauth2-login' — nothing to do
```

### Branch mismatch error

```text
[feature] ERROR: Session expects branch '20260502-oauth2-login' but current git branch is 'main'.
[feature]        Switch to the correct branch  ->  git checkout 20260502-oauth2-login
[feature]        Or release the current feature first  ->  /spec.release
```
