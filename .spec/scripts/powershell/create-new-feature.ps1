#!/usr/bin/env pwsh
# create-new-feature.ps1 — Resolves unique branch and folder names from session 'name',
# creates the git branch and specs/YYYYMMDD-<name>/ directory, then writes branch_name
# and feature_dir back to session.json.
#
# Naming conventions
#   branch  : <name>  →  <name>-YYYYMMDD  →  <name>-YYYYMMDD-2 …
#   folder  : YYYYMMDD-<name>  →  YYYYMMDD-<name>-2 …  (date-prefix for dir sorting)

[CmdletBinding()]
param(
    [switch]$Json,
    [switch]$DryRun,
    [switch]$Help
)
$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: create-new-feature.ps1 [-Json] [-DryRun]'
    Write-Host '  -Json     Output JSON ({BRANCH_NAME, SPEC_FILE})'
    Write-Host '  -DryRun   Compute names without creating branches or files'
    exit 0
}

. "$PSScriptRoot/common.ps1"
$repoRoot = Get-RepoRoot
$hasGit   = Test-HasGit
Set-Location $repoRoot

$specsDir = Join-Path $repoRoot 'specs'
if (-not $DryRun) { New-Item -ItemType Directory -Path $specsDir -Force | Out-Null }

function log([string]$msg) { Write-Host ('[feature] ' + $msg) -ForegroundColor DarkCyan }

function Get-UniqueBranchName([string]$base) {
    # ── Collect all existing branch names that start with $base (once) ───────
    $taken = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)
    if ($hasGit) {
        $ErrorActionPreference = 'Continue'
        git branch --list "$base*" 2>$null | ForEach-Object {
            if ($_) { $taken.Add($_.TrimStart('*', ' ').Trim()) | Out-Null }
        }
        git branch -r --list "*/$base*" 2>$null | ForEach-Object {
            if ($_) { $taken.Add(($_.Trim() -split '/')[-1]) | Out-Null }
        }
        $ErrorActionPreference = 'Stop'
    }

    # 1. Clean base name — preferred; keeps branch list readable
    if (-not $taken.Contains($base)) { return $base }
    # 2. Date suffix — clearly shows when the duplicate was created
    $ds = Get-Date -Format 'yyyyMMdd'
    $dc = "$base-$ds"
    if (-not $taken.Contains($dc)) { return $dc }
    # 3. Same-day counter
    $n = 2
    while ($true) { $c = "$base-$ds-$n"; if (-not $taken.Contains($c)) { return $c }; $n++ }
}

function Get-UniqueFolderName([string]$base) {
    # Folders are ALWAYS date-prefixed (YYYYMMDD-<name>) so `ls specs/` sorts
    # chronologically. Collect only dirs that share today's date prefix (once).
    $ds = Get-Date -Format 'yyyyMMdd'
    $prefix = "$ds-$base"

    $taken = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)
    if (Test-Path $specsDir) {
        Get-ChildItem -Path $specsDir -Directory -Filter "$prefix*" |
            ForEach-Object { $taken.Add($_.Name) | Out-Null }
    }

    # 1. Base date-prefixed name
    if (-not $taken.Contains($prefix)) { return $prefix }
    # 2. Counter suffix
    $n = 2
    while ($true) { $c = "$prefix-$n"; if (-not $taken.Contains($c)) { return $c }; $n++ }
}

function Invoke-SessionUpdate([string]$branchName, [string]$folderName) {
    $mgr = Join-Path $repoRoot '.spec/scripts/powershell/manage-session.ps1'
    if (-not (Test-Path $mgr)) { log 'manage-session.ps1 not found — skipping session update'; return }
    $patch = '{"branch_name":"' + $branchName + '","feature_dir":"specs/' + $folderName + '"}'
    $ErrorActionPreference = 'Continue'
    & $mgr -Action update-multi -JsonPatch $patch 2>$null
    $ErrorActionPreference = 'Stop'
    log ('Session updated: branch_name=' + $branchName + '  feature_dir=specs/' + $folderName)
}

