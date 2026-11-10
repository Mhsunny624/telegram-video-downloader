# Downloads the latest tdl for Windows into this folder and logs in to Telegram.
# tdl: https://github.com/iyear/tdl (AGPL-3.0)

$dir = $PSScriptRoot
$tdl = Join-Path $dir "tdl.exe"
$zip = Join-Path $env:TEMP "tdl_Windows_64bit.zip"
$tmp = Join-Path $env:TEMP "tdl_extract"

$arch = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "arm64" } else { "64bit" }
$url  = "https://github.com/iyear/tdl/releases/latest/download/tdl_Windows_$arch.zip"

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Write-Host "Downloading tdl from $url ..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    $exe = Get-ChildItem $tmp -Recurse -Filter "tdl.exe" | Select-Object -First 1
    if (-not $exe) { throw "tdl.exe not found in the download." }
    Copy-Item $exe.FullName $tdl -Force
    Remove-Item $zip, $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "tdl installed." -ForegroundColor Green
} catch {
    Write-Host "Could not download tdl: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Now sign in to your Telegram account." -ForegroundColor Cyan
Write-Host "Enter your phone number with country code (e.g. +441234567890),"
Write-Host "then the code Telegram sends to your Telegram app."
Write-Host ""
& $tdl login -T code