---
description: Validate current branch follows feature branch naming conventions
---

# Validate Feature Branch

Run the TypeScript script from the project root:

**TypeScript:**
```typescript
npm --prefix .spec/scripts run run -- ./validate_branch.ts
```

The script validates the current Git branch **only when an active session exists**. The validation logic is:

1. **No `.spec/session.json`** → skip validation entirely (exit 0). There is no active feature session, so branch naming is irrelevant.
2. **`session.json` exists but `branch_name` is null/missing** → skip validation (exit 0). The session has not yet been associated with a branch.
3. **`session.json` exists and has `branch_name`** → compare current Git branch against `session.branch_name`.
   - Match → valid (exit 0).
   - Mismatch → invalid (exit 1): error message tells the user which branch to switch to.

Use `--json` to get machine-readable output for use in other scripts.

## On Failure

- If the script exits with code `1` (branch mismatch): **stop immediately**, surface the error message to the user, and do not proceed with any further work.
- If the script exits with code `0`: the branch is valid (or validation was gracefully skipped).

## Graceful Degradation

- If `.spec/session.json` does not exist: validation is skipped — no active session means no branch constraint.
- If Git is not installed: checks `SPECIFY_FEATURE` env var as fallback; skips with a warning if unset.
- If not inside a Git repository: same fallback.
- Exit code `0` = valid or gracefully skipped; `1` = branch mismatch (stop and surface the error to the user).
