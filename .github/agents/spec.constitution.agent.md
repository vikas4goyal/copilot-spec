---
description: Create or update the project constitution from interactive or provided principle inputs, ensuring all dependent templates stay in sync.
handoffs:
  - label: Build Specification
    agent: spec.specify
    prompt: Implement the feature specification based on the updated constitution. I want to build...
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Pre-Execution: Git Setup _(runs FIRST, before anything else)_

1. **Initialize Git Repository** — Execute the `spec.git.initialize` sub-agent and wait for it to finish.
2. **Validate Feature Branch** — Execute the `spec.git.validate` sub-agent and wait for it to finish.
3. **Commit Pending Changes** — Execute the `spec.git.commit` sub-agent and wait for completion. Captures any pre-existing uncommitted work before this agent modifies anything.

## Workflow State Guard

Before doing any work, run:

```
npm --prefix .spec/scripts run run -- ./pre_agent.ts --agent-name spec.constitution --artifact-id constitution
```

If the script output contains `"ok": false`:
- Stop immediately.
- Do not modify files.
- Print the `reason`, `next_recommended`, `next_prompt_id`, and `next_prompt` from the script output.

If a prompt id is supplied by the user, pass it through:

```
npm --prefix .spec/scripts run run -- ./pre_agent.ts --agent-name spec.constitution --artifact-id constitution --prompt-id <prompt-id>
```


## Outline

You are updating the project constitution at `.spec/memory/constitution.md`. This file is a TEMPLATE containing placeholder tokens in square brackets (e.g. `[PROJECT_NAME]`, `[PRINCIPLE_1_NAME]`). Your job is to (a) collect/derive concrete values, (b) fill the template precisely, and (c) propagate any amendments across dependent artifacts.

**Note**: If `.spec/memory/constitution.md` does not exist yet, it should have been initialized from `.spec/templates/constitution-template.md` during project setup. If it's missing, copy the template first.

Follow this execution flow:

1. Load the existing constitution at `.spec/memory/constitution.md`.
    - Identify every placeholder token of the form `[ALL_CAPS_IDENTIFIER]`.
      **IMPORTANT**: The user might require less or more principles than the ones used in the template. If a number is specified, respect that - follow the general template. You will update the doc accordingly.

2. Collect/derive values for placeholders:
    - If user input (conversation) supplies a value, use it.
    - Otherwise infer from existing repo context (README, docs, prior constitution versions if embedded).
    - For governance dates: `RATIFICATION_DATE` is the original adoption date (if unknown ask or mark TODO), `LAST_AMENDED_DATE` is today if changes are made, otherwise keep previous.
    - `CONSTITUTION_VERSION` must increment according to semantic versioning rules:
        - MAJOR: Backward incompatible governance/principle removals or redefinitions.
        - MINOR: New principle/section added or materially expanded guidance.
        - PATCH: Clarifications, wording, typo fixes, non-semantic refinements.
    - If version bump type ambiguous, propose reasoning before finalizing.

3. Draft the updated constitution content:
    - Replace every placeholder with concrete text (no bracketed tokens left except intentionally retained template slots that the project has chosen not to define yet—explicitly justify any left).
    - Preserve heading hierarchy and comments can be removed once replaced unless they still add clarifying guidance.
    - Ensure each Principle section: succinct name line, paragraph (or bullet list) capturing non‑negotiable rules, explicit rationale if not obvious.
    - Ensure Governance section lists amendment procedure, versioning policy, and compliance review expectations.

4. Consistency propagation checklist (convert prior checklist into active validations):
    - Read `.spec/templates/plan-template.md` and ensure any "Constitution Check" or rules align with updated principles.
    - Read `.spec/templates/spec-template.md` for scope/requirements alignment—update if constitution adds/removes mandatory sections or constraints.
    - Read `.spec/templates/tasks-template.md` and ensure task categorization reflects new or removed principle-driven task types (e.g., observability, versioning, testing discipline).
    - Read each command file in `.spec/templates/commands/*.md` (including this one) to verify no outdated references (agent-specific names like CLAUDE only) remain when generic guidance is required.
    - Read any runtime guidance docs (e.g., `README.md`, `docs/quickstart.md`, or agent-specific guidance files if present). Update references to principles changed.

5. Produce a Sync Impact Report (prepend as an HTML comment at top of the constitution file after update):
    - Version change: old → new
    - List of modified principles (old title → new title if renamed)
    - Added sections
    - Removed sections
    - Templates requiring updates (✅ updated / ⚠ pending) with file paths
    - Follow-up TODOs if any placeholders intentionally deferred.

6. Validation before final output:
    - No remaining unexplained bracket tokens.
    - Version line matches report.
    - Dates ISO format YYYY-MM-DD.
    - Principles are declarative, testable, and free of vague language ("should" → replace with MUST/SHOULD rationale where appropriate).

7. Write the completed constitution back to `.spec/memory/constitution.md` (overwrite).

8. Output a final summary to the user with:
    - New version and bump rationale.
    - Any files flagged for manual follow-up.
    - Suggested commit message (e.g., `docs: amend constitution to vX.Y.Z (principle additions + governance update)`).

Formatting & Style Requirements:

- Use Markdown headings exactly as in the template (do not demote/promote levels).
- Wrap long rationale lines to keep readability (<100 chars ideally) but do not hard enforce with awkward breaks.
- Keep a single blank line between sections.
- Avoid trailing whitespace.

If the user supplies partial updates (e.g., only one principle revision), still perform validation and version decision steps.

If critical info missing (e.g., ratification date truly unknown), insert `TODO(<FIELD_NAME>): explanation` and include in the Sync Impact Report under deferred items.

Do not create a new template; always operate on the existing `.spec/memory/constitution.md` file.

## Workflow Handoff Update

After successful completion, run:

```
npm --prefix .spec/scripts run run -- ./post_agent.ts \
  --artifact-id constitution \
  --summary "<one sentence: e.g. 'Constitution amended to v1.2.0: added Observability principle.'>" \
  --handoff-agent spec.specify \
  --handoff "<what the next agent needs to know about this constitution update>"
```

> **Loop-prevention note:** The `--handoff-agent spec.specify` is a *suggestion*, not a forced override.
> The `post_agent.ts` script will **automatically ignore** this handoff and fall back to the workflow
> recommendation when `spec.specify` is already complete (e.g., when constitution is re-run from
> plan or clarify to add new libraries or guidelines). This prevents a re-work loop:
> `constitution → specify → …` even though specify was already finished.
>
> Only when `specify` has never been run (status `pending`) will this handoff take effect.

The post-agent script is responsible for:
- marking the artifact complete and incrementing revision if changed
- recording prompt usage and updating based_on revisions
- marking downstream artifacts stale if constitution changed
- calculating eligible agents and creating the next prompt record
- updating `pipeline.next_recommended`, `pipeline.next_prompt_id`, and `pipeline.next_prompt`
- **skipping the `--handoff-agent` if the target artifact is already complete, to prevent loops**

**Post-Execution: Commit Changes**:
- Execute the `spec.git.commit` sub-agent and wait for it to finish.


