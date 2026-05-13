#!/usr/bin/env node
/**
 * update_agent_context.ts
 * Updates agent context files (e.g. CLAUDE.md, .github/copilot-instructions.md)
 * with technology stack information extracted from the active feature's plan.md.
 *
 * Usage:
 *   npx tsx .spec/scripts/update_agent_context.ts [--agent-type <type>]
 *
 * Supported agent types:
 *   claude, gemini, copilot, cursor-agent, qwen, opencode, codex, windsurf,
 *   junie, kilocode, auggie, roo, codebuddy, amp, shai, tabnine, kiro-cli,
 *   agy, bob, vibe, qodercli, kimi, trae, pi, iflow, forge, generic
 *
 * If --agent-type is omitted, all existing agent files are updated.
 */

import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import { getFeaturePathsEnv, createLogger } from "./common";

// ---------------------------------------------------------------------------
// CLI argument parsing
// ---------------------------------------------------------------------------

function getCliArg(name: string): string {
  const index = process.argv.indexOf(name);
  return index >= 0 && index + 1 < process.argv.length ? process.argv[index + 1] : "";
}

const agentType = getCliArg("--agent-type");

// ---------------------------------------------------------------------------
// Environment & paths
// ---------------------------------------------------------------------------

const paths = getFeaturePathsEnv();
const REPO_ROOT = paths.REPO_ROOT;
const CURRENT_BRANCH = paths.CURRENT_BRANCH;
const HAS_GIT = paths.HAS_GIT;
const IMPL_PLAN = paths.IMPL_PLAN;

// Agent file destinations
const AGENT_FILES: Record<string, { file: string; label: string }> = {
  claude:        { file: "CLAUDE.md",                                     label: "Claude Code" },
  gemini:        { file: "GEMINI.md",                                     label: "Gemini CLI" },
  copilot:       { file: ".github/copilot-instructions.md",               label: "GitHub Copilot" },
  "cursor-agent":{ file: ".cursor/rules/specify-rules.mdc",               label: "Cursor IDE" },
  qwen:          { file: "QWEN.md",                                        label: "Qwen Code" },
  opencode:      { file: "AGENTS.md",                                      label: "opencode" },
  codex:         { file: "AGENTS.md",                                      label: "Codex CLI" },
  windsurf:      { file: ".windsurf/rules/specify-rules.md",               label: "Windsurf" },
  junie:         { file: ".junie/AGENTS.md",                               label: "Junie" },
  kilocode:      { file: ".kilocode/rules/specify-rules.md",               label: "Kilo Code" },
  auggie:        { file: ".augment/rules/specify-rules.md",                label: "Auggie CLI" },
  roo:           { file: ".roo/rules/specify-rules.md",                    label: "Roo Code" },
  codebuddy:     { file: "CODEBUDDY.md",                                   label: "CodeBuddy CLI" },
  qodercli:      { file: "QODER.md",                                       label: "Qoder CLI" },
  amp:           { file: "AGENTS.md",                                      label: "Amp" },
  shai:          { file: "SHAI.md",                                        label: "SHAI" },
  tabnine:       { file: "TABNINE.md",                                     label: "Tabnine CLI" },
  "kiro-cli":    { file: "AGENTS.md",                                      label: "Kiro CLI" },
  agy:           { file: ".agent/rules/specify-rules.md",                  label: "Antigravity" },
  bob:           { file: "AGENTS.md",                                      label: "IBM Bob" },
  vibe:          { file: ".vibe/agents/specify-agents.md",                 label: "Mistral Vibe" },
  kimi:          { file: "KIMI.md",                                        label: "Kimi Code" },
  trae:          { file: ".trae/rules/project_rules.md",                   label: "Trae" },
  pi:            { file: "AGENTS.md",                                      label: "Pi Coding Agent" },
  iflow:         { file: "IFLOW.md",                                       label: "iFlow CLI" },
  forge:         { file: "AGENTS.md",                                      label: "Forge" },
  generic:       { file: "",                                               label: "Generic" },
};

const TEMPLATE_FILE = path.join(REPO_ROOT, ".specs", "templates", "agent-file-template.md");

// ---------------------------------------------------------------------------
// Parsed plan data (module-level state)
// ---------------------------------------------------------------------------

let newLang = "";
let newFramework = "";
let newDb = "";
let newProjectType = "";

// ---------------------------------------------------------------------------
// Logging helpers (shared logger via common.ts)
// ---------------------------------------------------------------------------

const logger = createLogger("update-agent-context");

/**
 * Logs an informational/progress message to stdout with the script prefix.
 */
function info(msg: string): void    { logger.log(msg); }

/**
 * Logs a success message to stdout with a checkmark prefix.
 */
