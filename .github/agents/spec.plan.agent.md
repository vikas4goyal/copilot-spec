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

**Pre-Execution: Bootstrap Session State** _(must run first)_:
- Check if `.spec/session.json` exists.
  - If **missing**: run `.spec/scripts/powershell/manage-session.ps1 -Action init` (PowerShell) or `bash .spec/scripts/bash/manage-session.sh --action init` (Bash).
  - If **present**: read and continue.
- Record this agent: `.spec/scripts/powershell/manage-session.ps1 -Action add-agent -AgentName "spec.plan"` (or Bash equivalent).
- After generating plan.md, update session: `.spec/scripts/powershell/manage-session.ps1 -Action update -Field "paths.plan_file" -Value "<plan-path>"`.

**Check for extension hooks (before planning)**:

Run and display any output from:
- **PowerShell**: `.spec/scripts/powershell/check-hooks.ps1 -Event before_plan`
- **Bash**: `bash .spec/scripts/bash/check-hooks.sh --event before_plan`

The script outputs formatted hook blocks for executable hooks; silent if none. For **mandatory** hooks (non-optional), wait for the hook command to complete before proceeding. For **optional** hooks, present them to the user and proceed with the Outline.

## Outline

1. **Setup**: Run `.spec/scripts/powershell/setup-plan.ps1 -Json` from repo root and parse JSON for FEATURE_SPEC, IMPL_PLAN, SPECS_DIR, BRANCH. For single quotes in args like "I'm Groot", use escape syntax: e.g 'I'\''m Groot' (or double-quote if possible: "I'm Groot").

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

5. **Commit Changes**: Execute the `spec.git.commit` sub-agent and wait for it to finish.

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
    - Run `.spec/scripts/powershell/update-agent-context.ps1 -AgentType copilot`
    - These scripts detect which AI agent is in use
    - Update the appropriate agent-specific context file
    - Add only new technology from current plan
    - Preserve manual additions between markers

**Output**: data-model.md, /contracts/*, quickstart.md, agent-specific file

## Key rules

- Use absolute paths
- ERROR on gate failures or unresolved clarifications
