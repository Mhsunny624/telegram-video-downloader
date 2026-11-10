# Telegram Video Downloader - main menu (Windows)
# Add a whole channel or individual video links to links.txt, then download them.

$dir    = $PSScriptRoot
$tdl    = Join-Path $dir "tdl.exe"
$links  = Join-Path $dir "links.txt"
$done   = Join-Path $dir "done.txt"
$failed = Join-Path $dir "failed.txt"

foreach ($f in @($links, $done, $failed)) {
    if (-not (Test-Path $f)) { New-Item $f -ItemType File | Out-Null }
}

# Adds links to links.txt, skipping any already in links/done/failed. Returns how many were added.
function Add-Links([string[]]$list) {
    $known = @{}
    foreach ($f in @($links, $done, $failed)) {
        Get-Content $f | ForEach-Object { $t = $_.Trim(); if ($t) { $known[$t] = $true } }
    }
    $toAdd = New-Object System.Collections.Generic.List[string]
    foreach ($l in $list) {
        if ($l -and -not $known.ContainsKey($l)) { $known[$l] = $true; $toAdd.Add($l) }
    }
    if ($toAdd.Count -gt 0) {
        $raw = [IO.File]::ReadAllText($links)
        if ($raw.Length -gt 0 -and -not $raw.EndsWith("`n")) { [IO.File]::AppendAllText($links, "`r`n") }
        Add-Content $links $toAdd
    }
    return $toAdd.Count
}

# Pulls every Telegram post link out of a block of text and tidies it up
function Get-PostLinks([string]$text) {
    [regex]::Matches($text, '(?:https?://)?t\.me/[^\s"''<>]+') | ForEach-Object {
        $u = $_.Value -replace '^(https?://)?', 'https://' -replace '[?#].*$', '' -replace '/+$', ''
        if ($u -match '^https://t\.me/(c/\d+|[A-Za-z0-9_]{4,})(/\d+){1,2}$') { $u }
    }
}

function Add-Channel {
    Write-Host ""
    Write-Host " Paste the channel. Any of these work:"
    Write-Host "   https://t.me/c/1234567890      (private channel)"
    Write-Host "   https://t.me/c/1234567890/25   (any post from it)"
    Write-Host "   https://t.me/channelname       (public channel)"
    Write-Host "   @channelname"
    $in = (Read-Host " Channel").Trim().Trim('"')
    if (-not $in) { return }

    if ($in -match 't\.me/c/(\d+)') {
        $chat = $Matches[1]; $prefix = "https://t.me/c/$chat"
    } elseif ($in -match 't\.me/(?:s/)?([A-Za-z0-9_]{4,})') {
        $chat = $Matches[1]; $prefix = "https://t.me/$chat"
    } elseif ($in -match '^@?([A-Za-z0-9_]{4,})$') {
        $chat = $Matches[1]; $prefix = "https://t.me/$chat"
    } else {
        Write-Host " Could not understand that channel: $in" -ForegroundColor Red
        return
    }

    $tmp = Join-Path $dir "channel_export.json"
    if (Test-Path $tmp) { Remove-Item $tmp -Force }
    Write-Host "`n Exporting posts from $chat ..." -ForegroundColor Cyan
    & $tdl chat export -c $chat -o $tmp
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $tmp)) {
        Write-Host " Export failed. Check the link and that you are signed in." -ForegroundColor Red
        return
    }
    $json = Get-Content $tmp -Raw -Encoding UTF8 | ConvertFrom-Json
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    $found = @($json.messages | ForEach-Object { [int]$_.id } | Sort-Object -Unique | ForEach-Object { "$prefix/$_" })
    $added = Add-Links $found
    Write-Host (" Found {0} posts, added {1} new links." -f $found.Count, $added) -ForegroundColor Green
}