function success(msg: string): void { logger.log(`✓ ${msg}`); }

/**
 * Logs a warning message to stderr with the script prefix.
 */
function warn(msg: string): void    { logger.warn(msg); }

/**
 * Logs an error message to stderr with the script prefix.
 */
function err(msg: string): void     { logger.error(msg); }

// ---------------------------------------------------------------------------
// Environment validation
// ---------------------------------------------------------------------------

function validateEnvironment(): void {
  logger.info("Validating environment", { CURRENT_BRANCH, HAS_GIT, IMPL_PLAN, TEMPLATE_FILE });
  if (!CURRENT_BRANCH) {
    err("Unable to determine current feature");
    if (HAS_GIT) {
      info("Make sure you're on a feature branch");
    } else {
      info("Set SPECIFY_FEATURE environment variable or create a feature first");
    }
    process.exit(1);
  }
  if (!fs.existsSync(IMPL_PLAN)) {
    err(`No plan.md found at ${IMPL_PLAN}`);
    info("Ensure you are working on a feature with a corresponding spec directory");
    if (!HAS_GIT) {
      info("Use: SPECIFY_FEATURE=your-feature-name or create a new feature first");
    }
    process.exit(1);
  }
  if (!fs.existsSync(TEMPLATE_FILE)) {
    err(`Template file not found at ${TEMPLATE_FILE}`);
    info("Run specify init to scaffold .spec/specs/templates, or add agent-file-template.md there.");
    process.exit(1);
  }
  logger.info("Environment validation passed");
}

// ---------------------------------------------------------------------------
// Plan data extraction
// ---------------------------------------------------------------------------

function extractPlanField(fieldPattern: string, planFile: string): string {
  if (!fs.existsSync(planFile)) return "";
  const regex = new RegExp(`^\\*\\*${fieldPattern.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\*\\*: (.+)$`);
  const lines = fs.readFileSync(planFile, "utf-8").split(/\r?\n/);
  for (const line of lines) {
    const match = line.match(regex);
    if (match) {
      const val = match[1].trim();
      if (val !== "NEEDS CLARIFICATION" && val !== "N/A") return val;
    }
  }
  return "";
}

function parsePlanData(): boolean {
  if (!fs.existsSync(IMPL_PLAN)) { err(`Plan file not found: ${IMPL_PLAN}`); return false; }
  info(`Parsing plan data from ${IMPL_PLAN}`);
  newLang        = extractPlanField("Language/Version", IMPL_PLAN);
  newFramework   = extractPlanField("Primary Dependencies", IMPL_PLAN);
  newDb          = extractPlanField("Storage", IMPL_PLAN);
  newProjectType = extractPlanField("Project Type", IMPL_PLAN);

  if (newLang)        info(`Found language: ${newLang}`);
  else                warn("No language information found in plan");
  if (newFramework)   info(`Found framework: ${newFramework}`);
  if (newDb && newDb !== "N/A") info(`Found database: ${newDb}`);
  if (newProjectType) info(`Found project type: ${newProjectType}`);
  logger.info("Plan data extraction complete", { newLang, newFramework, newDb, newProjectType });
  return true;
}

// ---------------------------------------------------------------------------
// Content helpers
// ---------------------------------------------------------------------------

function formatTechStack(): string {
  const parts: string[] = [];
  if (newLang && newLang !== "NEEDS CLARIFICATION") parts.push(newLang);
  if (newFramework && newFramework !== "NEEDS CLARIFICATION" && newFramework !== "N/A") parts.push(newFramework);
  return parts.join(" + ");
}

function getProjectStructure(): string {
  return /web/i.test(newProjectType) ? "backend/\nfrontend/\ntests/" : "src/\ntests/";
}

function getCommandsForLanguage(): string {
  if (/Python/i.test(newLang))              return "cd src; pytest; ruff check .";
  if (/Rust/i.test(newLang))                return "cargo test; cargo clippy";
  if (/JavaScript|TypeScript/i.test(newLang)) return "npm test; npm run lint";
  return `# Add commands for ${newLang}`;
}

function getLanguageConventions(): string {
  return newLang ? `${newLang}: Follow standard conventions` : "General: Follow standard conventions";
}

// ---------------------------------------------------------------------------
// File creation / update
// ---------------------------------------------------------------------------

