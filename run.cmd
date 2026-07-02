@echo off
REM ====================================================================
REM  uTPro Sandbox (SQLite) - one-click launcher for Windows
REM  - downloads the latest uTPro release PUBLISH asset (pre-built, no build)
REM  - points it at a local SQLite database (via appsettings.Production.json)
REM  - installs the .NET runtime locally if it is missing
REM  - runs the website; re-runs just start it again
REM ====================================================================
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

REM uTPro targets .NET 10 (Umbraco 17+). If the current release still targets
REM .NET 9 it rolls forward onto the .NET 10 runtime automatically.
set "DOTNET_CHANNEL=10.0"
set "PUBLISH_DIR=publish"
set "APP_DLL=uTPro.Project.Web.dll"
set "APP_URL=http://localhost:5000"
set "DOTNET_LOCAL=%~dp0.dotnet"

echo.
echo ==== uTPro Sandbox ^(SQLite^) launcher ====
echo.

REM --- 1/3  Ensure a .NET runtime is available ---
set "DOTNET_CMD=dotnet"
set "USE_LOCAL=0"
set "FOUND=0"
where dotnet >nul 2>nul
if not errorlevel 1 (
  for /f "delims=" %%v in ('dotnet --list-runtimes 2^>nul') do (
    echo %%v | findstr /r /c:"^Microsoft.AspNetCore.App 1[0-9]\." >nul && set "FOUND=1"
  )
)
if "!FOUND!"=="1" (
  echo [1/3] .NET 10 runtime ^(ASP.NET Core 10.0+^) was found.
) else (
  if exist "%DOTNET_LOCAL%\dotnet.exe" (
    echo [1/3] Using local .NET runtime in .dotnet\
  ) else (
    echo [1/3] Installing .NET runtime %DOTNET_CHANNEL% locally into .dotnet\ ^(first time only^)...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri https://dot.net/v1/dotnet-install.ps1 -OutFile \"$env:TEMP\dotnet-install.ps1\"; & \"$env:TEMP\dotnet-install.ps1\" -Channel %DOTNET_CHANNEL% -Runtime aspnetcore -InstallDir \"%DOTNET_LOCAL%\""
    if errorlevel 1 ( echo [ERROR] .NET runtime install failed. & pause & exit /b 1 )
  )
  set "USE_LOCAL=1"
)
if "!USE_LOCAL!"=="1" (
  set "DOTNET_CMD=%DOTNET_LOCAL%\dotnet.exe"
  set "DOTNET_ROOT=%DOTNET_LOCAL%"
  set "PATH=%DOTNET_LOCAL%;%PATH%"
)

REM --- 2/3  Download the release + configure SQLite ---
echo [2/3] Preparing the uTPro release ^(SQLite^)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\prepare-sqlite.ps1" -PublishDir "%PUBLISH_DIR%" -AppDll "%APP_DLL%"
if errorlevel 1 ( echo [ERROR] Failed to prepare the uTPro release. & pause & exit /b 1 )

REM --- 3/3  Run the website ---
echo [3/3] Starting the website at %APP_URL%
echo       Open %APP_URL%/umbraco to finish the first-time install ^(SQLite^).
echo       Press Ctrl+C in this window to stop.
echo.
set "ASPNETCORE_URLS=%APP_URL%"
set "ASPNETCORE_ENVIRONMENT=Production"
set "DOTNET_ROLL_FORWARD=Major"
start "" "%APP_URL%/umbraco"
pushd "%PUBLISH_DIR%"
"!DOTNET_CMD!" "%APP_DLL%"
popd

endlocal
