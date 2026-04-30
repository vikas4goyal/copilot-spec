#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import * as path from "node:path";

const scriptDir = __dirname;

function runManageSession(args: string[]): number {
  const commandResult = spawnSync("npx", ["tsx", path.join(scriptDir, "manage_session.ts"), ...args], {
    cwd: scriptDir,
    stdio: "inherit",
  });
  return commandResult.status ?? 1;
}

function getCliArg(name: string): string {
  const index = process.argv.indexOf(name);
  return index >= 0 && index + 1 < process.argv.length ? process.argv[index + 1] : "";
}

const agentName = getCliArg("--agent-name");
const artifactId = getCliArg("--artifact-id");

if (!agentName) {
  console.error("Missing required --agent-name");
  process.exit(1);
}

const bootstrapArgs = [
  "npx",
  "tsx",
  path.join(scriptDir, "bootstrap_session.ts"),
  "--agent-name",
  agentName,
];
if (artifactId) bootstrapArgs.push("--artifact-id", artifactId);

const bootstrapResult = spawnSync(bootstrapArgs[0], bootstrapArgs.slice(1), { cwd: scriptDir, stdio: "inherit" });
if ((bootstrapResult.status ?? 1) !== 0) process.exit(1);

if (artifactId) {
  // Mark the target artifact in progress so downstream tooling can show active work.
  runManageSession([
    "--action",
    "update-artifact",
    "--artifact-id",
    artifactId,
    "--artifact-field",
    "status",
    "--artifact-value",
    "in_progress",
  ]);
}

const suffix = artifactId ? ` (artifact: ${artifactId})` : "";
console.log(`[pre-agent] Session ready: ${agentName}${suffix}`);

