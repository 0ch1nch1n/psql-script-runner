@echo off
setlocal DisableDelayedExpansion
title PSQL Script Runner v5.3

rem ================= PostgreSQL settings =================
set "PG_PSQL_EXE=C:\Program Files\PostgreSQL\16\bin\psql.exe"
set "PG_HOST=YOUR_DATABASE_HOST"
set "PG_PORT=5432"
set "PG_DATABASE=YOUR_DATABASE_NAME"
set "PG_USERNAME=YOUR_DATABASE_USER"
set "PGCLIENTENCODING=UTF8"

rem Leave PG_PASSWORD empty to receive a secure password prompt.
rem A value entered here is stored as plaintext. In a CMD file, write % as %%.
set "PG_PASSWORD="
rem =======================================================

set "PG_RUNNER_SELF=%~dpn0.ps1"

if not exist "%PG_RUNNER_SELF%" (
    echo ERROR: PowerShell runner was not found:
    echo "%PG_RUNNER_SELF%"
    echo.
    echo Keep the CMD and PS1 files in the same directory.
    echo.
    pause
    exit /b 98
)

powershell.exe -NoLogo -NoProfile -Sta -ExecutionPolicy Bypass -File "%PG_RUNNER_SELF%"
set "PG_RUNNER_RC=%ERRORLEVEL%"

echo.
if "%PG_RUNNER_RC%"=="0" (
    echo All scripts completed successfully.
) else if "%PG_RUNNER_RC%"=="2" (
    echo Operation cancelled. No further script was executed.
) else (
    echo Execution failed. Exit code: %PG_RUNNER_RC%
    echo Check the run report and same-name script log.
)
echo.
pause
exit /b %PG_RUNNER_RC%
