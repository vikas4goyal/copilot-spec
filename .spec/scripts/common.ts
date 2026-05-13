#!/usr/bin/env node
import * as fs from "node:fs";
import * as path from "node:path";
import { spawnSync } from "node:child_process";

export type FeaturePaths = {
  REPO_ROOT: string;
  CURRENT_BRANCH: string;
  HAS_GIT: boolean;
  FEATURE_DIR: string;
  FEATURE_SPEC: string;
  IMPL_PLAN: string;
  TASKS: string;
  RESEARCH: string;
  DATA_MODEL: string;
  QUICKSTART: string;
  CONTRACTS_DIR: string;
};

/**
 * Walks upward from the start directory to find a project root containing .specs.
 */
export function findSpecifyRoot(startDir?: string): string | null {
  let currentDir = path.resolve(startDir ?? process.cwd());
  while (true) {
    const markerDir = path.join(currentDir, ".specs");
    if (fs.existsSync(markerDir) && fs.statSync(markerDir).isDirectory()) {
      return currentDir;
    }
    const parentDir = path.dirname(currentDir);
    if (parentDir === currentDir) return null;
    currentDir = parentDir;
  }
}

/**
 * Resolves repository root using .specs marker first, then git, then script-relative fallback.
 */
export function getRepoRoot(): string {
  const specsMarkerRoot = findSpecifyRoot();
  if (specsMarkerRoot) return specsMarkerRoot;

  const git = spawnSync("git", ["rev-parse", "--show-toplevel"], { encoding: "utf-8" });
  if (git.status === 0) {
    return (git.stdout ?? "").trim();
  }

  return path.resolve(__dirname, "..", "..", "..");
}

/**
 * Returns true when the git executable is available on PATH.
 */
export function hasGitCommand(): boolean {
  try {
    const result = spawnSync("git", ["--version"], { stdio: "ignore" });
    return result.error == null;
  } catch {
    return false;
  }
}

/**
 * Returns true when the provided root is a git work tree.
 */
export function testHasGit(repoRoot?: string): boolean {
  if (!hasGitCommand()) return false;
  const root = repoRoot ?? getRepoRoot();
  if (!fs.existsSync(path.join(root, ".git"))) return false;
  const result = spawnSync("git", ["-C", root, "rev-parse", "--is-inside-work-tree"], { stdio: "ignore" });
  return result.status === 0;
}

/**
 * Resolves the active feature branch name from env, git, or latest specs directory.
 */
export function getCurrentBranch(repoRoot?: string): string {
  // Priority: env override -> git branch -> latest specs folder -> main
  const envBranch = (process.env.SPECIFY_FEATURE ?? "").trim();
  if (envBranch) return envBranch;

  const root = repoRoot ?? getRepoRoot();
  if (testHasGit(root)) {
    const result = spawnSync("git", ["-C", root, "rev-parse", "--abbrev-ref", "HEAD"], { encoding: "utf-8" });
    if (result.status === 0) return (result.stdout ?? "").trim();
  }

  const specsDir = path.join(root, ".spec", "specs");
  if (fs.existsSync(specsDir) && fs.statSync(specsDir).isDirectory()) {
    let latestFeatureDirName = "";
    let latestDatePrefix = "";

    for (const entryName of fs.readdirSync(specsDir)) {
      const entryPath = path.join(specsDir, entryName);
      if (!fs.statSync(entryPath).isDirectory()) continue;
      const dateMatch = entryName.match(/^(\d{8})-/);
      if (dateMatch) {
        if (dateMatch[1] > latestDatePrefix) {
          latestDatePrefix = dateMatch[1];
          latestFeatureDirName = entryName;
        }
      }
    }

    if (latestFeatureDirName) return latestFeatureDirName;
  }

  return "main";
}

/**
 * Validates that a branch follows expected date-prefixed feature naming.
 */
const _specifyLogger = createLogger("specify");

export function testFeatureBranch(branch: string, hasGit = true): boolean {
  if (!hasGit) {
    _specifyLogger.warn("Git repository not detected; skipped branch validation");
    return true;
  }

  const isDatePrefixed = /^[0-9]{8}-/.test(branch);

  if (!isDatePrefixed) {
    _specifyLogger.error(`Not on a feature branch. Current branch: ${branch}`);
    _specifyLogger.error("Feature branches should be named like: 20260430-feature-name");
    return false;
  }
  return true;
}

/**
 * Returns the feature directory path for a branch.
 */
export function getFeatureDir(repoRoot: string, branch: string): string {
  return path.join(repoRoot, "specs", branch);
}

/**
 * Builds the current feature path bundle from environment and repository state.
 */
