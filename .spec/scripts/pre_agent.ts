#!/usr/bin/env node
/**
 * pre_agent.ts — Workflow gate that every agent must pass before doing any work.
 *
 * Usage:
 *   npm --prefix .spec/scripts run run -- ./pre_agent.ts \
 *     --agent-name spec.plan \
 *     --artifact-id plan \
 *     [--prompt-id prompt_007] \
 *     [--force] \
 *     [--strict]
 *
 * Exit codes:
 *   0  — agent is eligible; artifact marked in_progress
 *   1  — agent is blocked; no files modified (except safe session init/migration)
 */

import * as path from "node:path";
import { getRepoRoot } from "./common";
import {
  loadSession,
  saveSession,
  calculateWorkflowState,
  nowIso,
  newSessionId,
  COMMAND_REGISTRY,
} from "./workflow";

// ─── CLI Arg Parsing ──────────────────────────────────────────────────────────

/**
 * Reads a CLI argument value by flag name.
 *
 * @param name CLI flag name (example: --agent-name)
 * @returns The flag value, or an empty string when missing
 */
function getArg(name: string): string {
  const i = process.argv.indexOf(name);
  return i >= 0 && i + 1 < process.argv.length ? process.argv[i + 1] : "";
}

/**
 * Checks whether a boolean CLI flag was provided.
 *
 * @param name CLI flag name (example: --force)
 * @returns True when the flag exists in process arguments
 */
function hasFlag(name: string): boolean {
  return process.argv.includes(name);
}

/**
 * Writes a structured diagnostic log to stderr so JSON stdout remains machine-readable.
 *
 * @param message Human-friendly message describing the current step
 * @param details Optional JSON-safe metadata for deeper debugging
 */
function logInfo(message: string, details?: unknown): void {
  if (details === undefined) {
    console.error(`[pre-agent] ${message}`);
    return;
  }
  console.error(`[pre-agent] ${message}`, details);
}

const agentName = getArg("--agent-name");
const artifactIdArg = getArg("--artifact-id");
const promptId = getArg("--prompt-id");
const force = hasFlag("--force");
const strict = hasFlag("--strict"); // NEEDS CLARIFICATION: blocks /spec.plan entirely instead of warning

logInfo("Starting pre-agent gate check", {
  agentName: agentName || null,
  artifactIdArg: artifactIdArg || null,
  promptId: promptId || null,
  force,
  strict,
});

if (!agentName) {
  logInfo("Missing required --agent-name; blocking execution");
  const err = { ok: false, reason: "Missing required --agent-name" };
  console.log(JSON.stringify(err, null, 2));
  process.exit(1);
}

// ─── Resolve Artifact ID ──────────────────────────────────────────────────────

