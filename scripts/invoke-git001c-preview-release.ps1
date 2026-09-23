[CmdletBinding()]
param(
  [ValidateSet("Preflight", "ApplyMigrations")]
  [string]$Phase = "Preflight",
  [string]$ContractFile = ".release/git001c-preview-release.json",
  [string]$ExpectedHead = "",
  [string]$ResponsibleOperator = "",
  [string]$BackupId = "",
  [string]$BackupCompletedAtUtc = "",
  [ValidateSet("OFF")]
  [string]$PitrState = "OFF",
  [switch]$Execute
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Push-Location $repoRoot

function Invoke-Checked {
  param(
    [Parameter(Mandatory = $true)][string]$Program,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments
  )
  $output = & $Program @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "$Program $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
  }
  return @($output)
}

function Assert-CloudflareResponse {
  param(
    [Parameter(Mandatory = $true)][object]$Response,
    [Parameter(Mandatory = $true)][string]$Label
  )
  $properties = @($Response.PSObject.Properties.Name)
  if ($properties -notcontains "success" -or $Response.success -ne $true -or $properties -notcontains "result") {
    throw "HARD STOP: unexpected Cloudflare response for $Label"
  }
}

try {
  $contract = Get-Content $ContractFile -Raw | ConvertFrom-Json
  $head = ([string](Invoke-Checked git rev-parse HEAD | Select-Object -First 1)).Trim()
  $branch = ([string](Invoke-Checked git branch --show-current | Select-Object -First 1)).Trim()
  if ($branch -ne "git001c-astro-preview-build-20260922") {
    throw "HARD STOP: unexpected branch $branch"
  }

  $expectedMigrations = @($contract.supabase.migrations)
  $migrationFiles = @(Get-ChildItem supabase/migrations/*.sql |
    Where-Object { $_.BaseName -match '^202609(22180000|23060000|23070000|23080000|23100000|23110000|23120000)_' } |
    ForEach-Object { $_.BaseName.Substring(0, 14) })
  if (@(Compare-Object $expectedMigrations $migrationFiles).Count -ne 0) {
    throw "HARD STOP: local migration set differs from the release contract"
  }
  foreach ($functionName in @($contract.supabase.functions)) {
    if (-not (Test-Path "supabase/functions/$functionName/index.ts" -PathType Leaf)) {
      throw "HARD STOP: missing function entrypoint $functionName"
    }
  }

  $migrationState = (Invoke-Checked npx supabase migration list --linked) -join "`n" | ConvertFrom-Json
  $pendingMigrations = @($migrationState.migrations |
    Where-Object { $_.local -and -not $_.remote } |
    ForEach-Object { [string]$_.local })
  if (@(Compare-Object $expectedMigrations $pendingMigrations).Count -ne 0) {
    throw "HARD STOP: remote pending migration set differs from the reviewed contract"
  }

  $functionState = (Invoke-Checked npx supabase functions list --project-ref $contract.supabase.projectRef) -join "`n" | ConvertFrom-Json
  $deployedFunctions = @($functionState.functions | ForEach-Object { [string]$_.slug })
  $unexpectedPreviewFunctions = @($deployedFunctions | Where-Object { $_ -like "website-project-preview-*" })
  if ($unexpectedPreviewFunctions.Count -ne 0) {
    throw "HARD STOP: preview functions are already deployed: $($unexpectedPreviewFunctions -join ',')"
  }

  $backupState = (Invoke-Checked npx supabase backups list --project-ref $contract.supabase.projectRef --output-format json) -join "`n" | ConvertFrom-Json
  $completedBackups = @($backupState.backups |
    Where-Object { $_.status -eq "COMPLETED" } |
    Sort-Object { [datetimeoffset]$_.inserted_at } -Descending)
  if ($completedBackups.Count -eq 0) { throw "HARD STOP: no completed production backup is available" }
  $latestBackup = $completedBackups[0]
  $latestBackupCompleted = ([datetimeoffset]$latestBackup.inserted_at).ToUniversalTime()
  $currentPitrState = if ([bool]$backupState.pitr_enabled) { "ON" } else { "OFF" }

  $secretState = (Invoke-Checked npx supabase secrets list --project-ref $contract.supabase.projectRef --output json) -join "`n" | ConvertFrom-Json
  $secretNames = @($secretState | ForEach-Object { [string]$_.name })
  foreach ($name in @($contract.supabase.existingSecretNames)) {
    if ($secretNames -notcontains $name) { throw "HARD STOP: required existing secret name is absent: $name" }
    Write-Host "$name=PRESENT"
  }
  foreach ($name in @($contract.supabase.requiredPreviewBindingNames)) {
    if ($secretNames -contains $name) { throw "HARD STOP: preview binding is unexpectedly already present: $name" }
    Write-Host "$name=MISSING"
  }

  $tokenOutput = @(& npx wrangler auth token 2>&1)
  if ($LASTEXITCODE -ne 0) { throw "HARD STOP: Wrangler authentication is unavailable" }
  $tokenCandidates = @($tokenOutput | Where-Object { $_ -match '^[A-Za-z0-9._~-]{20,}$' })
  if ($tokenCandidates.Count -ne 1) { throw "HARD STOP: Wrangler token response was not recognized uniquely" }
  $cloudflareToken = [string]$tokenCandidates[0]
  $cloudflareHeaders = @{ Authorization = "Bearer $cloudflareToken" }
  $pagesBase = "https://api.cloudflare.com/client/v4/accounts/$($contract.cloudflare.accountId)/pages/projects/$($contract.cloudflare.projectName)"
  $pagesProject = Invoke-RestMethod -Method Get -Uri $pagesBase -Headers $cloudflareHeaders
  $pagesDeployments = Invoke-RestMethod -Method Get -Uri "$pagesBase/deployments" -Headers $cloudflareHeaders
  $pagesDomainState = Invoke-RestMethod -Method Get -Uri "$pagesBase/domains" -Headers $cloudflareHeaders
  $workerState = Invoke-RestMethod -Method Get -Uri "https://api.cloudflare.com/client/v4/accounts/$($contract.cloudflare.accountId)/workers/scripts" -Headers $cloudflareHeaders
  Assert-CloudflareResponse $pagesProject "Pages project"
  Assert-CloudflareResponse $pagesDeployments "Pages deployments"
  Assert-CloudflareResponse $pagesDomainState "Pages domains"
  Assert-CloudflareResponse $workerState "Worker scripts"
  $pagesDeploymentCount = @($pagesDeployments.result).Count
  $pagesDomains = @($pagesDomainState.result | ForEach-Object { [string]$_.name })
  $workerScripts = @($workerState.result | ForEach-Object { [string]$_.id })
    $sourcePresent = $pagesProject.result.PSObject.Properties.Name -contains "source" -and $null -ne $pagesProject.result.source
  if (-not $pagesProject.success -or $pagesProject.result.id -ne $contract.cloudflare.projectId -or
      $pagesProject.result.subdomain -ne $contract.cloudflare.pagesHostname -or $sourcePresent) {
    throw "HARD STOP: Pages project identity or empty source state differs from the contract"
  }
  if ($pagesDeploymentCount -ne 0 -or $pagesDomains.Count -ne 0) {
    throw "HARD STOP: Pages deployments or domains already exist"
  }
  if ($workerScripts.Count -ne 1 -or $workerScripts[0] -ne $contract.cloudflare.existingWorker) {
    throw "HARD STOP: Cloudflare Worker inventory changed"
  }

  $previewDns = Invoke-RestMethod -Uri "https://cloudflare-dns.com/dns-query?name=$($contract.cloudflare.customHostname)&type=CNAME" -Headers @{ Accept = "application/dns-json" }
  $previewDnsAnswers = @()
  if ($previewDns.PSObject.Properties.Name -contains "Answer") {
    $previewDnsAnswers = @($previewDns.Answer | Where-Object { $_ })
  }
  $previewDnsStatus = [int]$previewDns.Status
  if ($previewDnsStatus -ne 3 -or $previewDnsAnswers.Count -ne 0) {
    throw "HARD STOP: preview DNS is no longer NXDOMAIN without a CNAME"
  }

  Invoke-Checked npx supabase db push --linked --dry-run | ForEach-Object { Write-Host $_ }
  Write-Host "GIT001C_HEAD=$head"
  Write-Host "GIT001C_PENDING_MIGRATIONS=$($pendingMigrations -join ',')"
  Write-Host "GIT001C_DEPLOYED_PREVIEW_FUNCTIONS=NONE"
  Write-Host "GIT001C_LATEST_BACKUP_ID=$($latestBackup.id)"
  Write-Host "GIT001C_LATEST_BACKUP_COMPLETED_AT=$($latestBackupCompleted.ToString('o'))"
  Write-Host "GIT001C_PITR_STATE=$currentPitrState"
  Write-Host "GIT001C_PAGES_DEPLOYMENTS=$pagesDeploymentCount"
  Write-Host "GIT001C_PAGES_DOMAINS=$($pagesDomains.Count)"
  Write-Host "GIT001C_PREVIEW_DNS_STATUS=$previewDnsStatus"
  Write-Host "GIT001C_RELEASE_PREFLIGHT=PASS"

  if ($Phase -eq "ApplyMigrations" -and -not $Execute) {
    throw "HARD STOP: ApplyMigrations requires -Execute"
  }
  if ($Phase -eq "ApplyMigrations") {
    if ($ExpectedHead -notmatch '^[0-9a-f]{40}$' -or $ExpectedHead -ne $head) {
      throw "HARD STOP: -ExpectedHead must equal the reviewed HEAD"
    }
    if ([string]::IsNullOrWhiteSpace($ResponsibleOperator) -or [string]::IsNullOrWhiteSpace($BackupId)) {
      throw "HARD STOP: -ResponsibleOperator and -BackupId are required"
    }
    $backupCompleted = [datetimeoffset]::MinValue
    if (-not [datetimeoffset]::TryParse($BackupCompletedAtUtc, [ref]$backupCompleted)) {
      throw "HARD STOP: -BackupCompletedAtUtc must be a valid timestamp"
    }
    $providerBackupCompleted = $latestBackupCompleted
    if ($BackupId -ne [string]$latestBackup.id -or
        $backupCompleted.ToUniversalTime() -ne $providerBackupCompleted.ToUniversalTime()) {
      throw "HARD STOP: supplied backup evidence does not match the latest completed provider backup"
    }
    if ($PitrState -ne $currentPitrState) {
      throw "HARD STOP: supplied PITR state does not match the provider"
    }
    $backupAge = [datetimeoffset]::UtcNow - $backupCompleted.ToUniversalTime()
    if ($backupAge.TotalSeconds -lt 0 -or $backupAge.TotalHours -gt 24) {
      throw "HARD STOP: the completed backup must be no more than 24 hours old"
    }
    $worktree = @(Invoke-Checked git status --short)
    if ($worktree.Count -ne 0) {
      throw "HARD STOP: migration execution requires a clean worktree"
    }

    $checkpointRoot = Join-Path $repoRoot ".local-backups/git001c"
    New-Item -ItemType Directory -Path $checkpointRoot -Force | Out-Null
    $checkpointPath = Join-Path $checkpointRoot "recovery-before-migrations-$((Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')).json"
    [ordered]@{
      capturedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
      head = $head
      responsibleOperator = $ResponsibleOperator
      backupId = [string]$latestBackup.id
      backupCompletedAtUtc = $providerBackupCompleted.ToUniversalTime().ToString("o")
      pitrState = $currentPitrState
      projectRef = [string]$contract.supabase.projectRef
      pendingMigrations = $pendingMigrations
      deployedFunctions = $deployedFunctions
      customerRepositoryId = [string]$contract.customerSource.repositoryId
      customerCommit = [string]$contract.customerSource.commit
      pagesProjectId = [string]$contract.cloudflare.projectId
      pagesDeploymentCount = $pagesDeploymentCount
      pagesDomains = $pagesDomains
      workerScripts = $workerScripts
      previewDnsStatus = $previewDnsStatus
      previewCnameAnswers = $previewDnsAnswers
    } | ConvertTo-Json -Depth 4 | Set-Content -Path $checkpointPath -Encoding utf8
    Write-Host "RECOVERY_CHECKPOINT=$checkpointPath"

    Invoke-Checked npx supabase db push --linked | ForEach-Object { Write-Host $_ }
    $afterState = (Invoke-Checked npx supabase migration list --linked) -join "`n" | ConvertFrom-Json
    $remaining = @($afterState.migrations | Where-Object { $_.local -and -not $_.remote })
    if ($remaining.Count -ne 0) {
      throw "HARD STOP: migrations remain pending after db push"
    }
    Write-Host "GIT001C_MIGRATIONS_APPLIED=PASS"
  }
} finally {
  Pop-Location
}