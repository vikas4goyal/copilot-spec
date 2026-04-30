#!/usr/bin/env node
/**
 * workflow.ts — Central workflow graph for the spec state machine.
 * This module owns: command registry, artifact dependency graph, stale propagation
 * rules, loop protection, prompt lifecycle, eligibility calculation, and session migration.
 *
 * Scripts are the authority for eligibility checks. Markdown agents must not
 * independently decide whether they are allowed to run.
 */

import * as fs from "node:fs";
import * as path from "node:path";
import { randomBytes } from "node:crypto";

// ─── Type Definitions ─────────────────────────────────────────────────────────

export type ArtifactStatus =
  | "pending"
  | "optional"
  | "blocked"
  | "in_progress"
  | "complete"
  | "stale"
  | "skipped"
  | "failed";

export type PromptStatus =
  | "draft"
  | "recommended"
  | "used"
  | "superseded"
  | "stale"
  | "rejected"
  | "expired";

export interface ArtifactHistoryEntry {
  revision: number;
  status: ArtifactStatus;
  prompt_id: string | null;
  summary: string | null;
  based_on: Record<string, number>;
  completed_at: string | null;
}

export interface Artifact {
  status: ArtifactStatus;
  required: boolean;
  revision: number;
  outputPath: string | null;
  based_on: Record<string, number>;
  created_by_prompt_id: string | null;
  last_updated_by_prompt_id: string | null;
  summary: string | null;
  reason: string | null;
  started_at: string | null;
  completed_at: string | null;
  history: ArtifactHistoryEntry[];
}

export interface PromptRecord {
  id: string;
  target_agent: string;
  command: string;
  prompt: string;
  reason: string;
  created_by: string;
  created_at: string;
  source_artifact: string;
  source_revision: number;
  consumes: Record<string, number>;
  refreshes: Record<string, number>;
  supersedes: string | null;
  status: PromptStatus;
  stale_reason: string | null;
}

export interface PipelineState {
  current_agent: string | null;
  last_completed: string | null;
  eligible_agents: string[];
  blocked_agents: Record<string, string>;
  next_recommended: string | null;
  next_prompt_id: string | null;
  next_prompt: string | null;
  agents_run: Array<{ agent: string; ran_at: string }>;
  transition_history: Array<{ from: string; to: string; reason: string; timestamp: string }>;
  warnings: string[];
  rework_counts: Record<string, number>;
  max_rework_per_artifact: number;
}

export interface Session {
  _schema: string;
  schemaName: string;
  status: string;
  isComplete: boolean;
  id: string | null;
  name: string | null;
  description: string | null;
  branch_name: string | null;
  feature_dir: string | null;
  artifacts: Record<string, Artifact>;
  pipeline: PipelineState;
  prompts: Record<string, PromptRecord>;
  created_at: string | null;
  updated_at: string | null;
  [key: string]: unknown;
}

export interface WorkflowState {
  eligible_agents: string[];
  blocked_agents: Record<string, string>;
  next_recommended: string | null;
  next_prompt_id: string | null;
  next_prompt: string | null;
  warnings: string[];
}

// ─── Command Registry ─────────────────────────────────────────────────────────

export interface CommandDef {
  command: string;
  agentId: string;
  artifactId: string;
  description: string;
  defaultOutputPath: string | null;
  defaultPrompt: string;
  required: boolean;
}

