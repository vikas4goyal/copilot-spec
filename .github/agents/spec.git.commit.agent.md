---
description: Auto-commit changes after a Spec command completes
---

# Auto-Commit Changes

Automatically stage and commit all changes after a Spec command completes.

## Behavior

This agent is designed to create meaningful Git commit messages that reflect the actual work done, not just generic file changes. It:

1. Runs `git status --porcelain` to check if there are any pending changes
2. If there are changes, runs `git --no-pager diff HEAD` (and `git --no-pager diff --cached` for staged files) to read the **actual content** of every change
3. Analyzes the full diff to understand **what actually changed** — e.g., a login feature was implemented, a spec was written, a bug was fixed — not just which files changed
4. Selects the correct **conventional commit prefix** based on the nature of the change (see Prefix Guide below)
5. Composes a concise, meaningful commit message that describes the real work done
6. Passes the complete commit message as a parameter to the auto-commit script

## Commit Message Construction

### Step 1 — Read the actual diff (with size guard)

First, check the size of the diff before reading everything:

```
git status --porcelain
git --no-pager diff HEAD --stat
git --no-pager diff --cached --stat
```

Then use the following strategy based on diff size:

#### Small diff (< 300 changed lines total)
Read the full diff — this is safe and gives the most accurate message:
```
git --no-pager diff HEAD
git --no-pager diff --cached
```

#### Medium diff (300 – 1500 changed lines)
Read file-level stats first, then read only the files most likely to reveal the *intent* of the change.
Prioritize in this order:
1. Files that are **new** (status `A` / `??`) — new files show what was built
2. The **largest changed files** by line count — most work happened there
3. Skip files that are likely auto-generated or noise: `*.lock`, `package-lock.json`, `yarn.lock`, `*.min.js`, `*.min.css`, `dist/`, `build/`, `node_modules/`

Read up to **5 key files** using:
```
git --no-pager diff HEAD -- <file>
```

#### Large diff (> 1500 changed lines)
Do **not** read full file diffs. Instead:
1. Run `git --no-pager diff HEAD --stat` and `git --no-pager diff HEAD --name-status` to see all changed files and their type (added/modified/deleted)
2. Group files by directory/module to identify the areas of the codebase affected
3. Read only the **first 80 lines** of the diff for the 5 most significant files:
   ```
   git --no-pager diff HEAD -- <file> | head -80
   ```
4. Use file paths, module names, and the partial diff to infer the overall nature of the change

In all cases, read **the content of the diff lines** (the `+` and `-` lines), not just the file names. Understand:
- What new behavior, feature, or content was introduced?
- What was removed or corrected?
- What category of change is this?

### Step 2 — Select a conventional commit prefix

| Prefix       | When to use                                                                 |
|--------------|-----------------------------------------------------------------------------|
| `feat`       | A new feature, capability, endpoint, screen, component, or workflow was added |
| `fix`        | A bug, broken logic, incorrect value, or error was corrected                |
| `docs`       | Spec files, plan files, README, task lists, or other documentation changed  |
| `chore`      | Config files, tooling, dependencies, CI setup, or scaffolding updated       |
| `refactor`   | Code restructured without changing behavior                                 |
| `test`       | Tests added or updated                                                      |
| `ci`         | CI/CD pipeline or workflow files changed                                    |
| `style`      | Formatting, whitespace, or naming only (no logic change)                    |
| `perf`       | Performance improvements                                                    |

**Spec context hints:**
- `spec.md` written or updated → `docs: add/update feature specification`
- `plan.md` created → `docs: add implementation plan`
- `tasks.md` generated → `docs: define implementation tasks`
- Source code feature implemented → `feat: implement <what>`
- Bug corrected in logic → `fix: <what was wrong>`
- Config or extension files changed → `chore: update <what>`

When **multiple categories apply**, choose the most prominent one (prefer `feat` > `fix` > `docs` > `chore`).

### Step 3 — Write the commit message

Use the standard two-part format:

```
<prefix>: <subject line>

<body>
```

#### Subject line
- Format: `<prefix>: <short description in present tense, lowercase>`
- Max **72 characters**
- Must reflect the **actual content of the change** — not generic phrases like "update files" or "make changes"

#### Body (required)
- Separated from the subject by a **blank line**
- Use **bullet points** (`-`) — one point per distinct change or area affected
- Max **5 bullets**, each no longer than **100 characters**
- Focus on *what* changed and *why* it matters, not *how* (the diff already shows the how)
- Skip bullets that just repeat the subject line

#### Limits
| Part        | Limit                        |
|-------------|------------------------------|
| Subject     | 72 chars max                 |
| Body        | Up to 5 bullets              |
| Each bullet | 100 chars max                |
| Total body  | Stop after covering the key changes — don't list every file |

Good examples:

```
feat: implement JWT-based user authentication

- Add login and register endpoints with bcrypt password hashing
- Issue signed JWT on successful login with configurable expiry
- Add auth middleware to protect private routes
```

```
docs: add specification for payment processing feature

- Define acceptance criteria for card and wallet payment flows
- Capture edge cases for failed transactions and refunds
```

```
fix: resolve null pointer exception in task loader

- Guard against missing task file when feature directory is empty
- Add fallback to empty task list instead of crashing
```

```
chore: standardize repository bootstrap scripts

- Align bash and PowerShell initialization flows
- Add clear logging for setup decisions and early exits
```

Bad examples (too generic — avoid):
```
chore: update files

- Made some changes
```

## Execution

After constructing the commit message (subject + body), run the TypeScript script, passing the full multi-line message as the argument:

- **TypeScript**: `npm --prefix .spec/scripts run run -- ./auto_commit.ts --commit-message "<commit_message>"`

For multi-line messages use a newline (`\n`) between the subject and body when constructing the string. The script passes it directly to `git commit -m`.

## Graceful Degradation

- If Git is not available or the current directory is not a repository: skips with a warning
- If no changes to commit: skips with a message
- If the diff is too large, apply the tiered size strategy in Step 1 — never read the full diff blindly
- If even the sampled diff provides no clear signal, fall back to a message derived purely from `--name-status` output, e.g. `chore: update multiple files across auth and api modules`
