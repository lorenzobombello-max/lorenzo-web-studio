[CmdletBinding()]
param(
  [string]$OutputDir = "dist"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir "..")
$outputPath = Join-Path $repoRoot $OutputDir

$requiredFiles = @(
  "index.html",
  "404.html",
  "robots.txt",
  "sitemap.xml",
  "site.webmanifest",
  "pages/about.html",
  "pages/admin-intake.html",
  "pages/algemene-voorwaarden.html",
  "pages/contact.html",
  "pages/cookies.html",
  "pages/faq.html",
  "pages/hosting-onderhoud.html",
  "pages/intake.html",
  "pages/integraties-automatisering.html",
  "pages/klanten-ledenomgevingen.html",
  "pages/multimedia-social.html",
  "pages/portfolio.html",
  "pages/pricing.html",
  "pages/privacy.html",
  "pages/process.html",
  "pages/quotation-acceptance.html",
  "pages/review-request.html",
  "pages/seo.html",
  "pages/services.html",
  "pages/voorwaarden.html",
  "pages/webshops.html",
  "pages/websites-op-maat.html",
  "assets/css/admin-intake.css",
  "assets/css/cookie-consent.css",
  "assets/css/intake.css",
  "assets/css/legal.css",
  "assets/css/pages.css",
  "assets/css/quotation-acceptance.css",
  "assets/css/redesign.css",
  "assets/css/review-request.css",
  "assets/css/service-details.css",
  "assets/css/style.css",
  "assets/css/demos/aurelis-architecture.css",
  "assets/css/demos/cafe.css",
  "assets/css/demos/garage.css",
  "assets/css/demos/industrieel-elektriciteit-light.css",
  "assets/css/demos/industrieel-elektriciteit.css",
  "assets/css/demos/luna-hair-studio.css",
  "assets/css/demos/mediterranean-brasserie.css",
  "assets/css/demos/nova-estate-contrast.css",
  "assets/css/demos/nova-estate.css",
  "assets/css/demos/personal-portfolio.css",
  "assets/css/demos/pulse-performance.css",
  "assets/css/demos/restaurant.css",
  "assets/js/admin-intake.js",
  "assets/js/cookie-consent.js",
  "assets/js/homepage-studio.js",
  "assets/js/intake.js",
  "assets/js/pages.js",
  "assets/js/quotation-acceptance.js",
  "assets/js/redesign.js",
  "assets/js/review-request.js",
  "assets/js/demos/aurelis-architecture.js",
  "assets/js/demos/cafe.js",
  "assets/js/demos/garage.js",
  "assets/js/demos/industrieel-elektriciteit.js",
  "assets/js/demos/luna-hair-studio.js",
  "assets/js/demos/mediterranean-brasserie.js",
  "assets/js/demos/nova-estate.js",
  "assets/js/demos/personal-portfolio.js",
  "assets/js/demos/pulse-performance.js",
  "assets/js/demos/restaurant.js",
  "assets/icons/apple-touch-icon.png",
  "assets/icons/favicon-32x32.png",
  "assets/icons/favicon.ico",
  "assets/icons/favicon.svg",
  "assets/icons/icon-192x192.png",
  "assets/images/branding/logo/lorenzo-web-solution-logo-transparent.png",
  "assets/images/branding/social/lws-social-share.jpg"
)

$requiredDirectories = @(
  "pages/demos/aurelis-architecture",
  "pages/demos/cafe",
  "pages/demos/garage",
  "pages/demos/industrieel-elektriciteit",
  "pages/demos/luna-hair-studio",
  "pages/demos/mediterranean-brasserie",
  "pages/demos/nova-estate",
  "pages/demos/personal-portfolio",
  "pages/demos/pulse-performance",
  "pages/demos/restaurant",
  "assets/images/home/showcase",
  "assets/images/demos/aurelis-architecture",
  "assets/images/demos/cafe",
  "assets/images/demos/garage",
  "assets/images/demos/industrieel-elektriciteit",
  "assets/images/demos/luna-hair-studio",
  "assets/images/demos/mediterranean-brasserie",
  "assets/images/demos/nova-estate",
  "assets/images/demos/personal-portfolio",
  "assets/images/demos/pulse-performance",
  "assets/images/demos/restaurant"
)

$optionalFiles = @("CNAME")

$denyPathRegexes = @(
  '(^|[\\/])supabase([\\/]|$)',
  '(^|[\\/])docs([\\/]|$)',
  '(^|[\\/])backup([\\/]|$)',
  '(^|[\\/])\.git([\\/]|$)',
  '(^|[\\/])\.github([\\/]|$)',
  '(^|[\\/])\.venv([\\/]|$)',
  '(^|[\\/])\.tmp([\\/]|$)',
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

if (Test-Path $outputPath) {
  Remove-Item $outputPath -Recurse -Force
}
New-Item -ItemType Directory -Path $outputPath | Out-Null

$copiedItems = @()

function Copy-AllowlistedPath {
  param([string]$RelativePath, [bool]$Required)

  $source = Join-Path $repoRoot $RelativePath
  if (-not (Test-Path $source)) {
    if ($Required) { throw "Required allowlist path missing: $RelativePath" }
    return
  }

  $destination = Join-Path $outputPath $RelativePath
  $destinationParent = Split-Path -Parent $destination
  if (-not (Test-Path $destinationParent)) {
    New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null
  }

  if (Test-Path $source -PathType Container) {
    Copy-Item -Path $source -Destination $destination -Recurse -Force
  } else {
    Copy-Item -Path $source -Destination $destination -Force
  }
  $script:copiedItems += $RelativePath
}

$requiredFiles | ForEach-Object { Copy-AllowlistedPath -RelativePath $_ -Required $true }
$requiredDirectories | ForEach-Object { Copy-AllowlistedPath -RelativePath $_ -Required $true }
$optionalFiles | ForEach-Object { Copy-AllowlistedPath -RelativePath $_ -Required $false }

$allEntries = Get-ChildItem -Path $outputPath -Recurse -Force
$forbidden = @()

foreach ($item in $allEntries) {
  $relative = $item.FullName.Substring($outputPath.Length).TrimStart([char[]]"\\/")
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

if ($forbidden.Count -gt 0) {
  $forbidden | Sort-Object -Unique | ForEach-Object { Write-Error $_ }
  throw "Forbidden content detected in $OutputDir"
}

$totalFiles = (Get-ChildItem -Path $outputPath -File -Recurse -Force).Count

Write-Host "DIST_READY=$outputPath"
Write-Host "DIST_FILES=$totalFiles"
Write-Host "ALLOWLIST_COPIED=$($copiedItems -join ',')"
Write-Host "FORBIDDEN_COUNT=0"
