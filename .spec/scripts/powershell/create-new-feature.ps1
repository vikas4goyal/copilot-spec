#!/usr/bin/env pwsh
# create-new-feature.ps1 — Create or switch to the feature branch for the active session.

[CmdletBinding()]
param(
    [switch]$Json,
    [switch]$DryRun,
    [string]$ShortName,
    [switch]$Timestamp,
    [switch]$Help,
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$FeatureDescription
)
$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host 'Usage: create-new-feature.ps1 [-Json] [-DryRun] [-Timestamp] [-ShortName <name>] <feature description>'
    Write-Host '  -Json          Output JSON ({BRANCH_NAME, SPEC_FILE, FEATURE_NUM})'
    Write-Host '  -DryRun        Compute names without creating branches or files'
    Write-Host '  -Timestamp     Use YYYYMMDD-HHmmss prefix instead of sequential numbering'
    Write-Host '  -ShortName     Override the generated slug (2-4 words, kebab-case)'
    exit 0
}

if (-not $FeatureDescription -or $FeatureDescription.Count -eq 0) {
    Write-Error 'Error: feature description is required.'; exit 1
}
$featureDesc = ($FeatureDescription -join ' ').Trim()
if ([string]::IsNullOrWhiteSpace($featureDesc)) {
    Write-Error 'Error: feature description cannot be empty.'; exit 1
}

# ─── Setup ───────────────────────────────────────────────────────────────────
. "$PSScriptRoot/common.ps1"
$repoRoot = Get-RepoRoot
$hasGit   = Test-HasGit
Set-Location $repoRoot

$specsDir = Join-Path $repoRoot 'specs'
if (-not $DryRun) { New-Item -ItemType Directory -Path $specsDir -Force | Out-Null }

# ─── Helpers ─────────────────────────────────────────────────────────────────
function log([string]$msg) { Write-Host ('[feature] ' + $msg) -ForegroundColor DarkCyan }

function ConvertTo-CleanSlug([string]$name) {
    $name.ToLower() -replace '[^a-z0-9]','-' -replace '-{2,}','-' -replace '^-','' -replace '-$',''
}

function Get-BranchSlug([string]$desc) {
    $stop = @('i','a','an','the','to','for','of','in','on','at','by','with','from',
              'is','are','was','were','be','been','being','have','has','had',
              'do','does','did','will','would','should','could','can','may','might','must','shall',
              'this','that','these','those','my','your','our','their','want','need','add','get','set')
    $words = ($desc.ToLower() -replace '[^a-z0-9]',' ') -split '\s+' | Where-Object { $_ }
    $kept  = @()
    foreach ($w in $words) {
        if ($stop -contains $w) { continue }
        if ($w.Length -ge 3)                             { $kept += $w; continue }
        if ($desc -match "\b$($w.ToUpper())\b")          { $kept += $w }
    }
    if ($kept.Count -gt 0) {
        $take = if ($kept.Count -eq 4) { 4 } else { 3 }
        return ($kept | Select-Object -First $take) -join '-'
    }
    $fallback = (ConvertTo-CleanSlug $desc) -split '-' | Where-Object { $_ } | Select-Object -First 3
    return $fallback -join '-'
}

function Get-HighestFromSpecs {
    [long]$h = 0
    if (Test-Path $specsDir) {
        Get-ChildItem -Path $specsDir -Directory | ForEach-Object {
            if ($_.Name -match '^(\d{3,})-' -and $_.Name -notmatch '^\d{8}-\d{6}-') {
                [long]$n = 0
                if ([long]::TryParse($matches[1],[ref]$n) -and $n -gt $h) { $h = $n }
            }
        }
    }
    return $h
}

