@echo off
title Telegram Video Downloader
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

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start.ps1"
echo.
pause