export const COMMAND_REGISTRY: Record<string, CommandDef> = {
  constitution: {
    command: "/spec.constitution",
    agentId: "spec.constitution",
    artifactId: "constitution",
    description: "Create or update project governing principles and development guidelines",
    defaultOutputPath: ".spec/memory/constitution.md",
    defaultPrompt: "Create or update the project constitution with governing principles and development guidelines.",
    required: false,
  },
  specify: {
    command: "/spec.specify",
    agentId: "spec.specify",
    artifactId: "specify",
    description: "Define requirements and user stories",
    defaultOutputPath: null,
    defaultPrompt: "Define the feature requirements and user stories.",
    required: true,
  },
  clarify: {
    command: "/spec.clarify",
    agentId: "spec.clarify",
    artifactId: "clarify",
    description: "Clarify underspecified areas",
    defaultOutputPath: null,
    defaultPrompt: "Identify and resolve underspecified areas in the current feature specification.",
    required: false,
  },
  plan: {
    command: "/spec.plan",
    agentId: "spec.plan",
    artifactId: "plan",
    description: "Create technical implementation plan",
    defaultOutputPath: null,
    defaultPrompt: "Create a technical implementation plan from the current specification.",
    required: true,
  },
  checklist: {
    command: "/spec.checklist",
    agentId: "spec.checklist",
    artifactId: "checklist",
    description: "Generate quality checklists for requirements",
    defaultOutputPath: null,
    defaultPrompt: "Generate quality checklists for the current feature requirements.",
    required: false,
  },
  tasks: {
    command: "/spec.tasks",
    agentId: "spec.tasks",
    artifactId: "tasks",
    description: "Generate actionable implementation task list",
    defaultOutputPath: null,
    defaultPrompt: "Generate an actionable, dependency-ordered implementation task list from the current plan.",
    required: true,
  },
  analyze: {
    command: "/spec.analyze",
    agentId: "spec.analyze",
    artifactId: "analyze",
    description: "Cross-artifact consistency and coverage analysis",
    defaultOutputPath: null,
    defaultPrompt: "Perform a cross-artifact consistency and coverage analysis across spec.md, plan.md, and tasks.md.",
    required: false,
  },
  implement: {
    command: "/spec.implement",
    agentId: "spec.implement",
    artifactId: "implement",
    description: "Execute tasks to build the feature",
    defaultOutputPath: null,
    defaultPrompt: "Execute the implementation plan by processing and executing all tasks defined in tasks.md.",
    required: true,
  },
  release: {
    command: "/spec.release",
    agentId: "spec.release",
    artifactId: "release",
    description: "Finalize, push, archive session, and reset workspace",
    defaultOutputPath: null,
    defaultPrompt:
      "Finalize and release the current feature: push the branch, archive the session, and reset the workspace.",
    required: false,
  },
};

// ─── Pipeline Order (for recommendation priority) ─────────────────────────────

export const PIPELINE_ORDER = [
  "constitution",
  "specify",
  "clarify",
  "plan",
  "checklist",
  "tasks",
  "analyze",
  "implement",
  "release",
];

// ─── Dependency Graph ─────────────────────────────────────────────────────────

/** Hard dependencies: artifact CANNOT run unless ALL of these are complete/skipped */
export const ARTIFACT_HARD_DEPS: Record<string, string[]> = {
  constitution: [],
  specify: [],
  clarify: ["specify"],
  plan: ["specify"],
  checklist: ["specify"],
  tasks: ["plan"],
  analyze: ["specify", "plan", "tasks"],
  implement: ["tasks"],
  release: ["implement"],
};

/** Soft dependencies: used for stale detection and based_on tracking */
export const ARTIFACT_SOFT_DEPS: Record<string, string[]> = {
  constitution: [],
  specify: [],
  clarify: ["specify"],
  plan: ["constitution", "specify", "clarify"],
  checklist: ["specify", "plan"],
  tasks: ["plan"],
  analyze: ["specify", "plan", "tasks"],
  implement: ["tasks", "analyze"],
  release: ["implement"],
};

/**
 * Stale propagation: when artifact X revision increments,
 * mark these downstream completed artifacts as stale.
 */
export const STALE_PROPAGATION: Record<string, string[]> = {
  constitution: ["plan", "checklist", "tasks", "analyze", "implement", "release"],
  specify: ["clarify", "plan", "checklist", "tasks", "analyze", "implement", "release"],
  clarify: ["plan", "checklist", "tasks", "analyze", "implement", "release"],
  plan: ["tasks", "analyze", "implement", "release"],
  checklist: [],
  tasks: ["analyze", "implement", "release"],
  analyze: [],
  implement: ["release"],
  release: [],
};

// ─── Helpers ──────────────────────────────────────────────────────────────────

export function nowIso(): string {
  return new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
}

