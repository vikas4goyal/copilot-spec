---
description: Finalize and release the current feature flow — push the branch to remote origin, archive the session state to .spec/features/<feature-name>/, and reset the workspace for the next feature.
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

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

Run the release script:

**PowerShell:**
```powershell
.spec/scripts/powershell/release-feature.ps1
```

**Bash:**
```bash
bash .spec/scripts/bash/release-feature.sh
```

Pass `-StayOnBranch` / `--stay-on-branch` if the user asked to stay on the feature branch.

The script:
- Reads `branch_name` and `git.base_branch` from `.spec/session.json`
- Pushes the branch to `origin` (warns if no remote, continues on push failure)
- Archives the session via `manage-session` (sets status `completed`, moves to `.spec/features/<name>/session.json`)
- Switches to `base_branch` unless flagged otherwise

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
