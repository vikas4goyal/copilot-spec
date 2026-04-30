#!/usr/bin/env node
import * as fs from "node:fs";
import * as path from "node:path";
import { randomBytes } from "node:crypto";
import { getRepoRoot } from "./common";
import {
  loadSession,
  calculateWorkflowState,
} from "./workflow";

type Json = Record<string, unknown>;

const VALID_ACTIONS = new Set([
  "init",
  "get",
  "get-multi",
  "update",
  "update-multi",
  "read",
  "add-agent",
  "archive",
  "complete-artifact",
  "update-artifact",
  "skip-artifact",
  "check-deps",
]);

const VALID_ARTIFACT_FIELDS = new Set(["summary", "handoff", "status", "outputPath"]);

function nowIso(): string {
  return new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
}

function newSessionId(): string {
  const d = new Date();
  const pad = (n: number) => `${n}`.padStart(2, "0");
  const ts = `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}-${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`;
  const rand = randomBytes(3).toString("base64url").slice(0, 4);
  return `${ts}-${rand}`;
}

function readSession(sessionFile: string): Json {
  return JSON.parse(fs.readFileSync(sessionFile, "utf-8")) as Json;
}

function saveSession(session: Json, sessionFile: string): void {
  session.updated_at = nowIso();
  fs.writeFileSync(sessionFile, `${JSON.stringify(session, null, 2)}\n`, "utf-8");
}

function getByDot(obj: unknown, dotPath: string): unknown {
  let currentValue: unknown = obj;
  for (const pathSegment of dotPath.split(".")) {
    if (currentValue == null) return null;
    if (typeof currentValue === "object" && !Array.isArray(currentValue)) {
      currentValue = (currentValue as Json)[pathSegment];
    } else {
      return null;
    }
  }
  return currentValue;
}

function setByDot(obj: Json, dotPath: string, value: unknown): void {
  const parts = dotPath.split(".");
  let currentObject: Json = obj;
  for (const pathSegment of parts.slice(0, -1)) {
    if (
      typeof currentObject[pathSegment] !== "object" ||
      currentObject[pathSegment] == null ||
      Array.isArray(currentObject[pathSegment])
    ) {
      currentObject[pathSegment] = {};
    }
    currentObject = currentObject[pathSegment] as Json;
  }
  currentObject[parts[parts.length - 1]] = value;
}

function mergePatch(target: Json, patch: Json): void {
  for (const [key, value] of Object.entries(patch)) {
    if (
      typeof value === "object" &&
      value !== null &&
      !Array.isArray(value) &&
      typeof target[key] === "object" &&
      target[key] !== null &&
      !Array.isArray(target[key])
    ) {
      mergePatch(target[key] as Json, value as Json);
    } else {
      target[key] = value;
    }
  }
}


function initializeSession(sessionFile: string, templateFile: string, name?: string, description?: string): Json {
  if (!fs.existsSync(sessionFile)) {
    if (!fs.existsSync(templateFile)) {
      console.error(`[session] Template not found at ${templateFile}. Cannot initialize session.`);
      process.exit(1);
    }
    const session = JSON.parse(fs.readFileSync(templateFile, "utf-8")) as Json;
    const now = nowIso();
    session.id = newSessionId();
    session.created_at = now;
    session.updated_at = now;
    session.status = "active";
    if (name) session.name = name;
    if (description) session.description = description;
    fs.mkdirSync(path.dirname(sessionFile), { recursive: true });
    fs.writeFileSync(sessionFile, `${JSON.stringify(session, null, 2)}\n`, "utf-8");
    console.log(`[session] Initialized session at ${sessionFile} (id: ${String(session.id)})`);
    return session;
  }

  console.log("[session] Session already exists — reusing.");
  const session = readSession(sessionFile);
  let changed = false;
  if (name && !session.name) {
    session.name = name;
    changed = true;
  }
  if (description && !session.description) {
    session.description = description;
    changed = true;
  }
  if (changed) {
    saveSession(session, sessionFile);
    console.log("[session] Applied missing name/description to existing session.");
  }
  return session;
}