export function generatePromptId(existingIds: string[]): string {
  const nums = existingIds
    .map((id) => {
      const m = id.match(/^prompt_(\d+)$/);
      return m ? parseInt(m[1], 10) : 0;
    })
    .filter((n) => n > 0);
  const next = nums.length > 0 ? Math.max(...nums) + 1 : 1;
  return `prompt_${String(next).padStart(3, "0")}`;
}

export function safeFileExists(p: string): boolean {
  try {
    return fs.existsSync(p);
  } catch {
    return false;
  }
}

function resolveFromRoot(p: string, repoRoot: string): string {
  return path.isAbsolute(p) ? p : path.join(repoRoot, p);
}

export function newSessionId(): string {
  const d = new Date();
  const pad = (n: number) => String(n).padStart(2, "0");
  const ts = `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}-${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`;
  const rand = randomBytes(3).toString("base64url").slice(0, 4);
  return `${ts}-${rand}`;
}

// ─── Default Artifact Registry ────────────────────────────────────────────────

export function buildDefaultArtifacts(): Record<string, Artifact> {
  return {
    constitution: {
      status: "optional",
      required: false,
      revision: 0,
      outputPath: ".spec/memory/constitution.md",
      based_on: {},
      created_by_prompt_id: null,
      last_updated_by_prompt_id: null,
      summary: null,
      reason: null,
      started_at: null,
      completed_at: null,
      history: [],
    },
    specify: {
      status: "pending",
      required: true,
      revision: 0,
      outputPath: null,
      based_on: {},
      created_by_prompt_id: null,
      last_updated_by_prompt_id: null,
      summary: null,
      reason: null,
      started_at: null,
      completed_at: null,
      history: [],
    },
    clarify: {
      status: "optional",
      required: false,
      revision: 0,
      outputPath: null,
      based_on: { specify: 0 },
      created_by_prompt_id: null,
      last_updated_by_prompt_id: null,
      summary: null,
      reason: null,
      started_at: null,
      completed_at: null,
      history: [],
    },
    plan: {
      status: "blocked",
      required: true,
      revision: 0,
      outputPath: null,
      based_on: { constitution: 0, specify: 0, clarify: 0 },
      created_by_prompt_id: null,
      last_updated_by_prompt_id: null,
      summary: null,
      reason: null,
      started_at: null,
      completed_at: null,
      history: [],
    },
    checklist: {
      status: "optional",
      required: false,
      revision: 0,
      outputPath: null,
      based_on: { specify: 0, plan: 0 },
      created_by_prompt_id: null,
      last_updated_by_prompt_id: null,
      summary: null,
      reason: null,
      started_at: null,
      completed_at: null,
      history: [],
    },
    tasks: {
      status: "blocked",
      required: true,
      revision: 0,
      outputPath: null,
      based_on: { plan: 0 },
      created_by_prompt_id: null,
      last_updated_by_prompt_id: null,
      summary: null,
      reason: null,
      started_at: null,
      completed_at: null,
      history: [],
    },
    analyze: {
      status: "optional",
      required: false,
      revision: 0,
      outputPath: null,
      based_on: { specify: 0, plan: 0, tasks: 0 },
      created_by_prompt_id: null,
      last_updated_by_prompt_id: null,
      summary: null,
      reason: null,
      started_at: null,
      completed_at: null,
      history: [],
    },
    implement: {
      status: "blocked",
      required: true,
      revision: 0,
      outputPath: null,
      based_on: { tasks: 0, analyze: 0 },
      created_by_prompt_id: null,
      last_updated_by_prompt_id: null,
      summary: null,
      reason: null,
      started_at: null,
      completed_at: null,
      history: [],
    },
    release: {
      status: "blocked",
      required: false,
      revision: 0,
      outputPath: null,
      based_on: { implement: 0 },
      created_by_prompt_id: null,
      last_updated_by_prompt_id: null,
      summary: null,
      reason: null,
      started_at: null,
      completed_at: null,
      history: [],
    },
  };
}

// ─── Stale Detection ──────────────────────────────────────────────────────────