function createAgentFile(targetFile: string, projectName: string): boolean {
  if (!fs.existsSync(TEMPLATE_FILE)) { err(`Template not found at ${TEMPLATE_FILE}`); return false; }

  const tmpFile = path.join(os.tmpdir(), `agent-ctx-${Date.now()}.md`);
  fs.copyFileSync(TEMPLATE_FILE, tmpFile);

  const dateStr = new Date().toISOString().slice(0, 10);
  const projectStructure = getProjectStructure();
  const commands = getCommandsForLanguage();
  const langConventions = getLanguageConventions();

  let techStackForTemplate = "";
  if (newLang && newFramework)      techStackForTemplate = `- ${newLang} + ${newFramework} (${CURRENT_BRANCH})`;
  else if (newLang)                 techStackForTemplate = `- ${newLang} (${CURRENT_BRANCH})`;
  else if (newFramework)            techStackForTemplate = `- ${newFramework} (${CURRENT_BRANCH})`;

  let recentChangesForTemplate = "";
  if (newLang && newFramework)      recentChangesForTemplate = `- ${CURRENT_BRANCH}: Added ${newLang} + ${newFramework}`;
  else if (newLang)                 recentChangesForTemplate = `- ${CURRENT_BRANCH}: Added ${newLang}`;
  else if (newFramework)            recentChangesForTemplate = `- ${CURRENT_BRANCH}: Added ${newFramework}`;

  let content = fs.readFileSync(tmpFile, "utf-8");
  content = content.replace(/\[PROJECT NAME]/g, projectName);
  content = content.replace(/\[DATE]/g, dateStr);
  content = content.replace(/\[EXTRACTED FROM ALL PLAN\.MD FILES]/g, techStackForTemplate);
  content = content.replace(/\[ACTUAL STRUCTURE FROM PLANS]/g, projectStructure.replace(/\n/g, "\\n"));
  content = content.replace(/\[ONLY COMMANDS FOR ACTIVE TECHNOLOGIES]/g, commands);
  content = content.replace(/\[LANGUAGE-SPECIFIC, ONLY FOR LANGUAGES IN USE]/g, langConventions);
  content = content.replace(/\[LAST 3 FEATURES AND WHAT THEY ADDED]/g, recentChangesForTemplate);
  content = content.replace(/\\n/g, "\n");

  if (targetFile.endsWith(".mdc")) {
    const frontmatter = `---\ndescription: Project Development Guidelines\nglobs: ["**/*"]\nalwaysApply: true\n---\n\n`;
    content = frontmatter + content;
  }

  const parentDir = path.dirname(targetFile);
  if (!fs.existsSync(parentDir)) fs.mkdirSync(parentDir, { recursive: true });
  fs.writeFileSync(targetFile, content, "utf-8");
  fs.unlinkSync(tmpFile);
  return true;
}

