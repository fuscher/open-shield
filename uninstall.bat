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

echo [0/11] Checking if OpenCode is running...
tasklist /FI "IMAGENAME eq opencode.exe" 2>nul | find /I "opencode.exe" >nul
if not errorlevel 1 (
    echo       WARNING: OpenCode appears to be running.
    set CONTINUE=n
    set /p "CONTINUE=      Continue with uninstall? (y/N): "
    if /i not "!CONTINUE!"=="y" (
        echo       Uninstall cancelled.
        pause
        exit /b 0
    )
)

echo [1/11] Removing plugin...
if exist "%PLUGIN_FILE%" (
    del /f /q "%PLUGIN_FILE%"
    echo       Removed: %PLUGIN_FILE%
) else (
    echo       Plugin not found, skipping.
)

echo [2/11] Removing Skill...
if exist "%SKILL_DIR%" (
    rmdir /s /q "%SKILL_DIR%"
    echo       Removed: %SKILL_DIR%
) else (
    echo       Skill not found, skipping.
)

echo [3/11] Removing plugin config...
if exist "%DATA_DIR%\config.json" (
    del /f /q "%DATA_DIR%\config.json"
    echo       Removed: %DATA_DIR%\config.json
) else (
    echo       Config not found, skipping.
)

echo [4/11] Removing security files...
if exist "%DATA_DIR%\path_policy.json" (
    del /f /q "%DATA_DIR%\path_policy.json"
    echo       Removed: path_policy.json
) else (
    echo       path_policy.json not found, skipping.
)
if exist "%DATA_DIR%\service.token" (
    del /f /q "%DATA_DIR%\service.token"
    echo       Removed: service.token
) else (
    echo       service.token not found, skipping.
)
if exist "%DATA_DIR%\config.json.backup*" (
    del /f /q "%DATA_DIR%\config.json.backup*"
    echo       Removed: config.json.backup files
) else (
    echo       config.json.backup not found, skipping.
)

echo [5/11] Removing Dashboard files...
if exist "%DATA_DIR%\dashboard_config.json" (
    del /f /q "%DATA_DIR%\dashboard_config.json"
    echo       Removed: dashboard_config.json
) else (
    echo       dashboard_config.json not found, skipping.
)
if exist "%DATA_DIR%\dashboard_config.json.bak" (
    del /f /q "%DATA_DIR%\dashboard_config.json.bak"
    echo       Removed: dashboard_config.json.bak
) else (
    echo       dashboard_config.json.bak not found, skipping.
)
if exist "%DATA_DIR%\config.json.bak" (
    del /f /q "%DATA_DIR%\config.json.bak"
    echo       Removed: config.json.bak
) else (
    echo       config.json.bak not found, skipping.
)

echo [6/11] Cleaning up detection rules...
echo.
set /p "DELETE_RULES=Do you want to delete detection rules? (y/N): "
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

echo [7/11] Cleaning up log files...
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

echo [8/11] Cleaning up captured data...
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

echo [9/11] Removing virtual environment...
set "SCRIPT_DIR=%~dp0"
set "VENV_DIR=%SCRIPT_DIR%.venv"
if exist "%VENV_DIR%" (
    echo.
    set /p "DELETE_VENV=Do you want to delete the virtual environment (.venv)? (y/N): "
    if /i "!DELETE_VENV!"=="y" (
        rmdir /s /q "%VENV_DIR%"
        echo       Removed: %VENV_DIR%
    ) else (
        echo       Virtual environment preserved at: %VENV_DIR%
    )
) else (
    echo       Virtual environment not found, skipping.
)

echo [10/11] Removing project-level opencode.json...
set "PROJECT_OPENCODE_JSON=%SCRIPT_DIR%opencode.json"
if exist "%PROJECT_OPENCODE_JSON%" (
    echo.
    set /p "DELETE_OPENCODE_JSON=Do you want to delete project-level opencode.json? (y/N): "
    if /i "!DELETE_OPENCODE_JSON!"=="y" (
        del /f /q "%PROJECT_OPENCODE_JSON%"
        echo       Removed: %PROJECT_OPENCODE_JSON%
    ) else (
        echo       opencode.json preserved.
    )
) else (
    echo       opencode.json not found, skipping.
)

echo [11/11] Cleaning up empty directories...
if exist "%DATA_DIR%" (
    rmdir "%DATA_DIR%" 2>nul
    if not exist "%DATA_DIR%" (
        echo       Removed empty directory: %DATA_DIR%
    ) else (
        echo       %DATA_DIR% is not empty, preserved.
    )
)

echo.
echo ========================================
echo    Uninstall Complete!
echo ========================================
echo.
echo To reinstall, run: install.bat
echo.
pause
