#!/usr/bin/env pwsh
# Standardized post-execution for any spec workflow agent:
#   1. Write artifact summary (what was produced)
#   2. Write artifact handoff (prompt/context for the next agent)
#   3. Mark artifact complete (cascades unblocking of downstream artifacts)
#
# Usage: post-agent.ps1 -ArtifactId plan -Summary "..." -Handoff "..."
#
# NOTE: Does NOT auto-commit. The calling agent must invoke the
#       spec.git.commit sub-agent separately — commit messages need AI.
param(
    [Parameter(Mandatory)][string]$ArtifactId,
    [string]$Summary = "",
    [string]$Handoff = ""
)
$ErrorActionPreference = 'Stop'

$manage = Join-Path $PSScriptRoot "manage-session.ps1"

if ($Summary) {
    & $manage -Action update-artifact -ArtifactId $ArtifactId -ArtifactField summary -ArtifactValue $Summary
}

if ($Handoff) {
    & $manage -Action update-artifact -ArtifactId $ArtifactId -ArtifactField handoff -ArtifactValue $Handoff
}

& $manage -Action complete-artifact -ArtifactId $ArtifactId
