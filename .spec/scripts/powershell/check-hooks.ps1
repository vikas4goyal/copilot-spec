#!/usr/bin/env pwsh
# Read .spec/extensions.yml and output formatted hook prompts for a given event.
# Usage: check-hooks.ps1 -Event before_plan
# Outputs ready-to-display markdown blocks; silent if no hooks / no file / no YAML parser.
# Hooks with non-empty `condition` are skipped (left to the HookExecutor).
param([Parameter(Mandatory)][string]$Event)
$ErrorActionPreference = 'SilentlyContinue'

$scriptRoot = $PSScriptRoot
$repoRoot   = Split-Path (Split-Path $scriptRoot -Parent) -Parent
$extFile    = Join-Path $repoRoot ".spec/extensions.yml"

if (-not (Test-Path $extFile)) { exit 0 }

$python = $null
foreach ($name in @('python3','python')) {
    if (Get-Command $name -ErrorAction SilentlyContinue) { $python = $name; break }
}
if (-not $python) { exit 0 }

$py = @'
import sys
try:
    import yaml
except ImportError:
    sys.exit(0)

ext_file, event = sys.argv[1], sys.argv[2]
try:
    with open(ext_file) as f:
        data = yaml.safe_load(f) or {}
except Exception:
    sys.exit(0)

hooks = (data.get("hooks") or {}).get(event) or []
if not hooks:
    sys.exit(0)

parts = []
for hook in hooks:
    if not isinstance(hook, dict):
        continue
    if hook.get("enabled") is False:
        continue
    if hook.get("condition"):
        continue
    ext      = hook.get("extension", "<unknown>")
    cmd      = hook.get("command", "<unknown>")
    desc     = hook.get("description", "")
    prompt   = hook.get("prompt", "")
    optional = bool(hook.get("optional", False))

    parts.append("## Extension Hooks\n")
    if optional:
        parts.append(f"**Optional Pre-Hook**: {ext}")
        parts.append(f"Command: `/{cmd}`")
        parts.append(f"Description: {desc}\n")
        parts.append(f"Prompt: {prompt}")
        parts.append(f"To execute: `/{cmd}`")
    else:
        parts.append(f"**Automatic Pre-Hook**: {ext}")
        parts.append(f"Executing: `/{cmd}`")
        parts.append(f"EXECUTE_COMMAND: {cmd}\n")
        parts.append("Wait for the result of the hook command before proceeding.")
    parts.append("")

if parts:
    print("\n".join(parts))
'@

$py | & $python - $extFile $Event
