# Exports every media post from a Telegram channel with tdl
# and appends the post links to links.txt (skipping duplicates).
param([Parameter(Mandatory = $true)][string]$Channel)

$dir    = $PSScriptRoot
$tdl    = Join-Path $dir "tdl.exe"
$links  = Join-Path $dir "links.txt"
$done   = Join-Path $dir "done.txt"
$failed = Join-Path $dir "failed.txt"
$tmp    = Join-Path $dir "channel_export.json"

$Channel = $Channel.Trim().Trim('"')

# Work out the chat ID / username and the link prefix
if ($Channel -match 't\.me/c/(\d+)') {
    $chat   = $Matches[1]
    $prefix = "https://t.me/c/$chat"
} elseif ($Channel -match 't\.me/(?:s/)?([A-Za-z0-9_]{4,})') {
    $chat   = $Matches[1]
    $prefix = "https://t.me/$chat"
} elseif ($Channel -match '^@?([A-Za-z0-9_]{4,})$') {
    $chat   = $Matches[1]
    $prefix = "https://t.me/$chat"
} else {
    Write-Host "Could not understand that channel link: $Channel" -ForegroundColor Red
    exit 1
}

Write-Host "`nExporting posts from $chat ..." -ForegroundColor Cyan
if (Test-Path $tmp) { Remove-Item $tmp -Force }
& $tdl chat export -c $chat -o $tmp
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $tmp)) {
    Write-Host "Export failed. Check the link and that tdl is logged in." -ForegroundColor Red
    exit 1
}

$json = Get-Content $tmp -Raw -Encoding UTF8 | ConvertFrom-Json
$new  = @($json.messages | ForEach-Object { [int]$_.id } | Sort-Object -Unique |
          ForEach-Object { "$prefix/$_" })

foreach ($f in @($links, $done, $failed)) {
    if (-not (Test-Path $f)) { New-Item $f -ItemType File | Out-Null }
}
$known = @{}
foreach ($f in @($links, $done, $failed)) {
    Get-Content $f | ForEach-Object { $t = $_.Trim(); if ($t) { $known[$t] = $true } }
}

$toAdd = @($new | Where-Object { -not $known.ContainsKey($_) })
if ($toAdd.Count -gt 0) {
    # Make sure links.txt ends with a newline so new links start on their own line
    $raw = [IO.File]::ReadAllText($links)
    if ($raw.Length -gt 0 -and -not $raw.EndsWith("`n")) { [IO.File]::AppendAllText($links, "`r`n") }
    Add-Content $links $toAdd
}
Remove-Item $tmp -Force -ErrorAction SilentlyContinue

Write-Host ("Found {0} posts, added {1} new links ({2} already listed or downloaded)." -f `
    $new.Count, $toAdd.Count, ($new.Count - $toAdd.Count)) -ForegroundColor Green