const targetArtifactId =
  artifactIdArg || agentName.replace(/^spec\./, "").replace(/^spec\//, "");

logInfo("Resolved target artifact", { targetArtifactId, agentName });

// ─── Load Session ─────────────────────────────────────────────────────────────

const repoRoot = getRepoRoot();
const sessionFile = path.join(repoRoot, ".spec", "session.json");

logInfo("Loading session", { sessionFile, repoRoot });

const session = loadSession(sessionFile, repoRoot);

// Bootstrap id if session was just created
if (!session.id) {
  logInfo("Session ID missing; bootstrapping metadata");
  session.id = newSessionId();
  session.created_at = session.created_at ?? nowIso();
}

logInfo("Session loaded", {
  sessionId: session.id,
  featureDir: session.feature_dir ?? null,
  currentAgent: session.pipeline.current_agent ?? null,
});

// ─── Loop / Rework Protection ─────────────────────────────────────────────────

const MAX_REWORK = session.pipeline.max_rework_per_artifact ?? 3;
const reworkCount = session.pipeline.rework_counts?.[targetArtifactId] ?? 0;

logInfo("Checking rework guard", { targetArtifactId, reworkCount, maxRework: MAX_REWORK, force });

if (reworkCount >= MAX_REWORK && !force) {
  logInfo("Rework guard blocked execution", { targetArtifactId, reworkCount, maxRework: MAX_REWORK });
  const ws = calculateWorkflowState(session, repoRoot);
  const result = {
    ok: false,
    requested: agentName,
    reason: `Blocked: ${agentName} has been run or reworked ${reworkCount} times (max ${MAX_REWORK}). Resolve manually or pass --force.`,
    eligible_agents: ws.eligible_agents,
    blocked_agents: ws.blocked_agents,
    next_recommended: ws.next_recommended,
    next_prompt_id: ws.next_prompt_id,
    next_prompt: ws.next_prompt,
  };
  console.log(JSON.stringify(result, null, 2));
  _printBlockedHuman(result);
  process.exit(1);
}

// ─── Calculate Workflow State ─────────────────────────────────────────────────

const workflowState = calculateWorkflowState(session, repoRoot);

logInfo("Workflow state calculated", {
  eligibleCount: workflowState.eligible_agents.length,
  blockedCount: Object.keys(workflowState.blocked_agents).length,
  nextRecommended: workflowState.next_recommended ?? null,
});

// ─── Validate Prompt (if provided) ───────────────────────────────────────────

if (promptId && !force) {
  logInfo("Validating prompt", { promptId });
  const prompt = session.prompts?.[promptId];

  if (!prompt) {
    logInfo("Prompt validation failed: prompt not found", { promptId });
    const result = {
      ok: false,
      requested: agentName,
      reason: `Prompt '${promptId}' not found in session.`,
      eligible_agents: workflowState.eligible_agents,
      blocked_agents: workflowState.blocked_agents,
      next_recommended: workflowState.next_recommended,
      next_prompt_id: workflowState.next_prompt_id,
      next_prompt: workflowState.next_prompt,
    };
    console.log(JSON.stringify(result, null, 2));
    process.exit(1);
  }

  if (prompt.status === "stale") {
    logInfo("Prompt validation failed: prompt is stale", {
      promptId,
      staleReason: prompt.stale_reason ?? "upstream artifact changed",
    });
    const result = {
      ok: false,
      requested: agentName,
      reason: `Prompt '${promptId}' is stale: ${prompt.stale_reason ?? "upstream artifact changed"}`,
      recommended_prompt_id: workflowState.next_prompt_id,
      next_prompt: workflowState.next_prompt,
      eligible_agents: workflowState.eligible_agents,
      blocked_agents: workflowState.blocked_agents,
      next_recommended: workflowState.next_recommended,
    };
    console.log(JSON.stringify(result, null, 2));
    _printBlockedHuman(result);
    process.exit(1);
  }

  if (
    prompt.status === "superseded" ||
    prompt.status === "used" ||
    prompt.status === "rejected" ||
    prompt.status === "expired"
  ) {
    logInfo("Prompt validation failed: terminal prompt status", {
      promptId,
      status: prompt.status,
    });
    const result = {
      ok: false,
      requested: agentName,
      reason: `Prompt '${promptId}' has status '${prompt.status}' and cannot be used.`,
      recommended_prompt_id: workflowState.next_prompt_id,
      next_prompt: workflowState.next_prompt,
      eligible_agents: workflowState.eligible_agents,
      blocked_agents: workflowState.blocked_agents,
      next_recommended: workflowState.next_recommended,
    };
    console.log(JSON.stringify(result, null, 2));
    process.exit(1);
  }

  // Verify prompt targets the requested agent
  const defForPrompt = COMMAND_REGISTRY[targetArtifactId];
  if (prompt.target_agent !== agentName && prompt.target_agent !== defForPrompt?.agentId) {
    logInfo("Prompt validation failed: target agent mismatch", {
      promptId,
      promptTarget: prompt.target_agent,
      requestedAgent: agentName,
      registryAgentId: defForPrompt?.agentId ?? null,
    });
    const result = {
      ok: false,
      requested: agentName,
      reason: `Prompt '${promptId}' targets agent '${prompt.target_agent}', not '${agentName}'.`,
      eligible_agents: workflowState.eligible_agents,
      blocked_agents: workflowState.blocked_agents,
      next_recommended: workflowState.next_recommended,
      next_prompt_id: workflowState.next_prompt_id,
      next_prompt: workflowState.next_prompt,
    };
    console.log(JSON.stringify(result, null, 2));
    process.exit(1);
  }

  logInfo("Prompt validation passed", { promptId, targetAgent: prompt.target_agent });
}

// ─── Eligibility Check ────────────────────────────────────────────────────────

const def = COMMAND_REGISTRY[targetArtifactId];
const requestedCommand = def?.command ?? `/${agentName}`;
const isEligible = workflowState.eligible_agents.includes(requestedCommand);

logInfo("Checking command eligibility", { requestedCommand, isEligible, force });

if (!isEligible && !force) {
  logInfo("Eligibility check blocked execution", { requestedCommand });
  const blockedReason =
    workflowState.blocked_agents[requestedCommand] ??
    `${requestedCommand} is not eligible to run at this time.`;

  const result = {
    ok: false,
    requested: agentName,
    reason: blockedReason,
    eligible_agents: workflowState.eligible_agents,
    blocked_agents: workflowState.blocked_agents,
    next_recommended: workflowState.next_recommended,
    next_prompt_id: workflowState.next_prompt_id,
    next_prompt: workflowState.next_prompt,
  };

  console.log(JSON.stringify(result, null, 2));
  _printBlockedHuman(result);
  process.exit(1);
}

// ─── Mark In Progress ─────────────────────────────────────────────────────────

const now = nowIso();

logInfo("Marking artifact in progress", { targetArtifactId, at: now });

// Mark prompt used
if (promptId && session.prompts?.[promptId]) {
  logInfo("Marking prompt as used", { promptId });
  session.prompts[promptId].status = "used";
}

// Update artifact
if (session.artifacts[targetArtifactId]) {
  logInfo("Updating artifact status", {
    targetArtifactId,
    previousStatus: session.artifacts[targetArtifactId].status,
    nextStatus: "in_progress",
  });
  session.artifacts[targetArtifactId].status = "in_progress";
  session.artifacts[targetArtifactId].started_at = now;
}

// Update pipeline
session.pipeline.current_agent = agentName;
session.pipeline.eligible_agents = workflowState.eligible_agents;
session.pipeline.blocked_agents = workflowState.blocked_agents;
session.pipeline.warnings = workflowState.warnings;
session.pipeline.agents_run = session.pipeline.agents_run ?? [];
session.pipeline.agents_run.push({ agent: agentName, ran_at: now });

// Increment rework counter if this artifact was previously completed
if ((session.artifacts[targetArtifactId]?.revision ?? 0) > 0) {
  session.pipeline.rework_counts = session.pipeline.rework_counts ?? {};
  session.pipeline.rework_counts[targetArtifactId] =
    (session.pipeline.rework_counts[targetArtifactId] ?? 0) + 1;
  logInfo("Incremented rework counter", {
    targetArtifactId,
    reworkCount: session.pipeline.rework_counts[targetArtifactId],
  });
}

saveSession(session, sessionFile);
logInfo("Session saved", { sessionFile });

// ─── Success Output ───────────────────────────────────────────────────────────

const successResult = {
  ok: true,
  requested: agentName,
  artifact_id: targetArtifactId,
  feature_dir: session.feature_dir,
  prompt_id: promptId || null,
  message: `${agentName} is eligible and marked in_progress.`,
};

console.log(JSON.stringify(successResult, null, 2));
logInfo("Pre-agent checks completed successfully", {
  agentName,
  targetArtifactId,
  promptId: promptId || null,
});

if (workflowState.warnings.length > 0) {
  console.error("\n[pre-agent] Warnings:");
  for (const w of workflowState.warnings) {
    console.error(`  ⚠  ${w}`);
  }
}

console.error(`\n[pre-agent] ✓ ${agentName} is eligible and marked in_progress.`);

// ─── Helpers ──────────────────────────────────────────────────────────────────

/**
 * Prints a human-readable blocked summary to stderr.
 *
 * @param res Structured failure payload that explains why the command is blocked
 */
function _printBlockedHuman(res: {
  requested: string;
  reason: string;
  next_recommended?: string | null;
  next_prompt_id?: string | null;
  next_prompt?: string | null;
  eligible_agents: string[];
}): void {
  console.error(`\nCannot run ${res.requested}.\n`);
  console.error("Reason:");
  console.error(`  - ${res.reason}\n`);

  if (res.next_recommended) {
    console.error("Next recommended:");
    console.error(`  - ${res.next_recommended}`);
    if (res.next_prompt_id) console.error(`  - Prompt ID: ${res.next_prompt_id}`);
    if (res.next_prompt) console.error(`  - Prompt:\n    ${res.next_prompt}\n`);
  }

  if (res.eligible_agents.length > 0) {
    console.error("Other eligible commands:");
    for (const cmd of res.eligible_agents) console.error(`  - ${cmd}`);
  }
}
