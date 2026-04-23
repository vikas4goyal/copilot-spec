---
agent: spec.git.commit
---

Analyze the actual git diff to understand what changed, then create a meaningful conventional commit message (subject + body) and commit the changes.

Steps:
1. Run `git status --porcelain` to see if there are pending changes. If none, stop.
2. Run `git diff HEAD --stat` and `git diff --cached --stat` to count changed lines.
3. Read the diff using the appropriate strategy based on size:
   - **< 300 lines**: read full diff with `git diff HEAD` and `git diff --cached`
   - **300–1500 lines**: read only new/key files (up to 5) — skip lock files, dist, build artefacts
   - **> 1500 lines**: use `git diff HEAD --name-status` for overview + `git diff HEAD -- <file> | head -80` for the 3 most significant files
4. Analyze the diff content (the `+`/`-` lines) to understand *what* was done.
5. Choose the appropriate conventional commit prefix: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `ci`, `style`, `perf`.
6. Write the commit message in two parts:
   - **Subject**: `<prefix>: <description>` — max 72 chars, present tense, lowercase
   - **Body**: blank line then up to 5 bullet points (`-`), each max 100 chars, describing what changed and why — no need to list every file, just the key changes
7. Pass the full message (subject + body) to the script:
   - **PowerShell**: `.spec/scripts/powershell/auto-commit.ps1 -CommitMessage "<message>"`
   - **Bash**: `.spec/scripts/bash/auto-commit.sh "<message>"`
