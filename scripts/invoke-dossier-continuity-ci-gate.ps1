[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("PreDeploy", "PostDeploy")]
  [string]$Phase,
  [string]$BeforeSnapshot = ".gate/dossiers-before.json",
  [string]$AfterSnapshot = ".gate/dossiers-after.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$productionSupabaseUrl = "https://xcsptvntvrizwhskaphr.supabase.co"
$gateScript = Join-Path $PSScriptRoot "invoke-dossier-continuity-release-gate.ps1"
$email = $null
$password = $null
$publishableKey = $null
$authBody = $null
$authResponse = $null
$accessToken = $null

function Get-JwtExpiry {
  param([Parameter(Mandatory = $true)][string]$Token)

  $parts = @($Token.Split("."))
  if ($parts.Count -ne 3 -or $parts | Where-Object { [string]::IsNullOrWhiteSpace($_) }) {
    throw "RELEASE_SMOKE_ACCESS_TOKEN_INVALID"
  }

  $payload = $parts[1].Replace("-", "+").Replace("_", "/")
  switch ($payload.Length % 4) {
    0 { }
    2 { $payload += "==" }
    3 { $payload += "=" }
    default { throw "RELEASE_SMOKE_ACCESS_TOKEN_INVALID" }
  }

  try {
    $claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json
    $expiry = [long]$claims.exp
  } catch {
    throw "RELEASE_SMOKE_ACCESS_TOKEN_INVALID"
  }
  if ($expiry -le 0) { throw "RELEASE_SMOKE_ACCESS_TOKEN_INVALID" }
  return $expiry
}

try {
  $email = [string]$env:LWS_RELEASE_SMOKE_EMAIL
  $password = [string]$env:LWS_RELEASE_SMOKE_PASSWORD
  $publishableKey = [string]$env:LWS_SUPABASE_PUBLISHABLE_KEY

  if ([string]::IsNullOrWhiteSpace($email)) { throw "LWS_RELEASE_SMOKE_EMAIL_REQUIRED" }
  if ([string]::IsNullOrWhiteSpace($password)) { throw "LWS_RELEASE_SMOKE_PASSWORD_REQUIRED" }
  if ([string]::IsNullOrWhiteSpace($publishableKey)) { throw "LWS_SUPABASE_PUBLISHABLE_KEY_REQUIRED" }
  if ($publishableKey -match "(?i)service_role|secret") { throw "LWS_SUPABASE_PUBLISHABLE_KEY_INVALID" }

  $authBody = @{ email = $email; password = $password } | ConvertTo-Json -Compress
  try {
    $authResponse = Invoke-RestMethod `
      -Method Post `
      -Uri "$productionSupabaseUrl/auth/v1/token?grant_type=password" `
      -Headers @{ apikey = $publishableKey } `
      -ContentType "application/json" `
      -Body $authBody
  } catch {
    throw "RELEASE_SMOKE_AUTH_FAILED"
  }

  $accessToken = [string]$authResponse.access_token
  if ([string]::IsNullOrWhiteSpace($accessToken) -or $accessToken.Length -lt 100) {
    throw "RELEASE_SMOKE_ACCESS_TOKEN_INVALID"
  }
  $expiry = Get-JwtExpiry -Token $accessToken
  $minimumExpiry = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 300
  if ($expiry -le $minimumExpiry) { throw "RELEASE_SMOKE_ACCESS_TOKEN_EXPIRES_TOO_SOON" }

  $env:LWS_SUPABASE_ANON_KEY = $publishableKey
  $env:LWS_OPERATOR_JWT = $accessToken

  & $gateScript `
    -Phase $Phase `
    -BeforeSnapshot $BeforeSnapshot `
    -AfterSnapshot $AfterSnapshot
  if ($LASTEXITCODE -ne 0) { throw "DOSSIER_CONTINUITY_GATE_FAILED" }

  Write-Host "DOSSIER_CONTINUITY_CI_GATE=PASS"
} catch {
  $failureMessage = $_.Exception.Message
  $safeCode = switch -Regex ($failureMessage) {
    "^(LWS_RELEASE_SMOKE_EMAIL_REQUIRED|LWS_RELEASE_SMOKE_PASSWORD_REQUIRED|LWS_SUPABASE_PUBLISHABLE_KEY_REQUIRED|LWS_SUPABASE_PUBLISHABLE_KEY_INVALID|RELEASE_SMOKE_AUTH_FAILED|RELEASE_SMOKE_ACCESS_TOKEN_INVALID|RELEASE_SMOKE_ACCESS_TOKEN_EXPIRES_TOO_SOON|DOSSIER_CONTINUITY_GATE_FAILED)$" { $failureMessage; break }
    default { "DOSSIER_CONTINUITY_CI_GATE_FAILED" }
  }
  Write-Host "DOSSIER_CONTINUITY_CI_GATE_ERROR=$safeCode"
  Write-Host "PRODUCTION_RELEASE_ALLOWED=NEE"
  throw $safeCode
} finally {
  Remove-Item Env:LWS_OPERATOR_JWT -ErrorAction SilentlyContinue
  Remove-Item Env:LWS_SUPABASE_ANON_KEY -ErrorAction SilentlyContinue
  Remove-Item Env:LWS_RELEASE_SMOKE_EMAIL -ErrorAction SilentlyContinue
  Remove-Item Env:LWS_RELEASE_SMOKE_PASSWORD -ErrorAction SilentlyContinue
  $accessToken = $null
  $authResponse = $null
  $authBody = $null
  $password = $null
  $email = $null
  $publishableKey = $null
}
