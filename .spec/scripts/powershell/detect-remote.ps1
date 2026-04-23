#!/usr/bin/env pwsh
# Detect Git remote URL and parse GitHub owner/repo.
# Usage: detect-remote.ps1 [-Json]
# Exit code 0 always (graceful degradation when no remote).
param([switch]$Json)
$ErrorActionPreference = 'Stop'

function Write-NoRemote([string]$Reason) {
    if ($Json) { Write-Output "{`"has_remote`":false,`"is_github`":false,`"reason`":`"$Reason`"}" }
    else       { Write-Warning "[specify] $Reason" }
    exit 0
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-NoRemote "Git not found; cannot determine remote URL"
}

try {
    git rev-parse --is-inside-work-tree 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { throw }
} catch {
    Write-NoRemote "Not inside a Git repository; cannot determine remote URL"
}

$remoteUrl = git config --get remote.origin.url 2>$null
if (-not $remoteUrl) { Write-NoRemote "No remote.origin configured" }

$isGitHub = $false
$owner    = ""
$repo     = ""

# HTTPS: https://github.com/<owner>/<repo>[.git]
if ($remoteUrl -match '^https://github\.com/([^/]+)/([^/]+?)(?:\.git)?$') {
    $isGitHub = $true; $owner = $Matches[1]; $repo = $Matches[2]
# SSH: git@github.com:<owner>/<repo>[.git]
} elseif ($remoteUrl -match '^git@github\.com:([^/]+)/([^/]+?)(?:\.git)?$') {
    $isGitHub = $true; $owner = $Matches[1]; $repo = $Matches[2]
}

if ($Json) {
    $gh = if ($isGitHub) { "true" } else { "false" }
    Write-Output "{`"has_remote`":true,`"is_github`":$gh,`"remote_url`":`"$remoteUrl`",`"owner`":`"$owner`",`"repo`":`"$repo`"}"
} else {
    Write-Host "Remote URL: $remoteUrl"
    if ($isGitHub) { Write-Host "GitHub repository: $owner/$repo" }
}