export function getFeaturePathsEnv(): FeaturePaths {
  const repoRoot = getRepoRoot();
  const currentBranch = getCurrentBranch(repoRoot);
  const hasGit = testHasGit(repoRoot);

  let featureDir: string | null = null;
  const featureJsonPath = path.join(repoRoot, ".specs", "feature.json");

  // Resolve feature dir in order: env -> .spec/specs/feature.json -> .spec/specs/<branch>
  const envFeatureDir = (process.env.SPECIFY_FEATURE_DIRECTORY ?? "").trim();
  if (envFeatureDir) {
    featureDir = path.isAbsolute(envFeatureDir) ? envFeatureDir : path.join(repoRoot, envFeatureDir);
  } else if (fs.existsSync(featureJsonPath)) {
    try {
      const data = JSON.parse(fs.readFileSync(featureJsonPath, "utf-8")) as { feature_directory?: string };
      const featureDirectoryFromConfig = data.feature_directory ?? "";
      if (featureDirectoryFromConfig) {
        featureDir = path.isAbsolute(featureDirectoryFromConfig)
          ? featureDirectoryFromConfig
          : path.join(repoRoot, featureDirectoryFromConfig);
      }
    } catch {
      // Ignore invalid feature.json and fall back.
    }
  }

  if (!featureDir) featureDir = getFeatureDir(repoRoot, currentBranch);

  return {
    REPO_ROOT: repoRoot,
    CURRENT_BRANCH: currentBranch,
    HAS_GIT: hasGit,
    FEATURE_DIR: featureDir,
    FEATURE_SPEC: path.join(featureDir, "spec.md"),
    IMPL_PLAN: path.join(featureDir, "plan.md"),
    TASKS: path.join(featureDir, "tasks.md"),
    RESEARCH: path.join(featureDir, "research.md"),
    DATA_MODEL: path.join(featureDir, "data-model.md"),
    QUICKSTART: path.join(featureDir, "quickstart.md"),
    CONTRACTS_DIR: path.join(featureDir, "contracts"),
  };
}

/**
 * Checks whether a file exists and prints a simple status marker.
 */
export function testFileExists(filePath: string, description: string): boolean {
  const ok = fs.existsSync(filePath) && fs.statSync(filePath).isFile();
  console.log(`  [${ok ? "OK" : "FAIL"}] ${description}`);
  return ok;
}

/**
 * Checks whether a directory contains at least one file and prints a status marker.
 */
export function testDirHasFiles(dirPath: string, description: string): boolean {
  const ok =
    fs.existsSync(dirPath) &&
    fs.statSync(dirPath).isDirectory() &&
    fs.readdirSync(dirPath).some((name) => fs.statSync(path.join(dirPath, name)).isFile());
  console.log(`  [${ok ? "OK" : "FAIL"}] ${description}`);
  return ok;
}

/**
 * Creates a scoped logger that writes diagnostic messages to stderr.
 * The returned `info` method is for verbose step-by-step diagnostics;
 * `log` writes user-facing messages to stdout; `warn` and `error` go to stderr.
 */
export function createLogger(prefix: string): {
  info: (message: string, details?: unknown) => void;
  log: (message: string) => void;
  warn: (message: string) => void;
  error: (message: string) => void;
} {
  return {
    info: (message: string, details?: unknown): void => {
      if (details === undefined) {
        console.error(`[${prefix}] ${message}`);
      } else {
        console.error(`[${prefix}] ${message}`, details);
      }
    },
    log: (message: string): void => {
      console.log(`[${prefix}] ${message}`);
    },
    warn: (message: string): void => {
      console.error(`[${prefix}] WARNING: ${message}`);
    },
    error: (message: string): void => {
      console.error(`[${prefix}] ERROR: ${message}`);
    },
  };
}

/**
 * Writes an INFO-level message to stdout (user-facing, no prefix).
 */
export function logInfo(message: string): void {
  console.log(`INFO: ${message}`);
}

/**
 * Writes a success message to stdout (user-facing, no prefix).
 */
export function logSuccess(message: string): void {
  console.log(`✓ ${message}`);
}

/**
 * Writes a WARNING-level message to stderr (user-facing, no prefix).
 */
export function logWarn(message: string): void {
  console.warn(`WARNING: ${message}`);
}

/**
 * Writes an ERROR-level message to stderr (user-facing, no prefix).
 */
export function logError(message: string): void {
  console.error(`ERROR: ${message}`);
}

/**
 * Resolves template file path with override/preset/extension/core priority.
 */
export function resolveTemplate(templateName: string, repoRoot: string): string | null {
  // Resolution order: overrides -> presets (priority) -> extensions -> core.
  const base = path.join(repoRoot, ".specs", "templates");

  const override = path.join(base, "overrides", `${templateName}.md`);
  if (fs.existsSync(override)) return override;

  const presetsDir = path.join(repoRoot, ".specs", "presets");
  if (fs.existsSync(presetsDir) && fs.statSync(presetsDir).isDirectory()) {
    let sortedPresets: string[] = [];
    const registry = path.join(presetsDir, ".registry");
    if (fs.existsSync(registry)) {
      try {
        const reg = JSON.parse(fs.readFileSync(registry, "utf-8")) as {
          presets?: Record<string, { priority?: number }>;
        };
        const presets = reg.presets ?? {};
        sortedPresets = Object.keys(presets).sort((a, b) => (presets[a]?.priority ?? 10) - (presets[b]?.priority ?? 10));
      } catch {
        sortedPresets = [];
      }
    }

    if (sortedPresets.length === 0) {
      sortedPresets = fs
        .readdirSync(presetsDir)
        .filter((name) => !name.startsWith("."))
        .filter((name) => fs.statSync(path.join(presetsDir, name)).isDirectory())
        .sort();
    }

    for (const presetId of sortedPresets) {
      const candidate = path.join(presetsDir, presetId, "templates", `${templateName}.md`);
      if (fs.existsSync(candidate)) return candidate;
    }
  }

  const extDir = path.join(repoRoot, ".specs", "extensions");
  if (fs.existsSync(extDir) && fs.statSync(extDir).isDirectory()) {
    const exts = fs
      .readdirSync(extDir)
      .filter((name) => !name.startsWith("."))
      .filter((name) => fs.statSync(path.join(extDir, name)).isDirectory())
      .sort();

    for (const ext of exts) {
      const candidate = path.join(extDir, ext, "templates", `${templateName}.md`);
      if (fs.existsSync(candidate)) return candidate;
    }
  }

  const core = path.join(base, `${templateName}.md`);
  return fs.existsSync(core) ? core : null;
}

