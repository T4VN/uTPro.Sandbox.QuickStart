@echo off
REM ====================================================================
REM  uTPro Sandbox (SQLite) - uninstall / clean-up for Windows
REM  Stops the running site and deletes everything the launcher generated,
REM  returning the folder to its clean checked-in (git) state.
REM
REM  Usage:  uninstall.cmd        (asks for confirmation)
REM          uninstall.cmd -y     (no prompt)
REM ====================================================================
setlocal EnableExtensions EnableDelayedExpansion
REM Scripts live in win\ ; clean up generated files at the repo ROOT (parent).
cd /d "%~dp0.."

set "FORCE="
if /i "%~1"=="-y"     set "FORCE=1"
if /i "%~1"=="/y"     set "FORCE=1"
if /i "%~1"=="force"  set "FORCE=1"

echo.
echo ==== uTPro Sandbox ^(SQLite^) uninstall ====
echo.
echo This will stop the running site and delete generated files:
echo   - publish\                       ^(release output + SQLite database^)
echo   - .dotnet\                        ^(locally installed .NET runtime^)
echo   - sandbox.config / sandbox.config.json
echo   - downloaded archives / installers
echo The repo returns to its clean checked-in state.
echo.

if not defined FORCE (
  set /p "CONFIRM=Continue? (y/N): "
  if /i not "!CONFIRM!"=="y" ( echo Cancelled. & endlocal & exit /b 0 )
)

echo.
echo Stopping the uTPro sandbox process ^(if running^)...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_Process | Where-Object { ($_.Name -eq 'dotnet.exe' -or $_.Name -eq 'uTPro.Project.Web.exe') -and $_.CommandLine -match 'uTPro\.Project\.Web' } | ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop; Write-Host ('  stopped PID ' + $_.ProcessId) } catch {} }"

echo Removing generated files...
for %%D in (publish .dotnet) do if exist "%%D" ( rmdir /s /q "%%D" & echo   removed %%D\ )
for %%F in (sandbox.config sandbox.config.json dotnet-install.ps1 dotnet-install.sh) do if exist "%%F" ( del /q "%%F" & echo   removed %%F )
if exist publish_output*.zip ( del /q publish_output*.zip & echo   removed publish_output*.zip )

echo.
echo Done. The sandbox is back to a clean state - run run.cmd to set it up again.
endlocal