function Add-Videos {
    Write-Host ""
    Write-Host " Paste video post links - one per line, or several on one line."
    Write-Host " Example: https://t.me/c/1234567890/25"
    Write-Host " Press Enter on an empty line when you're finished."
    $text = ""
    while ($true) {
        $line = Read-Host " "
        if (-not $line.Trim()) { break }
        $text += $line + "`n"
    }
    $found = @(Get-PostLinks $text | Select-Object -Unique)
    if ($found.Count -eq 0) {
        Write-Host " No valid post links found. A post link ends with a number, e.g. .../25" -ForegroundColor Yellow
        return
    }
    $added = Add-Links $found
    Write-Host (" Found {0} links, added {1} new ({2} already listed or downloaded)." -f `
        $found.Count, $added, ($found.Count - $added)) -ForegroundColor Green
}

$cfg = Join-Path $dir "download_folder.txt"

function Get-SavedFolder {
    if (Test-Path $cfg) {
        $v = Get-Content $cfg | Where-Object { $_.Trim() } | Select-Object -First 1
        if ($v) { return $v.Trim() }
    }
    return $null
}

# Opens the normal Windows "choose a folder" window. Returns the folder, or $null if cancelled.
function Select-FolderDialog([string]$start) {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = "Choose where to save Telegram videos"
        $dlg.ShowNewFolderButton = $true
        if ($start -and (Test-Path $start)) { $dlg.SelectedPath = $start }
        $owner = New-Object System.Windows.Forms.Form -Property @{ TopMost = $true }
        $res = $dlg.ShowDialog($owner)
        $owner.Dispose()
        if ($res -eq [System.Windows.Forms.DialogResult]::OK) { return $dlg.SelectedPath }
    } catch {
        Write-Host " Folder picker unavailable: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    return $null
}

function Change-Folder {
    $cur = Get-SavedFolder
    Write-Host ""
    Write-Host " A folder picker window is opening (check behind this window if you don't see it)..."
    $pick = Select-FolderDialog $cur
    if (-not $pick) {
        $pick = (Read-Host " No folder picked. Type a folder path, or press Enter to keep the current one").Trim().Trim('"')
        if (-not $pick) { Write-Host " Kept: $(if ($cur) { $cur } else { 'not set yet' })"; return }
    }
    try {
        if (-not (Test-Path $pick)) { New-Item $pick -ItemType Directory -ErrorAction Stop | Out-Null }
        $pick = (Resolve-Path $pick).Path
        Set-Content $cfg $pick
        Write-Host " Videos will now be saved to: $pick" -ForegroundColor Green
    } catch {
        Write-Host " Can't use that folder: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Get-Waiting {
    $skip = @{}
    foreach ($f in @($done, $failed)) { Get-Content $f | ForEach-Object { $t = $_.Trim(); if ($t) { $skip[$t] = $true } } }
    @(Get-Content $links | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $skip.ContainsKey($_) }).Count
}

Write-Host "============================================================"
Write-Host "                 TELEGRAM VIDEO DOWNLOADER"
Write-Host "============================================================"
Write-Host " Downloads 3 at a time. Finished links move to done.txt and"
Write-Host " are never downloaded again. Links that fail 3 times go to"
Write-Host " failed.txt. Safe to close any time - run again to continue."
Write-Host " Use option 3 to choose where videos are saved."

while ($true) {
    Write-Host ""
    Write-Host "  1     Add a whole channel"
    Write-Host "  2     Add video links (one or many)"
    $saved = Get-SavedFolder
    Write-Host ("  3     Change download folder ({0})" -f $(if ($saved) { $saved } else { "not set yet" }))
    Write-Host ("  Enter Start downloading ({0} waiting)" -f (Get-Waiting))
    Write-Host "  Q     Quit"
    $choice = (Read-Host " Choose").Trim()
    switch ($choice.ToLower()) {
        "1"     { Add-Channel }
        "2"     { Add-Videos }
        "3"     { Change-Folder }
        ""      { & (Join-Path $dir "download.ps1"); return }
        "q"     { return }
        default { Write-Host " Please type 1, 2, 3, Q or just press Enter." -ForegroundColor Yellow }
    }
}