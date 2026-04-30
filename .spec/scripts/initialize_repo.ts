#!/usr/bin/env node
import * as fs from "node:fs";
import * as path from "node:path";
import { spawnSync } from "node:child_process";

function log(msg: string): void {
  console.log(`[initialize-repo] ${msg}`);
}

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

function run(cmd: string[], cwd: string): { code: number; out: string } {
  const r = spawnSync(cmd[0], cmd.slice(1), { cwd, encoding: "utf-8" });
  return { code: r.status ?? 1, out: `${r.stdout ?? ""}${r.stderr ?? ""}`.trim() };
}

const scriptDir = __dirname;
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
  console.error("[spec] Warning: Git not found; skipped repository initialization");
  process.exit(0);
}

log("Git executable found");
if (run(["git", "rev-parse", "--is-inside-work-tree"], repoRoot).code === 0) {
  log("Repository already initialized; exiting early");
  console.error("[spec] Git repository already initialized; skipping");
  process.exit(0);
}

const init = run(["git", "init", "-q"], repoRoot);
if (init.code !== 0) {
  const out = init.out;
  console.error(`[spec] Error: git init failed: ${out}`);
  process.exit(1);
}
log("git init completed successfully");

const add = run(["git", "add", "."], repoRoot);
if (add.code !== 0) {
  console.error(`[spec] Error: git add failed: ${add.out}`);
  process.exit(1);
}
log("git add completed successfully");

const commit = run(["git", "commit", "--allow-empty", "-q", "-m", commitMsg], repoRoot);
if (commit.code !== 0) {
  console.error(`[spec] Error: git commit failed: ${commit.out}`);
  process.exit(1);
}

log("git commit completed successfully");
log("Repository initialization flow completed");
console.log("[OK] Git repository initialized");

