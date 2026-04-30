---
description: Finalize and release the current feature flow — push the branch to remote origin, archive the session state to .spec/features/<feature-name>/, and reset the workspace for the next feature.
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Pre-Execution: Git Setup _(runs FIRST, before anything else)_

1. **Initialize Git** — Execute the `spec.git.initialize` sub-agent and wait for completion.
2. **Validate Feature Branch** — Execute the `spec.git.validate` sub-agent and wait for completion.

## Workflow State Guard

Before doing any work, run:

```
npm --prefix .spec/scripts run run -- ./pre_agent.ts --agent-name spec.release --artifact-id release
```

If the script output contains `"ok": false`:
- Stop immediately.
- Do not modify files.
- Print the `reason`, `next_recommended`, `next_prompt_id`, and `next_prompt` from the script output.

To override blocking checks (e.g. releasing before implement is fully complete):

```
npm --prefix .spec/scripts run run -- ./pre_agent.ts --agent-name spec.release --artifact-id release --force
```

## Purpose

`spec.release` is the **final step** in any spec workflow. It:

1. Commits any uncommitted changes to the feature branch.
2. Pushes the feature branch to remote `origin`.
3. Archives `.spec/session.json` → `.spec/features/<feature-name>/session.json`.
4. Switches back to the base branch (unless `--stay-on-branch`).

After this completes, `.spec/session.json` is gone from the root — the workspace is ready for the next feature.

## Execution

### Step 1 — Commit any uncommitted changes

Execute the `spec.git.commit` sub-agent and wait for it to finish.

### Step 2 — Push, archive, and return to base (one script call)

Run the TypeScript release script:

**TypeScript:**
```typescript
npm --prefix .spec/scripts run run -- ./release_feature.ts
```

Pass `--stay-on-branch` if the user asked to stay on the feature branch.

The script:
- Reads `branch_name` and, if available, any recorded base-branch context from `.spec/session.json`
- Pushes the branch to `origin` (warns if no remote, continues on push failure)
- Archives the session via `manage-session` (sets status `completed`, moves to `.spec/features/<name>/session.json`)
- Switches back to the base branch when that value is available unless flagged otherwise

## Graceful Degradation

The script handles all degradation cases:
- No active session → warn and exit `0`
- No Git / no remote `origin` → skip push, still archive
- Push fails → warn, still archive locally
- If archive fails, session file is left intact for manual recovery

## Directory Layout After Release

```
.spec/
├── features/
│   └── 001-user-auth/
│       └── session.json     ← archived (status: completed)
├── templates/
└── memory/
```

## Workflow Handoff Update

After the release script runs, mark the release artifact complete:

```
npm --prefix .spec/scripts run run -- ./post_agent.ts \
  --artifact-id release \
  --summary "Feature released: branch pushed, session archived." \
  --handoff-agent spec.specify \
  --handoff "Start a new feature with /spec.specify or update the project constitution with /spec.constitution."
```

The post-agent script marks the session `isComplete = true` once all required artifacts are done.

## Output Summary

After the script runs, print a release summary:

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
  → Run spec.constitution or spec.specify to start a new feature
```
