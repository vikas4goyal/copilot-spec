#!/usr/bin/env pwsh
# Manage the active spec session state file (.spec/session.json)
#
# Usage:
#   manage-session.ps1 -Action init [-Name "oauth2-login"] [-Description "..."]
#   manage-session.ps1 -Action get -Field name
#   manage-session.ps1 -Action get-multi -Fields "name,branch_name,feature_dir"
#   manage-session.ps1 -Action update -Field name -Value "oauth2-login-google"
#   manage-session.ps1 -Action update-multi -JsonPatch '{"name":"oauth2-login-google","description":"Implements OAuth2 login with Google."}'
#   manage-session.ps1 -Action read
#   manage-session.ps1 -Action add-agent -AgentName "spec.specify"
#   manage-session.ps1 -Action complete-artifact -ArtifactId "specify"
#   manage-session.ps1 -Action update-artifact -ArtifactId "specify" -ArtifactField "summary" -ArtifactValue "Generated spec for login flow."
#   manage-session.ps1 -Action update-artifact -ArtifactId "specify" -ArtifactField "handoff" -ArtifactValue "Feature: OAuth2 login, mobile-first, React stack."
#   manage-session.ps1 -Action skip-artifact -ArtifactId "clarify"
#   manage-session.ps1 -Action check-deps -ArtifactId "plan"
#   manage-session.ps1 -Action archive

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('init','get','get-multi','update','update-multi','read','add-agent','archive',
                 'complete-artifact','update-artifact','skip-artifact','check-deps')]
    [string]$Action,

    # For init (optional — set fields on creation / fill missing on resume)
    [string]$Name,
    [string]$Description,

    # For get / get-multi
    [string]$Fields,          # comma-separated dot-notation paths, e.g. "name,branch_name,feature_dir"

    # For update / update-multi
    [string]$Field,
    [string]$Value,
    [string]$JsonPatch,

    # For add-agent
    [string]$AgentName,

    # For artifact actions
    [string]$ArtifactId,
    [string]$ArtifactField,
    [string]$ArtifactValue,

    [switch]$Json
)

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/common.ps1"

$repoRoot    = Get-RepoRoot
$sessionFile = Join-Path $repoRoot '.spec/session.json'
$templateFile= Join-Path $repoRoot '.spec/templates/session-state-template.json'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Get-NewSessionId {
    $ts   = Get-Date -Format 'yyyyMMdd-HHmmss'
    $rand = -join ((65..90) + (97..122) | Get-Random -Count 4 | ForEach-Object { [char]$_ })
    return "$ts-$rand"
}

function Read-Session {
    return (Get-Content $sessionFile -Raw | ConvertFrom-Json)
}

function Save-Session($session) {
    $session.updated_at = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    $session | ConvertTo-Json -Depth 20 | Set-Content $sessionFile -Encoding UTF8
}

