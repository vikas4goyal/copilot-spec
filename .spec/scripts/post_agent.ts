#!/usr/bin/env node
/**
 * post_agent.ts — Workflow finalization script that every agent must run after completing work.
 *
 * Usage:
 *   npm --prefix .spec/scripts run run -- ./post_agent.ts \
 *     --artifact-id plan \
 *     --summary "Updated technical plan after constitution change" \
 *     --handoff-agent spec.tasks \
 *     --handoff "Generate dependency-ordered implementation tasks from the current plan." \
 *     [--changed true|false]        (default: true if file exists, implicit)
 *     [--output-path "path/to/file"]
 *     [--workflow-request-json '{"recommend":"/spec.constitution","reason":"..."}']
 *     [--force]
 */

import * as path from "node:path";
import { getRepoRoot } from "./common";
import {
  loadSession,
  saveSession,
  calculateWorkflowState,
  applyStalePropagate,
  markPromptsStaleForArtifact,
  createPromptRecord,
  nowIso,
  COMMAND_REGISTRY,
  ARTIFACT_SOFT_DEPS,
  getCurrentRevisions,
} from "./workflow";

// ─── CLI Arg Parsing ──────────────────────────────────────────────────────────

function getArg(name: string): string {
  const i = process.argv.indexOf(name);
  return i >= 0 && i + 1 < process.argv.length ? process.argv[i + 1] : "";
}

function hasFlag(name: string): boolean {
  return process.argv.includes(name);
}

const artifactId = getArg("--artifact-id");
const summary = getArg("--summary");
const handoffAgent = getArg("--handoff-agent"); // e.g. "spec.tasks"
const handoffPrompt = getArg("--handoff");
const outputPath = getArg("--output-path");
const workflowRequestJson = getArg("--workflow-request-json");
const changedFlag = getArg("--changed"); // "true" | "false" — explicit override
const force = hasFlag("--force");

if (!artifactId) {
  console.error(JSON.stringify({ ok: false, reason: "Missing required --artifact-id" }));
  process.exit(1);
}

// ─── Load Session ─────────────────────────────────────────────────────────────

const repoRoot = getRepoRoot();
const sessionFile = path.join(repoRoot, ".spec", "session.json");
const session = loadSession(sessionFile, repoRoot);

const artifact = session.artifacts[artifactId];
if (!artifact) {
  console.error(
    JSON.stringify({ ok: false, reason: `Artifact '${artifactId}' not found in session registry.` }),
  );
  process.exit(1);
}

// ─── Determine Whether Artifact Changed ───────────────────────────────────────

// Explicit flag → trust it. Otherwise: changed if revision was 0 (first run) or artifact was stale.
let artifactChanged: boolean;
if (changedFlag === "false") {
  artifactChanged = false;
} else if (changedFlag === "true") {
  artifactChanged = true;
} else {
  // Default: changed if this is a new run (revision 0 or was stale/in_progress)
  artifactChanged = artifact.revision === 0 || artifact.status === "stale" || artifact.status === "in_progress";
}

// ─── Increment Revision + Update Artifact ────────────────────────────────────

const now = nowIso();

// Capture current upstream revisions for based_on tracking
const allRevisions = getCurrentRevisions(session.artifacts);
const softDepsForArtifact = ARTIFACT_SOFT_DEPS[artifactId] ?? [];
const basedOnSnapshot: Record<string, number> = {};
for (const dep of softDepsForArtifact) {
  basedOnSnapshot[dep] = allRevisions[dep] ?? 0;
}

if (artifactChanged) {
  const prevRevision = artifact.revision;
  artifact.revision = prevRevision + 1;
  artifact.based_on = { ...artifact.based_on, ...basedOnSnapshot };

  // Update output path if provided
  if (outputPath) artifact.outputPath = outputPath;

  // Record history entry
  artifact.history = artifact.history ?? [];
  artifact.history.push({
    revision: artifact.revision,
    status: "complete",
    prompt_id: artifact.last_updated_by_prompt_id ?? null,
    summary: summary || null,
    based_on: basedOnSnapshot,
    completed_at: now,
  });

  // If this was created for first time
  if (prevRevision === 0 && !artifact.created_by_prompt_id && artifact.last_updated_by_prompt_id) {
    artifact.created_by_prompt_id = artifact.last_updated_by_prompt_id;
  }
}

