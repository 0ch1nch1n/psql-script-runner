@echo off
setlocal DisableDelayedExpansion
title PSQL Script Runner v5.4 - Password window test only
powershell.exe -NoLogo -NoProfile -Sta -ExecutionPolicy Bypass -File "%~dp0tests\password-dialog-smoke.ps1"
set "PSQL_TEST_RC=%ERRORLEVEL%"
echo.
pause
exit /b %PSQL_TEST_RC%
