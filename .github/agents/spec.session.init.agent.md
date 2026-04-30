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
> | `branch_name` | `create-new-feature` | `oauth2-login` or `oauth2-login-20260423` |
> | `feature_dir` | `create-new-feature` | `.spec/specs/20260423-oauth2-login` |
>
> `branch_name` and `feature_dir` intentionally differ: branches are clean slugs (date only on conflict), folders are always date-prefixed so `.spec/specs/` lists chronologically.

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

**TypeScript:**
```typescript
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

After `create-new-feature` runs, `session.json` is created with the v3.0 schema and an empty pipeline:

```json
{
  "_schema": "spec-session/3.0",
  "id": "20260423-143022-AbCd",
  "name": "oauth2-login",
  "description": "Implements OAuth2 login flow allowing users to authenticate with their Google account.",
  "branch_name": "oauth2-login",
  "feature_dir": ".spec/specs/20260423-oauth2-login",
  "status": "active",
  "pipeline": {
    "running": [],
    "completed": [],
    "skipped": [],
    "next": null
  },
  "artifacts": []
}
```

Console output:
[session.init] Session created: .spec/session.json (id: 20260423-143022-AbCd)
[session.init] Branch 'oauth2-login' created and checked out
[session.init] Spec file created from template: .spec/specs/20260423-oauth2-login/spec.md
[session.init] Session updated: branch_name=oauth2-login  feature_dir=.spec/specs/20260423-oauth2-login
```

### Resume / idempotent output

```text
[session.init] Session name: 'oauth2-login'
[session.init] Current git branch: 'oauth2-login'
[session.init] Already on branch 'oauth2-login' with feature dir '.spec/specs/20260423-oauth2-login' — nothing to do
```

### Branch mismatch error

```text
[session.init] ERROR: Session expects branch 'oauth2-login' but the current git branch is 'main'.
[session.init]        Switch to the correct branch  →  git checkout oauth2-login
[session.init]        Or release the current feature first  →  /spec.release
```