export function isArtifactStaleByRevisions(
  artifactId: string,
  artifacts: Record<string, Artifact>,
): boolean {
  const artifact = artifacts[artifactId];
  if (!artifact) return false;
  if (artifact.status !== "complete") return false;

  const softDeps = ARTIFACT_SOFT_DEPS[artifactId] ?? [];
  for (const dep of softDeps) {
    const depArtifact = artifacts[dep];
    if (!depArtifact) continue;
    if (depArtifact.revision === 0) continue; // dep never produced output
    const basedOnRev = artifact.based_on[dep] ?? 0;
    if (depArtifact.revision > basedOnRev) {
      return true;
    }
  }
  return false;
}

// ─── Stale Propagation ────────────────────────────────────────────────────────

export function applyStalePropagate(session: Session, changedArtifactId: string): void {
  const downstream = STALE_PROPAGATION[changedArtifactId] ?? [];
  for (const id of downstream) {
    const artifact = session.artifacts[id];
    if (!artifact) continue;
    if (artifact.status === "complete" || artifact.status === "stale") {
      artifact.status = "stale";
      artifact.reason = `Upstream artifact '${changedArtifactId}' changed.`;
    }
    // If pending/blocked leave as-is; stale only applies to previously completed work
  }
}

// ─── Prompt Lifecycle ─────────────────────────────────────────────────────────

export function createPromptRecord(params: {
  prompts: Record<string, PromptRecord>;
  targetAgentId: string;
  prompt: string;
  reason: string;
  createdBy: string;
  sourceArtifact: string;
  sourceRevision: number;
  consumes: Record<string, number>;
  refreshes?: Record<string, number>;
  supersedes?: string | null;
}): PromptRecord {
  const {
    prompts,
    targetAgentId,
    prompt,
    reason,
    createdBy,
    sourceArtifact,
    sourceRevision,
    consumes,
    refreshes,
    supersedes,
  } = params;

  // Find existing recommended prompt for same target and supersede it
  let oldPromptId: string | null = supersedes ?? null;
  if (!oldPromptId) {
    const existing = Object.values(prompts).find(
      (p) =>
        p.target_agent === targetAgentId &&
        (p.status === "recommended" || p.status === "draft"),
    );
    if (existing) oldPromptId = existing.id;
  }

  if (oldPromptId && prompts[oldPromptId]) {
    prompts[oldPromptId].status = "superseded";
  }

  const def = Object.values(COMMAND_REGISTRY).find((d) => d.agentId === targetAgentId);
  const promptId = generatePromptId(Object.keys(prompts));

  const record: PromptRecord = {
    id: promptId,
    target_agent: targetAgentId,
    command: def?.command ?? `/${targetAgentId}`,
    prompt,
    reason,
    created_by: createdBy,
    created_at: nowIso(),
    source_artifact: sourceArtifact,
    source_revision: sourceRevision,
    consumes,
    refreshes: refreshes ?? {},
    supersedes: oldPromptId,
    status: "recommended",
    stale_reason: null,
  };

  prompts[promptId] = record;
  return record;
}

export function markPromptsStaleForArtifact(
  session: Session,
  changedArtifactId: string,
  newRevision: number,
): void {
  for (const prompt of Object.values(session.prompts ?? {})) {
    if (prompt.status === "recommended" || prompt.status === "draft") {
      const consumedRev = prompt.consumes[changedArtifactId];
      if (consumedRev !== undefined && consumedRev < newRevision) {
        prompt.status = "stale";
        prompt.stale_reason = `${changedArtifactId} changed from revision ${consumedRev} to ${newRevision}`;
      }
    }
  }
}

// ─── Workflow State Calculation ───────────────────────────────────────────────

