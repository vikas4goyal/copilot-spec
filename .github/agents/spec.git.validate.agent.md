---
description: Validate current branch follows feature branch naming conventions
---

# Validate Feature Branch

Run the appropriate script from the project root:

**PowerShell:**
```powershell
.spec/scripts/powershell/validate-branch.ps1
```

**Bash:**
```bash
bash .spec/scripts/bash/validate-branch.sh
```

The script checks whether the current branch name matches a sequential (`001-feature-name`) or timestamp (`20260319-143022-feature-name`) pattern. It also checks whether the corresponding `specs/<prefix>-*` directory exists.

Use `--json` / `-Json` to get machine-readable output for use in other scripts.

## Graceful Degradation

- If Git is not installed: checks `SPECIFY_FEATURE` env var as fallback; skips with a warning if unset
- If not inside a Git repository: same fallback
- Exit code `0` = valid feature branch; `1` = invalid branch (surface the error to the user)