function Get-HighestFromBranches {
    [long]$h = 0
    $ErrorActionPreference = 'Continue'
    $branches = git branch -a 2>$null
    $ErrorActionPreference = 'Stop'
    if ($LASTEXITCODE -eq 0 -and $branches) {
        $branches | ForEach-Object {
            $n = $_.Trim() -replace '^\*?\s+','' -replace '^remotes/[^/]+/',''
            if ($n -match '^(\d{3,})-' -and $n -notmatch '^\d{8}-\d{6}-') {
                [long]$num = 0
                if ([long]::TryParse($matches[1],[ref]$num) -and $num -gt $h) { $h = $num }
            }
        }
    }
    return $h
}

function Get-NextBranchNumber {
    if ($hasGit) {
        log 'Fetching remote branches to find next number...'
        $ErrorActionPreference = 'Continue'
        git fetch --all --prune 2>$null | Out-Null
        $ErrorActionPreference = 'Stop'
    }
    $hBranch = if ($hasGit) { Get-HighestFromBranches } else { 0 }
    $hSpec   = Get-HighestFromSpecs
    $max     = [Math]::Max($hBranch, $hSpec)
    log ('Highest existing number: ' + $max + ' next: ' + ($max+1))
    return $max + 1
}

function Invoke-SessionSync([string]$branch, [string]$featNum) {
    $mgr = Join-Path $repoRoot '.spec/scripts/powershell/manage-session.ps1'
    if (-not (Test-Path $mgr)) { log 'manage-session.ps1 not found — skipping session sync'; return }
    $patch = '{"branch_name":"' + $branch + '","feature_num":"' + $featNum + '","feature_dir":"specs/' + $branch + '"}'
    $ErrorActionPreference = 'Continue'
    & $mgr -Action update-multi -JsonPatch $patch 2>$null
    & $mgr -Action add-agent -AgentName 'spec.git.feature' 2>$null
    $ErrorActionPreference = 'Stop'
    log ('Session synced: branch_name=' + $branch + '  feature_num=' + $featNum + '  feature_dir=specs/' + $branch)
}

function Get-FeatureNumFromBranch([string]$name) {
    if ($name -match '^(\d{8}-\d{6}|\d{3,})-') { return $matches[1] }
    return $name
}

function Write-Result([string]$branch, [string]$featNum, [string]$featDir) {
    if ($Json) {
        [PSCustomObject]@{ BRANCH_NAME=$branch; SPEC_FILE="$featDir/spec.md"; FEATURE_NUM=$featNum } | ConvertTo-Json -Compress
    } else {
        Write-Output "BRANCH_NAME: $branch"
        Write-Output "SPEC_FILE:   $featDir/spec.md"
        Write-Output "FEATURE_NUM: $featNum"
    }
}

# ─── Session-first ───────────────────────────────────────────────────────────
$sessionFile   = Join-Path $repoRoot '.spec/session.json'
$sessionBranch = $null
$sess          = $null
if (Test-Path $sessionFile) {
    try { $sess = Get-Content $sessionFile -Raw | ConvertFrom-Json; $sessionBranch = $sess.branch_name } catch {}
    log ('Session found: branch_name=' + $sessionBranch)
} else {
    log 'No session.json found — will generate new branch'
}

$currentBranch = $null
if ($hasGit) {
    $ErrorActionPreference = 'Continue'
    try { $currentBranch = (git rev-parse --abbrev-ref HEAD 2>$null).Trim() } catch {}
    $ErrorActionPreference = 'Stop'
}
log ('Current git branch: ' + $currentBranch)

# Already on the correct branch — nothing to do
if ($sessionBranch -and $currentBranch -eq $sessionBranch) {
    log ('Already on session branch ' + $sessionBranch + ' - nothing to do')
    $fn = if ($sess -and $sess.feature_num) { $sess.feature_num } else { Get-FeatureNumFromBranch $sessionBranch }
    Write-Result $sessionBranch $fn (Join-Path $specsDir $sessionBranch)
    exit 0
}