function getFieldValue(sessionFile: string, fieldPath: string): void {
  if (!fs.existsSync(sessionFile)) {
    console.error("[session] No active session.");
    return;
  }
  const value = getByDot(readSession(sessionFile), fieldPath);
  console.log(value == null ? "" : String(value));
}

function getMultiValues(sessionFile: string, fieldPaths: string): void {
  if (!fs.existsSync(sessionFile)) {
    console.error("[session] No active session.");
    console.log("{}");
    return;
  }
  const session = readSession(sessionFile);
  const result: Json = {};
  for (const rawFieldPath of fieldPaths.split(",")) {
    const fieldPath = rawFieldPath.trim();
    result[fieldPath] = getByDot(session, fieldPath) as unknown;
  }
  console.log(JSON.stringify(result));
}

function updateSessionField(sessionFile: string, templateFile: string, fieldPath: string, value: string): Json {
  if (!fs.existsSync(sessionFile)) initializeSession(sessionFile, templateFile);
  const session = readSession(sessionFile);
  setByDot(session, fieldPath, value);
  saveSession(session, sessionFile);
  console.log(`[session] Updated ${fieldPath}`);
  return session;
}

function addAgentToSession(sessionFile: string, templateFile: string, agent: string): Json {
  if (!fs.existsSync(sessionFile)) initializeSession(sessionFile, templateFile);
  const session = readSession(sessionFile);
  const agentRunEntry = { agent, ran_at: nowIso() };
  const pipeline = ((session.pipeline as Json | undefined) ?? {}) as Json;
  const agentsRun = ((pipeline.agents_run as unknown[] | undefined) ?? []) as unknown[];
  agentsRun.push(agentRunEntry);
  pipeline.agents_run = agentsRun;
  pipeline.current_agent = agent;
  session.pipeline = pipeline;
  saveSession(session, sessionFile);
  console.log(`[session] Recorded agent '${agent}' in session.`);
  return session;
}

function completeArtifact(sessionFile: string, artifactId: string): Json {
  if (!fs.existsSync(sessionFile)) {
    console.error("[session] No active session. Run 'init' first.");
    process.exit(1);
  }
  // Use workflow.ts loadSession for migration support
  const session = loadSession(sessionFile, getRepoRoot());
  const artifact = session.artifacts[artifactId];
  if (!artifact) {
    console.error(`[session] Artifact '${artifactId}' not found in session.`);
    process.exit(1);
  }

  const now = nowIso();
  artifact.status = "complete";
  artifact.completed_at = now;

  const pipeline = session.pipeline;
  pipeline.last_completed = artifactId;
  pipeline.current_agent = null;
  if ((artifact as unknown as Json).handoff) pipeline.next_prompt = (artifact as unknown as Json).handoff as string;

  // Recompute completeness
  const requiredPending = Object.entries(session.artifacts).filter(
    ([, a]) => a.required && a.status !== "complete" && a.status !== "skipped",
  );
  session.isComplete = requiredPending.length === 0;

  // Recalculate next recommended via workflow state
  const ws = calculateWorkflowState(session, getRepoRoot());
  pipeline.next_recommended = ws.next_recommended;
  pipeline.eligible_agents = ws.eligible_agents;
  pipeline.blocked_agents = ws.blocked_agents;

  saveSession(session, sessionFile);
  console.log(`[session] Artifact '${artifactId}' marked complete. Next: ${pipeline.next_recommended ?? "none"}`);
  return session as unknown as Json;
}

function updateArtifact(sessionFile: string, artifactId: string, field: string, fieldValue: string): Json {
  if (!fs.existsSync(sessionFile)) {
    console.error("[session] No active session. Run 'init' first.");
    process.exit(1);
  }
  // Extend valid fields to include new schema fields
  const extendedValidFields = new Set([...VALID_ARTIFACT_FIELDS, "revision", "reason", "started_at", "completed_at"]);
  if (!extendedValidFields.has(field)) {
    console.error(`[session] Invalid ArtifactField '${field}'. Valid: ${Array.from(extendedValidFields).join(", ")}`);
    process.exit(1);
  }
  const session = loadSession(sessionFile, getRepoRoot());
  const artifact = session.artifacts[artifactId];
  if (!artifact) {
    console.error(`[session] Artifact '${artifactId}' not found.`);
    process.exit(1);
  }
  (artifact as unknown as Json)[field] = fieldValue;
  saveSession(session, sessionFile);
  console.log(`[session] Artifact '${artifactId}'.${field} updated.`);
  return session as unknown as Json;
}