// Mark complete
artifact.status = "complete";
artifact.completed_at = now;
artifact.summary = summary || artifact.summary;
if (outputPath) artifact.outputPath = outputPath;

// ─── Stale Propagation ────────────────────────────────────────────────────────

if (artifactChanged) {
  applyStalePropagate(session, artifactId);
  markPromptsStaleForArtifact(session, artifactId, artifact.revision);
}

// ─── Update Pipeline ──────────────────────────────────────────────────────────

session.pipeline.last_completed = artifactId;
session.pipeline.current_agent = null;

// Check if required artifacts are all done
const requiredPending = Object.entries(session.artifacts).filter(
  ([, a]) => a.required && a.status !== "complete" && a.status !== "skipped",
);
session.isComplete = requiredPending.length === 0;

// ─── Process Optional Workflow Request From Agent ─────────────────────────────

interface WorkflowRequest {
  recommend?: string;
  reason?: string;
  refreshes?: Record<string, number>;
  stale_if_completed?: string[];
}

let workflowRequest: WorkflowRequest | null = null;
if (workflowRequestJson) {
  try {
    workflowRequest = JSON.parse(workflowRequestJson) as WorkflowRequest;
  } catch {
    console.error("[post-agent] Warning: --workflow-request-json is not valid JSON, ignoring.");
  }
}

// Apply agent-requested stale overrides (validated by script)
if (workflowRequest?.stale_if_completed) {
  for (const staleId of workflowRequest.stale_if_completed) {
    const staleArt = session.artifacts[staleId];
    if (staleArt && staleArt.status === "complete" && COMMAND_REGISTRY[staleId]) {
      staleArt.status = "stale";
      staleArt.reason = workflowRequest.reason ?? `Requested stale by ${artifactId} agent.`;
    }
  }
}

// ─── Recalculate Workflow State ───────────────────────────────────────────────

const workflowState = calculateWorkflowState(session, repoRoot);

session.pipeline.eligible_agents = workflowState.eligible_agents;
session.pipeline.blocked_agents = workflowState.blocked_agents;
session.pipeline.warnings = workflowState.warnings;

// ─── Create Next Prompt Record ────────────────────────────────────────────────

// Determine the next agent: use agent-supplied handoff if valid, else workflow recommendation
let nextAgentId: string | null = null;
let nextPromptText: string | null = null;

// Validate agent-supplied handoff target
if (handoffAgent) {
  const handoffArtifactId = handoffAgent.replace(/^spec\./, "");
  const handoffDef = COMMAND_REGISTRY[handoffArtifactId];
  const handoffCommand = handoffDef?.command ?? `/${handoffAgent}`;
  const handoffArtifact = session.artifacts[handoffArtifactId];

  // Guard: do not loop back to an already-complete (non-stale) artifact.
  // This prevents chains like constitution → specify when specify is already done
  // (e.g. when constitution is re-run from plan/clarify to add new guidelines).
  const isAlreadyComplete =
    handoffArtifact?.status === "complete" || handoffArtifact?.status === "skipped";

  if (isAlreadyComplete && !force) {
    console.error(
      `[post-agent] Note: handoff target '${handoffAgent}' is already complete. ` +
      `Falling back to workflow recommendation to avoid a re-work loop.`,
    );
  } else if (workflowState.eligible_agents.includes(handoffCommand) || force) {
    nextAgentId = handoffAgent;
    nextPromptText = handoffPrompt || handoffDef?.defaultPrompt || null;
  } else {
    console.error(
      `[post-agent] Warning: handoff target '${handoffAgent}' is not eligible. Falling back to workflow recommendation.`,
    );
  }
}

// Fall back to workflow recommendation
if (!nextAgentId && workflowState.next_recommended) {
  const nextArtifactId = workflowState.next_recommended.replace(/^\/spec\./, "");
  const nextDef = COMMAND_REGISTRY[nextArtifactId];
  nextAgentId = nextDef?.agentId ?? null;
  nextPromptText = handoffPrompt || nextDef?.defaultPrompt || null;
}

