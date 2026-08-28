[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$ScopeFile,
  [string]$ContractFile = ".release/production-preservation.json",
  [ValidateSet("PrePublication", "PostPublication")]
  [string]$AuthorityMode = "PrePublication",
  [switch]$SkipFetch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Push-Location $repoRoot

function Invoke-Git {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
  $output = & git @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "git $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
  }
  return @($output)
}

function Test-PathPattern {
  param([string]$Path, [string[]]$Patterns)
  foreach ($pattern in $Patterns) {
    $wildcard = [System.Management.Automation.WildcardPattern]::new(
      $pattern,
      [System.Management.Automation.WildcardOptions]::IgnoreCase
    )
    if ($wildcard.IsMatch($Path)) { return $true }
  }
  return $false
}

try {
  $contract = Get-Content $ContractFile -Raw | ConvertFrom-Json
  $scope = Get-Content $ScopeFile -Raw | ConvertFrom-Json
  $remote = $contract.productionAuthority.remote
  $branch = $contract.productionAuthority.branch
  $remoteRef = "refs/remotes/$remote/$branch"

  if (-not $SkipFetch) {
    & git -c gc.auto=0 fetch $remote $branch
    if ($LASTEXITCODE -ne 0) { throw "HARD STOP: fetch $remote $branch failed" }
  }

  $remoteSha = ([string](Invoke-Git rev-parse $remoteRef | Select-Object -First 1)).Trim()
  $remoteListing = [string](Invoke-Git ls-remote $remote "refs/heads/$branch" | Select-Object -First 1)
  $trueRemoteSha = ($remoteListing -split "\s+")[0]
  if ($remoteSha -ne $trueRemoteSha) {
    throw "HARD STOP: fetched $remoteRef ($remoteSha) differs from true remote main ($trueRemoteSha)"
  }

  $baseSha = [string]$scope.baseRemoteMainSha
  $releaseSha = if ($scope.PSObject.Properties.Name -contains "releaseSha") { [string]$scope.releaseSha } else { "" }
  $authoritySha = $baseSha
  $diffTarget = "HEAD"

  if ($AuthorityMode -eq "PostPublication") {
    if ([string]::IsNullOrWhiteSpace($releaseSha)) {
      throw "HARD STOP: post-publication mode requires scope releaseSha"
    }
    Invoke-Git rev-parse --verify "$releaseSha^{commit}" | Out-Null
    $releaseParent = ([string](Invoke-Git rev-parse "$releaseSha^" | Select-Object -First 1)).Trim()
    $releaseMergeBase = ([string](Invoke-Git merge-base $baseSha $releaseSha | Select-Object -First 1)).Trim()
    if ($releaseParent -ne $baseSha -or $releaseMergeBase -ne $baseSha) {
      throw "HARD STOP: release $releaseSha is not the single forward commit from base $baseSha"
    }
    $headReleaseMergeBase = ([string](Invoke-Git merge-base HEAD $releaseSha | Select-Object -First 1)).Trim()
    if ($headReleaseMergeBase -ne $releaseSha) {
      throw "HARD STOP: HEAD does not contain published release $releaseSha"
    }
    $authoritySha = $releaseSha
    $diffTarget = $releaseSha
  }

  if ($authoritySha -ne $remoteSha) {
    throw "HARD STOP: $AuthorityMode authority $authoritySha is not current remote main $remoteSha"
  }

  $mergeBase = ([string](Invoke-Git merge-base $baseSha $diffTarget | Select-Object -First 1)).Trim()
  $behindCount = [int](Invoke-Git rev-list --count "HEAD..$remoteRef" | Select-Object -First 1)
  if ($mergeBase -ne $baseSha -or $behindCount -ne 0) {
    throw "HARD STOP: release is not forward-only from historical base $baseSha"
  }

  $committed = Invoke-Git diff --name-only "$baseSha..$diffTarget"
  $staged = Invoke-Git diff --cached --name-only
  $unstaged = Invoke-Git diff --name-only
  $untracked = Invoke-Git ls-files --others --exclude-standard
  $changedPaths = @($committed + $staged + $unstaged + $untracked | Where-Object { $_ } | Sort-Object -Unique)
  $allowedPatterns = @($scope.allowedPaths)
  $protectedPatterns = @($contract.protectedSurfaces | ForEach-Object { $_.paths })
  $generatedPatterns = @($contract.generatedArtifactPatterns)

  $unexpected = @($changedPaths | Where-Object { -not (Test-PathPattern $_ $allowedPatterns) })
  $protectedChanged = @($changedPaths | Where-Object { Test-PathPattern $_ $protectedPatterns })
  $protectedUnexpected = @($protectedChanged | Where-Object { -not (Test-PathPattern $_ @($scope.protectedChanges)) })
  $generatedChanged = @($changedPaths | Where-Object { Test-PathPattern $_ $generatedPatterns })
  $generatedUnexpected = @($generatedChanged | Where-Object { -not (Test-PathPattern $_ @($scope.generatedArtifactChanges)) })

  Write-Host "PRODUCTION_AUTHORITY=$remoteSha"
  Write-Host "AUTHORITY_MODE=$AuthorityMode"
  Write-Host "HISTORICAL_RELEASE_BASE=$baseSha"
  if ($releaseSha) { Write-Host "PUBLISHED_RELEASE=$releaseSha" }
  Write-Host "RELEASE_MERGE_BASE=$mergeBase"
  Write-Host "EXACT_DIFF_BEGIN"
  & git diff --no-ext-diff "$baseSha..$diffTarget" --
  Write-Host "EXACT_DIFF_END"
  Write-Host "STAGED_FILES_BEGIN"
  $staged | ForEach-Object { Write-Host $_ }
  Write-Host "STAGED_FILES_END"
  Write-Host "UNTRACKED_FILES_BEGIN"
  $untracked | ForEach-Object { Write-Host $_ }
  Write-Host "UNTRACKED_FILES_END"
  Write-Host "UNEXPECTED_FILES=$($unexpected.Count)"
  Write-Host "PROTECTED_UNEXPECTED_CHANGES=$($protectedUnexpected.Count)"
  Write-Host "GENERATED_ARTIFACT_VIOLATIONS=$($generatedUnexpected.Count)"

  & git diff --check "$baseSha..$diffTarget"
  if ($LASTEXITCODE -ne 0) { throw "HARD STOP: git diff --check failed" }

  if ($scope.historicalSourceUse.used -and [string]::IsNullOrWhiteSpace($scope.historicalSourceUse.forwardPortProof)) {
    throw "HARD STOP: historical source use lacks forward-port preservation proof"
  }
  if ($unexpected.Count -ne 0) {
    throw "HARD STOP: unexpected files: $($unexpected -join ', ')"
  }
  if ($protectedUnexpected.Count -ne 0) {
    throw "HARD STOP: protected changes were not explicitly declared: $($protectedUnexpected -join ', ')"
  }
  if ($generatedUnexpected.Count -ne 0) {
    throw "HARD STOP: generated artifacts were not explicitly declared: $($generatedUnexpected -join ', ')"
  }

  Write-Host "PRE_RELEASE_GATE=PASS"
} finally {
  Pop-Location
}
