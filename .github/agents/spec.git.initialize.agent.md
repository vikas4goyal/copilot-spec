---
description: Initialize a Git repository with an initial commit
---

## Execution

Run the TypeScript script from the project root:

```
npm --prefix .spec/scripts run run -- ./initialize_repo.ts
```

Fallback if script missing: `git init && git add . && git commit -m "Initial commit from Specify template"`

Idempotent — skips if Git is unavailable or repo already exists. Ignores: `*.lock`, `package-lock.json`, `yarn.lock`, `*.min.js`, `*.min.css`, `dist/`, `build/`, `node_modules/`, `target/`, `.gradle/`, `out/`, `*.class`, `*.jar`, `*.war`, `*.ear`, `.settings/`, `.classpath`, `.project`

## Output

On success:
- `[OK] Git repository initialized`

## Graceful Degradation

If Git is not installed:
- Warn the user
- Skip repository initialization
- The project continues to function without Git (specs can still be created under `.spec/specs/`)

If Git is installed but `git init`, `git add .`, or `git commit` fails:
- Surface the error to the user
- Stop this command rather than continuing with a partially initialized repository