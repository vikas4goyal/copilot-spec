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

_(run in order, every time)_

1. **Initialize Git** — Execute the `spec.git.initialize` sub-agent and wait for completion. Idempotent; safe when the repo already exists.
2. **Commit Pending Changes** — Execute the `spec.git.commit` sub-agent and wait for completion. Captures any pre-existing uncommitted work before this agent modifies anything.
3. **Start Session Step** — Run the pre-agent script:
   - **TypeScript**: `npm --prefix .spec/scripts run run -- ./pre_agent.ts --agent-name spec.plan --artifact-id plan`

   The script bootstraps the session (`init` + `add-agent` + `check-deps`) and marks the artifact `in_progress`. **Stop and inform the user** if `check-deps` reports missing prerequisites.

## Outline

1. **Setup**: Run `npm --prefix .spec/scripts run run -- ./setup_plan.ts --json` from repo root and parse JSON for FEATURE_SPEC, IMPL_PLAN, SPECS_DIR, BRANCH. For single quotes in args like "I'm Groot", use escape syntax: e.g 'I'\''m Groot' (or double-quote if possible: "I'm Groot").

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

_(run in order, after the main Outline completes)_

1. **Complete Session Step** — Run the post-agent script with a concise `summary` of what was produced and a `handoff` prompt for the next agent:
   - **TypeScript**: `npm --prefix .spec/scripts run run -- ./post_agent.ts --artifact-id plan --summary "..." --handoff "..."`

   Marks the artifact `complete`, cascades unblocking of downstream artifacts, and sets `pipeline.next_recommended` + `pipeline.next_prompt`.

2. **Commit Changes** — Execute the `spec.git.commit` sub-agent and wait for completion. Commits this agent's outputs and the session updates together.

## Phases

### Phase 0: Outline & Research

1. **Extract unknowns from Technical Context** above:
    - For each NEEDS CLARIFICATION → research task
    - For each dependency → best practices task
    - For each integration → patterns task

2. **Generate and dispatch research agents**:

   ```text
   For each unknown in Technical Context:
     Task: "Research {unknown} for {feature context}"
   For each technology choice:
     Task: "Find best practices for {tech} in {domain}"
   ```

3. **Consolidate findings** in `research.md` using format:
    - Decision: [what was chosen]
    - Rationale: [why chosen]
    - Alternatives considered: [what else evaluated]

**Output**: research.md with all NEEDS CLARIFICATION resolved

### Phase 1: Design & Contracts

**Prerequisites:** `research.md` complete

1. **Extract entities from feature spec** → `data-model.md`:
    - Entity name, fields, relationships
    - Validation rules from requirements
    - State transitions if applicable

2. **Define interface contracts** (if project has external interfaces) → `/contracts/`:
    - Identify what interfaces the project exposes to users or other systems
    - Document the contract format appropriate for the project type
    - Examples: public APIs for libraries, command schemas for CLI tools, endpoints for web services, grammars for parsers, UI contracts for applications
    - Skip if project is purely internal (build scripts, one-off tools, etc.)

3. **Agent context update**:
    - Run `npm --prefix .spec/scripts run run -- ./update_agent_context.ts --agent-type copilot`
    - These scripts detect which AI agent is in use
    - Update the appropriate agent-specific context file
    - Add only new technology from current plan
    - Preserve manual additions between markers

**Output**: data-model.md, /contracts/*, quickstart.md, agent-specific file

## Key rules

- Use absolute paths
- ERROR on gate failures or unresolved clarifications
