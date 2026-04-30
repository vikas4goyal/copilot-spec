---
description: Detect Git remote URL for GitHub integration
---

# Detect Git Remote URL

Run the TypeScript script from the project root:

**TypeScript:**
```typescript
npm --prefix .spec/scripts run run -- ./detect_remote.ts
```

Use `--json` to get machine-readable output:
```json
{"has_remote":true,"is_github":true,"remote_url":"https://github.com/owner/repo.git","owner":"owner","repo":"repo"}
```

## Graceful Degradation

Always exits `0`. Returns `has_remote: false` when Git is not available, not inside a repo, or no `remote.origin` is configured. Never error — callers continue without remote information.

> **CAUTION**: Only report `is_github: true` when the URL actually points to `github.com`. Do NOT assume GitHub from URL format alone.
