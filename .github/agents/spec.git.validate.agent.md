---
description: Validate current branch follows feature branch naming conventions
---

# Validate Feature Branch

Run the TypeScript script from the project root:

**TypeScript:**
```typescript
npm --prefix .spec/scripts run run -- ./validate_branch.ts
```

The script checks whether the current branch name matches the date-prefixed pattern (`20260430-feature-name`). It also checks whether the corresponding `.spec/specs/<date>-*` directory exists.

Use `--json` to get machine-readable output for use in other scripts.

## On Failure

- If the script exits with code `1` (invalid branch): **stop immediately**, surface the error message to the user, and do not proceed with any further work.
- If the script exits with code `0`: the branch is valid (or git is unavailable and validation was gracefully skipped).

## Graceful Degradation

- If Git is not installed: checks `SPECIFY_FEATURE` env var as fallback; skips with a warning if unset
- If not inside a Git repository: same fallback
- Exit code `0` = valid feature branch (or gracefully skipped); `1` = invalid branch (stop and surface the error to the user)
