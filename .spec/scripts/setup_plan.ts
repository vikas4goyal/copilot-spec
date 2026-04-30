#!/usr/bin/env node
import * as fs from "node:fs";
import {
  getFeaturePathsEnv,
  resolveTemplate,
  testFeatureBranch,
} from "./common";

const useJson = process.argv.includes("--json");
const paths = getFeaturePathsEnv();

if (!testFeatureBranch(paths.CURRENT_BRANCH, paths.HAS_GIT)) process.exit(1);

fs.mkdirSync(paths.FEATURE_DIR, { recursive: true });

const template = resolveTemplate("plan-template", paths.REPO_ROOT);
if (template && fs.existsSync(template)) {
  fs.copyFileSync(template, paths.IMPL_PLAN);
  console.log(`Copied plan template to ${paths.IMPL_PLAN}`);
} else {
  console.error("[setup-plan] Warning: Plan template not found");
  fs.closeSync(fs.openSync(paths.IMPL_PLAN, "a"));
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

