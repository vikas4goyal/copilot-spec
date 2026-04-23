#!/usr/bin/env pwsh
# Git extension: auto-commit.ps1
# Automatically stage and commit all changes using a pre-composed commit message.
# The commit message is passed directly by the caller (e.g., the spec.git.commit agent),
# which analyzes the actual git diff and selects the appropriate conventional-commit prefix.
#
# Usage: auto-commit.ps1 -CommitMessage "<message>"
#   e.g.: auto-commit.ps1 -CommitMessage "feat: implement JWT-based user authentication"
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [string]$CommitMessage
)
$ErrorActionPreference = 'Stop'

function Find-ProjectRoot {
    param([string]$StartDir)
    $current = Resolve-Path $StartDir
    while ($true) {
        foreach ($marker in @('.specify', '.spec', '.git')) {
            if (Test-Path (Join-Path $current $marker)) {
                return $current
            }
        }
        $parent = Split-Path $current -Parent
        if ($parent -eq $current) { return $null }
        $current = $parent
    }
}

$repoRoot = Find-ProjectRoot -StartDir $PSScriptRoot
if (-not $repoRoot) { $repoRoot = Get-Location }
Set-Location $repoRoot

# Check if git is available
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Warning "[specify] Warning: Git not found; skipped auto-commit"
    exit 0
}

try {
    git rev-parse --is-inside-work-tree 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "not a repo" }
} catch {
    Write-Warning "[specify] Warning: Not a Git repository; skipped auto-commit"
    exit 0
}

# Check if there are changes to commit
$diffHead = git diff --quiet HEAD 2>$null; $d1 = $LASTEXITCODE
$diffCached = git diff --cached --quiet 2>$null; $d2 = $LASTEXITCODE
$untracked = git ls-files --others --exclude-standard 2>$null

if ($d1 -eq 0 -and $d2 -eq 0 -and -not $untracked) {
    Write-Host "[specify] No changes to commit" -ForegroundColor DarkGray
    exit 0
}

# Stage and commit using the provided message
try {
    $out = git add . 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "git add failed: $out" }
    $out = git commit -q -m $CommitMessage 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "git commit failed: $out" }
} catch {
    Write-Warning "[specify] Error: $_"
    exit 1
}

Write-Host "✓ Committed: $CommitMessage"
