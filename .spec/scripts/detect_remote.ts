#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { createLogger } from "./common";

const { info: logInfo } = createLogger("detect-remote");
const specifyLogger = createLogger("specify");

/**
 * Terminates with a non-error "no remote" outcome.
 */
function exitWithoutRemote(reason: string, useJson: boolean): never {
  logInfo("Remote detection ended without a remote", { reason, useJson });
  if (useJson) {
    console.log(JSON.stringify({ has_remote: false, is_github: false, reason }));
  } else {
    specifyLogger.info(reason);
  }
  process.exit(0);
}

/**
 * Parses known GitHub HTTPS/SSH origin URL formats.
 */
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
logInfo("Starting remote detection", { useJson });

if (spawnSync("git", ["--version"], { stdio: "ignore" }).error) {
  exitWithoutRemote("Git not found; cannot determine remote URL", useJson);
}

const inWorkTreeResult = spawnSync("git", ["rev-parse", "--is-inside-work-tree"], { encoding: "utf-8" });
if (inWorkTreeResult.status !== 0) exitWithoutRemote("Not inside a Git repository; cannot determine remote URL", useJson);

const remoteUrlResult = spawnSync("git", ["config", "--get", "remote.origin.url"], { encoding: "utf-8" });
const remoteUrl = (remoteUrlResult.stdout ?? "").trim();
if (!remoteUrl) exitWithoutRemote("No remote.origin configured", useJson);
logInfo("Found remote origin URL", { remoteUrl });

const { isGithub, owner, repo } = parseGithubRemote(remoteUrl);
logInfo("Parsed remote metadata", { isGithub, owner: owner || null, repo: repo || null });

if (useJson) {
  console.log(JSON.stringify({ has_remote: true, is_github: isGithub, remote_url: remoteUrl, owner, repo }));
} else {
  console.log(`Remote URL: ${remoteUrl}`);
  if (isGithub) console.log(`GitHub repository: ${owner}/${repo}`);
}

