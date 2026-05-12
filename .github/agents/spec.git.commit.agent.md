---
description: Auto-commit changes after a Spec command completes
---

Stage and commit all pending changes with a meaningful conventional commit message.

## Steps

### 1. Read the diff (size-tiered strategy)

First check: `git status --porcelain` + `git --no-pager diff HEAD --stat`

| Diff size | Strategy |
|-----------|----------|
| < 300 lines | Read full diff: `git --no-pager diff HEAD` + `git --no-pager diff --cached` |
| 300–1500 lines | Read up to 5 key files (prioritize: new files → largest changed → skip `*.lock`, `*.min.*`, `dist/`, `build/`, `node_modules/`) via `git --no-pager diff HEAD -- <file>` |
| > 1500 lines | Use `--stat` + `--name-status` only; read first 80 lines of 5 most significant files via `git --no-pager diff HEAD -- <file> \| head -80` |

Read the `+`/`-` diff content to understand **what changed**, not just file names.

### 2. Select conventional commit prefix

| Prefix | Use when |
|--------|----------|
| `feat` | New feature, capability, endpoint, screen, component, or workflow added |
| `fix` | Bug, broken logic, or error corrected |
| `docs` | Spec files, plan files, README, task lists, or other documentation changed |
| `chore` | Config, tooling, dependencies, CI setup, or scaffolding updated |
| `refactor` | Code restructured without changing behavior |
| `test` | Tests added or updated |
| `ci` | CI/CD pipeline or workflow files changed |
| `style` | Formatting, whitespace, or naming only |
| `perf` | Performance improvements |

Spec hints: `spec.md` → `docs`, `plan.md` → `docs`, `tasks.md` → `docs`, source code → `feat`/`fix`. When multiple apply, prefer `feat > fix > docs > chore`.

### 3. Write the commit message

```
<prefix>: <subject — present tense, lowercase, max 72 chars>

- <bullet: what changed and why, max 100 chars>
- <up to 5 bullets total>
```

Subject must reflect actual content — not "update files" or "make changes".

### 4. Execute

After constructing the commit message (subject + body), run the TypeScript script, passing the full multi-line message as the argument:
```
npm --prefix .spec/scripts run run -- ./auto_commit.ts --commit-message "<message>"
```

For multi-line messages use a newline (`\n`) between the subject and body when constructing the message string.

## Graceful Degradation

- If Git is not available or the current directory is not a repository: skips with a warning
- If no changes to commit: skips with a message
- If the diff is too large, apply the tiered size strategy in Step 1 — never read the full diff blindly
- If even the sampled diff provides no clear signal, fall back to a message derived purely from `--name-status` output, e.g. `chore: update multiple files across auth and api modules`
