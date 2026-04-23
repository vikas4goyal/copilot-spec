#!/usr/bin/env pwsh
# Finalize a spec feature release: push branch + archive session + (optionally) switch to base.
# Usage: release-feature.ps1 [-StayOnBranch]
# Does NOT commit — assumes the caller (spec.release agent) has already committed.
param([switch]$StayOnBranch)
$ErrorActionPreference = 'Stop'

$scriptRoot  = $PSScriptRoot
$repoRoot    = Split-Path (Split-Path $scriptRoot -Parent) -Parent
$sessionFile = Join-Path $repoRoot ".spec/session.json"

if (-not (Test-Path $sessionFile)) {
    Write-Warning "[release] No active session found. Nothing to release."
    exit 0
}

$session = Get-Content $sessionFile -Raw | ConvertFrom-Json

# Resolve branch_name and base_branch (support both flat and nested)
$branchName = $session.branch_name
if (-not $branchName -and $session.feature) { $branchName = $session.feature.branch_name }
$baseBranch = $null
if ($session.git) { $baseBranch = $session.git.base_branch }

if (-not $branchName) {
    Write-Error "[release] Could not determine branch_name from session.json"
    exit 1
}

$hasGit = $false
if (Get-Command git -ErrorAction SilentlyContinue) {
    try {
        git -C $repoRoot rev-parse --is-inside-work-tree 2>$null | Out-Null
        $hasGit = ($LASTEXITCODE -eq 0)
    } catch { $hasGit = $false }
}

# Push to origin
if ($hasGit) {
    $remoteUrl = git -C $repoRoot config --get remote.origin.url 2>$null
    if ($remoteUrl) {
        Write-Host "[release] Pushing branch: $branchName"
        git -C $repoRoot push origin $branchName --set-upstream
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "[release] Push failed; continuing with archive"
        }
    } else {
        Write-Host "[release] No remote 'origin' found — skipping push. Branch is available locally only."
    }
} else {
    Write-Host "[release] Git not available — skipping push."
}

# Archive session
& (Join-Path $scriptRoot "manage-session.ps1") -Action archive

# Switch to base branch
if (-not $StayOnBranch -and $baseBranch -and $baseBranch -ne $branchName -and $hasGit) {
    git -C $repoRoot checkout $baseBranch
    if ($LASTEXITCODE -eq 0) { Write-Host "[release] Switched to base branch: $baseBranch" }
}

$baseDisplay = if ($baseBranch) { $baseBranch } else { "<none>" }
Write-Host "[release] Done. Branch: $branchName  Base: $baseDisplay"
