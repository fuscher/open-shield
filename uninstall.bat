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

echo [0/9] Checking if OpenCode is running...
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

echo [1/9] Removing plugin...
if exist "%PLUGIN_FILE%" (
    del /f /q "%PLUGIN_FILE%"
    echo       Removed: %PLUGIN_FILE%
) else (
    echo       Plugin not found, skipping.
)

echo [2/9] Removing Skill...
if exist "%SKILL_DIR%" (
    rmdir /s /q "%SKILL_DIR%"
    echo       Removed: %SKILL_DIR%
) else (
    echo       Skill not found, skipping.
)

echo [3/9] Removing plugin config...
if exist "%DATA_DIR%\config.json" (
    del /f /q "%DATA_DIR%\config.json"
    echo       Removed: %DATA_DIR%\config.json
) else (
    echo       Config not found, skipping.
)

echo [4/9] Removing security files...
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
if exist "%DATA_DIR%\config.json.backup" (
    del /f /q "%DATA_DIR%\config.json.backup"
    echo       Removed: config.json.backup
) else (
    echo       config.json.backup not found, skipping.
)

echo [5/9] Removing Dashboard files...
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

echo [6/9] Cleaning up detection rules...
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

echo [7/9] Cleaning up log files...
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

echo [8/9] Cleaning up captured data...
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

echo [9/9] Uninstalling Python dependencies...
echo.
echo       Affected packages: fastapi uvicorn pydantic pyyaml flask
echo       NOTE: These are common dependencies that other projects may use.
echo.

set "PYTHON_CMD="
for %%c in (python python3) do (
    %%c --version >nul 2>&1
    if not errorlevel 1 set "PYTHON_CMD=%%c"
)

set /p "PIP_UNINSTALL=Do you want to uninstall them? (y/N): "
if /i "%PIP_UNINSTALL%"=="y" (
    if not "%PYTHON_CMD%"=="" (
        %PYTHON_CMD% -m pip uninstall -y fastapi uvicorn pydantic pyyaml flask 2>nul
        if not errorlevel 1 (
            echo       Dependencies uninstalled.
        ) else (
            echo       Some dependencies may not have been installed.
        )
    ) else (
        echo       Python not found, cannot uninstall. Remove manually with pip.
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
