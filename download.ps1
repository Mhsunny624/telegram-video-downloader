$dir     = $PSScriptRoot
$tdl     = Join-Path $dir "tdl.exe"
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
    $ans = Read-Host "Where should videos be saved? (press Enter for $default)"
    $ans = $ans.Trim().Trim('"')
    if (-not $ans) { $ans = $default }
    try {
        if (-not (Test-Path $ans)) { New-Item $ans -ItemType Directory -ErrorAction Stop | Out-Null }
        $out = (Resolve-Path $ans).Path
        Set-Content $cfg $out
        Write-Host "Saved. Videos will go to: $out" -ForegroundColor Green
        Write-Host "(To change this later, delete download_folder.txt)"
    } catch {
        Write-Host "Can't use that folder: $($_.Exception.Message)" -ForegroundColor Red
    }
}
Write-Host "Saving videos to: $out" -ForegroundColor DarkGray
$batch   = 3
$maxTry  = 3

foreach ($f in @($done, $failed)) {
    if (-not (Test-Path $f)) { New-Item $f -ItemType File | Out-Null }
}
if (-not (Test-Path $out)) { New-Item $out -ItemType Directory | Out-Null }

$tries = 0

while ($true) {
    $doneList   = @(Get-Content $done   | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $failedList = @(Get-Content $failed | ForEach-Object { $_.Trim() } | Where-Object { $_ })

    $todo = @(Get-Content $links | ForEach-Object { $_.Trim() } |
              Where-Object { $_ -and ($doneList -notcontains $_) -and ($failedList -notcontains $_) })

    if ($todo.Count -eq 0) {
        Clear-Content $links
        Write-Host "`nAll done! Downloaded: $($doneList.Count)  Failed: $($failedList.Count)" -ForegroundColor Green
        break
    }

    $now = @($todo | Select-Object -First $batch)
    Write-Host "`n[$($todo.Count) left] Downloading:" -ForegroundColor Cyan
    $now | ForEach-Object { Write-Host "  $_" }

    $tdlArgs = @("dl", "-d", $out, "-l", $batch, "--skip-same", "--continue")
    foreach ($l in $now) { $tdlArgs += @("-u", $l) }

    & $tdl @tdlArgs

    if ($LASTEXITCODE -eq 0) {
        $rawDone = [IO.File]::ReadAllText($done)
        if ($rawDone.Length -gt 0 -and -not $rawDone.EndsWith("`n")) { [IO.File]::AppendAllText($done, "`r`n") }
        Add-Content $done $now
        $tries = 0
    } else {
        $tries++
        if ($tries -ge $maxTry) {
            Write-Host "Failed $maxTry times, moving these to failed.txt" -ForegroundColor Red
            Add-Content $failed $now
            $tries = 0
        } else {
            Write-Host "Download failed (try $tries of $maxTry). Retrying in 10 seconds..." -ForegroundColor Yellow
            Start-Sleep -Seconds 10
            continue
        }
    }

    $rest = @($todo | Select-Object -Skip $now.Count)
    if ($rest.Count -gt 0) { Set-Content $links $rest } else { Clear-Content $links }
}