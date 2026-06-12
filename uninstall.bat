@echo off
setlocal enabledelayedexpansion

echo ========================================
echo    OpenShield - Uninstall Script
echo ========================================
echo.

set "PLUGIN_DIR=%USERPROFILE%\.config\opencode\plugins"
set "SKILL_DIR=%USERPROFILE%\.config\opencode\skills\openshield-safety"
set "DATA_DIR=%USERPROFILE%\.openshield"
set "PLUGIN_FILE=%PLUGIN_DIR%\open_shield.ts"
set "RULES_DIR=%DATA_DIR%\rules"
set "LOGS_DIR=%DATA_DIR%\logs"
set "CAPTURES_DIR=%DATA_DIR%\captures"

echo [1/7] Removing plugin...
if exist "%PLUGIN_FILE%" (
    del /f /q "%PLUGIN_FILE%"
    echo       Removed: %PLUGIN_FILE%
) else (
    echo       Plugin not found, skipping.
)

echo [2/7] Removing Skill...
if exist "%SKILL_DIR%" (
    rmdir /s /q "%SKILL_DIR%"
    echo       Removed: %SKILL_DIR%
) else (
    echo       Skill not found, skipping.
)

echo [3/7] Removing plugin config...
if exist "%DATA_DIR%\config.json" (
    del /f /q "%DATA_DIR%\config.json"
    echo       Removed: %DATA_DIR%\config.json
) else (
    echo       Config not found, skipping.
)

echo [4/7] Cleaning up detection rules...
echo.
set /p "DELETE_RULES=Do you want to delete custom rules? (y/N): "
if /i "%DELETE_RULES%"=="y" (
    if exist "%RULES_DIR%" (
        rmdir /s /q "%RULES_DIR%"
        echo       Removed: %RULES_DIR%
    ) else (
        echo       Rules directory not found, skipping.
    )
) else (
    echo       Rules preserved at: %RULES_DIR%
)

echo [5/7] Cleaning up log files...
echo.
set /p "DELETE_LOGS=Do you want to delete log files? (y/N): "
if /i "%DELETE_LOGS%"=="y" (
    if exist "%LOGS_DIR%" (
        rmdir /s /q "%LOGS_DIR%"
        echo       Removed: %LOGS_DIR%
    ) else (
        echo       Logs directory not found, skipping.
    )
) else (
    echo       Logs preserved at: %LOGS_DIR%
)

echo [6/7] Cleaning up captured data...
echo.
set /p "DELETE_CAPTURES=Do you want to delete captured data? (y/N): "
if /i "%DELETE_CAPTURES%"=="y" (
    if exist "%CAPTURES_DIR%" (
        rmdir /s /q "%CAPTURES_DIR%"
        echo       Removed: %CAPTURES_DIR%
    ) else (
        echo       Captures directory not found, skipping.
    )
) else (
    echo       Captured data preserved at: %CAPTURES_DIR%
)

echo [7/7] Uninstalling Python dependencies...
echo.
echo       Affected packages: fastapi uvicorn pydantic pyyaml
echo       NOTE: These are common dependencies that other projects may use.
echo.
set /p "PIP_UNINSTALL=Do you want to uninstall them? (y/N): "
if /i "%PIP_UNINSTALL%"=="y" (
    pip uninstall -y fastapi uvicorn pydantic pyyaml 2>nul
    if not errorlevel 1 (
        echo       Dependencies uninstalled.
    ) else (
        echo       Some dependencies may not have been installed.
    )
) else (
    echo       Dependencies preserved.
)

echo.
echo ========================================
echo    Uninstall Complete!
echo ========================================
echo.
echo To reinstall, run: install.bat
echo.
pause
