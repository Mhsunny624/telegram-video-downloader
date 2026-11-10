@echo off
title Telegram Downloader
cd /d "%~dp0"

if not exist "%~dp0tdl.exe" (
    echo tdl.exe was not found. Setting it up now...
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-tdl.ps1"
    if not exist "%~dp0tdl.exe" (
        echo.
        echo Setup failed. Download tdl manually from https://github.com/iyear/tdl/releases
        echo and put tdl.exe in this folder.
        pause
        exit /b 1
    )
)

echo ============================================================
echo                   TELEGRAM VIDEO DOWNLOADER
echo ============================================================
echo.
echo  Paste a channel to add all of its posts to links.txt.
echo  Any of these formats work:
echo.
echo    Private channel link :  https://t.me/c/1234567890
echo    Post from a channel  :  https://t.me/c/1234567890/25
echo    Public channel link  :  https://t.me/channelname
echo    Channel username     :  @channelname
echo.
echo  Or just press Enter to download the links already in links.txt.
echo.
echo  Notes:
echo   - First run downloads tdl and asks you to sign in to Telegram.
echo   - Downloads 3 at a time. Finished links move to done.txt.
echo   - Links that fail 3 times go to failed.txt.
echo   - Safe to close any time. Run again to continue.
echo   - Download folder is asked once and saved in download_folder.txt.
echo     Delete that file to choose a different folder.
echo ============================================================
echo.
set "CH="
set /p "CH=Channel link: "

if defined CH (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0add-channel.ps1" -Channel "%CH%"
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0download.ps1"
echo.
pause