#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import * as path from "node:path";

const scriptDir = __dirname;

/**
 * Emits bootstrap diagnostics to stderr.
 */
function logInfo(message: string, details?: unknown): void {
  if (details === undefined) {
    console.error(`[bootstrap-session] ${message}`);
    return;
  }
  console.error(`[bootstrap-session] ${message}`, details);
}

/**
 * Executes manage_session.ts with passthrough stdio.
 */
function runManageSession(args: string[]): number {
  logInfo("Running manage_session action", { args });
  const commandResult = spawnSync("npx", ["tsx", path.join(scriptDir, "manage_session.ts"), ...args], {
    cwd: scriptDir,
    stdio: "inherit",
  });
  logInfo("manage_session action finished", { args, exitCode: commandResult.status ?? 1 });
  return commandResult.status ?? 1;
}

/**
 * Reads a CLI argument by flag name.
 */
function getCliArg(name: string): string {
  const index = process.argv.indexOf(name);
  return index >= 0 && index + 1 < process.argv.length ? process.argv[index + 1] : "";
}

const agentName = getCliArg("--agent-name");
const artifactId = getCliArg("--artifact-id");

logInfo("Starting bootstrap sequence", {
  agentName: agentName || null,
  artifactId: artifactId || null,
});

if (!agentName) {
  console.error("Missing required --agent-name");
  process.exit(1);
}

// Ensure the session exists, track this agent run, then verify artifact deps when provided.
const initArgs = ["--action", "init", ...(agentName ? ["--agent-name", agentName] : [])];
logInfo("Ensuring active session exists");
if (runManageSession(initArgs) !== 0) process.exit(1);
logInfo("Recording current agent in session", { agentName });
if (runManageSession(["--action", "add-agent", "--agent-name", agentName]) !== 0) process.exit(1);
if (artifactId) {
  logInfo("Checking artifact dependencies", { artifactId });
  if (runManageSession(["--action", "check-deps", "--artifact-id", artifactId]) !== 0) process.exit(1);
}

logInfo("Bootstrap sequence completed successfully", { agentName, artifactId: artifactId || null });

