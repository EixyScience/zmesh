. "$PSScriptRoot\lib.ps1"

$dir = VirtualPathDir
$files = Get-ChildItem $dir -Filter "*.conf" -ErrorAction SilentlyContinue
if (-not $files) { Write-Host "no virtualpaths"; exit 0 }

"{0,-24}  {1,-20}  {2}" -f "VPATH","SCALEFS","SUBPATH"
"{0,-24}  {1,-20}  {2}" -f ("-"*24),("-"*20),("-"*7)

foreach ($f in $files) {
  $txt = Get-Content $f.FullName
  $p = ($txt | Where-Object { $_ -match '^path=' } | Select-Object -First 1) -replace '^path=',''
  $s = ($txt | Where-Object { $_ -match '^scalefs=' } | Select-Object -First 1) -replace '^scalefs=',''
  $u = ($txt | Where-Object { $_ -match '^subpath=' } | Select-Object -First 1) -replace '^subpath=',''
  if (-not $u) { $u="/" }
  "{0,-24}  {1,-20}  {2}" -f $p,$s,$u
}