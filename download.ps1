$dir     = $PSScriptRoot
$tdl     = if ($env:TGDL_TDL) { $env:TGDL_TDL } else { Join-Path $dir "tdl.exe" }
$links   = Join-Path $dir "links.txt"
$done    = Join-Path $dir "done.txt"
$failed  = Join-Path $dir "failed.txt"
# Download folder: saved in download_folder.txt, asked for on first run
$cfg = Join-Path $dir "download_folder.txt"
$out = $null
if (Test-Path $cfg) { $out = (Get-Content $cfg | Where-Object { $_.Trim() } | Select-Object -First 1) }
if ($out) { $out = $out.Trim().Trim('"') }
while (-not $out) {
    $default = Join-Path $dir "Downloads"
    Write-Host ""
    Write-Host "Where should videos be saved?"
    Write-Host "  B      Browse for a folder"
    Write-Host "  Enter  Use $default"
    $ans = Read-Host "  ...or type a full folder path"
    $ans = $ans.Trim().Trim('"')
    if ($ans -eq "b" -or $ans -eq "B") {
        $ans = $null
        try {
            Add-Type -AssemblyName System.Windows.Forms
            $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
            $dlg.Description = "Choose where to save Telegram videos"
            $dlg.ShowNewFolderButton = $true
            $owner = New-Object System.Windows.Forms.Form -Property @{ TopMost = $true }
            if ($dlg.ShowDialog($owner) -eq [System.Windows.Forms.DialogResult]::OK) { $ans = $dlg.SelectedPath }
            $owner.Dispose()
        } catch { Write-Host "Folder picker unavailable - please type the path instead." -ForegroundColor Yellow }
        if (-not $ans) { continue }
    }
    if (-not $ans) { $ans = $default }
    try {
        if (-not (Test-Path $ans)) { New-Item $ans -ItemType Directory -ErrorAction Stop | Out-Null }
        $out = (Resolve-Path $ans).Path
        Set-Content $cfg $out
        Write-Host "Saved. Videos will go to: $out" -ForegroundColor Green
        Write-Host "(Change it any time with option 3 in the menu)"
    } catch {
        Write-Host "Can't use that folder: $($_.Exception.Message)" -ForegroundColor Red
    }
}
Write-Host "Saving videos to: $out" -ForegroundColor DarkGray
$batch   = 3
$bcfg    = Join-Path $dir "batch_size.txt"
if (Test-Path $bcfg) {
    $v = "$(Get-Content $bcfg | Select-Object -First 1)".Trim()
    if ($v -match '^[1-4]$') { $batch = [int]$v }
}
Write-Host "Downloading $batch at a time" -ForegroundColor DarkGray
$maxTry  = 3

$names   = Join-Path $dir "done_names.txt"

foreach ($f in @($links, $done, $failed)) {
    if (-not (Test-Path $f)) { New-Item $f -ItemType File | Out-Null }
}
if (-not (Test-Path $out)) { New-Item $out -ItemType Directory | Out-Null }

# ---------- duplicate check (same file name + size) ----------
$KEY  = @{}   # link -> key
$NAME = @{}   # link -> file name
$DK   = @{}   # keys already downloaded

# Size + name lower-cased with spaces and punctuation removed ("My Video.mp4" = "my_video.mp4")
function Get-FileKey($size, $name) {
    if (-not $size -or -not $name) { return "" }
    $n = ($name.ToLowerInvariant() -replace '[\x09\x20-\x2F\x3A-\x40\x5B-\x60\x7B-\x7E]', '')
    if (-not $n) { return "" }
    return "$size|$n"
}

function Add-AppendLines($file, [string[]]$lines) {
    if (-not $lines -or $lines.Count -eq 0) { return }
    if (Test-Path $file) {
        $raw = [IO.File]::ReadAllText($file)
        if ($raw.Length -gt 0 -and -not $raw.EndsWith("`n")) { [IO.File]::AppendAllText($file, "`r`n") }
    }
    Add-Content $file $lines
}

# Removes the given links from links.txt (keeps anything added while downloading)
function Remove-FromLinks([string[]]$list) {
    $drop = @{}; foreach ($l in $list) { $drop[$l] = $true }
    $keep = @(Get-Content $links | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $drop.ContainsKey($_) })
    if ($keep.Count -gt 0) { Set-Content $links $keep } else { Clear-Content $links }
}

# Everything already downloaded: done_names.txt plus the videos in the download folder
if (Test-Path $names) { Get-Content $names | ForEach-Object { $t = $_.Trim(); if ($t) { $DK[$t] = $true } } }
Get-ChildItem $out -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -notin @('.tmp', '.txt', '.json', '.ps1', '.bat', '.exe') } |
    ForEach-Object {
        $k = Get-FileKey $_.Length ($_.Name -replace '^-?\d+_\d+_', '')
        if ($k) { $DK[$k] = $true }
    }

