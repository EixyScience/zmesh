$ErrorActionPreference = "Stop"

$dirs = @(
  "internal\queue",
  "tools"
)

$files = @(
  "internal\queue\queue.go"
)

foreach ($d in $dirs) {
  if (-not (Test-Path $d)) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    Write-Host "MKDIR $d"
  }
}

foreach ($f in $files) {
  if (-not (Test-Path $f)) {
    New-Item -ItemType File -Force -Path $f | Out-Null
    Write-Host "TOUCH $f"
  }
}

Write-Host "Done. Paste code into the created files in VS Code (UTF-8 without BOM), then gofmt/go build."