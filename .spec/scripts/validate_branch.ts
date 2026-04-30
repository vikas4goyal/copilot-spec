#!/usr/bin/env node
import * as fs from "node:fs";
import * as path from "node:path";
import { spawnSync } from "node:child_process";

function noBranch(reason: string, json: boolean): never {
  if (json) {
    console.log(JSON.stringify({ valid: false, reason }));
  } else {
    console.error(`[specify] ${reason}`);
  }
  process.exit(0);
}

const useJson = process.argv.includes("--json");
let branch: string | null = null;
let gitAvailable = true;

if (spawnSync("git", ["--version"], { stdio: "ignore" }).error) gitAvailable = false;

if (!gitAvailable) {
  branch = (process.env.SPECIFY_FEATURE ?? "").trim() || null;
  if (!branch) noBranch("Git not found and SPECIFY_FEATURE not set; skipped branch validation", useJson);
} else {
  const inside = spawnSync("git", ["rev-parse", "--is-inside-work-tree"], { encoding: "utf-8" });
  if (inside.status !== 0) {
    branch = (process.env.SPECIFY_FEATURE ?? "").trim() || null;
    if (!branch) noBranch("Not inside a Git repository; skipped branch validation", useJson);
  } else {
    const b = spawnSync("git", ["rev-parse", "--abbrev-ref", "HEAD"], { encoding: "utf-8" });
    branch = (b.stdout ?? "").trim() || null;
  }
}

if (!branch) noBranch("Could not determine branch name", useJson);

const datePrefixRe = /^[0-9]{8}-/;

let prefix = "";
if (datePrefixRe.test(branch)) {
  prefix = (branch.match(/^[0-9]{8}/) ?? [""])[0];
} else {
  if (useJson) {
    console.log(JSON.stringify({ valid: false, branch, reason: "not-a-feature-branch" }));
  } else {
    console.log(`[FAIL] Not on a feature branch. Current branch: ${branch}`);
    console.log("Feature branches must be named like: 20260430-feature-name");
  }
  process.exit(1);
}

const _gitRoot = spawnSync("git", ["rev-parse", "--show-toplevel"], { encoding: "utf-8" });
const repoRoot = (_gitRoot.status === 0 ? (_gitRoot.stdout ?? "").trim() : null) ?? path.resolve(__dirname, "..", "..");
const specsDir = path.join(repoRoot, ".spec", "specs");
let specDir = "";
if (fs.existsSync(specsDir) && fs.statSync(specsDir).isDirectory()) {
  const match = fs.readdirSync(specsDir).find((d) => {
    const full = path.join(specsDir, d);
    return fs.statSync(full).isDirectory() && d.startsWith(`${prefix}-`);
  });
  if (match) specDir = path.join(specsDir, match);
}

if (useJson) {
  console.log(JSON.stringify({ valid: true, branch, prefix, spec_dir: specDir }));
} else {
  console.log(`[OK] On feature branch: ${branch}`);
  if (specDir) console.log(`[OK] Spec directory found: ${specDir}`);
  else console.log(`[WARN] No spec directory found for prefix ${prefix}`);
}

