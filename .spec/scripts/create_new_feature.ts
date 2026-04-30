#!/usr/bin/env node
import * as fs from "node:fs";
import * as path from "node:path";
import { spawnSync } from "node:child_process";
import { getRepoRoot, resolveTemplate, testHasGit } from "./common";

const scriptDir = __dirname;

function runManage(args: string[], capture = false): { code: number; out: string } {
  const commandArgs = ["tsx", path.join(scriptDir, "manage_session.ts"), ...args];
  const result = spawnSync("npx", commandArgs, {
    cwd: scriptDir,
    encoding: "utf-8",
    stdio: capture ? "pipe" : "inherit",
  });
  return { code: result.status ?? 1, out: (result.stdout ?? "").trim() };
}

function log(msg: string): void {
  console.log(`[feature] ${msg}`);
}

function gitRun(args: string[], repoRoot: string, capture = false): { code: number; out: string } {
  const gitResult = spawnSync("git", ["-C", repoRoot, ...args], {
    encoding: "utf-8",
    stdio: capture ? "pipe" : "ignore",
  });
  return { code: gitResult.status ?? 1, out: (gitResult.stdout ?? "").trim() };
}

function today(): string {
  const now = new Date();
  const pad2 = (value: number) => `${value}`.padStart(2, "0");
  return `${now.getFullYear()}${pad2(now.getMonth() + 1)}${pad2(now.getDate())}`;
}

function getUniqueBranchName(base: string, repoRoot: string, hasGit: boolean): string {
  const takenBranchNames = new Set<string>();
  if (hasGit) {
    const localBranches = gitRun(["branch", "--list", `${base}*`], repoRoot, true);
    if (localBranches.code === 0) {
      for (const line of localBranches.out.split("\n").filter(Boolean)) {
        takenBranchNames.add(line.trim().replace(/^\*/, "").trim());
      }
    }

    const remoteBranches = gitRun(["branch", "-r", "--list", `*/${base}*`], repoRoot, true);
    if (remoteBranches.code === 0) {
      for (const line of remoteBranches.out.split("\n").filter(Boolean)) {
        const clean = line.trim();
        takenBranchNames.add(clean.split("/").at(-1) ?? clean);
      }
    }
  }

  // Keep original name if available; otherwise append date/counter suffixes.
  if (!takenBranchNames.has(base)) return base;
  const dateSuffixed = `${base}-${today()}`;
  if (!takenBranchNames.has(dateSuffixed)) return dateSuffixed;

  let counter = 2;
  while (true) {
    const candidate = `${base}-${today()}-${counter}`;
    if (!takenBranchNames.has(candidate)) return candidate;
    counter += 1;
  }
}

function getUniqueFolderName(base: string, specsDir: string): string {
  const prefix = `${today()}-${base}`;
  const takenFolderNames = new Set<string>();

  if (fs.existsSync(specsDir) && fs.statSync(specsDir).isDirectory()) {
    for (const name of fs.readdirSync(specsDir)) {
      const full = path.join(specsDir, name);
      if (fs.statSync(full).isDirectory() && name.startsWith(prefix)) takenFolderNames.add(name);
    }
  }

  if (!takenFolderNames.has(prefix)) return prefix;
  let counter = 2;
  while (true) {
    const candidate = `${prefix}-${counter}`;
    if (!takenFolderNames.has(candidate)) return candidate;
    counter += 1;
  }
}

function writeResult(branch: string, featureDir: string, useJson: boolean): void {
  if (useJson) {
    console.log(JSON.stringify({ BRANCH_NAME: branch, FEATURE_DIR: featureDir, SPEC_FILE: `${featureDir}/spec.md` }));
  } else {
    console.log(`BRANCH_NAME: ${branch}`);
    console.log(`FEATURE_DIR: ${featureDir}`);
    console.log(`SPEC_FILE:   ${featureDir}/spec.md`);
  }
}

function arg(name: string): string {
  const flagIndex = process.argv.indexOf(name);
  return flagIndex >= 0 && flagIndex + 1 < process.argv.length ? process.argv[flagIndex + 1] : "";
}

const name = arg("--name");
const description = arg("--description");
const agentName = arg("--agent-name");
const useJson = process.argv.includes("--json");
const dryRun = process.argv.includes("--dry-run");

const repoRoot = getRepoRoot();
const hasGit = testHasGit(repoRoot);
const specsDir = path.join(repoRoot, ".spec", "specs");

if (!dryRun) fs.mkdirSync(specsDir, { recursive: true });

if (!dryRun) {
  const initArgs = ["--action", "init"];
  if (name) initArgs.push("--name", name);
  if (description) initArgs.push("--description", description);
  const init = runManage(initArgs);
  if (init.code !== 0) process.exit(init.code);
}

let sessionFeatureName = "";
let sessionBranch = "";
let sessionFeatureDir = "";

