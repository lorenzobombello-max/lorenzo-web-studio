[CmdletBinding()]
param(
  [string]$OutputDir = "dist"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir "..")
$outputPath = Join-Path $repoRoot $OutputDir

$allowlist = @(
  @{ Path = "index.html"; Required = $true }
  @{ Path = "pages"; Required = $true }
  @{ Path = "assets"; Required = $true }
  @{ Path = "robots.txt"; Required = $true }
  @{ Path = "sitemap.xml"; Required = $true }
  @{ Path = "site.webmanifest"; Required = $true }
  @{ Path = "CNAME"; Required = $false }
)

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

$allowedAssetExtensions = @(
  ".css",
  ".js",
  ".mjs",
  ".png",
  ".jpg",
  ".jpeg",
  ".svg",
  ".webp",
  ".gif",
  ".ico",
  ".avif",
  ".woff",
  ".woff2",
  ".ttf",
  ".eot",
  ".mp4",
  ".webm"
)

if (Test-Path $outputPath) {
  Remove-Item $outputPath -Recurse -Force
}
New-Item -ItemType Directory -Path $outputPath | Out-Null

$copiedItems = @()

foreach ($entry in $allowlist) {
  $source = Join-Path $repoRoot $entry.Path
  if (-not (Test-Path $source)) {
    if ($entry.Required) {
      throw "Required allowlist path missing: $($entry.Path)"
    }
    continue
  }

  $destination = Join-Path $outputPath $entry.Path
  if (Test-Path $source -PathType Container) {
    if ($entry.Path -eq "assets") {
      $files = Get-ChildItem -Path $source -Recurse -File -Force
      foreach ($file in $files) {
        $relativeToRepo = $file.FullName.Substring($repoRoot.Path.Length).TrimStart([char[]]"\\/")
        $blockedPath = $false

        foreach ($pathRegex in $denyPathRegexes) {
          if ($relativeToRepo -match $pathRegex) {
            $blockedPath = $true
            break
          }
        }
        if ($blockedPath) { continue }

        if ($denyFileRegexes | Where-Object { $file.Name -match $_ }) {
          continue
        }

        $ext = $file.Extension.ToLowerInvariant()
        if (-not ($allowedAssetExtensions -contains $ext)) {
          continue
        }

        $relativeInAssets = $file.FullName.Substring($source.Length).TrimStart([char[]]"\\/")
        $targetFile = Join-Path $destination $relativeInAssets
        $targetDir = Split-Path -Parent $targetFile
        if (-not (Test-Path $targetDir)) {
          New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }
        Copy-Item -Path $file.FullName -Destination $targetFile -Force
      }
    } else {
      Copy-Item -Path $source -Destination $destination -Recurse -Force
    }
  } else {
    $destinationParent = Split-Path -Parent $destination
    if (-not (Test-Path $destinationParent)) {
      New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null
    }
    Copy-Item -Path $source -Destination $destination -Force
  }

  $copiedItems += $entry.Path
}

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
