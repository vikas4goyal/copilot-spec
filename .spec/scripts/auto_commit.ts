#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { getRepoRoot } from "./common";

/**
 * Writes diagnostic output to stderr so command/status stdout stays script-friendly.
 */
function logInfo(message: string, details?: unknown): void {
  if (details === undefined) {
    console.error(`[auto-commit] ${message}`);
    return;
  }
  console.error(`[auto-commit] ${message}`, details);
}

/**
 * Runs a command synchronously and returns both exit code and captured output.
 */
function runCommand(command: string[], cwd: string): { code: number; out: string } {
  const commandResult = spawnSync(command[0], command.slice(1), { cwd, encoding: "utf-8" });
  return { code: commandResult.status ?? 1, out: `${commandResult.stdout ?? ""}${commandResult.stderr ?? ""}`.trim() };
}

/**
 * Reads a long/short CLI flag value.
 */
function getCliArg(longName: string, shortName?: string): string {
  const cliArgs = process.argv.slice(2);
  const argIndex = cliArgs.findIndex((argValue) => argValue === longName || (shortName ? argValue === shortName : false));
  if (argIndex >= 0 && argIndex + 1 < cliArgs.length) return cliArgs[argIndex + 1];
  return "";
}

const commitMessage = getCliArg("--commit-message", "-m");
logInfo("Starting auto-commit", {
  commitMessageProvided: Boolean(commitMessage),
  argv: process.argv.slice(2),
});

if (!commitMessage) {
  console.error("Missing required --commit-message");
  process.exit(1);
}

const repoRoot = getRepoRoot();
logInfo("Resolved repository root", { repoRoot });

if (runCommand(["git", "--version"], repoRoot).code !== 0) {
  logInfo("Git executable not available; commit skipped");
  console.error("[auto-commit] Git not found; skipping commit.");
  process.exit(0);
}

if (runCommand(["git", "rev-parse", "--is-inside-work-tree"], repoRoot).code !== 0) {
  logInfo("Current root is not a git worktree; commit skipped", { repoRoot });
  console.error("[auto-commit] Not a Git repository; skipping commit.");
  process.exit(0);
}

const workingTreeDiffStatus = runCommand(["git", "diff", "--quiet", "HEAD"], repoRoot).code;
const stagedDiffStatus = runCommand(["git", "diff", "--cached", "--quiet"], repoRoot).code;
const untrackedFiles = runCommand(["git", "ls-files", "--others", "--exclude-standard"], repoRoot).out;

logInfo("Collected working tree change state", {
  workingTreeDiffStatus,
  stagedDiffStatus,
  untrackedCount: untrackedFiles ? untrackedFiles.split("\n").filter(Boolean).length : 0,
});

// Skip commit when there are no staged/unstaged/untracked changes.
if (workingTreeDiffStatus === 0 && stagedDiffStatus === 0 && !untrackedFiles.trim()) {
  logInfo("No changes detected; nothing to commit");
  console.log("[auto-commit] Nothing to commit.");
  process.exit(0);
}

logInfo("Staging repository changes", { repoRoot });
const gitAddResult = runCommand(["git", "add", "."], repoRoot);
if (gitAddResult.code !== 0) {
  console.error(`[auto-commit] git add failed: ${gitAddResult.out}`);
  process.exit(1);
}

logInfo("Creating commit", { message: commitMessage });
const gitCommitResult = runCommand(["git", "commit", "-m", commitMessage], repoRoot);
if (gitCommitResult.code !== 0) {
  console.error(`[auto-commit] git commit failed: ${gitCommitResult.out}`);
  process.exit(1);
}

logInfo("Commit completed successfully");
console.log("[auto-commit] Committed successfully.");

