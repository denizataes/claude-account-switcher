@echo off
setlocal
powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Install.ps1" %*
set "INSTALL_EXIT=%errorlevel%"
if not "%INSTALL_EXIT%"=="0" pause
endlocal & exit /b %INSTALL_EXIT%
