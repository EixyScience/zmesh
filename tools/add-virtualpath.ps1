. "$PSScriptRoot\lib.ps1"

$vp   = Ask "Virtual path (e.g. hobby/car)"
$vp   = NormalizeVPath $vp

$scalefs = Ask "Scalefs id (e.g. democell.28e671)"
$subpath = Ask "Subpath inside scalefs" "/"
$mode    = Ask "Mode (link|mount|junction)" "link"
$ro      = Ask "Readonly (true|false)" "false"

$dir = VirtualPathDir
$file = Join-Path $dir ("vp.{0}.conf" -f (VpFileName $vp))

@"
[virtualpath]
path=$vp
scalefs=$scalefs
subpath=$subpath
mode=$mode
readonly=$ro
"@ | Set-Content -Encoding UTF8 $file

Write-Host "OK virtualpath added: $vp -> $scalefs ($subpath)"
Write-Host "  file: $file"