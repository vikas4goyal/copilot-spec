#!/usr/bin/env pwsh
# Standardized pre-execution session step for a spec workflow agent:
#   1. Bootstrap session (init + add-agent + check-deps)
#   2. Mark this agent's artifact as in_progress
#
# Call order inside the agent:
#   1. spec.git.initialize sub-agent  (ensures repo exists)
#   2. spec.git.commit    sub-agent  (commits any pending pre-agent work)
#   3. pre-agent.ps1      (THIS)     (marks the session step started)
#
# Usage: pre-agent.ps1 -AgentName spec.plan -ArtifactId plan
param(
    [Parameter(Mandatory)][string]$AgentName,
    [string]$ArtifactId = ""
)
$ErrorActionPreference = 'Stop'

# 1. Bootstrap session (init + add-agent + check-deps)
if ($ArtifactId) {
    & (Join-Path $PSScriptRoot "bootstrap-session.ps1") -AgentName $AgentName -ArtifactId $ArtifactId
} else {
    & (Join-Path $PSScriptRoot "bootstrap-session.ps1") -AgentName $AgentName
}
if ($LASTEXITCODE -ne 0) { exit 1 }

# 2. Mark artifact in_progress
if ($ArtifactId) {
    & (Join-Path $PSScriptRoot "manage-session.ps1") `
        -Action update-artifact `
        -ArtifactId $ArtifactId `
        -ArtifactField status `
        -ArtifactValue in_progress
}

$suffix = if ($ArtifactId) { " (artifact: $ArtifactId)" } else { "" }
Write-Host "[pre-agent] Session ready: $AgentName$suffix"
