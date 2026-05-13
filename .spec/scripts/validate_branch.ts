#!/usr/bin/env node
import * as fs from "node:fs";
import * as path from "node:path";
import { spawnSync } from "node:child_process";
import { createLogger } from "./common";

const { info: logInfo } = createLogger("validate-branch");

/**
 * Returns a successful skipped-validation response and exits.
 */
function skipValidation(reason: string, json: boolean): never {
  logInfo("Skipping branch validation", { reason, json });
  if (json) {
    console.log(JSON.stringify({ valid: true, skipped: true, reason }));
  } else {
    console.log(`[specify] ${reason}`);
  }
  process.exit(0);
}

const useJson = process.argv.includes("--json");
logInfo("Starting branch validation", { useJson });

// --- Step 1: Resolve repo root and check for session.json ---
const _gitRootCheck = spawnSync("git", ["rev-parse", "--show-toplevel"], { encoding: "utf-8" });
const repoRoot =
  (_gitRootCheck.status === 0 ? (_gitRootCheck.stdout ?? "").trim() : null) ??
  path.resolve(__dirname, "..", "..");
logInfo("Resolved repository root", { repoRoot });

const sessionFile = path.join(repoRoot, ".spec", "session.json");

if (!fs.existsSync(sessionFile)) {
  skipValidation("No active session (session.json not found); skipped branch validation", useJson);
}

// --- Step 2: Read expected branch from session.json ---
let sessionBranch: string | null = null;
try {
  const session = JSON.parse(fs.readFileSync(sessionFile, "utf-8")) as Record<string, unknown>;
  sessionBranch = (session.branch_name as string | undefined | null) ?? null;
} catch {
  skipValidation("Could not parse session.json; skipped branch validation", useJson);
}

if (!sessionBranch) {
  skipValidation("session.json exists but branch_name is not set yet; skipped branch validation", useJson);
}

logInfo("Loaded expected session branch", { sessionBranch });

// --- Step 3: Resolve current Git branch ---
let branch: string | null = null;
let gitAvailable = true;

if (spawnSync("git", ["--version"], { stdio: "ignore" }).error) gitAvailable = false;
logInfo("Git availability", { gitAvailable });

if (!gitAvailable) {
  branch = (process.env.SPECIFY_FEATURE ?? "").trim() || null;
  if (!branch) skipValidation("Git not found and SPECIFY_FEATURE not set; skipped branch validation", useJson);
} else {
  const inside = spawnSync("git", ["rev-parse", "--is-inside-work-tree"], { encoding: "utf-8" });
  if (inside.status !== 0) {
    branch = (process.env.SPECIFY_FEATURE ?? "").trim() || null;
    if (!branch) skipValidation("Not inside a Git repository; skipped branch validation", useJson);
  } else {
    const b = spawnSync("git", ["rev-parse", "--abbrev-ref", "HEAD"], { encoding: "utf-8" });
    branch = (b.stdout ?? "").trim() || null;
  }
}

if (!branch) skipValidation("Could not determine current branch name; skipped branch validation", useJson);

logInfo("Resolved current branch", { branch });

// --- Step 4: Compare current branch against session branch_name ---
if (branch !== sessionBranch) {
  logInfo("Branch mismatch detected", { branch, expected: sessionBranch });
  if (useJson) {
    console.log(
      JSON.stringify({
        valid: false,
        branch,
        expected: sessionBranch,
        reason: "branch-mismatch",
      })
    );
  } else {
    console.log(`[FAIL] Current branch '${branch}' does not match the active session branch '${sessionBranch}'.`);
    console.log(`Switch to the correct branch: git checkout ${sessionBranch}`);
  }
  process.exit(1);
}

logInfo("Branch validation passed", { branch, expected: sessionBranch });

// --- Step 5: All good — report success ---
const datePrefixRe = /^[0-9]{8}-/;
const prefix = datePrefixRe.test(branch) ? (branch.match(/^[0-9]{8}/) ?? [""])[0] : "";

const specsDir = path.join(repoRoot, ".spec", "specs");
let specDir = "";
if (fs.existsSync(specsDir) && fs.statSync(specsDir).isDirectory()) {
  const match = fs.readdirSync(specsDir).find((d) => {
    const full = path.join(specsDir, d);
    return fs.statSync(full).isDirectory() && (prefix ? d.startsWith(`${prefix}-`) : false);
  });
  if (match) specDir = path.join(specsDir, match);
}

if (useJson) {
  console.log(JSON.stringify({ valid: true, branch, prefix, spec_dir: specDir }));
} else {
  console.log(`[OK] On feature branch: ${branch}`);
  if (specDir) console.log(`[OK] Spec directory found: ${specDir}`);
  else if (prefix) console.log(`[WARN] No spec directory found for prefix ${prefix}`);
}

