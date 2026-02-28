. "$PSScriptRoot\lib.ps1"

$dir = VirtualPathDir
$files = Get-ChildItem $dir -Filter "*.conf" -ErrorAction SilentlyContinue
if (-not $files) { Write-Host "OK: no virtualpath.d"; exit 0 }

$seen = @{}
$warn = $false

foreach ($f in $files) {
  $txt = Get-Content $f.FullName
  $p = ($txt | Where-Object { $_ -match '^path=' } | Select-Object -First 1) -replace '^path=',''
  $s = ($txt | Where-Object { $_ -match '^scalefs=' } | Select-Object -First 1) -replace '^scalefs=',''
  if (-not $p) { Write-Warning "missing path= in $($f.Name)"; $warn=$true; continue }
  if ($seen.ContainsKey($p)) { Write-Warning "duplicate vpath: $p ($($f.Name), $($seen[$p]))"; $warn=$true } else { $seen[$p]=$f.Name }
  if ($s -notmatch '^[a-z0-9._-]+\.[0-9a-f]{6,8}$') { Write-Warning "suspicious scalefs id: '$s' in $($f.Name)"; $warn=$true }
}

if (-not $warn) { Write-Host "OK: virtualpath.d checked" }