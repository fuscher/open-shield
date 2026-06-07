@echo off
setlocal enabledelayedexpansion

echo ========================================
echo    OpenShield - Uninstall Script
echo ========================================
echo.

set "PLUGIN_DIR=%USERPROFILE%\.config\opencode\plugins"
set "DATA_DIR=%USERPROFILE%\.openshield"
set "PLUGIN_FILE=%PLUGIN_DIR%\openshield-capture.ts"

echo [1/2] Removing plugin...
if exist "%PLUGIN_FILE%" (
    del /f /q "%PLUGIN_FILE%"
    echo       Removed: %PLUGIN_FILE%
) else (
    echo       Plugin not found, skipping.
)

echo [2/2] Cleaning up data directory...
echo.
set /p "DELETE_DATA=Do you want to delete captured data? (y/N): "
if /i "%DELETE_DATA%"=="y" (
    if exist "%DATA_DIR%" (
        rmdir /s /q "%DATA_DIR%"
        echo       Removed: %DATA_DIR%
    ) else (
        echo       Data directory not found, skipping.
    )
) else (
    echo       Data directory preserved at: %DATA_DIR%
)

echo.
echo ========================================
echo    Uninstall Complete!
echo ========================================
echo.
echo To reinstall, run: install.bat
echo.
pause