export function calculateWorkflowState(session: Session, repoRoot: string): WorkflowState {
  const artifacts = session.artifacts;
  const featureDir = session.feature_dir;
  const warnings: string[] = [];
  const eligible_agents: string[] = [];
  const blocked_agents: Record<string, string> = {};

  const resolvedFeatureDir = featureDir
    ? path.isAbsolute(featureDir)
      ? featureDir
      : path.join(repoRoot, featureDir)
    : null;

  const fe = (p: string) => safeFileExists(path.isAbsolute(p) ? p : path.join(repoRoot, p));

  const isDone = (id: string): boolean => {
    const a = artifacts[id];
    return !!(a && (a.status === "complete" || a.status === "skipped"));
  };

  const isStale = (id: string): boolean => isArtifactStaleByRevisions(id, artifacts);

  // Check spec.md for NEEDS CLARIFICATION
  let specHasNeedsClarity = false;
  if (resolvedFeatureDir) {
    const specPath = path.join(resolvedFeatureDir, "spec.md");
    if (safeFileExists(specPath)) {
      try {
        specHasNeedsClarity = fs.readFileSync(specPath, "utf-8").includes("NEEDS CLARIFICATION");
      } catch {
        /* ignore */
      }
    }
  }

  // Check for incomplete checklists
  let hasIncompleteChecklists = false;
  if (resolvedFeatureDir) {
    const checklistsDir = path.join(resolvedFeatureDir, "checklists");
    if (safeFileExists(checklistsDir)) {
      try {
        const files = fs.readdirSync(checklistsDir).filter((f) => f.endsWith(".md"));
        for (const f of files) {
          if (fs.readFileSync(path.join(checklistsDir, f), "utf-8").includes("- [ ]")) {
            hasIncompleteChecklists = true;
            break;
          }
        }
      } catch {
        /* ignore */
      }
    }
  }

  // Helper: resolve artifact-specific file paths
  const artifactFilePath = (id: string): string | null => {
    if (!resolvedFeatureDir) return null;
    switch (id) {
      case "specify":
      case "clarify":
        return path.join(resolvedFeatureDir, "spec.md");
      case "plan":
        return path.join(resolvedFeatureDir, "plan.md");
      case "tasks":
        return path.join(resolvedFeatureDir, "tasks.md");
      case "constitution":
        return path.join(repoRoot, ".spec", "memory", "constitution.md");
      default:
        return null;
    }
  };

  for (const [artifactId, def] of Object.entries(COMMAND_REGISTRY)) {
    const artifact = artifacts[artifactId];
    if (!artifact) continue;

    const hardDeps = ARTIFACT_HARD_DEPS[artifactId] ?? [];
    const reasons: string[] = [];

    // Check hard dependencies
    for (const dep of hardDeps) {
      if (!isDone(dep)) {
        const depDef = COMMAND_REGISTRY[dep];
        reasons.push(`Requires ${depDef?.command ?? dep} to be complete first`);
      }
    }

    // Per-artifact extra checks
    if (reasons.length === 0) {
      switch (artifactId) {
        case "clarify": {
          const f = artifactFilePath("specify");
          if (!f || !fe(f)) reasons.push("Requires spec.md to exist in the feature directory");
          break;
        }
        case "plan": {
          const f = artifactFilePath("specify");
          if (!f || !fe(f)) reasons.push("Requires spec.md to exist in the feature directory");
          if (isStale("plan")) {
            warnings.push("/spec.plan is stale — upstream artifacts changed since last run");
          }
          if (specHasNeedsClarity) {
            warnings.push(
              "/spec.plan: spec.md contains NEEDS CLARIFICATION markers — consider running /spec.clarify first",
            );
          }
          break;
        }
        case "checklist": {
          const f = artifactFilePath("specify");
          if (!f || !fe(f)) reasons.push("Requires spec.md to exist in the feature directory");
          break;
        }
        case "tasks": {
          const sf = artifactFilePath("specify");
          const pf = artifactFilePath("plan");
          if (!sf || !fe(sf)) reasons.push("Requires spec.md to exist in the feature directory");
          if (!pf || !fe(pf)) reasons.push("Requires plan.md to exist in the feature directory");
          if (isStale("plan"))
            reasons.push("plan is stale — run /spec.plan first to refresh the plan");
          break;
        }
        case "analyze": {
          const sf = artifactFilePath("specify");
          const pf = artifactFilePath("plan");
          const tf = artifactFilePath("tasks");
          if (!sf || !fe(sf)) reasons.push("Requires spec.md to exist in the feature directory");
          if (!pf || !fe(pf)) reasons.push("Requires plan.md to exist in the feature directory");
          if (!tf || !fe(tf)) reasons.push("Requires tasks.md to exist in the feature directory");
          break;
        }
        case "implement": {
          const sf = artifactFilePath("specify");
          const pf = artifactFilePath("plan");
          const tf = artifactFilePath("tasks");
          if (!sf || !fe(sf)) reasons.push("Requires spec.md to exist in the feature directory");
          if (!pf || !fe(pf)) reasons.push("Requires plan.md to exist in the feature directory");
          if (!tf || !fe(tf)) reasons.push("Requires tasks.md to exist in the feature directory");
          if (isStale("tasks"))
            reasons.push("tasks is stale — run /spec.tasks first to refresh the task list");
          if (isStale("plan"))
            reasons.push("plan is stale — run /spec.plan first to refresh the plan");
          if (hasIncompleteChecklists) {
            warnings.push(
              "/spec.implement: Some checklists have incomplete items — agent will prompt for confirmation before proceeding",
            );
          }
          break;
        }
        case "release": {
          if (!isDone("implement")) reasons.push("Requires /spec.implement to be complete first");
          break;
        }
      }
    }

    if (reasons.length > 0) {
      blocked_agents[def.command] = reasons.join("; ");
    } else {
      eligible_agents.push(def.command);
    }
  }

  // Warn about stale completed artifacts not already warned
  for (const [id, artifact] of Object.entries(artifacts)) {
    if (artifact.status === "complete" && isArtifactStaleByRevisions(id, artifacts)) {
      const def = COMMAND_REGISTRY[id];
      if (def && !warnings.some((w) => w.includes(def.command))) {
        warnings.push(`${def.command} is stale — upstream artifact changed since last run`);
      }
    }
  }

  const next_recommended = _determineNextRecommended(artifacts, specHasNeedsClarity, isStale);

  // Find recommended prompt for next agent
  let next_prompt_id: string | null = null;
  let next_prompt: string | null = null;

  if (next_recommended) {
    const nextArtifactId = next_recommended.replace(/^\/spec\./, "");
    const nextDef = COMMAND_REGISTRY[nextArtifactId];
    const existingPrompt = Object.values(session.prompts ?? {})
      .filter(
        (p) =>
          p.target_agent === nextDef?.agentId &&
          (p.status === "recommended" || p.status === "draft"),
      )
      .sort((a, b) => b.created_at.localeCompare(a.created_at))[0];

    if (existingPrompt) {
      next_prompt_id = existingPrompt.id;
      next_prompt = existingPrompt.prompt;
    } else if (nextDef) {
      next_prompt = nextDef.defaultPrompt;
    }
  }

  return { eligible_agents, blocked_agents, next_recommended, next_prompt_id, next_prompt, warnings };
}

