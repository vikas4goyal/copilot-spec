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

export function getRepoRoot(): string {
  const specsMarkerRoot = findSpecifyRoot();
  if (specsMarkerRoot) return specsMarkerRoot;

  const git = spawnSync("git", ["rev-parse", "--show-toplevel"], { encoding: "utf-8" });
  if (git.status === 0) {
    return (git.stdout ?? "").trim();
  }

  return path.resolve(__dirname, "..", "..", "..");
}

export function hasGitCommand(): boolean {
  try {
    const result = spawnSync("git", ["--version"], { stdio: "ignore" });
    return result.error == null;
  } catch {
    return false;
  }
}

export function testHasGit(repoRoot?: string): boolean {
  if (!hasGitCommand()) return false;
  const root = repoRoot ?? getRepoRoot();
  if (!fs.existsSync(path.join(root, ".git"))) return false;
  const result = spawnSync("git", ["-C", root, "rev-parse", "--is-inside-work-tree"], { stdio: "ignore" });
  return result.status === 0;
}

export function getCurrentBranch(repoRoot?: string): string {
  // Priority: env override -> git branch -> latest specs folder -> main
  const envBranch = (process.env.SPECIFY_FEATURE ?? "").trim();
  if (envBranch) return envBranch;

  const root = repoRoot ?? getRepoRoot();
  if (testHasGit(root)) {
    const result = spawnSync("git", ["-C", root, "rev-parse", "--abbrev-ref", "HEAD"], { encoding: "utf-8" });
    if (result.status === 0) return (result.stdout ?? "").trim();
  }

  const specsDir = path.join(root, "specs");
  if (fs.existsSync(specsDir) && fs.statSync(specsDir).isDirectory()) {
    let latestFeatureDirName = "";
    let highestSequentialPrefix = 0;
    let latestTimestampPrefix = "";

    for (const entryName of fs.readdirSync(specsDir)) {
      const entryPath = path.join(specsDir, entryName);
      if (!fs.statSync(entryPath).isDirectory()) continue;
      const timestampMatch = entryName.match(/^(\d{8}-\d{6})-/);
      const sequentialMatch = entryName.match(/^(\d{3,})-/);
      if (timestampMatch) {
        if (timestampMatch[1] > latestTimestampPrefix) {
          latestTimestampPrefix = timestampMatch[1];
          latestFeatureDirName = entryName;
        }
      } else if (sequentialMatch && !latestTimestampPrefix) {
        const sequentialNumber = Number.parseInt(sequentialMatch[1], 10);
        if (sequentialNumber > highestSequentialPrefix) {
          highestSequentialPrefix = sequentialNumber;
          latestFeatureDirName = entryName;
        }
      }
    }

    if (latestFeatureDirName) return latestFeatureDirName;
  }

  return "main";
}

export function testFeatureBranch(branch: string, hasGit = true): boolean {
  if (!hasGit) {
    console.error("[specify] Warning: Git repository not detected; skipped branch validation");
    return true;
  }

  const malformed = /^[0-9]{7}-[0-9]{6}-/.test(branch) || /^(?:\d{7}|\d{8})-\d{6}$/.test(branch);
  const isSequential = /^[0-9]{3,}-/.test(branch) && !malformed;
  const isTimestamp = /^\d{8}-\d{6}-/.test(branch);

  if (!isSequential && !isTimestamp) {
    console.log(`ERROR: Not on a feature branch. Current branch: ${branch}`);
    console.log(
      "Feature branches should be named like: 001-feature-name, 1234-feature-name, or 20260319-143022-feature-name",
    );
    return false;
  }
  return true;
}

export function getFeatureDir(repoRoot: string, branch: string): string {
  return path.join(repoRoot, "specs", branch);
}

export function getFeaturePathsEnv(): FeaturePaths {
  const repoRoot = getRepoRoot();
  const currentBranch = getCurrentBranch(repoRoot);
  const hasGit = testHasGit(repoRoot);

  let featureDir: string | null = null;
  const featureJsonPath = path.join(repoRoot, ".specs", "feature.json");

  // Resolve feature dir in order: env -> .specs/feature.json -> specs/<branch>
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

export function testFileExists(filePath: string, description: string): boolean {
  const ok = fs.existsSync(filePath) && fs.statSync(filePath).isFile();
  console.log(`  [${ok ? "OK" : "FAIL"}] ${description}`);
  return ok;
}

export function testDirHasFiles(dirPath: string, description: string): boolean {
  const ok =
    fs.existsSync(dirPath) &&
    fs.statSync(dirPath).isDirectory() &&
    fs.readdirSync(dirPath).some((name) => fs.statSync(path.join(dirPath, name)).isFile());
  console.log(`  [${ok ? "OK" : "FAIL"}] ${description}`);
  return ok;
}

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

