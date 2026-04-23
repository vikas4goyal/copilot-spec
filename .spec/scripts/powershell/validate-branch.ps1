#!/usr/bin/env pwsh
# Validate current git branch follows feature branch naming conventions.
# Patterns: sequential (001-name) or timestamp (20260319-143022-name).
# Usage: validate-branch.ps1 [-Json]
# Exit code 0 = valid, 1 = invalid/not a feature branch.
param([switch]$Json)
$ErrorActionPreference = 'Stop'

function Write-NoRemote([string]$Reason) {
    if ($Json) { Write-Output "{`"valid`":false,`"reason`":`"$Reason`"}" }
    else { Write-Warning "[specify] $Reason" }
    exit 0
}

# Resolve branch name
$branch = $null
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    $branch = $env:SPECIFY_FEATURE
    if (-not $branch) { Write-NoRemote "Git not found and SPECIFY_FEATURE not set; skipped branch validation" }
} else {
    try {
        git rev-parse --is-inside-work-tree 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { throw }
        $branch = git rev-parse --abbrev-ref HEAD 2>$null
    } catch {
        $branch = $env:SPECIFY_FEATURE
        if (-not $branch) { Write-NoRemote "Not inside a Git repository; skipped branch validation" }
    }
}

$sequentialRe = '^[0-9]{3,}-'
$timestampRe  = '^[0-9]{8}-[0-9]{6}-'

if ($branch -match $sequentialRe) {
    $prefix = [regex]::Match($branch, '^[0-9]{3,}').Value
} elseif ($branch -match $timestampRe) {
    $prefix = [regex]::Match($branch, '^[0-9]{8}-[0-9]{6}').Value
} else {
    if ($Json) {
        Write-Output "{`"valid`":false,`"branch`":`"$branch`",`"reason`":`"not-a-feature-branch`"}"
    } else {
        Write-Host "[FAIL] Not on a feature branch. Current branch: $branch"
        Write-Host "Feature branches must be named like: 001-feature-name or 20260319-143022-feature-name"
    }
    exit 1
}

# Find spec directory
$scriptRoot = $PSScriptRoot
$repoRoot   = Split-Path (Split-Path $scriptRoot -Parent) -Parent
$specsDir   = Join-Path $repoRoot "specs"
$specDir    = ""
if (Test-Path $specsDir) {
    $match = Get-ChildItem -LiteralPath $specsDir -Directory | Where-Object { $_.Name -like "$prefix-*" } | Select-Object -First 1
    if ($match) { $specDir = $match.FullName }
}

if ($Json) {
    Write-Output "{`"valid`":true,`"branch`":`"$branch`",`"prefix`":`"$prefix`",`"spec_dir`":`"$specDir`"}"
} else {
    Write-Host "[OK] On feature branch: $branch"
    if ($specDir) { Write-Host "[OK] Spec directory found: $specDir" }
    else          { Write-Host "[WARN] No spec directory found for prefix $prefix" }
}