// Agent-requested recommendation override (loop-protected)
if (workflowRequest?.recommend) {
  const reqArtifactId = workflowRequest.recommend.replace(/^\/spec\./, "");
  const reqDef = COMMAND_REGISTRY[reqArtifactId];
  const reqCommand = reqDef?.command ?? workflowRequest.recommend;

  const reworkCount = session.pipeline.rework_counts?.[reqArtifactId] ?? 0;
  const MAX_REWORK = session.pipeline.max_rework_per_artifact ?? 3;

  if (reworkCount >= MAX_REWORK && !force) {
    session.pipeline.warnings = session.pipeline.warnings ?? [];
    session.pipeline.warnings.push(
      `Agent requested /spec.${reqArtifactId} but it has reached the rework limit (${reworkCount}/${MAX_REWORK}). Ignored.`,
    );
  } else if (workflowState.eligible_agents.includes(reqCommand)) {
    // Record the backward transition
    session.pipeline.transition_history = session.pipeline.transition_history ?? [];
    session.pipeline.transition_history.push({
      from: `spec.${artifactId}`,
      to: `spec.${reqArtifactId}`,
      reason: workflowRequest.reason ?? "Agent-requested transition",
      timestamp: now,
    });
    nextAgentId = reqDef?.agentId ?? null;
    nextPromptText = workflowRequest.reason ?? reqDef?.defaultPrompt ?? null;
  }
}

// Write next prompt record
if (nextAgentId && nextPromptText) {
  const consumesSnapshot: Record<string, number> = {};
  const nextArtifactId = nextAgentId.replace(/^spec\./, "");
  const softDepsForNext = ARTIFACT_SOFT_DEPS[nextArtifactId] ?? [];
  for (const dep of softDepsForNext) {
    consumesSnapshot[dep] = session.artifacts[dep]?.revision ?? 0;
  }

  const newPrompt = createPromptRecord({
    prompts: session.prompts,
    targetAgentId: nextAgentId,
    prompt: nextPromptText,
    reason: `${artifactId} completed (revision ${artifact.revision}).`,
    createdBy: `spec.${artifactId}`,
    sourceArtifact: artifactId,
    sourceRevision: artifact.revision,
    consumes: consumesSnapshot,
    refreshes: workflowRequest?.refreshes ?? {},
    supersedes: null,
  });

  // Update artifact to record this prompt
  if (artifactChanged) {
    artifact.last_updated_by_prompt_id = newPrompt.id;
    if (!artifact.created_by_prompt_id && artifact.history.length === 1) {
      artifact.created_by_prompt_id = newPrompt.id;
    }
  }

  session.pipeline.next_recommended = newPrompt.command;
  session.pipeline.next_prompt_id = newPrompt.id;
  session.pipeline.next_prompt = newPrompt.prompt;
} else if (workflowState.next_recommended) {
  session.pipeline.next_recommended = workflowState.next_recommended;
  session.pipeline.next_prompt_id = workflowState.next_prompt_id;
  session.pipeline.next_prompt = workflowState.next_prompt;
}

// ─── Save Session ─────────────────────────────────────────────────────────────

saveSession(session, sessionFile);

// ─── User-Facing Output ───────────────────────────────────────────────────────

const def = COMMAND_REGISTRY[artifactId];

console.log("\n" + "─".repeat(60));
console.log("Workflow updated.\n");
console.log("Completed:");
console.log(`  - Artifact : ${artifactId}`);
console.log(`  - Revision : ${artifact.revision}`);
if (summary) console.log(`  - Summary  : ${summary}`);
console.log("");

if (session.pipeline.next_recommended) {
  console.log("Next recommended:");
  console.log(`  - Command  : ${session.pipeline.next_recommended}`);
  if (session.pipeline.next_prompt_id)
    console.log(`  - Prompt ID: ${session.pipeline.next_prompt_id}`);
  if (session.pipeline.next_prompt)
    console.log(`  - Prompt   :\n    ${session.pipeline.next_prompt}`);
  console.log("");
}

const otherEligible = workflowState.eligible_agents.filter(
  (c) => c !== session.pipeline.next_recommended,
);
if (otherEligible.length > 0) {
  console.log("Other eligible commands:");
  for (const cmd of otherEligible) console.log(`  - ${cmd}`);
  console.log("");
}

if (workflowState.warnings.length > 0) {
  console.log("Warnings:");
  for (const w of workflowState.warnings) console.log(`  ⚠  ${w}`);
  console.log("");
}

console.log("─".repeat(60));

console.error(`\n[post-agent] ✓ ${artifactId} marked complete (revision ${artifact.revision}).`);
