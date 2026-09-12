[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("Local", "PreDeploy", "PostDeploy")]
  [string]$Phase,
  [string]$BeforeSnapshot = ".gate/dossiers-before.json",
  [string]$AfterSnapshot = ".gate/dossiers-after.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Push-Location $repoRoot

function Invoke-Node {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
  & node @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "node $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
  }
}

function Invoke-LocalGate {
  Invoke-Node --test scripts/dossier-continuity-regression-gate.test.mjs scripts/dossier-continuity-release-integration.test.mjs
  Invoke-Node scripts/dossier-continuity-regression-gate.mjs local
}

function Initialize-SnapshotPath {
  param([string]$Path)
  if (Test-Path $Path) {
    throw "snapshot already exists: $Path"
  }
  $parent = Split-Path -Parent $Path
  if ($parent -and -not (Test-Path $parent)) {
    New-Item -ItemType Directory -Path $parent | Out-Null
  }
}

try {
  switch ($Phase) {
    "Local" {
      Invoke-LocalGate
      Write-Host "DOSSIER_CONTINUITY_LOCAL_GATE=PASS"
    }
    "PreDeploy" {
      Invoke-LocalGate
      Initialize-SnapshotPath $BeforeSnapshot
      Invoke-Node scripts/dossier-continuity-regression-gate.mjs snapshot --output $BeforeSnapshot
      Write-Host "DOSSIER_CONTINUITY_PREDEPLOY=PASS"
    }
    "PostDeploy" {
      if (-not (Test-Path $BeforeSnapshot -PathType Leaf)) {
        throw "before snapshot is required: $BeforeSnapshot"
      }
      Initialize-SnapshotPath $AfterSnapshot
      Invoke-Node scripts/dossier-continuity-regression-gate.mjs smoke
      Invoke-Node scripts/dossier-continuity-regression-gate.mjs snapshot --output $AfterSnapshot
      Invoke-Node scripts/dossier-continuity-regression-gate.mjs compare --before $BeforeSnapshot --after $AfterSnapshot
      Write-Host "DOSSIER_CONTINUITY_POSTDEPLOY=PASS"
      Write-Host "PRODUCTION_RELEASE_ALLOWED=JA"
    }
  }
} catch {
  Write-Host "DOSSIER_CONTINUITY_RELEASE_GATE_ERROR=$($_.Exception.Message)"
  Write-Host "PRODUCTION_RELEASE_ALLOWED=NEE"
  throw
} finally {
  Pop-Location
}
