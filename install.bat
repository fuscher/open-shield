@echo off
setlocal enabledelayedexpansion

echo ========================================
echo    OpenShield - Installation Script
echo ========================================
echo.

set "PLUGIN_DIR=%USERPROFILE%\.config\opencode\plugins"
set "DATA_DIR=%USERPROFILE%\.openshield\captures"
set "PLUGIN_SRC=%~dp0src\plugin\openshield-capture.ts"

echo [1/3] Checking OpenCode config directory...
if not exist "%PLUGIN_DIR%" (
    mkdir "%PLUGIN_DIR%"
    echo       Created: %PLUGIN_DIR%
) else (
    echo       Found: %PLUGIN_DIR%
)

echo [2/3] Installing plugin...
if exist "%PLUGIN_SRC%" (
    copy /Y "%PLUGIN_SRC%" "%PLUGIN_DIR%\openshield-capture.ts" >nul
    echo       Plugin installed to: %PLUGIN_DIR%\openshield-capture.ts
) else (
    echo       ERROR: Plugin source not found at %PLUGIN_SRC%
    echo       Please run this script from the open-shield project directory.
    pause
    exit /b 1
)

echo [3/3] Creating data directory...
if not exist "%DATA_DIR%" (
    mkdir "%DATA_DIR%"
    echo       Created: %DATA_DIR%
) else (
    echo       Found: %DATA_DIR%
)

echo.
echo ========================================
echo    Installation Complete!
echo ========================================
echo.
echo Next steps:
echo   1. Restart OpenCode (TUI, Web, or Desktop)
echo   2. The plugin will automatically capture LLM responses
echo   3. Captured data is stored in: %DATA_DIR%
echo.
echo To uninstall, run: uninstall.bat
echo.
pause
