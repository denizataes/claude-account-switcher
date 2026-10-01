@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Claude-Hesap.ps1" %*
set "SWITCHER_EXIT=%errorlevel%"
if not "%SWITCHER_EXIT%"=="0" pause
endlocal & exit /b %SWITCHER_EXIT%
