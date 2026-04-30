#!/usr/bin/env node
import * as fs from "node:fs";
import {
  getFeaturePathsEnv,
  testFeatureBranch,
  testFileExists,
  testDirHasFiles,
} from "./common";

const args = new Set(process.argv.slice(2));
const useJson = args.has("--json");
const requireTasks = args.has("--require-tasks");
const includeTasks = args.has("--include-tasks");
const pathsOnly = args.has("--paths-only");

const paths = getFeaturePathsEnv();
if (!testFeatureBranch(paths.CURRENT_BRANCH, paths.HAS_GIT)) process.exit(1);

if (pathsOnly) {
  const payload = {
    REPO_ROOT: paths.REPO_ROOT,
    BRANCH: paths.CURRENT_BRANCH,
    FEATURE_DIR: paths.FEATURE_DIR,
    FEATURE_SPEC: paths.FEATURE_SPEC,
    IMPL_PLAN: paths.IMPL_PLAN,
    TASKS: paths.TASKS,
  };
  if (useJson) {
    console.log(JSON.stringify(payload));
  } else {
    Object.entries(payload).forEach(([k, v]) => console.log(`${k}: ${v}`));
  }
  process.exit(0);
}

if (!fs.existsSync(paths.FEATURE_DIR) || !fs.statSync(paths.FEATURE_DIR).isDirectory()) {
  console.log(`ERROR: Feature directory not found: ${paths.FEATURE_DIR}`);
  console.log("Run /spec.specs first to create the feature structure.");
  process.exit(1);
}

if (!fs.existsSync(paths.IMPL_PLAN) || !fs.statSync(paths.IMPL_PLAN).isFile()) {
  console.log(`ERROR: plan.md not found in ${paths.FEATURE_DIR}`);
  console.log("Run /spec.plan first to create the implementation plan.");
  process.exit(1);
}

if (requireTasks && (!fs.existsSync(paths.TASKS) || !fs.statSync(paths.TASKS).isFile())) {
  console.log(`ERROR: tasks.md not found in ${paths.FEATURE_DIR}`);
  console.log("Run /spec.tasks first to create the task list.");
  process.exit(1);
}

const docs: string[] = [];
if (fs.existsSync(paths.RESEARCH) && fs.statSync(paths.RESEARCH).isFile()) docs.push("research.md");
if (fs.existsSync(paths.DATA_MODEL) && fs.statSync(paths.DATA_MODEL).isFile()) docs.push("data-model.md");
if (
  fs.existsSync(paths.CONTRACTS_DIR) &&
  fs.statSync(paths.CONTRACTS_DIR).isDirectory() &&
  fs.readdirSync(paths.CONTRACTS_DIR).some((f) => fs.statSync(`${paths.CONTRACTS_DIR}/${f}`).isFile())
) {
  docs.push("contracts/");
}
if (fs.existsSync(paths.QUICKSTART) && fs.statSync(paths.QUICKSTART).isFile()) docs.push("quickstart.md");
if (includeTasks && fs.existsSync(paths.TASKS) && fs.statSync(paths.TASKS).isFile()) docs.push("tasks.md");

if (useJson) {
  console.log(JSON.stringify({ FEATURE_DIR: paths.FEATURE_DIR, AVAILABLE_DOCS: docs }));
} else {
  console.log(`FEATURE_DIR:${paths.FEATURE_DIR}`);
  console.log("AVAILABLE_DOCS:");
  testFileExists(paths.RESEARCH, "research.md");
  testFileExists(paths.DATA_MODEL, "data-model.md");
  testDirHasFiles(paths.CONTRACTS_DIR, "contracts/");
  testFileExists(paths.QUICKSTART, "quickstart.md");
  if (includeTasks) testFileExists(paths.TASKS, "tasks.md");
}

