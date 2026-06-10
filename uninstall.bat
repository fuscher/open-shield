@echo off
setlocal enabledelayedexpansion

echo ========================================
echo    OpenShield - Uninstall Script
echo ========================================
echo.

set "PLUGIN_DIR=%USERPROFILE%\.config\opencode\plugins"
set "DATA_DIR=%USERPROFILE%\.openshield"
set "PLUGIN_FILE=%PLUGIN_DIR%\open_shield.ts"

echo [1/3] Removing plugin...
if exist "%PLUGIN_FILE%" (
    del /f /q "%PLUGIN_FILE%"
    echo       Removed: %PLUGIN_FILE%
) else (
    echo       Plugin not found, skipping.
)

echo [1.5/3] Removing Skill...
set "SKILL_DIR=%USERPROFILE%\.config\opencode\skills\openShield-safety"
if exist "%SKILL_DIR%" (
    rmdir /s /q "%SKILL_DIR%"
    echo       Removed: %SKILL_DIR%
) else (
    echo       Skill not found, skipping.
)

echo [2/3] Removing plugin config...
if exist "%DATA_DIR%\config.json" (
    del /f /q "%DATA_DIR%\config.json"
    echo       Removed: %DATA_DIR%\config.json
) else (
    echo       Config not found, skipping.
)

echo [3/3] Cleaning up data directory...
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
