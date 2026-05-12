---
description: Execute the implementation planning workflow using the plan template to generate design artifacts.
handoffs:
  - label: Create Tasks
    agent: spec.tasks
    prompt: Break the plan into tasks
    send: true
  - label: Create Checklist
    agent: spec.checklist
    prompt: Create a checklist for the following domain...
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Pre-Execution Checks

1. Execute `spec.git.initialize` sub-agent and wait for completion.
2. Execute `spec.git.validate` sub-agent and wait for completion. **If validation fails (exit code 1), stop immediately and report the error to the user. Do not proceed.**
3. Execute `spec.git.commit` sub-agent and wait for completion.
4. Run the following command to check prerequisites.
   ```
   npm --prefix .spec/scripts run run -- ./pre_agent.ts --agent-name spec.plan --artifact-id plan
   ```

   If the script output contains `"ok": false`:
   - Stop immediately.
      - Do not modify files.
      - Print the `reason`, `next_recommended`, `next_prompt_id`, and `next_prompt` from the script output.

## Outline

1. **Setup**: Run `npm --prefix .spec/scripts run run -- ./setup_plan.ts --json` from repo root and parse JSON for FEATURE_SPEC, IMPL_PLAN, SPECS_DIR, BRANCH. For single quotes in args like "I'm Groot", use escape syntax: e.g 'I'\''m Groot' (or double-quote if possible: "I'm Groot").

2. **Load context**: Read FEATURE_SPEC and `.spec/memory/constitution.md`. Load IMPL_PLAN template (already copied).

3. **Execute plan workflow** following IMPL_PLAN template structure:
   - Fill Technical Context (mark unknowns as "NEEDS CLARIFICATION")
   - Fill Constitution Check from constitution; ERROR on violations
   - Phase 0: Generate `research.md` (resolve all NEEDS CLARIFICATION)
   - Phase 1: Generate `data-model.md`, `contracts/`, `quickstart.md`; update agent context
   - Re-evaluate Constitution Check post-design

4. **Report**: Branch, IMPL_PLAN path, generated artifacts. Command ends after Phase 1.

## Phase 0: Outline & Research

1. For each NEEDS CLARIFICATION → research task; for each dependency → best practices task; for each integration → patterns task.

2. **Load context**: Read FEATURE_SPEC and `.spec/memory/constitution.md`. Load IMPL_PLAN template (already copied).

3. **Execute plan workflow**: Follow the structure in IMPL_PLAN template to:
   - Fill Technical Context (mark unknowns as "NEEDS CLARIFICATION")
   - Fill Constitution Check section from constitution
   - Evaluate gates (ERROR if violations unjustified)
   - Phase 0: Generate research.md (resolve all NEEDS CLARIFICATION)
   - Phase 1: Generate data-model.md, contracts/, quickstart.md
   - Phase 1: Update agent context by running the agent script
   - Re-evaluate Constitution Check post-design

4. **Stop and report**: Command ends after Phase 2 planning. Report branch, IMPL_PLAN path, and generated artifacts.

## Post-Execution Checks

1. Run the following command:

   ```
   npm --prefix .spec/scripts run run -- ./post_agent.ts \
     --artifact-id plan \
     --summary "<one sentence describing the plan produced>" \
     --output-path "<feature_dir>/plan.md" \
     --handoff-agent spec.tasks \
     --handoff "Generate dependency-ordered implementation tasks from the current plan."
   ```

   If new governance-sensitive technology requires a constitution update, add:
      ```
        --workflow-request-json '{"recommend":"/spec.constitution","reason":"New library choice requires governance update"}'
      ```

2. Execute `spec.git.commit` sub-agent and wait for completion.
