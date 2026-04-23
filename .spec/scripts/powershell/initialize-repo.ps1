#!/usr/bin/env pwsh
# Git extension: initialize-repo.ps1
# Initialize a Git repository with an initial commit.
# Customizable — replace this script to add .gitignore templates,
# default branch config, git-flow, LFS, signing, etc.
$ErrorActionPreference = 'Stop'

function Write-Log {
    param([string]$Message)
    Write-Host "[spec] $Message"
}

# Find project root
function Find-ProjectRoot {
    param([string]$StartDir)
    Write-Log "Searching for project root from: $StartDir"
    $current = Resolve-Path $StartDir
    while ($true) {
        Write-Log "Inspecting directory for project markers: $current"
        foreach ($marker in @('.spec', '.git')) {
            if (Test-Path (Join-Path $current $marker)) {
                Write-Log "Found project marker '$marker' in: $current"
                return $current
            }
        }
        $parent = Split-Path $current -Parent
        if ($parent -eq $current) {
            Write-Log "Reached filesystem root without finding a project marker"
            return $null
        }
        $current = $parent
    }
}

$repoRoot = Find-ProjectRoot -StartDir $PSScriptRoot
if (-not $repoRoot) {
    Write-Log "Project root not found from script path; falling back to current working directory"
    $repoRoot = Get-Location
} else {
    Write-Log "Using discovered project root: $repoRoot"
}
Set-Location $repoRoot
Write-Log "Changed working directory to: $repoRoot"

# Read commit message from extension config, fall back to default
$commitMsg = "[Spec] Initial commit"
# $configFile = Join-Path $repoRoot ".spec/git-config.yml"
# if (Test-Path $configFile) {
#     Write-Log "Found git config file: $configFile"
#     $messageFound = $false
#     foreach ($line in Get-Content $configFile) {
#         if ($line -match '^init_commit_message:\s*(.+)$') {
#             $messageFound = $true
#             $val = $matches[1].Trim() -replace '^["'']' -replace '["'']$'
#             if ($val) {
#                 $commitMsg = $val
#                 Write-Log "Using init commit message from config"
#             } else {
#                 Write-Log "Config init commit message was empty; using default message"
#             }
#             Write-Log "Stopping config scan after locating init_commit_message entry"
#             break
#         }
#     }
#     if (-not $messageFound) {
#         Write-Log "Config file did not define init_commit_message; using default message"
#     }
# } else {
#     Write-Log "Git config file not found; using default commit message"
# }
Write-Log "Final commit message: $commitMsg"

# Check if git is available
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Log "Git executable not found; exiting without initializing repository"
    Write-Warning "[spec] Warning: Git not found; skipped repository initialization"
    exit 0
}
Write-Log "Git executable found"

# Check if already a git repo
try {
    Write-Log "Checking whether current directory is already inside a Git work tree"
    git rev-parse --is-inside-work-tree 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Log "Repository already initialized; exiting early"
        Write-Warning "[spec] Git repository already initialized; skipping"
        exit 0
    }
    Write-Log "Current directory is not an initialized Git repository"
} catch {
    Write-Log "git rev-parse check raised an exception; continuing with initialization"
}

# Initialize
try {
    Write-Log "Running: git init -q"
    $out = git init -q 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "git init failed: $out" }
    Write-Log "git init completed successfully"
    Write-Log "Running: git add ."
    $out = git add . 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "git add failed: $out" }
    Write-Log "git add completed successfully"
    Write-Log "Running: git commit --allow-empty -q -m <message>"
    $out = git commit --allow-empty -q -m $commitMsg 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "git commit failed: $out" }
    Write-Log "git commit completed successfully"
} catch {
    Write-Log "Repository initialization failed; exiting with error"
    Write-Warning "[spec] Error: $_"
    exit 1
}

Write-Log "Repository initialization flow completed"
Write-Host "[OK] Git repository initialized"
