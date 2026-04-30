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

// Ensure the session exists, track this agent run, then verify artifact deps when provided.
const initArgs = ["--action", "init", ...(agentName ? ["--agent-name", agentName] : [])];
if (runManageSession(initArgs) !== 0) process.exit(1);
if (runManageSession(["--action", "add-agent", "--agent-name", agentName]) !== 0) process.exit(1);
if (artifactId && runManageSession(["--action", "check-deps", "--artifact-id", artifactId]) !== 0) process.exit(1);