const multi = runManage(["--action", "get-multi", "--fields", "name,branch_name,feature_dir"], true);
if (multi.code === 0 && multi.out) {
  try {
    const sessionSnapshot = JSON.parse(multi.out) as { name?: string; branch_name?: string; feature_dir?: string };
    sessionFeatureName = sessionSnapshot.name ?? "";
    sessionBranch = sessionSnapshot.branch_name ?? "";
    sessionFeatureDir = sessionSnapshot.feature_dir ?? "";
  } catch {
    // Ignore malformed output.
  }
}

if (!sessionFeatureName) sessionFeatureName = name;
if (!sessionFeatureName) {
  const msg = dryRun
    ? "ERROR: No active session and --name not provided. Pass --name <slug> for dry-run."
    : "ERROR: Feature name is not set. Pass --name <slug> to provide one.";
  log(msg);
  process.exit(1);
}

log(`Session name: ${sessionFeatureName}`);

let currentBranch = "";
if (hasGit) {
  const cb = gitRun(["rev-parse", "--abbrev-ref", "HEAD"], repoRoot, true);
  if (cb.code === 0) currentBranch = cb.out;
}
log(`Current git branch: ${currentBranch || "none"}`);

// If session already points to the current branch + directory, this call is idempotent.
if (sessionBranch && sessionFeatureDir) {
  const existingDir = path.isAbsolute(sessionFeatureDir) ? sessionFeatureDir : path.join(repoRoot, sessionFeatureDir);
  if (currentBranch === sessionBranch && fs.existsSync(existingDir) && fs.statSync(existingDir).isDirectory()) {
    log(`Already on branch '${sessionBranch}' with feature dir '${sessionFeatureDir}' — nothing to do`);
    writeResult(sessionBranch, existingDir, useJson);
    process.exit(0);
  }
  if (currentBranch && currentBranch !== sessionBranch) {
    log(`ERROR: Session expects branch '${sessionBranch}' but current git branch is '${currentBranch}'.`);
    log(`       Switch to the correct branch  ->  git checkout ${sessionBranch}`);
    log("       Or release the current feature first  ->  /spec.release");
    process.exit(1);
  }
}

if (hasGit && !dryRun) {
  spawnSync("git", ["-C", repoRoot, "fetch", "--all", "--prune"], { stdio: "ignore" });
}

const branchName = getUniqueBranchName(sessionFeatureName, repoRoot, hasGit);
const folderName = getUniqueFolderName(sessionFeatureName, specsDir);
if (branchName !== sessionFeatureName) log(`Branch '${sessionFeatureName}' taken — using '${branchName}'`);
log(`Folder name: ${folderName}`);

const featureDir = path.join(specsDir, folderName);
const specFile = path.join(featureDir, "spec.md");

if (!dryRun) {
  if (hasGit) {
    log(`Creating git branch '${branchName}'...`);
    const createBranchResult = gitRun(["checkout", "-q", "-b", branchName], repoRoot);
    if (createBranchResult.code !== 0) {
      const switchBranchResult = gitRun(["checkout", "-q", branchName], repoRoot);
      if (switchBranchResult.code !== 0) {
        log(`ERROR: Failed to create or checkout '${branchName}'`);
        process.exit(1);
      }
      log(`Switched to existing branch '${branchName}'`);
    } else {
      log(`Branch '${branchName}' created and checked out`);
    }
  } else {
    log("No git repo — skipping branch creation");
  }

  fs.mkdirSync(featureDir, { recursive: true });

  if (!fs.existsSync(specFile)) {
    const tmpl = resolveTemplate("spec-template", repoRoot);
    if (tmpl && fs.existsSync(tmpl)) {
      fs.copyFileSync(tmpl, specFile);
      log(`Spec file created from template: ${specFile}`);
    } else {
      fs.closeSync(fs.openSync(specFile, "a"));
      log(`Spec file created (empty): ${specFile}`);
    }
  } else {
    log(`Spec file already exists: ${specFile}`);
  }

  const patch = JSON.stringify({ branch_name: branchName, feature_dir: `.spec/specs/${folderName}` });
  const upd = runManage(["--action", "update-multi", "--json-patch", patch]);
  if (upd.code !== 0) process.exit(upd.code);

  if (agentName) {
    const add = runManage(["--action", "add-agent", "--agent-name", agentName]);
    if (add.code !== 0) process.exit(add.code);
  }

  log(`Session updated: branch_name=${branchName}  feature_dir=.spec/specs/${folderName}`);
} else {
  log(`[dry-run] branch_name  -> ${branchName}`);
  log(`[dry-run] feature_dir  -> .spec/specs/${folderName}`);
  log("[dry-run] Would create session.json (if needed), branch and spec dir");
}

writeResult(branchName, featureDir, useJson);

