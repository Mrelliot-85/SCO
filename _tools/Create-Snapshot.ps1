param(
  [string]$Name = ""
)

$ErrorActionPreference = "Stop"

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
if ([string]::IsNullOrWhiteSpace($Name)) {
  $Name = "snapshot"
}

$safeName = ($Name -replace '[^a-zA-Z0-9._-]', '_')
$target = Join-Path $projectRoot "_snapshots\$stamp-$safeName"

New-Item -ItemType Directory -Force -Path $target | Out-Null

function Copy-IfExists {
  param(
    [string]$RelativePath,
    [string]$TargetSubDir = ""
  )

  $source = Join-Path $projectRoot $RelativePath
  if (-not (Test-Path $source)) {
    return
  }

  $destinationRoot = if ([string]::IsNullOrWhiteSpace($TargetSubDir)) {
    $target
  } else {
    Join-Path $target $TargetSubDir
  }

  New-Item -ItemType Directory -Force -Path $destinationRoot | Out-Null
  Copy-Item -LiteralPath $source -Destination $destinationRoot -Recurse -Force
}

Copy-IfExists "Win32\Debug\www" "runtime"
Copy-IfExists "Win32\Debug\Config.ini" "runtime"
Copy-IfExists "Win32\Debug\labeltemplates" "runtime"
Copy-IfExists "Win32\Debug\ZVT" "runtime"

$sourceTarget = Join-Path $target "source"
New-Item -ItemType Directory -Force -Path $sourceTarget | Out-Null

Get-ChildItem -LiteralPath $projectRoot -File |
  Where-Object {
    $_.Extension -in ".pas", ".dfm", ".fmx", ".dpr", ".dproj", ".res", ".ico", ".md"
  } |
  Copy-Item -Destination $sourceTarget -Force

$meta = @{
  CreatedAt = (Get-Date).ToString("s")
  Name = $Name
  GitBranch = (git -C $projectRoot branch --show-current 2>$null)
  GitCommit = (git -C $projectRoot rev-parse --short HEAD 2>$null)
} | ConvertTo-Json -Depth 3

$meta | Set-Content -LiteralPath (Join-Path $target "snapshot.json") -Encoding UTF8

Write-Host "Snapshot erstellt: $target"
