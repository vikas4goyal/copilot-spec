#!/usr/bin/env node
import * as fs from "node:fs";
import * as path from "node:path";
import { spawnSync } from "node:child_process";

function run(cmd: string[], cwd: string): { code: number; out: string } {
  const r = spawnSync(cmd[0], cmd.slice(1), { cwd, encoding: "utf-8" });
  return { code: r.status ?? 1, out: `${r.stdout ?? ""}${r.stderr ?? ""}`.trim() };
}

const stayOnBranch = process.argv.includes("--stay-on-branch");
const scriptDir = __dirname;
const repoRoot = path.resolve(scriptDir, "..", "..", "..");
const sessionFile = path.join(repoRoot, ".spec", "session.json");

if (!fs.existsSync(sessionFile)) {
  console.error("[release] No active session found. Nothing to release.");
  process.exit(0);
}

const session = JSON.parse(fs.readFileSync(sessionFile, "utf-8")) as {
  branch_name?: string;
  feature?: { branch_name?: string };
  git?: { base_branch?: string };
};

const branchName = session.branch_name ?? session.feature?.branch_name;
const baseBranch = session.git?.base_branch;

if (!branchName) {
  console.error("[release] Could not determine branch_name from session.json");
  process.exit(1);
}

let hasGit = false;
if (!spawnSync("git", ["--version"], { stdio: "ignore" }).error) {
  hasGit = run(["git", "-C", repoRoot, "rev-parse", "--is-inside-work-tree"], repoRoot).code === 0;
}

if (hasGit) {
  const remote = run(["git", "-C", repoRoot, "config", "--get", "remote.origin.url"], repoRoot);
  if (remote.code === 0 && remote.out.trim()) {
    console.log(`[release] Pushing branch: ${branchName}`);
    const push = run(["git", "-C", repoRoot, "push", "origin", branchName, "--set-upstream"], repoRoot);
    if (push.code !== 0) {
      console.error(`[release] Push failed; continuing with archive. (${push.out})`);
    }
  } else {
    console.log("[release] No remote 'origin' found — skipping push. Branch is available locally only.");
  }
} else {
  console.log("[release] Git not available — skipping push.");
}

const archive = spawnSync("npx", ["tsx", path.join(scriptDir, "manage_session.ts"), "--action", "archive"], {
  cwd: scriptDir,
  stdio: "inherit",
});
if ((archive.status ?? 1) !== 0) {
  console.error("[release] Warning: archive step returned non-zero.");
}

if (!stayOnBranch && baseBranch && baseBranch !== branchName && hasGit) {
  const sw = run(["git", "-C", repoRoot, "checkout", baseBranch], repoRoot);
  if (sw.code === 0) console.log(`[release] Switched to base branch: ${baseBranch}`);
}

console.log(`[release] Done. Branch: ${branchName}  Base: ${baseBranch ?? "<none>"}`);