# Looks up the file name and size of each link (a quick tdl export per channel)
function Update-Keys([string[]]$list) {
    $byChat = @{}; $pfx = @{}
    foreach ($l in $list) {
        if ($KEY.ContainsKey($l)) { continue }
        if ($l -match '^https://t\.me/c/(\d+)/(\d+)$') {
            $chat = $Matches[1]; $id = [long]$Matches[2]; $pfx[$chat] = "https://t.me/c/$chat"
        } elseif ($l -match '^https://t\.me/([A-Za-z0-9_]{4,})/(\d+)$') {
            $chat = $Matches[1]; $id = [long]$Matches[2]; $pfx[$chat] = "https://t.me/$chat"
        } else { $KEY[$l] = ""; continue }
        if (-not $byChat.ContainsKey($chat)) { $byChat[$chat] = New-Object System.Collections.Generic.List[long] }
        $byChat[$chat].Add($id)
    }
    if ($byChat.Count -gt 0) {
        Write-Host "Checking file names and sizes..." -ForegroundColor DarkGray
        $tmp = Join-Path $dir "lookup_export.json"
        foreach ($chat in $byChat.Keys) {
            # Export in small ranges so the file stays small enough to read
            $ids = @($byChat[$chat] | Sort-Object -Unique)
            $groups = @(); $g = @($ids[0])
            foreach ($id in @($ids | Select-Object -Skip 1)) {
                if ($id - $g[0] -le 300) { $g += $id } else { $groups += ,$g; $g = @($id) }
            }
            $groups += ,$g
            foreach ($grp in $groups) {
                if (Test-Path $tmp) { Remove-Item $tmp -Force }
                & $tdl chat export -c $chat -T id -i "$($grp[0]),$($grp[-1])" --raw -o $tmp *> $null
                if (-not (Test-Path $tmp)) { continue }
                try {
                    $json = Get-Content $tmp -Raw -Encoding UTF8 | ConvertFrom-Json
                    foreach ($m in $json.messages) {
                        $size = $null
                        try { $size = $m.raw.Media.Document.Size } catch {}
                        $l = "$($pfx[$chat])/$($m.id)"
                        $KEY[$l] = Get-FileKey $size $m.file
                        $NAME[$l] = $m.file
                    }
                } catch {}
            }
        }
        if (Test-Path $tmp) { Remove-Item $tmp -Force }
    }
    foreach ($l in $list) { if (-not $KEY.ContainsKey($l)) { $KEY[$l] = "" } }
}

$tries = 0
$skipped = 0

while ($true) {
    $doneList   = @(Get-Content $done   | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $failedList = @(Get-Content $failed | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $finished = @{}; foreach ($x in $doneList + $failedList) { $finished[$x] = $true }

    $todo = @(Get-Content $links | ForEach-Object { $_.Trim() } |
              Where-Object { $_ -and -not $finished.ContainsKey($_) } | Select-Object -Unique)

    if ($todo.Count -eq 0) {
        Remove-FromLinks ($doneList + $failedList)
        Write-Host "`nAll done! Finished: $($doneList.Count)  Failed: $($failedList.Count)  (skipped $skipped duplicates this run)" -ForegroundColor Green
        break
    }

    Update-Keys $todo

    # Pick the next batch, skipping files already downloaded under another link
    $now = @(); $dup = @(); $plan = @{}
    foreach ($l in $todo) {
        $k = $KEY[$l]
        if ($k -and ($DK.ContainsKey($k) -or $plan.ContainsKey($k))) {
            $label = if ($NAME[$l]) { $NAME[$l] } else { $l }
            Write-Host " Skipped (already downloaded): $label" -ForegroundColor Yellow
            $dup += $l; continue
        }
        $now += $l
        if ($k) { $plan[$k] = $true }
        if ($now.Count -ge $batch) { break }
    }
    if ($dup.Count -gt 0) {
        Add-AppendLines $done $dup
        Remove-FromLinks $dup
        $skipped += $dup.Count
    }
    if ($now.Count -eq 0) { continue }

    Write-Host "`n[$($todo.Count) left] Downloading:" -ForegroundColor Cyan
    foreach ($l in $now) { if ($NAME[$l]) { Write-Host "  $l  ($($NAME[$l]))" } else { Write-Host "  $l" } }

    $tdlArgs = @("dl", "-d", $out, "-l", $batch, "--skip-same", "--continue")
    foreach ($l in $now) { $tdlArgs += @("-u", $l) }

    & $tdl @tdlArgs

    if ($LASTEXITCODE -eq 0) {
        Add-AppendLines $done $now
        $newKeys = @($now | ForEach-Object { $KEY[$_] } | Where-Object { $_ })
        Add-AppendLines $names $newKeys
        foreach ($k in $newKeys) { $DK[$k] = $true }
        $tries = 0
    } else {
        $tries++
        if ($tries -ge $maxTry) {
            Write-Host "Failed $maxTry times, moving these to failed.txt" -ForegroundColor Red
            Add-AppendLines $failed $now
            $tries = 0
        } else {
            Write-Host "Download failed (try $tries of $maxTry). Retrying in 10 seconds..." -ForegroundColor Yellow
            Start-Sleep -Seconds 10
            continue
        }
    }

    Remove-FromLinks $now
}
