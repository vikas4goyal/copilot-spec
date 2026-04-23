---
description: Create a feature branch with sequential or timestamp numbering
---



# Create Feature Branch

Create and switch to a new git feature branch for the given specification. This command handles **branch creation only** — the spec directory and files are created by the core `/speckit.specify` workflow.

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Environment Variable Override

If the user explicitly provided `GIT_BRANCH_NAME` (e.g., via environment variable, argument, or in their request), pass it through to the script by setting the `GIT_BRANCH_NAME` environment variable before invoking the script. When `GIT_BRANCH_NAME` is set:
- The script uses the exact value as the branch name, bypassing all prefix/suffix generation
- `--short-name`, `--number`, and `--timestamp` flags are ignored
- `FEATURE_NUM` is extracted from the name if it starts with a numeric prefix, otherwise set to the full branch name

## Prerequisites

- Verify Git is available by running `git rev-parse --is-inside-work-tree 2>/dev/null`
- If Git is not available, warn the user and skip branch creation

## Branch Numbering Mode

Determine the branch numbering strategy by checking configuration in this order:

1. Check `.spec/git-config.yml` for `branch_numbering` value
2. Check `.specify/init-options.json` for `branch_numbering` value (backward compatibility)
3. Default to `sequential` if neither exists

## Execution

Generate a concise short name (2-4 words) for the branch:
- Analyze the feature description and extract the most meaningful keywords
- Use action-noun format when possible (e.g., "add-user-auth", "fix-payment-bug")
- Preserve technical terms and acronyms (OAuth2, API, JWT, etc.)

Run the appropriate script based on your platform:

- **Bash**: `.spec/scripts/bash/create-new-feature.sh --json --short-name "<short-name>" "<feature description>"`
- **Bash (timestamp)**: `.spec/scripts/bash/create-new-feature.sh --json --timestamp --short-name "<short-name>" "<feature description>"`
- **PowerShell**: `.spec/scripts/powershell/create-new-feature.ps1 -Json -ShortName "<short-name>" "<feature description>"`
- **PowerShell (timestamp)**: `.spec/scripts/powershell/create-new-feature.ps1 -Json -Timestamp -ShortName "<short-name>" "<feature description>"`

**IMPORTANT**:
- Do NOT pass `--number` — the script determines the correct next number automatically
- Always include the JSON flag (`--json` for Bash, `-Json` for PowerShell) so the output can be parsed reliably
- You must only ever run this script once per feature
- The JSON output will contain `BRANCH_NAME` and `FEATURE_NUM`

## Graceful Degradation

If Git is not installed or the current directory is not a Git repository:
- Branch creation is skipped with a warning: `[specify] Warning: Git repository not detected; skipped branch creation`
- The script still outputs `BRANCH_NAME` and `FEATURE_NUM` so the caller can reference them

## Output

The script outputs JSON with:
- `BRANCH_NAME`: The branch name (e.g., `003-user-auth` or `20260319-143022-user-auth`)
- `FEATURE_NUM`: The numeric or timestamp prefix used

## Session State Update

After the branch has been created successfully, update the active session state with the branch details.

Parse `BRANCH_NAME` and `FEATURE_NUM` from the JSON output above, then run:

**PowerShell:**
```powershell
$featureDir = "specs/$branchName"
.spec/scripts/powershell/manage-session.ps1 -Action update-multi -JsonPatch "{
  \"feature\": {
    \"branch_name\": \"$branchName\",
    \"feature_num\": \"$featureNum\",
    \"feature_dir\": \"$featureDir\"
  },
  \"paths\": {
    \"spec_file\": \"$featureDir/spec.md\"
  },
  \"workflow\": {
    \"last_completed_step\": \"branch-created\"
  }
}"
.spec/scripts/powershell/manage-session.ps1 -Action add-agent -AgentName "spec.git.feature"
```

**Bash:**
```bash
feature_dir="specs/$branch_name"
bash .spec/scripts/bash/manage-session.sh --action update-multi --json-patch \
  "{\"feature\":{\"branch_name\":\"$branch_name\",\"feature_num\":\"$feature_num\",\"feature_dir\":\"$feature_dir\"},\"paths\":{\"spec_file\":\"$feature_dir/spec.md\"},\"workflow\":{\"last_completed_step\":\"branch-created\"}}"
bash .spec/scripts/bash/manage-session.sh --action add-agent --agent-name "spec.git.feature"
```

If the session file does not exist (i.e., the feature agent was invoked standalone without going through `spec.constitution`), initialize it first:

**PowerShell:**
```powershell
if (-not (Test-Path .spec/session.json)) {
    .spec/scripts/powershell/manage-session.ps1 -Action init
}
```

**Bash:**
```bash
[[ -f .spec/session.json ]] || bash .spec/scripts/bash/manage-session.sh --action init
```
