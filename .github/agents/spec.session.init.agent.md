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
- Seeding root metadata such as `name`, `description`, `branch_name`, and `feature_dir`
- Recording the initiating agent in `pipeline.agents_run`
- Triggering feature bootstrap steps such as branch creation when the workflow needs them

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

If the caller provides feature-level context, populate the root session fields after `init`:

**PowerShell:**
```powershell
.spec/scripts/powershell/manage-session.ps1 -Action update-multi -JsonPatch '{"name":"<short-name>","description":"<desc>","branch_name":"<branch>","feature_dir":"<dir>"}'
```

**Bash:**
```bash
bash .spec/scripts/bash/manage-session.sh --action update-multi --json-patch '{"name":"<short-name>","description":"<desc>","branch_name":"<branch>","feature_dir":"<dir>"}'
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

If this workflow needs a feature branch and spec directory, run the feature bootstrap after `branch_name` is available:

**PowerShell:**
```powershell
.spec/scripts/powershell/create-new-feature.ps1 -Json
```

**Bash:**
```bash
bash .spec/scripts/bash/create-new-feature.sh --json
```

The script reads `branch_name` from `.spec/session.json`, resolves conflicts (`-v1`, `-v2`, ...), updates `branch_name` / `feature_dir`, and creates the feature directory scaffold.

## Typical Callers

- `spec.constitution`
- `spec.specify`
- Any entry-point workflow that may begin a new feature

## Output

```text
[session] Initialized session at .spec/session.json (id: 20260423-143022-AbCd)
[session] Recorded agent 'spec.constitution' in session.
```
