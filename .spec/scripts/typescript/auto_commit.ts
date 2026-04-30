#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { getRepoRoot } from "./common";

function runCommand(command: string[], cwd: string): { code: number; out: string } {
  const commandResult = spawnSync(command[0], command.slice(1), { cwd, encoding: "utf-8" });
  return { code: commandResult.status ?? 1, out: `${commandResult.stdout ?? ""}${commandResult.stderr ?? ""}`.trim() };
}

function getCliArg(longName: string, shortName?: string): string {
  const cliArgs = process.argv.slice(2);
  const argIndex = cliArgs.findIndex((argValue) => argValue === longName || (shortName ? argValue === shortName : false));
  if (argIndex >= 0 && argIndex + 1 < cliArgs.length) return cliArgs[argIndex + 1];
  return "";
}

const commitMessage = getCliArg("--commit-message", "-m");
if (!commitMessage) {
  console.error("Missing required --commit-message");
  process.exit(1);
}

const repoRoot = getRepoRoot();

if (runCommand(["git", "--version"], repoRoot).code !== 0) {
  console.error("[auto-commit] Git not found; skipping commit.");
  process.exit(0);
}

if (runCommand(["git", "rev-parse", "--is-inside-work-tree"], repoRoot).code !== 0) {
  console.error("[auto-commit] Not a Git repository; skipping commit.");
  process.exit(0);
}

const workingTreeDiffStatus = runCommand(["git", "diff", "--quiet", "HEAD"], repoRoot).code;
const stagedDiffStatus = runCommand(["git", "diff", "--cached", "--quiet"], repoRoot).code;
const untrackedFiles = runCommand(["git", "ls-files", "--others", "--exclude-standard"], repoRoot).out;

// Skip commit when there are no staged/unstaged/untracked changes.
if (workingTreeDiffStatus === 0 && stagedDiffStatus === 0 && !untrackedFiles.trim()) {
  console.log("[auto-commit] Nothing to commit.");
  process.exit(0);
}

const gitAddResult = runCommand(["git", "add", "."], repoRoot);
if (gitAddResult.code !== 0) {
  console.error(`[auto-commit] git add failed: ${gitAddResult.out}`);
  process.exit(1);
}

const gitCommitResult = runCommand(["git", "commit", "-m", commitMessage], repoRoot);
if (gitCommitResult.code !== 0) {
  console.error(`[auto-commit] git commit failed: ${gitCommitResult.out}`);
  process.exit(1);
}

console.log("[auto-commit] Committed successfully.");

