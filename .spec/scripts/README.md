# TypeScript Script Ports

This folder contains TypeScript conversions of scripts from `.spec/scripts/python`.

## What these scripts do

- `manage_session.ts`: Reads and updates `.spec/session.json` state.
- `create_new_feature.ts`: Creates a feature branch/folder and initializes `spec.md`.
- `pre_agent.ts` / `post_agent.ts`: Shared wrappers to mark agent start/completion.
- `setup_plan.ts`, `check_prerequisites.ts`: Validate and prepare feature artifacts.
- `auto_commit.ts`, `release_feature.ts`: Optional Git automation helpers.

Most scripts are intentionally small entrypoints that delegate shared logic to
`common.ts` and `manage_session.ts`.

## Quick start

```bash
cd /home/vicky/IdeaProjects/copilot-spec/.spec/scripts
npm install
npm run typecheck
```

Run any script with:

```bash
npm run run -- ./check_prerequisites.ts --json
npm run run -- ./manage_session.ts --action init
```

## Maintenance notes

- Prefer descriptive names over short aliases (for example, `commandResult` instead of `r`).
- Keep command wrappers side-effect free where possible and return structured results.
- Add short comments only where orchestration order or edge-case behavior is not obvious.

