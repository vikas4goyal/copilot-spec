---
description: Finalize and release the current feature flow — push the branch to remote origin, archive the session state to .spec/features/<feature-name>/, and reset the workspace for the next feature.
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Purpose

The `spec.release` agent is the **final step** in any spec workflow. It:

1. Reads the active `.spec/session.json` to determine the feature branch and metadata.
2. Commits any uncommitted changes to the feature branch.
3. Pushes the feature branch to the remote (`origin`).
4. Archives `.spec/session.json` → `.spec/features/<feature-name>/session.json`.
5. Optionally checks out the base branch (so the workspace is clean for the next feature).

After this agent completes, there is no `.spec/session.json` in the root `.spec/` folder, which signals that the **next agent run will start a brand-new session**.

## Pre-Execution Checks

**Step 1 — Verify active session:**
Check if `.spec/session.json` exists.
- If missing: warn the user and stop — there is nothing to release.
- If present: read it to extract `feature.branch_name`, `git.base_branch`, and `git.remote_url`.

Run on PowerShell:
```powershell
if (-not (Test-Path .spec/session.json)) {
    Write-Warning "[release] No active session found. Nothing to release."
    exit 0
}
$session = Get-Content .spec/session.json -Raw | ConvertFrom-Json
$branchName = $session.feature.branch_name
$baseBranch = $session.git.base_branch
```

Run on Bash:
```bash
if [[ ! -f .spec/session.json ]]; then
  echo "[release] No active session found. Nothing to release."
  exit 0
fi
branch_name=$(jq -r '.feature.branch_name' .spec/session.json)
base_branch=$(jq -r '.git.base_branch' .spec/session.json)
```

## Execution Steps

### Step 1 — Commit any uncommitted changes

Execute the `spec.git.commit` sub-agent and wait for it to finish before proceeding.

### Step 2 — Push the feature branch to remote

Verify Git is available and a remote named `origin` exists. Then push:

**PowerShell:**
```powershell
git push origin $branchName --set-upstream
```

**Bash:**
```bash
git push origin "$branch_name" --set-upstream
```

If no remote exists (local-only project), skip the push step with a warning:
```
[release] No remote 'origin' found — skipping push. Branch is available locally only.
```

### Step 3 — Archive the session state file

Run the session management script to archive the session:

**PowerShell:**
```powershell
.spec/scripts/powershell/manage-session.ps1 -Action archive
```

**Bash:**
```bash
bash .spec/scripts/bash/manage-session.sh --action archive
```

This will:
- Set `session.status = "completed"` in the JSON.
- Move `.spec/session.json` → `.spec/features/<feature-name>/session.json`.
- Create the `.spec/features/<feature-name>/` directory if it does not exist.

### Step 4 — Return to base branch (optional)

If the user did not specify `--stay-on-branch` (or equivalent), switch back to the base branch:

**PowerShell:**
```powershell
if ($baseBranch -and $baseBranch -ne $branchName) {
    git checkout $baseBranch
    Write-Output "[release] Switched back to base branch: $baseBranch"
}
```

**Bash:**
```bash
if [[ -n "$base_branch" && "$base_branch" != "$branch_name" ]]; then
  git checkout "$base_branch"
  echo "[release] Switched back to base branch: $base_branch"
fi
```

## Directory Layout After Release

```
.spec/
├── features/
│   └── 001-user-auth/          ← created on first release for this feature
│       └── session.json        ← archived session (status: completed)
├── templates/
│   └── session-state-template.json
└── memory/
    └── constitution.md
```

The `.spec/session.json` file is **gone** from the root, signalling the workspace is ready for a new feature.

## Post-Execution Checks

- Confirm `.spec/session.json` no longer exists in the root `.spec/` directory.
- Confirm `.spec/features/<feature-name>/session.json` was created successfully.
- If you are on the base branch, inform the user that a new spec workflow can begin.

## Output Summary

Print a release summary to the user:

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

## Graceful Degradation

- If Git is not available, skip Steps 2 and 4 (push and branch switch), but still archive the session.
- If the push fails (e.g., auth error), inform the user but still archive locally — do not block archiving.
- If archiving fails, do not delete `.spec/session.json` — warn the user to archive manually.