function skipArtifact(sessionFile: string, artifactId: string): Json {
  if (!fs.existsSync(sessionFile)) {
    console.error("[session] No active session. Run 'init' first.");
    process.exit(1);
  }
  const session = loadSession(sessionFile, getRepoRoot());
  const artifact = session.artifacts[artifactId];
  if (!artifact) {
    console.error(`[session] Artifact '${artifactId}' not found.`);
    process.exit(1);
  }

  if (artifact.required) {
    console.error(`[session] Artifact '${artifactId}' is marked required. Skipping it may break downstream steps.`);
  }

  artifact.status = "skipped";
  artifact.completed_at = nowIso();

  const pipeline = session.pipeline;
  pipeline.last_completed = artifactId;

  const ws = calculateWorkflowState(session, getRepoRoot());
  pipeline.next_recommended = ws.next_recommended;
  pipeline.eligible_agents = ws.eligible_agents;

  const requiredPending = Object.entries(session.artifacts).filter(
    ([, a]) => a.required && a.status !== "complete" && a.status !== "skipped",
  );
  session.isComplete = requiredPending.length === 0;

  saveSession(session, sessionFile);
  console.log(`[session] Artifact '${artifactId}' skipped. Next: ${pipeline.next_recommended ?? "none"}`);
  return session as unknown as Json;
}

function checkArtifactDeps(sessionFile: string, artifactId: string): boolean {
  if (!fs.existsSync(sessionFile)) {
    console.error("[session] No active session.");
    process.exit(1);
  }
  const session = loadSession(sessionFile, getRepoRoot());
  const artifact = session.artifacts[artifactId];
  if (!artifact) {
    console.error(`[session] Artifact '${artifactId}' not found.`);
    process.exit(1);
  }

  // Use workflow state to determine if blocked
  const ws = calculateWorkflowState(session, getRepoRoot());
  const { COMMAND_REGISTRY } = require("./workflow") as typeof import("./workflow");
  const def = COMMAND_REGISTRY[artifactId];
  const command = def?.command ?? `/${artifactId}`;

  if (command in ws.blocked_agents) {
    console.error(`[session] '${artifactId}' is blocked: ${ws.blocked_agents[command]}`);
    return false;
  }

  console.log(`[session] '${artifactId}' is ready — all dependencies met.`);
  return true;
}

function archiveSession(sessionFile: string, repoRoot: string): void {
  if (!fs.existsSync(sessionFile)) {
    console.error(`[session] No active session file found at ${sessionFile}`);
    return;
  }

  const session = readSession(sessionFile);
  const featureName =
    (session.branch_name as string | undefined) ??
    (session.name as string | undefined) ??
    (session.id as string | undefined) ??
    "unknown";
  const safeName = featureName.replace(/[^a-zA-Z0-9\-_.]/g, "-");
  const archiveDir = path.join(repoRoot, ".spec", "features", safeName);
  fs.mkdirSync(archiveDir, { recursive: true });

  session.status = "completed";
  session.updated_at = nowIso();
  fs.writeFileSync(sessionFile, `${JSON.stringify(session, null, 2)}\n`, "utf-8");

  const dest = path.join(archiveDir, "session.json");
  fs.renameSync(sessionFile, dest);
  console.log(`[session] Archived session to ${dest}`);
}

function arg(name: string): string {
  const flagIndex = process.argv.indexOf(name);
  return flagIndex >= 0 && flagIndex + 1 < process.argv.length ? process.argv[flagIndex + 1] : "";
}