function _determineNextRecommended(
  artifacts: Record<string, Artifact>,
  specHasNeedsClarity: boolean,
  isStale: (id: string) => boolean,
): string | null {
  const isDone = (id: string) => {
    const a = artifacts[id];
    return !!(a && (a.status === "complete" || a.status === "skipped"));
  };

  // 1. If specify not started/done, recommend specify
  if (!isDone("specify")) return "/spec.specify";

  // 2. If spec has NEEDS CLARIFICATION and clarify not done, recommend clarify
  if (specHasNeedsClarity && !isDone("clarify")) return "/spec.clarify";

  // 3. If plan stale or not done, recommend plan
  if (!isDone("plan") || isStale("plan")) return "/spec.plan";

  // 4. If tasks stale or not done, recommend tasks
  if (!isDone("tasks") || isStale("tasks")) return "/spec.tasks";

  // 5. If analyze not done, recommend analyze
  if (!isDone("analyze")) return "/spec.analyze";

  // 6. If implement not done, recommend implement
  if (!isDone("implement")) return "/spec.implement";

  // 7. If release not done, recommend release
  if (!isDone("release")) return "/spec.release";

  return null;
}

// ─── Session Migration ────────────────────────────────────────────────────────

export function migrateSessionIfNeeded(
  raw: Record<string, unknown>,
  repoRoot: string,
): Session {
  const schema = raw._schema as string | undefined;

  // Already correct schema
  if (
    schema === "spec-session/2.0" &&
    typeof raw.artifacts === "object" &&
    !Array.isArray(raw.artifacts) &&
    raw.artifacts !== null
  ) {
    return _ensureNewSessionFields(raw as unknown as Session);
  }

  console.error("[session] Migrating session to spec-session/2.0 schema...");

  const oldPipeline = (raw.pipeline as Record<string, unknown> | undefined) ?? {};
  const oldArtifactsArr = Array.isArray(raw.artifacts)
    ? (raw.artifacts as Record<string, unknown>[])
    : [];

  const newArtifacts = buildDefaultArtifacts();
  const featureDir = (raw.feature_dir as string | undefined) ?? "";

  // Map old array items
  for (const oldArt of oldArtifactsArr) {
    const id = oldArt.id as string | undefined;
    if (!id || !newArtifacts[id]) continue;
    const art = newArtifacts[id];
    const oldStatus = (oldArt.status as string | undefined) ?? "";

    if (oldStatus === "complete") {
      art.status = "complete";
      art.revision = 1;
      art.completed_at = (oldArt.completedAt as string | null) ?? nowIso();
      art.summary = (oldArt.summary as string | null) ?? null;
      art.history.push({
        revision: 1,
        status: "complete",
        prompt_id: null,
        summary: art.summary,
        based_on: {},
        completed_at: art.completed_at,
      });
    } else if (oldStatus === "skipped") {
      art.status = "skipped";
      art.completed_at = (oldArt.completedAt as string | null) ?? nowIso();
    }

    if (oldArt.outputPath) art.outputPath = oldArt.outputPath as string;
  }

  // Infer from file system
  if (featureDir) {
    const fp = (relPath: string) =>
      safeFileExists(path.isAbsolute(relPath) ? relPath : path.join(repoRoot, relPath));

    if (fp(".spec/memory/constitution.md") && newArtifacts.constitution.status !== "complete") {
      newArtifacts.constitution.status = "complete";
      newArtifacts.constitution.revision = 1;
    }
    if (fp(`${featureDir}/spec.md`) && newArtifacts.specify.status !== "complete") {
      newArtifacts.specify.status = "complete";
      newArtifacts.specify.revision = 1;
    }
    if (fp(`${featureDir}/plan.md`) && newArtifacts.plan.status !== "complete") {
      newArtifacts.plan.status = "complete";
      newArtifacts.plan.revision = 1;
    }
    if (fp(`${featureDir}/tasks.md`) && newArtifacts.tasks.status !== "complete") {
      newArtifacts.tasks.status = "complete";
      newArtifacts.tasks.revision = 1;
    }
  }

  // Re-calculate blocked status based on what's actually complete
  for (const [id, art] of Object.entries(newArtifacts)) {
    if (art.status === "blocked" || art.status === "pending") {
      const hardDeps = ARTIFACT_HARD_DEPS[id] ?? [];
      const allDone = hardDeps.every((dep) => {
        const d = newArtifacts[dep];
        return d && (d.status === "complete" || d.status === "skipped");
      });
      if (allDone && art.status === "blocked") {
        art.status = "pending";
      }
    }
  }

  // Build prompts from old next_prompt
  const prompts: Record<string, PromptRecord> = {};
  const oldNextPrompt = (oldPipeline.next_prompt as string | null) ?? null;
  const oldNextRecommended = (oldPipeline.next_recommended as string | null) ?? null;

  if (oldNextPrompt && oldNextRecommended) {
    const targetArtifactId = oldNextRecommended.replace(/^\/spec\./, "");
    const targetDef = COMMAND_REGISTRY[targetArtifactId];
    if (targetDef) {
      const lastCompleted = (oldPipeline.last_completed as string | null) ?? null;
      const promptId = "prompt_001";
      prompts[promptId] = {
        id: promptId,
        target_agent: targetDef.agentId,
        command: targetDef.command,
        prompt: oldNextPrompt,
        reason: "Migrated from previous session next_prompt field.",
        created_by: lastCompleted ? `spec.${lastCompleted}` : "migration",
        created_at: nowIso(),
        source_artifact: lastCompleted ?? "",
        source_revision: lastCompleted ? (newArtifacts[lastCompleted]?.revision ?? 0) : 0,
        consumes: {},
        refreshes: {},
        supersedes: null,
        status: "recommended",
        stale_reason: null,
      };
    }
  }

  const oldAgentsRun = Array.isArray(oldPipeline.agents_run)
    ? (oldPipeline.agents_run as Array<Record<string, unknown>>)
    : [];

  const migrated: Session = {
    _schema: "spec-session/2.0",
    schemaName: "spec-driven",
    status: (raw.status as string | undefined) ?? "active",
    isComplete: false,
    id: (raw.id as string | null) ?? null,
    name: (raw.name as string | null) ?? null,
    description: (raw.description as string | null) ?? null,
    branch_name: (raw.branch_name as string | null) ?? null,
    feature_dir: (raw.feature_dir as string | null) ?? null,
    artifacts: newArtifacts,
    pipeline: {
      current_agent: null,
      last_completed: (oldPipeline.last_completed as string | null) ?? null,
      eligible_agents: [],
      blocked_agents: {},
      next_recommended: oldNextRecommended ?? "/spec.specify",
      next_prompt_id: Object.keys(prompts)[0] ?? null,
      next_prompt: oldNextPrompt,
      agents_run: oldAgentsRun.map((e) => ({
        agent: (e.agent as string) ?? "",
        ran_at: (e.ran_at as string) ?? nowIso(),
      })),
      transition_history: [],
      warnings: [],
      rework_counts: {},
      max_rework_per_artifact: 3,
    },
    prompts,
    created_at: (raw.created_at as string | null) ?? null,
    updated_at: nowIso(),
    _migration_note: `Migrated from '${schema ?? "unknown"}' to spec-session/2.0 at ${nowIso()}`,
  };

  return migrated;
}

