param(
  [switch]$Force
)

$ErrorActionPreference = "Stop"

function Move-One([string]$from, [string]$to) {
  if (-not (Test-Path $from)) { return }

  if ((Test-Path $to) -and (-not $Force)) {
    throw "Target exists: $to (use -Force to overwrite)"
  }

  Write-Host "rename: $from -> $to"
  Move-Item -Force:$Force $from $to
}

# --- zmesh / scalefs start-stop naming unification (sh side) ---
Move-One "start-zmesh.sh" "zmesh-start.sh"
Move-One "stop-zmesh.sh"  "zmesh-stop.sh"

Move-One "start-scalefs.sh" "scalefs-start.sh"
Move-One "stop-scalefs.sh"  "scalefs-stop.sh"

# --- root scripts (sh side) ---
Move-One "zmesh-add-root.sh" "add-root.sh"

# NOTE: list-root.sh / remove-root.sh are missing in sh -> generated later

# --- optional: if you want .txt artifact to become a script name placeholder ---
# Move-One "add-scalefs.txt" "add-scalefs.note.txt"

Write-Host "done."