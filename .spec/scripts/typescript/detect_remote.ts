#!/usr/bin/env node
import { spawnSync } from "node:child_process";

function exitWithoutRemote(reason: string, useJson: boolean): never {
  if (useJson) {
    console.log(JSON.stringify({ has_remote: false, is_github: false, reason }));
  } else {
    console.error(`[specify] ${reason}`);
  }
  process.exit(0);
}

function parseGithubRemote(remoteUrl: string): { isGithub: boolean; owner: string; repo: string } {
  const httpsMatch = remoteUrl.match(/^https:\/\/github\.com\/([^/]+)\/([^/]+?)(?:\.git)?$/);
  if (httpsMatch) {
    return { isGithub: true, owner: httpsMatch[1], repo: httpsMatch[2] };
  }

  const sshMatch = remoteUrl.match(/^git@github\.com:([^/]+)\/([^/]+?)(?:\.git)?$/);
  if (sshMatch) {
    return { isGithub: true, owner: sshMatch[1], repo: sshMatch[2] };
  }

  return { isGithub: false, owner: "", repo: "" };
}

const useJson = process.argv.includes("--json");

if (spawnSync("git", ["--version"], { stdio: "ignore" }).error) {
  exitWithoutRemote("Git not found; cannot determine remote URL", useJson);
}

const inWorkTreeResult = spawnSync("git", ["rev-parse", "--is-inside-work-tree"], { encoding: "utf-8" });
if (inWorkTreeResult.status !== 0) exitWithoutRemote("Not inside a Git repository; cannot determine remote URL", useJson);

const remoteUrlResult = spawnSync("git", ["config", "--get", "remote.origin.url"], { encoding: "utf-8" });
const remoteUrl = (remoteUrlResult.stdout ?? "").trim();
if (!remoteUrl) exitWithoutRemote("No remote.origin configured", useJson);

const { isGithub, owner, repo } = parseGithubRemote(remoteUrl);

if (useJson) {
  console.log(JSON.stringify({ has_remote: true, is_github: isGithub, remote_url: remoteUrl, owner, repo }));
} else {
  console.log(`Remote URL: ${remoteUrl}`);
  if (isGithub) console.log(`GitHub repository: ${owner}/${repo}`);
}

