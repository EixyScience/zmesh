$ErrorActionPreference = "Stop"

$dirs = @(
  ".vscode",
  "cmd\zmesh",
  "internal\agent",
  "internal\config",
  "internal\id",
  "internal\instance",
  "internal\membership",
  "internal\router",
  "internal\transport",
  "internal\version",
  "tools"
)

$files = @(
  "go.mod",
  ".vscode\settings.json",
  "zmesh.conf",
  "zmesh.conf.example",
  "cmd\zmesh\main.go",
  "internal\agent\agent.go",
  "internal\config\config.go",
  "internal\id\uuid7.go",
  "internal\instance\instance.go",
  "internal\membership\udp.go",
  "internal\router\router.go",
  "internal\transport\http.go",
  "internal\version\version.go"
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
Write-Host "Done. Now paste contents in VS Code, then run gofmt/go build."