function _ensureNewSessionFields(session: Session): Session {
  const defaults = buildDefaultArtifacts();
  for (const [id, def] of Object.entries(defaults)) {
    if (!session.artifacts[id]) session.artifacts[id] = def;
  }
  if (!session.pipeline.transition_history) session.pipeline.transition_history = [];
  if (!session.pipeline.rework_counts) session.pipeline.rework_counts = {};
  if (session.pipeline.max_rework_per_artifact == null)
    session.pipeline.max_rework_per_artifact = 3;
  if (!session.pipeline.eligible_agents) session.pipeline.eligible_agents = [];
  if (!session.pipeline.blocked_agents) session.pipeline.blocked_agents = {};
  if (!session.pipeline.warnings) session.pipeline.warnings = [];
  if (!session.prompts) session.prompts = {};
  return session;
}

// ─── Session I/O ──────────────────────────────────────────────────────────────

export function loadSession(sessionFile: string, repoRoot: string): Session {
  if (!safeFileExists(sessionFile)) return initializeEmptySession();
  const raw = JSON.parse(fs.readFileSync(sessionFile, "utf-8")) as Record<string, unknown>;
  return migrateSessionIfNeeded(raw, repoRoot);
}

export function saveSession(session: Session, sessionFile: string): void {
  session.updated_at = nowIso();
  fs.mkdirSync(path.dirname(sessionFile), { recursive: true });
  fs.writeFileSync(sessionFile, `${JSON.stringify(session, null, 2)}\n`, "utf-8");
}

export function initializeEmptySession(): Session {
  const now = nowIso();
  return {
    _schema: "spec-session/2.0",
    schemaName: "spec-driven",
    status: "active",
    isComplete: false,
    id: null,
    name: null,
    description: null,
    branch_name: null,
    feature_dir: null,
    artifacts: buildDefaultArtifacts(),
    pipeline: {
      current_agent: null,
      last_completed: null,
      eligible_agents: [],
      blocked_agents: {},
      next_recommended: "/spec.specify",
      next_prompt_id: null,
      next_prompt: "Define the feature requirements and user stories.",
      agents_run: [],
      transition_history: [],
      warnings: [],
      rework_counts: {},
      max_rework_per_artifact: 3,
    },
    prompts: {},
    created_at: now,
    updated_at: now,
  };
}

export function getCurrentRevisions(artifacts: Record<string, Artifact>): Record<string, number> {
  const result: Record<string, number> = {};
  for (const [id, art] of Object.entries(artifacts)) result[id] = art.revision;
  return result;
}

