#!/usr/bin/env node
import * as fs from "node:fs";
import * as path from "node:path";
import { spawnSync } from "node:child_process";
import { createLogger } from "./common";

const { info: logInfo } = createLogger("initialize-repo:debug");
const { log, warn: logWarn, error: logError } = createLogger("initialize-repo");
const specLogger = createLogger("spec");

/**
 * Walks upward to find a directory containing a project marker.
 */
function findProjectRoot(startDir: string): string | null {
  log(`Searching for project root from: ${startDir}`);
  let current = path.resolve(startDir);
  while (true) {
    log(`Inspecting directory for project markers: ${current}`);
    for (const marker of [".spec", ".git"]) {
      if (fs.existsSync(path.join(current, marker))) {
        log(`Found project marker '${marker}' in: ${current}`);
        return current;
      }
    }
    const parent = path.dirname(current);
    if (parent === current) {
      log("Reached filesystem root without finding a project marker");
      return null;
    }
    current = parent;
  }
}

/**
 * Executes a git command and captures stdout/stderr.
 */
function run(cmd: string[], cwd: string): { code: number; out: string } {
  const r = spawnSync(cmd[0], cmd.slice(1), { cwd, encoding: "utf-8" });
  return { code: r.status ?? 1, out: `${r.stdout ?? ""}${r.stderr ?? ""}`.trim() };
}

const scriptDir = __dirname;
logInfo("Starting repository initialization", { scriptDir, cwd: process.cwd() });
const discoveredRoot = findProjectRoot(scriptDir);
const repoRoot = discoveredRoot ?? process.cwd();
if (!discoveredRoot) {
  log("Project root not found from script path; falling back to current working directory");
} else {
  log(`Using discovered project root: ${repoRoot}`);
}

log(`Changed working directory to: ${repoRoot}`);
const commitMsg = "[Spec] Initial commit";
log(`Final commit message: ${commitMsg}`);

if (spawnSync("git", ["--version"], { stdio: "ignore" }).error) {
  log("Git executable not found; exiting without initializing repository");
  specLogger.warn("Git not found; skipped repository initialization");
  process.exit(0);
}

log("Git executable found");
logInfo("Checking whether repository already exists", { repoRoot });
if (run(["git", "rev-parse", "--is-inside-work-tree"], repoRoot).code === 0) {
  log("Repository already initialized; exiting early");
  specLogger.info("Git repository already initialized; skipping");
  process.exit(0);
}

const init = run(["git", "init", "-q"], repoRoot);
logInfo("Ran git init", { code: init.code });
if (init.code !== 0) {
  const out = init.out;
  specLogger.error(`git init failed: ${out}`);
  process.exit(1);
}
log("git init completed successfully");

const add = run(["git", "add", "."], repoRoot);
logInfo("Ran git add", { code: add.code });
if (add.code !== 0) {
  specLogger.error(`git add failed: ${add.out}`);
  process.exit(1);
}
log("git add completed successfully");

const commit = run(["git", "commit", "--allow-empty", "-q", "-m", commitMsg], repoRoot);
logInfo("Ran git commit", { code: commit.code, message: commitMsg });
if (commit.code !== 0) {
  specLogger.error(`git commit failed: ${commit.out}`);
  process.exit(1);
}

log("git commit completed successfully");
log("Repository initialization flow completed");
console.log("[OK] Git repository initialized");