# Session has a branch but we are not on it — create or checkout
if ($sessionBranch -and $currentBranch -ne $sessionBranch) {
    log ('Session branch ' + $sessionBranch + ' set; current is ' + $currentBranch + ' - switching')
    if ($hasGit -and -not $DryRun) {
        $ErrorActionPreference = 'Continue'
        git checkout -b $sessionBranch 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            git checkout $sessionBranch 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0) {
                $ErrorActionPreference = 'Stop'
        log ('ERROR: Failed to create or checkout ' + $sessionBranch)
                exit 1
            }
        }
        $ErrorActionPreference = 'Stop'
        log ('Switched to branch ' + $sessionBranch)
    } elseif ($DryRun) {
        log ('[dry-run] Would checkout/create branch ' + $sessionBranch)
    }
    $fn = Get-FeatureNumFromBranch $sessionBranch
    if (-not $DryRun) {
        New-Item -ItemType Directory -Path (Join-Path $specsDir $sessionBranch) -Force | Out-Null
        Invoke-SessionSync $sessionBranch $fn
    }
    Write-Result $sessionBranch $fn (Join-Path $specsDir $sessionBranch)
    exit 0
}

# ─── No session branch — generate new ────────────────────────────────────────
log 'No branch_name in session — generating new branch from description'

if ($ShortName) {
    $branchSuffix = ConvertTo-CleanSlug $ShortName
    log ('Using provided short name: ' + $branchSuffix)
} else {
    $branchSuffix = Get-BranchSlug $featureDesc
    log "Generated slug from description: '$branchSuffix'"
}

if ($Timestamp) {
    $featureNum = Get-Date -Format 'yyyyMMdd-HHmmss'
    log "Using timestamp prefix: $featureNum"
} else {
    $num        = Get-NextBranchNumber
    $featureNum = '{0:000}' -f $num
    log "Using sequential prefix: $featureNum"
}

$branchName = "$featureNum-$branchSuffix"

# Truncate if over GitHub's 244-byte limit
if ($branchName.Length -gt 244) {
    $maxSuffix    = 244 - $featureNum.Length - 1
    $branchSuffix = $branchSuffix.Substring(0, [Math]::Min($branchSuffix.Length, $maxSuffix)) -replace '-$',''
    log "WARNING: Branch name too long — truncated suffix to '$branchSuffix'"
    $branchName = "$featureNum-$branchSuffix"
}
log "New branch name: '$branchName'"

$featureDir = Join-Path $specsDir $branchName
$specFile   = Join-Path $featureDir 'spec.md'

if (-not $DryRun) {
    if ($hasGit) {
        log "Creating git branch '$branchName'..."
        $ErrorActionPreference = 'Continue'
        git checkout -q -b $branchName 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            $exists = git branch --list $branchName 2>$null
            if ($exists) {
                log "Branch '$branchName' already exists — switching to it"
                git checkout -q $branchName 2>$null | Out-Null
                if ($LASTEXITCODE -ne 0) { $ErrorActionPreference='Stop'; log "ERROR: Failed to switch to '$branchName'"; exit 1 }
            } else {
                $ErrorActionPreference = 'Stop'
                log "ERROR: Failed to create branch '$branchName'"
                exit 1
            }
        } else {
            log "Branch '$branchName' created and checked out"
        }
        $ErrorActionPreference = 'Stop'
    } else {
        log 'No git repo — skipping branch creation'
    }

    New-Item -ItemType Directory -Path $featureDir -Force | Out-Null
    if (-not (Test-Path -PathType Leaf $specFile)) {
        $tmpl = Resolve-Template -TemplateName 'spec-template' -RepoRoot $repoRoot
        if ($tmpl -and (Test-Path $tmpl)) {
            Copy-Item $tmpl $specFile -Force
            log ('Spec file created from template: ' + $specFile)
        } else {
            New-Item -ItemType File -Path $specFile -Force | Out-Null
            log ('Spec file created (empty - template not found): ' + $specFile)
        }
    } else {
        log ('Spec file already exists: ' + $specFile)
    }

    Invoke-SessionSync $branchName $featureNum
    $env:SPECIFY_FEATURE = $branchName
} else {
    log ('[dry-run] Would create branch ' + $branchName + ' and spec at ' + $specFile)
}

Write-Result $branchName $featureNum $featureDir
