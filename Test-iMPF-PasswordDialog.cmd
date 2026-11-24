@echo off
setlocal DisableDelayedExpansion
title iMPF v5.3 - Password window test only
powershell.exe -NoLogo -NoProfile -Sta -ExecutionPolicy Bypass -File "%~dp0tests\password-dialog-smoke.ps1"
set "IMPF_TEST_RC=%ERRORLEVEL%"
echo.
pause
exit /b %IMPF_TEST_RC%
