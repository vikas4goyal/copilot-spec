#!/usr/bin/env pwsh
# auto-commit.ps1
# Stage all changes and commit with the message supplied by the caller (spec.git.commit agent).
#
# Usage: auto-commit.ps1 -CommitMessage "<subject line>\n\n<body>"

param(
    [Parameter(Mandatory = $true)]
    [string]$CommitMessage
)

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/common.ps1"

$repoRoot = Get-RepoRoot
Set-Location $repoRoot

# Require git
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Warning '[auto-commit] Git not found; skipping commit.'
    exit 0
}

# Require a git repo
$ErrorActionPreference = 'Continue'
git rev-parse --is-inside-work-tree 2>$null | Out-Null
$ErrorActionPreference = 'Stop'
if ($LASTEXITCODE -ne 0) {
    Write-Warning '[auto-commit] Not a Git repository; skipping commit.'
    exit 0
}

# Nothing to commit?
$ErrorActionPreference = 'Continue'
git diff --quiet HEAD 2>$null;          $d1 = $LASTEXITCODE
git diff --cached --quiet 2>$null;     $d2 = $LASTEXITCODE
$untracked = git ls-files --others --exclude-standard 2>$null
$ErrorActionPreference = 'Stop'

if ($d1 -eq 0 -and $d2 -eq 0 -and -not $untracked) {
    Write-Host '[auto-commit] Nothing to commit.' -ForegroundColor DarkGray
    exit 0
}

# Stage and commit
$ErrorActionPreference = 'Continue'
try {
    $out = git add . 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "git add failed: $out" }

    $out = git commit -m $CommitMessage 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "git commit failed: $out" }

    Write-Host '[auto-commit] Committed successfully.' -ForegroundColor Green
} catch {
    Write-Warning ('[auto-commit] Error: ' + $_)
    exit 1
} finally {
    $ErrorActionPreference = 'Stop'
}