function updateExistingAgentFile(targetFile: string): boolean {
  if (!fs.existsSync(targetFile)) {
    return createAgentFile(targetFile, path.basename(REPO_ROOT));
  }

  const techStack = formatTechStack();
  const dateStr = new Date().toISOString().slice(0, 10);
  const existingContent = fs.readFileSync(targetFile, "utf-8");

  const newTechEntries: string[] = [];
  if (techStack && !existingContent.includes(techStack)) {
    newTechEntries.push(`- ${techStack} (${CURRENT_BRANCH})`);
  }
  if (newDb && newDb !== "N/A" && newDb !== "NEEDS CLARIFICATION" && !existingContent.includes(newDb)) {
    newTechEntries.push(`- ${newDb} (${CURRENT_BRANCH})`);
  }

  let newChangeEntry = "";
  if (techStack)                                        newChangeEntry = `- ${CURRENT_BRANCH}: Added ${techStack}`;
  else if (newDb && newDb !== "N/A" && newDb !== "NEEDS CLARIFICATION") newChangeEntry = `- ${CURRENT_BRANCH}: Added ${newDb}`;

  const lines = existingContent.split(/\r?\n/);
  const output: string[] = [];
  let inTech = false;
  let inChanges = false;
  let techAdded = false;
  let changeAdded = false;
  let existingChanges = 0;

  for (const line of lines) {
    if (line === "## Active Technologies") {
      output.push(line);
      inTech = true;
      continue;
    }
    if (inTech && /^##\s/.test(line)) {
      if (!techAdded && newTechEntries.length > 0) { output.push(...newTechEntries); techAdded = true; }
      output.push(line); inTech = false; continue;
    }
    if (inTech && !line.trim()) {
      if (!techAdded && newTechEntries.length > 0) { output.push(...newTechEntries); techAdded = true; }
      output.push(line); continue;
    }
    if (line === "## Recent Changes") {
      output.push(line);
      if (newChangeEntry) { output.push(newChangeEntry); changeAdded = true; }
      inChanges = true; continue;
    }
    if (inChanges && /^##\s/.test(line)) { output.push(line); inChanges = false; continue; }
    if (inChanges && /^- /.test(line)) {
      if (existingChanges < 2) { output.push(line); existingChanges++; }
      continue;
    }
    if (/(\*\*)?Last updated(\*\*)?: .*\d{4}-\d{2}-\d{2}/.test(line)) {
      output.push(line.replace(/\d{4}-\d{2}-\d{2}/, dateStr));
      continue;
    }
    output.push(line);
  }

  // Post-loop: flush remaining tech entries if still inside section at EOF
  if (inTech && !techAdded && newTechEntries.length > 0) output.push(...newTechEntries);

  let result = output.join("\n");

  // Ensure Cursor .mdc files have YAML frontmatter
  if (targetFile.endsWith(".mdc") && !result.startsWith("---")) {
    const frontmatter = `---\ndescription: Project Development Guidelines\nglobs: ["**/*"]\nalwaysApply: true\n---\n\n`;
    result = frontmatter + result;
  }

  fs.writeFileSync(targetFile, result, "utf-8");
  return true;
}

function updateAgentFile(relativeFile: string, label: string): boolean {
  if (!relativeFile) { info(`Generic agent: no predefined context file.`); return true; }
  const targetFile = path.join(REPO_ROOT, relativeFile);
  logger.info("Updating agent context file", { label, targetFile });
  info(`Updating ${label} context file: ${targetFile}`);

  const parentDir = path.dirname(targetFile);
  if (!fs.existsSync(parentDir)) fs.mkdirSync(parentDir, { recursive: true });

  if (!fs.existsSync(targetFile)) {
    logger.info("Agent file does not exist — will create from template", { targetFile });
    if (createAgentFile(targetFile, path.basename(REPO_ROOT))) {
      success(`Created new ${label} context file`);
      return true;
    }
    err(`Failed to create new agent file`);
    return false;
  }

  logger.info("Agent file exists — will update in place", { targetFile });
  try {
    if (updateExistingAgentFile(targetFile)) {
      success(`Updated existing ${label} context file`);
      return true;
    }
    err(`Failed to update agent file`);
    return false;
  } catch (e) {
    err(`Cannot access or update existing file: ${targetFile}. ${e}`);
    return false;
  }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

function updateSpecificAgent(type: string): boolean {
  const entry = AGENT_FILES[type];
  if (!entry) {
    err(`Unknown agent type '${type}'`);
    err(`Expected: ${Object.keys(AGENT_FILES).join("|")}`);
    return false;
  }
  return updateAgentFile(entry.file, entry.label);
}

function updateAllExistingAgents(): boolean {
  let ok = true;
  let found = false;
  const updatedPaths = new Set<string>();

  function updateIfExists(relativeFile: string, label: string): void {
    if (!relativeFile) return;
    const fullPath = path.resolve(REPO_ROOT, relativeFile);
    if (!fs.existsSync(fullPath)) return;
    const realPath = fs.realpathSync(fullPath);
    if (updatedPaths.has(realPath)) return;
    updatedPaths.add(realPath);
    found = true;
    if (!updateAgentFile(relativeFile, label)) ok = false;
  }

  for (const [, entry] of Object.entries(AGENT_FILES)) {
    if (entry.file) updateIfExists(entry.file, entry.label);
  }

  if (!found) {
    info("No existing agent files found, creating default Claude file...");
    if (!updateAgentFile(AGENT_FILES["claude"].file, AGENT_FILES["claude"].label)) ok = false;
  }
  return ok;
}

function printSummary(): void {
  console.log("");
  info("Summary of changes:");
  if (newLang)                              console.log(`  - Added language: ${newLang}`);
  if (newFramework)                         console.log(`  - Added framework: ${newFramework}`);
  if (newDb && newDb !== "N/A")             console.log(`  - Added database: ${newDb}`);
  console.log("");
  info(`Usage: npx tsx update_agent_context.ts [--agent-type ${Object.keys(AGENT_FILES).join("|")}]`);
}

validateEnvironment();
info(`=== Updating agent context files for feature ${CURRENT_BRANCH} ===`);
logger.info("Starting agent context update", { agentType: agentType || "all", CURRENT_BRANCH, REPO_ROOT });
if (!parsePlanData()) { err("Failed to parse plan data"); process.exit(1); }

let overallSuccess = true;
if (agentType) {
  info(`Updating specific agent: ${agentType}`);
  logger.info("Targeting specific agent type", { agentType });
  if (!updateSpecificAgent(agentType)) overallSuccess = false;
} else {
  info("No agent specified, updating all existing agent files...");
  logger.info("Updating all existing agent context files");
  if (!updateAllExistingAgents()) overallSuccess = false;
}

printSummary();
if (overallSuccess) {
  logger.info("Agent context update completed successfully");
  success("Agent context update completed successfully");
  process.exit(0);
} else {
  logger.info("Agent context update completed with errors");
  err("Agent context update completed with errors");
  process.exit(1);
}



