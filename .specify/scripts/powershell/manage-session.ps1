#!/usr/bin/env pwsh
# Manage the active spec session state file (.spec/session.json)
# Usage:
#   manage-session.ps1 -Action init
#   manage-session.ps1 -Action update -Field feature.branch_name -Value "001-my-feature"
#   manage-session.ps1 -Action update-multi -JsonPatch '{"feature":{"branch_name":"001-x","feature_num":"001"}}'
#   manage-session.ps1 -Action read
#   manage-session.ps1 -Action add-agent -AgentName "spec.constitution"
#   manage-session.ps1 -Action archive  (moves session.json to .spec/features/<feature-name>/)

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('init', 'update', 'update-multi', 'read', 'add-agent', 'archive')]
    [string]$Action,

    [string]$Field,
    [string]$Value,
    [string]$JsonPatch,
    [string]$AgentName,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/common.ps1"

$repoRoot = Get-RepoRoot
$sessionFile = Join-Path $repoRoot '.spec/session.json'
$templateFile = Join-Path $repoRoot '.spec/templates/session-state-template.json'

function Get-NewSessionId {
    # Generate a short unique ID: timestamp + random suffix
    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    $rand = -join ((65..90) + (97..122) | Get-Random -Count 4 | ForEach-Object { [char]$_ })
    return "$ts-$rand"
}

function Initialize-Session {
    if (Test-Path $sessionFile) {
        Write-Verbose "[session] Session file already exists at $sessionFile — skipping init."
        return (Get-Content $sessionFile -Raw | ConvertFrom-Json)
    }

    if (-not (Test-Path $templateFile)) {
        Write-Error "[session] Template not found at $templateFile. Cannot initialize session."
        exit 1
    }

    $session = Get-Content $templateFile -Raw | ConvertFrom-Json

    # Populate initial values
    $now = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    $session.session.id = Get-NewSessionId
    $session.session.created_at = $now
    $session.session.updated_at = $now
    $session.session.status = 'active'

    # Detect base branch from git
    if (Test-HasGit) {
        try {
            $base = (git -C $repoRoot rev-parse --abbrev-ref HEAD 2>$null).Trim()
            if ($base) { $session.git.base_branch = $base }
        } catch {}

        try {
            $remote = (git -C $repoRoot remote get-url origin 2>$null).Trim()
            if ($remote) { $session.git.remote_url = $remote }
        } catch {}

        try {
            $repo = (git -C $repoRoot rev-parse --show-toplevel 2>$null).Trim()
            if ($repo) { $session.git.repository = $repo }
        } catch {}
    }

    $session | ConvertTo-Json -Depth 10 | Set-Content $sessionFile -Encoding UTF8
    Write-Output "[session] Initialized session at $sessionFile (id: $($session.session.id))"
    return $session
}

function Set-DotNotation {
    param($Object, [string]$Path, $Value)
    $parts = $Path -split '\.'
    $current = $Object
    for ($i = 0; $i -lt $parts.Count - 1; $i++) {
        $current = $current.($parts[$i])
    }
    $current.($parts[-1]) = $Value
}

function Update-SessionField {
    param([string]$FieldPath, $FieldValue)

    if (-not (Test-Path $sessionFile)) {
        Initialize-Session | Out-Null
    }

    $session = Get-Content $sessionFile -Raw | ConvertFrom-Json
    Set-DotNotation -Object $session -Path $FieldPath -Value $FieldValue
    $session.session.updated_at = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    $session | ConvertTo-Json -Depth 10 | Set-Content $sessionFile -Encoding UTF8
    Write-Verbose "[session] Updated $FieldPath = $FieldValue"
    return $session
}

function Merge-JsonPatch {
    param($Target, $Patch)
    foreach ($prop in $Patch.PSObject.Properties) {
        if ($prop.Value -is [PSCustomObject] -and $Target.($prop.Name) -is [PSCustomObject]) {
            Merge-JsonPatch -Target $Target.($prop.Name) -Patch $prop.Value
        } else {
            $Target.($prop.Name) = $prop.Value
        }
    }
}

function Add-AgentToSession {
    param([string]$Agent)

    if (-not (Test-Path $sessionFile)) {
        Initialize-Session | Out-Null
    }

    $session = Get-Content $sessionFile -Raw | ConvertFrom-Json
    $now = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')

    $entry = [PSCustomObject]@{ agent = $Agent; ran_at = $now }
    $list = @($session.workflow.agents_run) + $entry
    $session.workflow.agents_run = $list
    $session.workflow.current_agent = $Agent
    $session.session.updated_at = $now
    $session | ConvertTo-Json -Depth 10 | Set-Content $sessionFile -Encoding UTF8
    Write-Verbose "[session] Recorded agent '$Agent' in session."
    return $session
}

function Archive-Session {
    if (-not (Test-Path $sessionFile)) {
        Write-Warning "[session] No active session file found at $sessionFile"
        return
    }

    $session = Get-Content $sessionFile -Raw | ConvertFrom-Json
    $featureName = $session.feature.branch_name

    if ([string]::IsNullOrWhiteSpace($featureName)) {
        # Fallback: use session ID
        $featureName = $session.session.id
        Write-Warning "[session] feature.branch_name not set; archiving under session id: $featureName"
    }

    # Sanitize folder name
    $safeName = $featureName -replace '[^a-zA-Z0-9\-_.]', '-'
    $archiveDir = Join-Path $repoRoot ".spec/features/$safeName"
    New-Item -ItemType Directory -Path $archiveDir -Force | Out-Null

    # Mark session as completed
    $session.session.status = 'completed'
    $session.session.updated_at = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    $session | ConvertTo-Json -Depth 10 | Set-Content $sessionFile -Encoding UTF8

    $dest = Join-Path $archiveDir 'session.json'
    Move-Item $sessionFile $dest -Force
    Write-Output "[session] Archived session to $dest"
}

# ---------------------------------------------------------------------------
switch ($Action) {
    'init' {
        $result = Initialize-Session
        if ($Json) { $result | ConvertTo-Json -Depth 10 }
    }
    'update' {
        if (-not $Field) { Write-Error "-Field is required for 'update' action"; exit 1 }
        $result = Update-SessionField -FieldPath $Field -FieldValue $Value
        if ($Json) { $result | ConvertTo-Json -Depth 10 }
    }
    'update-multi' {
        if (-not $JsonPatch) { Write-Error "-JsonPatch is required for 'update-multi' action"; exit 1 }
        if (-not (Test-Path $sessionFile)) { Initialize-Session | Out-Null }
        $session = Get-Content $sessionFile -Raw | ConvertFrom-Json
        $patch = $JsonPatch | ConvertFrom-Json
        Merge-JsonPatch -Target $session -Patch $patch
        $session.session.updated_at = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
        $session | ConvertTo-Json -Depth 10 | Set-Content $sessionFile -Encoding UTF8
        Write-Output "[session] Applied JSON patch to session."
        if ($Json) { $session | ConvertTo-Json -Depth 10 }
    }
    'read' {
        if (-not (Test-Path $sessionFile)) {
            Write-Warning "[session] No active session file found."
        } else {
            Get-Content $sessionFile -Raw
        }
    }
    'add-agent' {
        if (-not $AgentName) { Write-Error "-AgentName is required for 'add-agent' action"; exit 1 }
        $result = Add-AgentToSession -Agent $AgentName
        if ($Json) { $result | ConvertTo-Json -Depth 10 }
    }
    'archive' {
        Archive-Session
    }
}