const action = arg("--action");
if (!action || !VALID_ACTIONS.has(action)) {
  console.error(`--action is required and must be one of: ${Array.from(VALID_ACTIONS).join(", ")}`);
  process.exit(1);
}

const useJson = process.argv.includes("--json");
const name = arg("--name");
const description = arg("--description");
const field = arg("--field");
const fields = arg("--fields");
const value = arg("--value");
const jsonPatch = arg("--json-patch");
const agentName = arg("--agent-name");
const artifactId = arg("--artifact-id");
const artifactField = arg("--artifact-field");
const artifactValue = arg("--artifact-value");

const repoRoot = getRepoRoot();
const sessionFile = path.join(repoRoot, ".spec", "session.json");
const templateFile = path.join(repoRoot, ".spec", "templates", "session-state-template.json");

switch (action) {
  case "init": {
    const result = initializeSession(sessionFile, templateFile, name || undefined, description || undefined);
    if (useJson) console.log(JSON.stringify(result, null, 2));
    break;
  }
  case "get": {
    const requestedField = field || fields;
    if (!requestedField) {
      console.error("-field (or --fields) is required for 'get'");
      process.exit(1);
    }
    getFieldValue(sessionFile, requestedField);
    break;
  }
  case "get-multi": {
    if (!fields) {
      console.error("--fields is required for 'get-multi'");
      process.exit(1);
    }
    getMultiValues(sessionFile, fields);
    break;
  }
  case "update": {
    if (!field) {
      console.error("--field is required for 'update'");
      process.exit(1);
    }
    const result = updateSessionField(sessionFile, templateFile, field, value);
    if (useJson) console.log(JSON.stringify(result, null, 2));
    break;
  }
  case "update-multi": {
    if (!jsonPatch) {
      console.error("--json-patch is required for 'update-multi'");
      process.exit(1);
    }
    if (!fs.existsSync(sessionFile)) initializeSession(sessionFile, templateFile);
    const session = readSession(sessionFile);
    mergePatch(session, JSON.parse(jsonPatch) as Json);
    saveSession(session, sessionFile);
    console.log("[session] Applied JSON patch to session.");
    if (useJson) console.log(JSON.stringify(session, null, 2));
    break;
  }
  case "read": {
    if (!fs.existsSync(sessionFile)) {
      console.error("[session] No active session file.");
    } else {
      process.stdout.write(fs.readFileSync(sessionFile, "utf-8"));
    }
    break;
  }
  case "add-agent": {
    if (!agentName) {
      console.error("--agent-name is required for 'add-agent'");
      process.exit(1);
    }
    const result = addAgentToSession(sessionFile, templateFile, agentName);
    if (useJson) console.log(JSON.stringify(result, null, 2));
    break;
  }
  case "complete-artifact": {
    if (!artifactId) {
      console.error("--artifact-id is required for 'complete-artifact'");
      process.exit(1);
    }
    const result = completeArtifact(sessionFile, artifactId);
    if (useJson) console.log(JSON.stringify(result, null, 2));
    break;
  }
  case "update-artifact": {
    if (!artifactId) {
      console.error("--artifact-id is required for 'update-artifact'");
      process.exit(1);
    }
    if (!artifactField) {
      console.error("--artifact-field is required for 'update-artifact'");
      process.exit(1);
    }
    const result = updateArtifact(sessionFile, artifactId, artifactField, artifactValue);
    if (useJson) console.log(JSON.stringify(result, null, 2));
    break;
  }
  case "skip-artifact": {
    if (!artifactId) {
      console.error("--artifact-id is required for 'skip-artifact'");
      process.exit(1);
    }
    const result = skipArtifact(sessionFile, artifactId);
    if (useJson) console.log(JSON.stringify(result, null, 2));
    break;
  }
  case "check-deps": {
    if (!artifactId) {
      console.error("--artifact-id is required for 'check-deps'");
      process.exit(1);
    }
    if (!checkArtifactDeps(sessionFile, artifactId)) process.exit(1);
    break;
  }
  case "archive": {
    archiveSession(sessionFile, repoRoot);
    break;
  }
  default:
    process.exit(1);
}

