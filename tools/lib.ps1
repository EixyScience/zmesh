function Ask($prompt, $default="")
{
    $msg = $prompt
    if ($default -ne "") { $msg += " [$default]" }

    $v = Read-Host $msg
    if ($v -eq "") { return $default }
    return $v
}

function EnsureDir($path)
{
    if (!(Test-Path $path))
    {
        New-Item -ItemType Directory -Force $path | Out-Null
    }
}

function ShortID()
{
    return ([guid]::NewGuid().ToString("N")).Substring(0,8)
}