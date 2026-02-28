. "$PSScriptRoot\lib.ps1"

$vp = Ask "Virtual path (e.g. hobby/car)"
$vp = NormalizeVPath $vp

$dir = VirtualPathDir
$file = Join-Path $dir ("vp.{0}.conf" -f (VpFileName $vp))

if (Test-Path $file) {
  Remove-Item $file -Force
  Write-Host "OK removed: $vp"
} else {
  Write-Host "not found: $vp"
}