function Write-Result([string]$branch, [string]$featDir) {
    if ($Json) {
        [PSCustomObject]@{
            BRANCH_NAME = $branch
            FEATURE_DIR = $featDir
            SPEC_FILE   = "$featDir/spec.md"
        } | ConvertTo-Json -Compress
    } else {
        Write-Output "BRANCH_NAME: $branch"
        Write-Output "FEATURE_DIR: $featDir"
        Write-Output "SPEC_FILE:   $featDir/spec.md"
    }
}

# ─── Read session.json ───────────────────────────────────────────────────────
$sessionFile = Join-Path $repoRoot '.spec/session.json'
if (-not (Test-Path $sessionFile)) {
    log 'No session.json found — run spec.session init first'; exit 1
}

try { $sess = Get-Content $sessionFile -Raw | ConvertFrom-Json }
catch { log 'ERROR: Could not parse session.json'; exit 1 }

$baseName = $sess.name
if ([string]::IsNullOrWhiteSpace($baseName)) {
    log 'session.json has no name — populate it before creating a feature'; exit 1
}
log ('Session name: ' + $baseName)

# Current git branch
$currentBranch = $null
if ($hasGit) {
    $ErrorActionPreference = 'Continue'
    try { $currentBranch = (git rev-parse --abbrev-ref HEAD 2>$null).Trim() } catch {}
    $ErrorActionPreference = 'Stop'
}
log ('Current git branch: ' + ($currentBranch ?? 'none'))

# ── Early-exit: session already resolved and environment matches ─────────────
if ($sess.branch_name -and $sess.feature_dir) {
    $existingDir = Join-Path $repoRoot $sess.feature_dir
    if ($currentBranch -eq $sess.branch_name -and (Test-Path $existingDir)) {
        log ('Already on branch ''' + $sess.branch_name + ''' with feature dir ''' + $sess.feature_dir + ''' — nothing to do')
        Write-Result $sess.branch_name $existingDir
        exit 0
    }
}

# ─── Fetch remote refs so branch availability check is accurate ─────────────
if ($hasGit -and -not $DryRun) {
    $ErrorActionPreference = 'Continue'
    git fetch --all --prune 2>$null | Out-Null
    $ErrorActionPreference = 'Stop'
}

# ─── Resolve unique branch name and unique folder name (independent) ─────────
$branchName = Get-UniqueBranchName $baseName
$folderName = Get-UniqueFolderName $baseName

if ($branchName -ne $baseName) { log ("Branch '$baseName' taken — using '$branchName'") }
log ("Folder name: $folderName")

$featureDir = Join-Path $specsDir $folderName
$specFile   = Join-Path $featureDir 'spec.md'

# ─── Create branch and spec dir ─────────────────────────────────────────────
if (-not $DryRun) {
    if ($hasGit) {
        log ("Creating git branch '$branchName'...")
        $ErrorActionPreference = 'Continue'
        git checkout -q -b $branchName 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            git checkout -q $branchName 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0) {
                $ErrorActionPreference = 'Stop'
                log ("ERROR: Failed to create or checkout '$branchName'"); exit 1
            }
            log ("Switched to existing branch '$branchName'")
        } else {
            log ("Branch '$branchName' created and checked out")
        }
        $ErrorActionPreference = 'Stop'
    } else {
        log 'No git repo — skipping branch creation'
    }

    New-Item -ItemType Directory -Path $featureDir -Force | Out-Null
    if (-not (Test-Path -PathType Leaf $specFile)) {
        $tmpl = Resolve-Template -TemplateName 'spec-template' -RepoRoot $repoRoot
        if ($tmpl -and (Test-Path $tmpl)) {
            Copy-Item $tmpl $specFile -Force
            log ('Spec file created from template: ' + $specFile)
        } else {
            New-Item -ItemType File -Path $specFile -Force | Out-Null
            log ('Spec file created (empty): ' + $specFile)
        }
    } else {
        log ('Spec file already exists: ' + $specFile)
    }

    Invoke-SessionUpdate $branchName $folderName
} else {
    log ('[dry-run] branch_name  → ' + $branchName)
    log ('[dry-run] feature_dir  → specs/' + $folderName)
    log ('[dry-run] Would create branch and spec dir, then update session')
}

Write-Result $branchName $featureDir