function Set-DotNotation {
    param($Object, [string]$Path, $Value)
    $parts   = $Path -split '\.'
    $current = $Object
    for ($i = 0; $i -lt $parts.Count - 1; $i++) { $current = $current.($parts[$i]) }
    $current.($parts[-1]) = $Value
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

# Recalculate pipeline.next_recommended after any artifact status change
function Update-PipelineNext($session) {
    $completedId = $session.pipeline.last_completed
    # First: find a required artifact that is ready (not the one just completed)
    $nextArtifact = $session.artifacts |
        Where-Object { $_.status -eq 'ready' -and $_.required -eq $true -and $_.id -ne $completedId } |
        Select-Object -First 1
    # Fallback: any ready artifact
    if (-not $nextArtifact) {
        $nextArtifact = $session.artifacts |
            Where-Object { $_.status -eq 'ready' -and $_.id -ne $completedId } |
            Select-Object -First 1
    }
    $session.pipeline.next_recommended = if ($nextArtifact) { $nextArtifact.command } else { $null }
}

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

function Initialize-Session {
    if (-not (Test-Path $sessionFile)) {
        if (-not (Test-Path $templateFile)) {
            Write-Error ('[session] Template not found at ' + $templateFile + '. Cannot initialize session.')
            exit 1
        }
        $session            = Get-Content $templateFile -Raw | ConvertFrom-Json
        $now                = Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ'
        $session.id         = Get-NewSessionId
        $session.created_at = $now
        $session.updated_at = $now
        $session.status     = 'active'
        # Apply name/description if provided at creation time
        if (-not [string]::IsNullOrWhiteSpace($Name))        { $session.name        = $Name }
        if (-not [string]::IsNullOrWhiteSpace($Description)) { $session.description = $Description }
        $session | ConvertTo-Json -Depth 20 | Set-Content $sessionFile -Encoding UTF8
        Write-Host ('[session] Initialized session at ' + $sessionFile + ' (id: ' + $session.id + ')') -ForegroundColor Green
        return $session
    }

    # Session already exists — reuse, but fill missing name/description non-destructively
    Write-Host ('[session] Session already exists — reusing.') -ForegroundColor DarkGray
    $session = Read-Session
    $changed = $false
    if (-not [string]::IsNullOrWhiteSpace($Name) -and [string]::IsNullOrWhiteSpace($session.name)) {
        $session.name = $Name; $changed = $true
    }
    if (-not [string]::IsNullOrWhiteSpace($Description) -and [string]::IsNullOrWhiteSpace($session.description)) {
        $session.description = $Description; $changed = $true
    }
    if ($changed) {
        Save-Session $session
        Write-Host '[session] Applied missing name/description to existing session.' -ForegroundColor DarkGray
    }
    return $session
}

# ---------------------------------------------------------------------------
# Get a single field value by dot-notation path (outputs raw value to stdout)
# ---------------------------------------------------------------------------
function Get-FieldValue([string]$FieldPath) {
    if (-not (Test-Path $sessionFile)) {
        Write-Host '[session] No active session.' -ForegroundColor Yellow; return
    }
    $session = Read-Session
    $parts   = $FieldPath -split '\.'
    $current = $session
    foreach ($p in $parts) {
        if ($null -eq $current) { $current = $null; break }
        $current = $current.$p
    }
    if ($null -ne $current) { Write-Output $current.ToString() }
    else                    { Write-Output '' }
}

# ---------------------------------------------------------------------------
# Get multiple field values by comma-separated dot-notation paths (outputs JSON)
# ---------------------------------------------------------------------------
function Get-MultiValues([string]$FieldPaths) {
    if (-not (Test-Path $sessionFile)) {
        Write-Host '[session] No active session.' -ForegroundColor Yellow
        Write-Output '{}'
        return
    }
    $session = Read-Session
    $result  = [ordered]@{}
    foreach ($rawPath in ($FieldPaths -split ',')) {
        $path    = $rawPath.Trim()
        $parts   = $path -split '\.'
        $current = $session
        foreach ($p in $parts) {
            if ($null -eq $current) { $current = $null; break }
            $current = $current.$p
        }
        $result[$path] = $current
    }
    $result | ConvertTo-Json -Compress | Write-Output
}

function Update-SessionField([string]$FieldPath, $FieldValue) {
    if (-not (Test-Path $sessionFile)) { Initialize-Session | Out-Null }
    $session = Read-Session
    Set-DotNotation -Object $session -Path $FieldPath -Value $FieldValue
    Save-Session $session
    Write-Host ('[session] Updated ' + $FieldPath) -ForegroundColor DarkGray
    return $session
}

function Add-AgentToSession([string]$Agent) {
    if (-not (Test-Path $sessionFile)) { Initialize-Session | Out-Null }
    $session = Read-Session
    $now     = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    $entry   = [PSCustomObject]@{ agent = $Agent; ran_at = $now }
    $session.pipeline.agents_run    = @($session.pipeline.agents_run) + $entry
    $session.pipeline.current_agent = $Agent
    Save-Session $session
    Write-Host ('[session] Recorded agent ''' + $Agent + ''' in session.') -ForegroundColor DarkGray
    return $session
}

function Complete-Artifact([string]$Id) {
    if (-not (Test-Path $sessionFile)) {
        Write-Error '[session] No active session. Run ''init'' first.'; exit 1
    }
    $session = Read-Session
    $now     = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')

    # Find the artifact
    $artifact = $session.artifacts | Where-Object { $_.id -eq $Id }
    if (-not $artifact) {
        Write-Error ('[session] Artifact ''' + $Id + ''' not found in session.'); exit 1
    }

    # Mark it complete
    $artifact.status      = 'complete'
    $artifact.completedAt = $now
    $handoff              = $artifact.handoff

    # Cascade: remove $Id from missingDeps of every other artifact
    foreach ($a in $session.artifacts) {
        if ($a.missingDeps -contains $Id) {
            $a.missingDeps = @($a.missingDeps | Where-Object { $_ -ne $Id })
            if ($a.missingDeps.Count -eq 0 -and $a.status -eq 'pending') {
                $a.status = 'ready'
            }
        }
    }

    # Update pipeline tracking
    $session.pipeline.last_completed  = $Id
    $session.pipeline.current_agent   = $null

    # Propagate handoff as next_prompt
    if ($handoff) { $session.pipeline.next_prompt = $handoff }

    Update-PipelineNext $session

    # isComplete: all required artifacts done or skipped?
    $requiredPending = $session.artifacts |
        Where-Object { $_.required -eq $true -and $_.status -notin @('complete','skipped') }
    $session.isComplete = ($requiredPending.Count -eq 0)


    Save-Session $session
    Write-Host ('[session] Artifact ''' + $Id + ''' marked complete. Next: ' + $session.pipeline.next_recommended) -ForegroundColor Green
    return $session
}

function Update-Artifact([string]$Id, [string]$Field, [string]$FieldValue) {
    if (-not (Test-Path $sessionFile)) {
        Write-Error '[session] No active session. Run ''init'' first.'; exit 1
    }
    $validFields = @('summary','handoff','status','outputPath')
    if ($Field -notin $validFields) {
        Write-Error ('[session] Invalid ArtifactField ''' + $Field + '''. Valid: ' + ($validFields -join ', ')); exit 1
    }
    $session  = Read-Session
    $artifact = $session.artifacts | Where-Object { $_.id -eq $Id }
    if (-not $artifact) {
        Write-Error ('[session] Artifact ''' + $Id + ''' not found.'); exit 1
    }
    $artifact.$Field = $FieldValue
    Save-Session $session
    Write-Host ('[session] Artifact ''' + $Id + '''.' + $Field + ' updated.') -ForegroundColor DarkGray
    return $session
}

function Skip-Artifact([string]$Id) {
    if (-not (Test-Path $sessionFile)) {
        Write-Error '[session] No active session. Run ''init'' first.'; exit 1
    }
    $session  = Read-Session
    $artifact = $session.artifacts | Where-Object { $_.id -eq $Id }
    if (-not $artifact) {
        Write-Error ('[session] Artifact ''' + $Id + ''' not found.'); exit 1
    }
    if ($artifact.required -eq $true) {
        Write-Warning ('[session] Artifact ''' + $Id + ''' is marked required. Skipping it may break downstream steps.')
    }

    $artifact.status      = 'skipped'
    $artifact.completedAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')

    # Cascade same as complete so dependents unblock
    foreach ($a in $session.artifacts) {
        if ($a.missingDeps -contains $Id) {
            $a.missingDeps = @($a.missingDeps | Where-Object { $_ -ne $Id })
            if ($a.missingDeps.Count -eq 0 -and $a.status -eq 'pending') {
                $a.status = 'ready'
            }
        }
    }

    $session.pipeline.last_completed = $Id
    Update-PipelineNext $session

    $requiredPending = $session.artifacts |
        Where-Object { $_.required -eq $true -and $_.status -notin @('complete','skipped') }
    $session.isComplete = ($requiredPending.Count -eq 0)

    Save-Session $session
    Write-Host ('[session] Artifact ''' + $Id + ''' skipped. Next: ' + $session.pipeline.next_recommended) -ForegroundColor Yellow
    return $session
}

function Test-ArtifactDeps([string]$Id) {
    if (-not (Test-Path $sessionFile)) {
        Write-Error '[session] No active session.'; exit 1
    }
    $session  = Read-Session
    $artifact = $session.artifacts | Where-Object { $_.id -eq $Id }
    if (-not $artifact) {
        Write-Error ('[session] Artifact ''' + $Id + ''' not found.'); exit 1
    }

    if ($artifact.missingDeps.Count -eq 0) {
        Write-Host ('[session] ''' + $Id + ''' is ready - all dependencies met.') -ForegroundColor Green
        return $true
    }

    Write-Warning ('[session] ''' + $Id + ''' is blocked. Missing dependencies:')
    foreach ($dep in $artifact.missingDeps) {
        $depArt = $session.artifacts | Where-Object { $_.id -eq $dep }
        $cmd    = if ($depArt) { $depArt.command } else { $dep }
        Write-Host "  → Run $cmd first  (id: $dep)" -ForegroundColor Yellow
    }
    return $false
}

function Archive-Session {
    if (-not (Test-Path $sessionFile)) {
        Write-Warning ('[session] No active session file found at ' + $sessionFile); return
    }
    $session     = Read-Session
    $featureName = if ($session.branch_name) { $session.branch_name }
                   elseif ($session.name)    { $session.name }
                   else                      { $null }
    if ([string]::IsNullOrWhiteSpace($featureName)) {
        $featureName = $session.id
        Write-Warning '[session] branch_name and name not set; archiving under session id'
    }
    $safeName   = $featureName -replace '[^a-zA-Z0-9\-_.]', '-'
    $archiveDir = Join-Path $repoRoot ".spec/features/$safeName"
    New-Item -ItemType Directory -Path $archiveDir -Force | Out-Null

    $session.status     = 'completed'
    $session.updated_at = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    $session | ConvertTo-Json -Depth 20 | Set-Content $sessionFile -Encoding UTF8

    $dest = Join-Path $archiveDir 'session.json'
    Move-Item $sessionFile $dest -Force
    Write-Host ('[session] Archived session to ' + $dest) -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
switch ($Action) {
    'init' {
        $result = Initialize-Session
        if ($Json) { $result | ConvertTo-Json -Depth 20 }
    }
    'get' {
        if (-not $Field -and -not $Fields) { Write-Error "-Field (or -Fields) is required for 'get'"; exit 1 }
        Get-FieldValue -FieldPath ($Field ?? $Fields)
    }
    'get-multi' {
        if (-not $Fields) { Write-Error "-Fields is required for 'get-multi'"; exit 1 }
        Get-MultiValues -FieldPaths $Fields
    }
    'update' {
        if (-not $Field) { Write-Error "-Field is required for 'update'"; exit 1 }
        $result = Update-SessionField -FieldPath $Field -FieldValue $Value
        if ($Json) { $result | ConvertTo-Json -Depth 20 }
    }
    'update-multi' {
        if (-not $JsonPatch) { Write-Error "-JsonPatch is required for 'update-multi'"; exit 1 }
        if (-not (Test-Path $sessionFile)) { Initialize-Session | Out-Null }
        $session = Read-Session
        Merge-JsonPatch -Target $session -Patch ($JsonPatch | ConvertFrom-Json)
        Save-Session $session
        Write-Host '[session] Applied JSON patch to session.' -ForegroundColor DarkGray
        if ($Json) { $session | ConvertTo-Json -Depth 20 }
    }
    'read' {
        if (-not (Test-Path $sessionFile)) { Write-Warning '[session] No active session file.' }
        else { Get-Content $sessionFile -Raw }
    }
    'add-agent' {
        if (-not $AgentName) { Write-Error "-AgentName is required for 'add-agent'"; exit 1 }
        $result = Add-AgentToSession -Agent $AgentName
        if ($Json) { $result | ConvertTo-Json -Depth 20 }
    }
    'complete-artifact' {
        if (-not $ArtifactId) { Write-Error "-ArtifactId is required for 'complete-artifact'"; exit 1 }
        $result = Complete-Artifact -Id $ArtifactId
        if ($Json) { $result | ConvertTo-Json -Depth 20 }
    }
    'update-artifact' {
        if (-not $ArtifactId)    { Write-Error "-ArtifactId is required for 'update-artifact'";    exit 1 }
        if (-not $ArtifactField) { Write-Error "-ArtifactField is required for 'update-artifact'"; exit 1 }
        $result = Update-Artifact -Id $ArtifactId -Field $ArtifactField -FieldValue $ArtifactValue
        if ($Json) { $result | ConvertTo-Json -Depth 20 }
    }
    'skip-artifact' {
        if (-not $ArtifactId) { Write-Error "-ArtifactId is required for 'skip-artifact'"; exit 1 }
        $result = Skip-Artifact -Id $ArtifactId
        if ($Json) { $result | ConvertTo-Json -Depth 20 }
    }
    'check-deps' {
        if (-not $ArtifactId) { Write-Error "-ArtifactId is required for 'check-deps'"; exit 1 }
        Test-ArtifactDeps -Id $ArtifactId | Out-Null
    }
    'archive' {
        Archive-Session
    }
}
