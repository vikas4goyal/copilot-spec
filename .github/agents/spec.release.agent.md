---
description: Finalize and release the current feature flow — push the branch to remote origin, archive the session state to .spec/features/<feature-name>/, and reset the workspace for the next feature.
---

## User Input

```text
$ARGUMENTS
```

## Pre-Execution: Git Setup _(runs FIRST)_

1. Execute `spec.git.initialize` sub-agent → wait.
2. Execute `spec.git.validate` sub-agent → wait. **Stop if exit code 1.**

## Workflow State Guard

```
npm --prefix .spec/scripts run run -- ./pre_agent.ts --agent-name spec.release --artifact-id release
```

Stop if `"ok": false` — print `reason`, `next_recommended`, `next_prompt_id`, `next_prompt`.

To override blocking checks (e.g., releasing before implement completes):
```
npm --prefix .spec/scripts run run -- ./pre_agent.ts --agent-name spec.release --artifact-id release --force
```

## Execution

### Step 1 — Commit uncommitted changes

Execute `spec.git.commit` sub-agent → wait.

### Step 2 — Push, archive, return to base

```
npm --prefix .spec/scripts run run -- ./release_feature.ts
```

Pass `--stay-on-branch` if the user asked to stay on the feature branch.

The script: reads `branch_name` from `session.json`, pushes to `origin`, archives session to `.spec/features/<name>/session.json` with status `completed`, switches back to base branch.

**After this:** `.spec/session.json` is removed from root — workspace is ready for the next feature.

## Graceful Degradation

- No active session → warn, exit 0
- No Git / no remote → skip push, still archive
- Push fails → warn, still archive locally
- Archive fails → leave session file intact for manual recovery

## Workflow Handoff

```
npm --prefix .spec/scripts run run -- ./post_agent.ts \
  --artifact-id release \
  --summary "Feature released: branch pushed, session archived." \
  --handoff-agent spec.specify \
  --handoff "Start a new feature with /spec.specify or update the project constitution with /spec.constitution."
```

## Output Summary

```
╔══════════════════════════════════════════════════════╗
║                 SPEC RELEASE COMPLETE                ║
╠══════════════════════════════════════════════════════╣
║  Feature Branch : 001-user-auth                      ║
║  Pushed to      : origin/001-user-auth               ║
║  Session        : Archived to .spec/features/...     ║
║  Current Branch : develop                            ║
╚══════════════════════════════════════════════════════╝

Next steps:
  → Create a Pull Request from '001-user-auth' into 'develop'
  → Run /spec.specify or /spec.constitution to start a new feature
```
