#!/usr/bin/env pwsh
# create-new-feature.ps1 — Create or switch to the feature branch defined in session.json.
# Reads branch_name from session.json. If that branch already exists, appends -v1, -v2, ...
# and updates session.json with the actual name used.

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

function Test-LocalBranchExists([string]$name) {
    $ErrorActionPreference = 'Continue'
    $r = git branch --list $name 2>$null
    $ErrorActionPreference = 'Stop'
    return ($null -ne $r -and $r.Trim() -ne '')
}

function Test-RemoteBranchExists([string]$name) {
    $ErrorActionPreference = 'Continue'
    $r = git branch -r --list "*/$name" 2>$null
    $ErrorActionPreference = 'Stop'
    return ($null -ne $r -and $r.Trim() -ne '')
}

function Get-AvailableBranchName([string]$base) {
    if (-not (Test-LocalBranchExists $base) -and -not (Test-RemoteBranchExists $base)) {
        return $base
    }
    $v = 1
    while ($true) {
        $candidate = "$base-v$v"
        if (-not (Test-LocalBranchExists $candidate) -and -not (Test-RemoteBranchExists $candidate)) {
            return $candidate
        }
        $v++
    }
}

function Invoke-SessionUpdate([string]$branch) {
    $mgr = Join-Path $repoRoot '.spec/scripts/powershell/manage-session.ps1'
    if (-not (Test-Path $mgr)) { log 'manage-session.ps1 not found — skipping session update'; return }
    $patch = '{"branch_name":"' + $branch + '","feature_dir":"specs/' + $branch + '"}'
    $ErrorActionPreference = 'Continue'
    & $mgr -Action update-multi -JsonPatch $patch 2>$null
    $ErrorActionPreference = 'Stop'
    log ('Session updated: branch_name=' + $branch + '  feature_dir=specs/' + $branch)
}

function Write-Result([string]$branch, [string]$featDir) {
    if ($Json) {
        [PSCustomObject]@{ BRANCH_NAME = $branch; SPEC_FILE = "$featDir/spec.md" } | ConvertTo-Json -Compress
    } else {
        Write-Output "BRANCH_NAME: $branch"
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

$sessionBranch = $sess.branch_name
if ([string]::IsNullOrWhiteSpace($sessionBranch)) {
    log 'session.json has no branch_name — populate it before creating a branch'; exit 1
}

log ('Session branch_name: ' + $sessionBranch)

# Current git branch
$currentBranch = $null
if ($hasGit) {
    $ErrorActionPreference = 'Continue'
    try { $currentBranch = (git rev-parse --abbrev-ref HEAD 2>$null).Trim() } catch {}
    $ErrorActionPreference = 'Stop'
}
log ('Current git branch: ' + ($currentBranch ?? 'none'))

# Already on the correct branch — nothing to do
if ($currentBranch -eq $sessionBranch) {
    log ('Already on session branch ' + $sessionBranch + ' — nothing to do')
    Write-Result $sessionBranch (Join-Path $specsDir $sessionBranch)
    exit 0
}

# ─── Find an available branch name ──────────────────────────────────────────
if ($hasGit -and -not $DryRun) {
    $ErrorActionPreference = 'Continue'
    git fetch --all --prune 2>$null | Out-Null
    $ErrorActionPreference = 'Stop'
    $branchName = Get-AvailableBranchName $sessionBranch
} else {
    $branchName = $sessionBranch
}

if ($branchName -ne $sessionBranch) {
    log ("Branch '$sessionBranch' exists — using '$branchName'")
}

$featureDir = Join-Path $specsDir $branchName
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

    Invoke-SessionUpdate $branchName
} else {
    log ('[dry-run] Would create branch ' + $branchName + ' and spec at ' + $specFile)
}

Write-Result $branchName $featureDir