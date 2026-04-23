#!/usr/bin/env pwsh
# create-new-feature.ps1 — Bootstrap a new feature: derives branch/folder names,
# creates the git branch and specs/YYYYMMDD-<name>/ directory, and keeps
# session.json in sync — entirely via manage-session.ps1 (no direct file access).
#
# Naming conventions
#   branch  : <name>  →  <name>-YYYYMMDD  →  <name>-YYYYMMDD-2 …
#   folder  : YYYYMMDD-<name>  →  YYYYMMDD-<name>-2 …  (date-prefix for dir sorting)
#
# Usage:
#   create-new-feature.ps1 -Name "oauth2-login" -Description "Implements OAuth2 login" [-AgentName "spec.specify"] [-Json] [-DryRun]

[CmdletBinding()]
param(
    [string]$Name,
    [string]$Description,
    [string]$AgentName,
    [switch]$Json,
    [switch]$DryRun,
    [switch]$Help
)
$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: create-new-feature.ps1 -Name <slug> -Description <desc> [-AgentName <agent>] [-Json] [-DryRun]'
    Write-Host '  -Name         Feature name slug (e.g. oauth2-login-google)'
    Write-Host '  -Description  One-line feature description'
    Write-Host '  -AgentName    Calling agent to record in session (e.g. spec.specify)'
    Write-Host '  -Json         Output JSON ({BRANCH_NAME, FEATURE_DIR, SPEC_FILE})'
    Write-Host '  -DryRun       Compute names without creating branches or files'
    exit 0
}

. "$PSScriptRoot/common.ps1"
$repoRoot = Get-RepoRoot
$hasGit   = Test-HasGit
Set-Location $repoRoot

$specsDir = Join-Path $repoRoot 'specs'
$mgrPs    = Join-Path $repoRoot '.spec/scripts/powershell/manage-session.ps1'

if (-not (Test-Path $mgrPs)) {
    Write-Host '[feature] ERROR: manage-session.ps1 not found.' -ForegroundColor Red; exit 1
}

if (-not $DryRun) { New-Item -ItemType Directory -Path $specsDir -Force | Out-Null }

function log([string]$msg) { Write-Host ('[feature] ' + $msg) -ForegroundColor DarkCyan }

# ─── Thin wrapper so callers always get a clean exit-code check ──────────────
function Invoke-Session([hashtable]$Params) {
    & $mgrPs @Params
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

# ─── Branch / folder naming ───────────────────────────────────────────────────

function Get-UniqueBranchName([string]$base) {
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
    if (-not $taken.Contains($base)) { return $base }
    $ds = Get-Date -Format 'yyyyMMdd'
    $dc = "$base-$ds"
    if (-not $taken.Contains($dc)) { return $dc }
    $n = 2
    while ($true) { $c = "$base-$ds-$n"; if (-not $taken.Contains($c)) { return $c }; $n++ }
}

function Get-UniqueFolderName([string]$base) {
    $ds     = Get-Date -Format 'yyyyMMdd'
    $prefix = "$ds-$base"
    $taken  = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)
    if (Test-Path $specsDir) {
        Get-ChildItem -Path $specsDir -Directory -Filter "$prefix*" |
            ForEach-Object { $taken.Add($_.Name) | Out-Null }
    }
    if (-not $taken.Contains($prefix)) { return $prefix }
    $n = 2
    while ($true) { $c = "$prefix-$n"; if (-not $taken.Contains($c)) { return $c }; $n++ }
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

# ─── Session bootstrap ────────────────────────────────────────────────────────

if (-not $DryRun) {
    # Step 1: Init — creates session from template (or reuses existing).
    #         Passes name/description so they are written on creation, or filled
    #         in non-destructively if the session already exists but has blanks.
    $initArgs = @{ Action = 'init' }
    if (-not [string]::IsNullOrWhiteSpace($Name))        { $initArgs['Name']        = $Name }
    if (-not [string]::IsNullOrWhiteSpace($Description)) { $initArgs['Description'] = $Description }
    Invoke-Session $initArgs
}

# Step 2: Read current session values via manage-session (captures stdout JSON)
$baseName    = $null
$sessBranch  = $null
$sessFeatDir = $null

$ErrorActionPreference = 'Continue'
$sessRaw = & $mgrPs -Action get-multi -Fields 'name,branch_name,feature_dir' 2>$null
$ErrorActionPreference = 'Stop'

if ($sessRaw) {
    try {
        $sessData    = $sessRaw | ConvertFrom-Json
        $baseName    = $sessData.name
        $sessBranch  = $sessData.branch_name
        $sessFeatDir = $sessData.feature_dir
    } catch { <# session may not exist in dry-run; handled below #> }
}

# In dry-run (no session created), still honour the -Name param
if ([string]::IsNullOrWhiteSpace($baseName)) { $baseName = $Name }
if ([string]::IsNullOrWhiteSpace($baseName)) {
    if ($DryRun) { log 'ERROR: No active session and -Name not provided. Pass -Name <slug> for dry-run.' }
    else         { log 'ERROR: Feature name is not set. Pass -Name <slug> to provide one.' }
    exit 1
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

# ── Idempotency / consistency check ──────────────────────────────────────────
if ($sessBranch -and $sessFeatDir) {
    $existingDir = Join-Path $repoRoot $sessFeatDir

    if ($currentBranch -eq $sessBranch -and (Test-Path $existingDir)) {
        log ('Already on branch ''' + $sessBranch + ''' with feature dir ''' + $sessFeatDir + ''' — nothing to do')
        Write-Result $sessBranch $existingDir
        exit 0
    }

    if ($currentBranch -ne $sessBranch) {
        log ('ERROR: Session expects branch ''' + $sessBranch + ''' but the current git branch is ''' + $currentBranch + '''.')
        log ('       Switch to the correct branch  →  git checkout ' + $sessBranch)
        log ('       Or release the current feature first  →  /spec.release')
        exit 1
    }
    # branch matches but folder is missing — fall through and re-create
}

# ─── Fetch remote refs so branch availability check is accurate ──────────────
if ($hasGit -and -not $DryRun) {
    $ErrorActionPreference = 'Continue'
    git fetch --all --prune 2>$null | Out-Null
    $ErrorActionPreference = 'Stop'
}

# ─── Resolve unique branch name and folder name ───────────────────────────────
$branchName = Get-UniqueBranchName $baseName
$folderName = Get-UniqueFolderName $baseName

if ($branchName -ne $baseName) { log ("Branch '$baseName' taken — using '$branchName'") }
log ("Folder name: $folderName")

$featureDir = Join-Path $specsDir $folderName
$specFile   = Join-Path $featureDir 'spec.md'

# ─── Create branch and spec dir ──────────────────────────────────────────────
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

    # ── Write branch_name and feature_dir back to session ────────────────────
    $patch = '{"branch_name":"' + $branchName + '","feature_dir":"specs/' + $folderName + '"}'
    Invoke-Session @{ Action = 'update-multi'; JsonPatch = $patch }

    # ── Record calling agent (if provided) ───────────────────────────────────
    if (-not [string]::IsNullOrWhiteSpace($AgentName)) {
        Invoke-Session @{ Action = 'add-agent'; AgentName = $AgentName }
    }

    log ('Session updated: branch_name=' + $branchName + '  feature_dir=specs/' + $folderName)
} else {
    log ('[dry-run] branch_name  → ' + $branchName)
    log ('[dry-run] feature_dir  → specs/' + $folderName)
    log ('[dry-run] Would create session.json (if needed), branch and spec dir')
}

Write-Result $branchName $featureDir
