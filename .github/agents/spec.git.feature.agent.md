---
description: Create a feature branch with sequential or timestamp numbering
---

# Create Feature Branch

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Prerequisites

- Verify Git is available: `git rev-parse --is-inside-work-tree 2>/dev/null`
- If Git is not available, warn the user — the script will still output branch info

## Execution

Generate a concise 2–4 word kebab-case short name from the feature description or `session.name` (action-noun format, e.g. `add-user-auth`, `fix-payment-bug`). Preserve technical terms (OAuth2, JWT, API, etc.).

Run the appropriate script — it handles everything internally:

**PowerShell:**
```powershell
.spec/scripts/powershell/create-new-feature.ps1 -Json -ShortName "<short-name>" "<feature description>"
```

**PowerShell (timestamp numbering):**
```powershell
.spec/scripts/powershell/create-new-feature.ps1 -Json -Timestamp -ShortName "<short-name>" "<feature description>"
```

**Bash:**
```bash
.spec/scripts/bash/create-new-feature.sh --json --short-name "<short-name>" "<feature description>"
```

**Bash (timestamp numbering):**
```bash
.spec/scripts/bash/create-new-feature.sh --json --timestamp --short-name "<short-name>" "<feature description>"
```

> Do **not** pass `--number` / `-Number` — the script auto-detects the next available number.

The script will:
1. Read `session.json` — if `branch_name` matches the current branch, exit immediately (nothing to do)
2. If `branch_name` is set but not checked out, create or switch to that branch
3. If no `branch_name` in session, generate a new branch using sequential or timestamp numbering
4. Update `session.json` with `branch_name`, `feature_num`, and `feature_dir`

JSON output contains `BRANCH_NAME`, `FEATURE_NUM`, and `SPEC_FILE`.

## Graceful Degradation

- Not a git repo: skips branch creation, still writes branch info to session
- Branch already exists remotely: `git checkout` tracks it without error
