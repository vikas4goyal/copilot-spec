#!/usr/bin/env node
import * as path from "node:path";
import { spawnSync } from "node:child_process";

export function testHasGit(repoRoot?: string): boolean {
  const version = spawnSync("git", ["--version"], { stdio: "ignore" });
  if (version.error) return false;

  const root = repoRoot ?? process.cwd();
  if (!require("node:fs").existsSync(path.join(root, ".git"))) return false;
  const inside = spawnSync("git", ["-C", root, "rev-parse", "--is-inside-work-tree"], { stdio: "ignore" });
  return inside.status === 0;
}

export function getSpecKitEffectiveBranchName(branch: string): string {
  const m = branch.match(/^([^/]+)\/([^/]+)$/);
  return m ? m[2] : branch;
}

export function testFeatureBranch(branch: string, hasGit = true): boolean {
  if (!hasGit) {
    console.error("[specify] Warning: Git repository not detected; skipped branch validation");
    return true;
  }

  const raw = branch;
  const effective = getSpecKitEffectiveBranchName(branch);
  const malformed = /^[0-9]{7}-[0-9]{6}-/.test(effective) || /^(?:\d{7}|\d{8})-\d{6}$/.test(effective);
  const isSequential = /^[0-9]{3,}-/.test(effective) && !malformed;
  const isTimestamp = /^\d{8}-\d{6}-/.test(effective);

  if (!isSequential && !isTimestamp) {
    console.error(`ERROR: Not on a feature branch. Current branch: ${raw}`);
    console.error(
      "Feature branches should be named like: 001-feature-name, 1234-feature-name, or 20260319-143022-feature-name",
    );
    return false;
  }
  return true;
}

