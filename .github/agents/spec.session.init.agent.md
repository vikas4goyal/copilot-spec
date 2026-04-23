---
description: Initialize the active spec workflow session (.spec/session.json) for a new or resumed feature flow. Entry-point agents should call this before creating feature artifacts.
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Purpose

`spec.session.init` is the feature-flow bootstrap agent. Use it when an agent may be starting a new workflow or needs to ensure the active session exists before work begins.

This agent is responsible for:
- Creating `.spec/session.json` if it does not exist
- Safely reusing the active session if it already exists
- Deriving a branch-compatible `name` slug from the caller's input and rephrasing the `description`
- Recording the initiating agent in `pipeline.agents_run`
- Creating the git branch and `specs/YYYYMMDD-<name>/` directory

> **Session field roles:**
> | Field | Set by | Example |
> |---|---|---|
> | `name` | This agent | `oauth2-login` |
> | `description` | This agent | `"Implements OAuth2 login…"` |
> | `branch_name` | `create-new-feature` | `oauth2-login` or `oauth2-login-20260423` |
> | `feature_dir` | `create-new-feature` | `specs/20260423-oauth2-login` |
>
> `branch_name` and `feature_dir` intentionally differ: branches are clean slugs (date only on conflict), folders are always date-prefixed so `specs/` lists chronologically.

This agent should be idempotent:
- If the session already exists, do not overwrite populated metadata unless the caller explicitly provides replacement values.
- Prefer filling missing values over recomputing existing ones.

Use `spec.session.manage` for artifact-state updates after the flow has started.

## Execution

Run the appropriate script from the repo root:

**PowerShell:**
```powershell
.spec/scripts/powershell/manage-session.ps1 -Action init
```

**Bash:**
```bash
bash .spec/scripts/bash/manage-session.sh --action init
```

### Context Population

When the caller provides a feature description you **must**:

1. **Derive `name`** — Generate a short, lowercase, hyphen-separated slug valid as a git branch name.
   - Strip special characters, replace whitespace with hyphens, lowercase everything.
   - Keep it concise: 3–6 meaningful words, max 50 characters.
   - Examples: `"Add OAuth2 login with Google"` → `oauth2-login-google`; `"Fix pagination on user dashboard"` → `fix-pagination-user-dashboard`

2. **Rephrase `description`** — Rewrite the caller's raw input into one clear, concise sentence in present tense.
   - Example: `"i want oauth login so users can sign in with google"` → `"Implements OAuth2 login flow allowing users to authenticate with their Google account."`

3. **Write `name` and `description` to session** (`branch_name` and `feature_dir` are populated by `create-new-feature` in the next step):

**PowerShell:**
```powershell
.spec/scripts/powershell/manage-session.ps1 -Action update-multi -JsonPatch '{"name":"<slug>","description":"<rephrased-desc>"}'
```

**Bash:**
```bash
bash .spec/scripts/bash/manage-session.sh --action update-multi --json-patch '{"name":"<slug>","description":"<rephrased-desc>"}'
```

If the calling agent is identifiable, record it:

**PowerShell:**
```powershell
.spec/scripts/powershell/manage-session.ps1 -Action add-agent -AgentName "spec.<agent-name>"
```

**Bash:**
```bash
bash .spec/scripts/bash/manage-session.sh --action add-agent --agent-name "spec.<agent-name>"
```

### Branch / Feature Bootstrap

After the session `name` is set, run the feature bootstrap. The script:
- Reads `name` from `.spec/session.json` as the base slug
- Resolves a unique **`branch_name`** independently: tries `<name>` → `<name>-YYYYMMDD` → `<name>-YYYYMMDD-2` …
- Resolves a unique **`feature_dir`** independently: always `YYYYMMDD-<name>` → `YYYYMMDD-<name>-2` … (date-first for chronological directory sorting)
- Creates the git branch and `specs/<folder>/` scaffold
- Writes `branch_name` and `feature_dir` back to session

**PowerShell:**
```powershell
.spec/scripts/powershell/create-new-feature.ps1 -Json
```

**Bash:**
```bash
bash .spec/scripts/bash/create-new-feature.sh --json
```

## Typical Callers

- `spec.constitution`
- `spec.specify`
- Any entry-point workflow that may begin a new feature

## Output

```text
[session] Initialized session at .spec/session.json (id: 20260423-143022-AbCd)
[session] Applied JSON patch to session.
[session] Recorded agent 'spec.specify' in session.
[feature] Branch 'oauth2-login' created and checked out
[feature] Spec file created from template: specs/20260423-oauth2-login/spec.md
[feature] Session updated: branch_name=oauth2-login  feature_dir=specs/20260423-oauth2-login
```
