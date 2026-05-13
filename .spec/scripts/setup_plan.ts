#!/usr/bin/env node
import * as fs from "node:fs";
import {
  getFeaturePathsEnv,
  resolveTemplate,
  testFeatureBranch,
  createLogger,
} from "./common";

const { info: logInfo, warn: logWarn } = createLogger("setup-plan");

const useJson = process.argv.includes("--json");
const paths = getFeaturePathsEnv();

logInfo("Starting plan setup", {
  useJson,
  branch: paths.CURRENT_BRANCH,
  hasGit: paths.HAS_GIT,
  featureDir: paths.FEATURE_DIR,
  implPlan: paths.IMPL_PLAN,
});

if (!testFeatureBranch(paths.CURRENT_BRANCH, paths.HAS_GIT)) process.exit(1);

fs.mkdirSync(paths.FEATURE_DIR, { recursive: true });
logInfo("Ensured feature directory exists", { featureDir: paths.FEATURE_DIR });

const template = resolveTemplate("plan-template", paths.REPO_ROOT);
logInfo("Resolved plan template path", { template: template || null });
if (template && fs.existsSync(template)) {
  fs.copyFileSync(template, paths.IMPL_PLAN);
  logInfo("Copied plan template", { source: template, destination: paths.IMPL_PLAN });
  console.log(`Copied plan template to ${paths.IMPL_PLAN}`);
} else {
  logWarn("Plan template not found");
  fs.closeSync(fs.openSync(paths.IMPL_PLAN, "a"));
  logInfo("Created empty plan file because template was missing", { destination: paths.IMPL_PLAN });
}

if (useJson) {
  console.log(
    JSON.stringify({
      FEATURE_SPEC: paths.FEATURE_SPEC,
      IMPL_PLAN: paths.IMPL_PLAN,
      SPECS_DIR: paths.FEATURE_DIR,
      BRANCH: paths.CURRENT_BRANCH,
      HAS_GIT: paths.HAS_GIT,
    }),
  );
} else {
  console.log(`FEATURE_SPEC: ${paths.FEATURE_SPEC}`);
  console.log(`IMPL_PLAN: ${paths.IMPL_PLAN}`);
  console.log(`SPECS_DIR: ${paths.FEATURE_DIR}`);
  console.log(`BRANCH: ${paths.CURRENT_BRANCH}`);
  console.log(`HAS_GIT: ${paths.HAS_GIT}`);
}

