#!/usr/bin/env pwsh
# Bootstrap a spec agent: init session, record agent, check dependencies — in one call.
# Usage: bootstrap-session.ps1 -AgentName spec.plan [-ArtifactId plan]
# Exit code 1 if deps are unmet.
param(
    [Parameter(Mandatory)][string]$AgentName,
    [string]$ArtifactId = ""
)
$ErrorActionPreference = 'Stop'

$manage = Join-Path $PSScriptRoot "manage-session.ps1"

& $manage -Action init
if ($LASTEXITCODE -ne 0) { exit 1 }

& $manage -Action add-agent -AgentName $AgentName
if ($LASTEXITCODE -ne 0) { exit 1 }

if ($ArtifactId) {
    & $manage -Action check-deps -ArtifactId $ArtifactId
    if ($LASTEXITCODE -ne 0) { exit 1 }
}
