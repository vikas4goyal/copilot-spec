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

const artifactId = getCliArg("--artifact-id");
const summary = getCliArg("--summary");
const handoff = getCliArg("--handoff");

if (!artifactId) {
  console.error("Missing required --artifact-id");
  process.exit(1);
}

// Persist optional result metadata before marking the artifact complete.
if (summary) {
  runManageSession([
    "--action",
    "update-artifact",
    "--artifact-id",
    artifactId,
    "--artifact-field",
    "summary",
    "--artifact-value",
    summary,
  ]);
}

if (handoff) {
  runManageSession([
    "--action",
    "update-artifact",
    "--artifact-id",
    artifactId,
    "--artifact-field",
    "handoff",
    "--artifact-value",
    handoff,
  ]);
}

const completionResult = runManageSession(["--action", "complete-artifact", "--artifact-id", artifactId]);
if (completionResult !== 0) process.exit(completionResult);

