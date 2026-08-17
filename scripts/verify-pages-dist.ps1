[CmdletBinding()]
param(
  [string]$DistDir = "dist",
  [string]$ExpectedFunctionsBaseUrl = "https://xcsptvntvrizwhskaphr.supabase.co/functions/v1",
  [string]$ReportPath = "dist-verification-report.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir "..")
$distPath = Join-Path $repoRoot $DistDir

if (-not (Test-Path $distPath -PathType Container)) {
  throw "Dist directory not found: $distPath"
}

$requiredRootEntries = @(
  "index.html",
  "404.html",
  "assets",
  "operator",
  "pages",
  "robots.txt",
  "sitemap.xml",
  "site.webmanifest"
)

$forbiddenPublicPaths = @(
  "pages/404.html",
  "pages/project-1.html",
  "pages/project-2.html",
  "pages/project-3.html",
  "pages/project-4.html",
  "pages/project-5.html",
  "pages/project-6.html",
  "pages/redesign-preview"
)

$denyPathRegexes = @(
  '(^|[\\/])supabase([\\/]|$)',
  '(^|[\\/])docs([\\/]|$)',
  '(^|[\\/])backup([\\/]|$)',
  '(^|[\\/])\.git([\\/]|$)',
  '(^|[\\/])\.github([\\/]|$)',
  '(^|[\\/])node_modules([\\/]|$)'
)

$denyFileRegexes = @(
  '(?i)^\.env($|\.)',
  '(?i)\.sql$',
  '(?i)\.ts$',
  '(?i)\.md$',
  '(?i)^README\.md$',
  '(?i)\.zip$',
  '(?i)\.log$',
  '(?i)\.toml$',
  '(?i)^package(-lock)?\.json$'
)

$missingRequired = @()
foreach ($entry in $requiredRootEntries) {
  if (-not (Test-Path (Join-Path $distPath $entry))) {
    $missingRequired += $entry
  }
}

$publishedLegacyPaths = @()
foreach ($entry in $forbiddenPublicPaths) {
  if (Test-Path (Join-Path $distPath $entry)) {
    $publishedLegacyPaths += $entry
  }
}

$allEntries = Get-ChildItem -Path $distPath -Recurse -Force
$forbidden = @()
foreach ($item in $allEntries) {
  $relative = $item.FullName.Substring($distPath.Length).TrimStart([char[]]"\\/")
  if ([string]::IsNullOrWhiteSpace($relative)) { continue }

  foreach ($pathRegex in $denyPathRegexes) {
    if ($relative -match $pathRegex) {
      $forbidden += "Path denied: $relative"
      break
    }
  }

  if (-not $item.PSIsContainer) {
    $name = $item.Name
    foreach ($fileRegex in $denyFileRegexes) {
      if ($name -match $fileRegex) {
        $forbidden += "File denied: $relative"
        break
      }
    }
  }
}

$htmlFiles = Get-ChildItem -Path $distPath -Filter *.html -Recurse -File
$brokenLinks = @()

function Resolve-LocalTarget {
  param(
    [string]$HtmlFullName,
    [string]$RawUrl
  )

  $url = $RawUrl.Trim()
  if ([string]::IsNullOrWhiteSpace($url)) { return $null }
  if ($url.StartsWith("#")) { return $null }

  $lower = $url.ToLowerInvariant()
  if (
    $lower.StartsWith("http://") -or
    $lower.StartsWith("https://") -or
    $lower.StartsWith("mailto:") -or
    $lower.StartsWith("tel:") -or
    $lower.StartsWith("data:") -or
    $lower.StartsWith("javascript:")
  ) { return $null }

  $clean = ($url -split '#')[0]
  $clean = ($clean -split '\?')[0]
  if ([string]::IsNullOrWhiteSpace($clean)) { return $null }

  if ($clean.StartsWith("/")) {
    $candidate = Join-Path $distPath ($clean.TrimStart('/'))
  } else {
    $htmlDir = Split-Path -Parent $HtmlFullName
    $candidate = Join-Path $htmlDir $clean
  }

  return $candidate
}

foreach ($html in $htmlFiles) {
  $content = Get-Content -Path $html.FullName -Raw
  $matches = [regex]::Matches($content, '(?i)(?:href|src)\s*=\s*"([^"]+)"')

  foreach ($m in $matches) {
    $ref = $m.Groups[1].Value
    $candidate = Resolve-LocalTarget -HtmlFullName $html.FullName -RawUrl $ref
    if ($null -eq $candidate) { continue }

    if (Test-Path $candidate) { continue }

    $dirIndex = Join-Path $candidate "index.html"
    if (Test-Path $dirIndex) { continue }

    $relativeHtml = $html.FullName.Substring($distPath.Length).TrimStart([char[]]"\\/")
    $brokenLinks += "$relativeHtml -> $ref"
  }
}

$functionMetaTargets = @(
  (Join-Path $distPath "index.html"),
  (Join-Path $distPath "pages/contact.html")
)

$functionMetaMismatches = @()
foreach ($target in $functionMetaTargets) {
  if (-not (Test-Path $target)) {
    $functionMetaMismatches += "Missing expected file for function base URL check: $target"
    continue
  }

  $content = Get-Content -Path $target -Raw
  $metaMatch = [regex]::Match($content, '(?i)<meta\s+name="lws-functions-base-url"\s+content="([^"]+)"')
  if (-not $metaMatch.Success) {
    $functionMetaMismatches += "Missing lws-functions-base-url meta tag in $target"
    continue
  }

  $actual = $metaMatch.Groups[1].Value.Trim()
  if ($actual -ne $ExpectedFunctionsBaseUrl) {
    $functionMetaMismatches += "Unexpected base URL in $target. Found: $actual"
  }
}

$socialImagePath = "assets/images/branding/social/lws-social-share.jpg"
$socialImageUrl = "https://lorenzowebsolutions.be/$socialImagePath"
$primarySocialTargets = @(
  "index.html",
  "pages/services.html",
  "pages/slimme-documentenflow.html",
  "pages/websites-op-maat.html",
  "pages/seo.html",
  "pages/about.html",
  "pages/process.html",
  "pages/portfolio.html",
  "pages/pricing.html",
  "pages/faq.html",
  "pages/contact.html"
)
$socialMetaExpected = [ordered]@{
  "og:image" = $socialImageUrl
  "og:image:secure_url" = $socialImageUrl
  "og:image:type" = "image/jpeg"
  "og:image:width" = "1200"
  "og:image:height" = "630"
  "og:image:alt" = "Lorenzo Web Solutions logo"
  "twitter:card" = "summary_large_image"
  "twitter:image" = $socialImageUrl
  "twitter:image:alt" = "Lorenzo Web Solutions logo"
}
$socialMetaMismatches = @()

if (-not (Test-Path (Join-Path $distPath $socialImagePath) -PathType Leaf)) {
  $socialMetaMismatches += "Missing social image: $socialImagePath"
}

foreach ($relativeTarget in $primarySocialTargets) {
  $target = Join-Path $distPath $relativeTarget
  if (-not (Test-Path $target -PathType Leaf)) {
    $socialMetaMismatches += "Missing primary page for social metadata check: $relativeTarget"
    continue
  }

  $content = Get-Content -Path $target -Raw
  foreach ($entry in $socialMetaExpected.GetEnumerator()) {
    $attribute = if ($entry.Key.StartsWith("og:")) { "property" } else { "name" }
    $pattern = '(?i)<meta\s+' + $attribute + '="' + [regex]::Escape($entry.Key) + '"\s+content="([^"]*)"'
    $matches = [regex]::Matches($content, $pattern)
    if ($matches.Count -ne 1 -or $matches[0].Groups[1].Value -ne $entry.Value) {
      $socialMetaMismatches += "Unexpected $($entry.Key) in $relativeTarget"
    }
  }
}

$operatorAuthMismatches = @()
$operatorRequiredPaths = @(
  "operator/index.html",
  "operator/login/index.html",
  "operator/auth/callback/index.html",
  "assets/css/operator-auth.css",
  "assets/js/operator-auth-core.mjs",
  "assets/js/operator-auth-client.mjs",
  "assets/js/operator-login.mjs",
  "assets/js/operator-callback.mjs",
  "assets/js/operator-shell.mjs",
  "assets/config/operator-auth.json"
)
foreach ($relativePath in $operatorRequiredPaths) {
  if (-not (Test-Path (Join-Path $distPath $relativePath) -PathType Leaf)) {
    $operatorAuthMismatches += "Missing operator Auth artifact: $relativePath"
  }
}

$operatorConfigPath = Join-Path $distPath "assets/config/operator-auth.json"
if (Test-Path $operatorConfigPath -PathType Leaf) {
  $operatorConfig = Get-Content $operatorConfigPath -Raw | ConvertFrom-Json
  if ($operatorConfig.supabaseUrl -ne "https://xcsptvntvrizwhskaphr.supabase.co") {
    $operatorAuthMismatches += "Unexpected operator Supabase URL"
  }
  if ($operatorConfig.callbackUrl -ne "https://lorenzowebsolutions.be/operator/auth/callback/") {
    $operatorAuthMismatches += "Unexpected operator callback URL"
  }
  if ([string]::IsNullOrWhiteSpace($operatorConfig.publishableKey) -or $operatorConfig.publishableKey -match '(?i)service_role|secret') {
    $operatorAuthMismatches += "Missing or forbidden operator browser key"
  }
}

$allFiles = Get-ChildItem -Path $distPath -File -Recurse
$topLevelPaths = Get-ChildItem -Path $distPath -Force | ForEach-Object { $_.Name } | Sort-Object

$forbiddenUnique = @($forbidden | Sort-Object -Unique)
$brokenLinksUnique = @($brokenLinks | Sort-Object -Unique)
$functionMetaMismatchList = @($functionMetaMismatches)
$missingRequiredList = @($missingRequired)

$report = [ordered]@{
  distPath = $distPath.ToString()
  fileCount = $allFiles.Count
  allowedTopLevelPaths = $topLevelPaths
  forbiddenCount = $forbiddenUnique.Count
  forbiddenFindings = $forbiddenUnique
  brokenLinksCount = $brokenLinksUnique.Count
  brokenLinks = $brokenLinksUnique
  functionBaseUrlCheckCount = $functionMetaTargets.Count
  functionBaseUrlMismatches = $functionMetaMismatchList
  socialMetaCheckCount = $primarySocialTargets.Count
  socialMetaMismatches = @($socialMetaMismatches)
  operatorAuthCheckCount = $operatorRequiredPaths.Count
  operatorAuthMismatches = @($operatorAuthMismatches)
  requiredRootMissing = $missingRequiredList
  publishedLegacyPaths = $publishedLegacyPaths
}

$reportPath = if ([IO.Path]::IsPathRooted($ReportPath)) { $ReportPath } else { Join-Path $repoRoot $ReportPath }
$report | ConvertTo-Json -Depth 6 | Set-Content -Path $reportPath -Encoding UTF8

Write-Host "DIST_REPORT=$reportPath"
Write-Host "DIST_FILE_COUNT=$($report.fileCount)"
Write-Host "DIST_TOP_LEVEL=$($report.allowedTopLevelPaths -join ',')"
Write-Host "FORBIDDEN_COUNT=$($report.forbiddenCount)"
Write-Host "BROKEN_LINKS=$($report.brokenLinksCount)"
Write-Host "FUNCTION_META_MISMATCHES=$($functionMetaMismatchList.Count)"
Write-Host "SOCIAL_META_MISMATCHES=$($socialMetaMismatches.Count)"
Write-Host "OPERATOR_AUTH_MISMATCHES=$($operatorAuthMismatches.Count)"
Write-Host "REQUIRED_MISSING=$($missingRequiredList.Count)"
Write-Host "PUBLISHED_LEGACY_PATHS=$($publishedLegacyPaths.Count)"

$hasFailures = $false
if ($report.forbiddenCount -ne 0) { $hasFailures = $true }
if ($report.brokenLinksCount -ne 0) { $hasFailures = $true }
if ($functionMetaMismatchList.Count -ne 0) { $hasFailures = $true }
if ($socialMetaMismatches.Count -ne 0) { $hasFailures = $true }
if ($operatorAuthMismatches.Count -ne 0) { $hasFailures = $true }
if ($missingRequiredList.Count -ne 0) { $hasFailures = $true }
if ($publishedLegacyPaths.Count -ne 0) { $hasFailures = $true }

if ($hasFailures) {
  throw "Dist verification failed. See $reportPath"
}
