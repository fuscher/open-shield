@echo off
setlocal enabledelayedexpansion

echo ========================================
echo    OpenShield - Installation Script
echo ========================================
echo.

set "PROJECT_DIR=%~dp0"
set "PLUGIN_DIR=%USERPROFILE%\.config\opencode\plugins"
set "SKILL_DIR=%USERPROFILE%\.config\opencode\skills\openshield-safety"
set "RULES_DIR=%USERPROFILE%\.openshield\rules"
set "LOGS_DIR=%USERPROFILE%\.openshield\logs"
set "DATA_DIR=%USERPROFILE%\.openshield\captures"
set "PLUGIN_SRC=%PROJECT_DIR%src\plugin\open_shield.ts"
set "RULES_SRC=%PROJECT_DIR%core\rules"

echo [0/5] Checking environment...

python --version >nul 2>&1
if errorlevel 1 (
    echo       ERROR: Python not found. Install Python 3.9+ first.
    pause
    exit /b 1
)
python -c "import sys; print('      Python', sys.version.split()[0])"

python -m pip --version >nul 2>&1
if errorlevel 1 (
    echo       ERROR: pip not found. Run: python -m ensurepip
    pause
    exit /b 1
)
echo       pip OK

if exist "%PLUGIN_DIR%" (
    echo       OpenCode config found.
) else (
    echo       NOTE: OpenCode config not found. Will be created on first OpenCode launch.
)

echo [1/5] Installing Python dependencies...
cd /d "%PROJECT_DIR%"
pip install -r core\requirements.txt
if errorlevel 1 (
    echo       Retrying with Tsinghua mirror...
    pip install -r core\requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple
    if errorlevel 1 (
        echo       WARNING: pip install failed. Install manually:
        echo         pip install -r core\requirements.txt
    ) else (
        echo       Dependencies installed via mirror.
    )
) else (
    echo       Dependencies ready.
)

echo [2/5] Copying detection rules...
if not exist "%RULES_DIR%" mkdir "%RULES_DIR%"
if not exist "%RULES_DIR%\custom" mkdir "%RULES_DIR%\custom"
if exist "%RULES_SRC%\pii.yaml" (
    copy /Y "%RULES_SRC%\pii.yaml" "%RULES_DIR%" >nul
    echo       pii.yaml installed.
)
if exist "%RULES_SRC%\keywords.yaml" (
    copy /Y "%RULES_SRC%\keywords.yaml" "%RULES_DIR%" >nul
    echo       keywords.yaml installed.
)
if exist "%RULES_SRC%\injection.yaml" (
    copy /Y "%RULES_SRC%\injection.yaml" "%RULES_DIR%" >nul
    echo       injection.yaml installed.
)
if exist "%RULES_SRC%\custom\*.yaml" (
    xcopy /Y /Q "%RULES_SRC%\custom\*.yaml" "%RULES_DIR%\custom\" >nul
    echo       custom rules installed.
)

echo [3/5] Installing plugin...
if not exist "%PLUGIN_DIR%" mkdir "%PLUGIN_DIR%"
if exist "%PLUGIN_SRC%" (
    copy /Y "%PLUGIN_SRC%" "%PLUGIN_DIR%\open_shield.ts" >nul
    echo       Plugin installed to: %PLUGIN_DIR%\open_shield.ts
) else (
    echo       ERROR: Plugin source not found at %PLUGIN_SRC%
    pause
    exit /b 1
)

echo [4/5] Installing Skill...
if not exist "%SKILL_DIR%" mkdir "%SKILL_DIR%"
if exist "%PROJECT_DIR%.opencode\skills\openshield-safety\SKILL.md" (
    copy /Y "%PROJECT_DIR%.opencode\skills\openshield-safety\SKILL.md" "%SKILL_DIR%" >nul
    echo       Skill installed to: %SKILL_DIR%
) else (
    echo       Skill file not found, skipping.
)

echo [5/5] Creating directories and config...
if not exist "%DATA_DIR%" mkdir "%DATA_DIR%"
if not exist "%LOGS_DIR%" mkdir "%LOGS_DIR%"
set "PROJECT_DIR_FWD=%PROJECT_DIR:\=/%"
set "PROJECT_DIR_FWD=%PROJECT_DIR_FWD:~0,-1%"
> "%USERPROFILE%\.openshield\config.json" echo {"project_dir":"%PROJECT_DIR_FWD%","webhooks":[]}
echo       Data dir: %DATA_DIR%
echo       Logs dir: %LOGS_DIR%
echo       Config written: %USERPROFILE%\.openshield\config.json

echo.
echo ========================================
echo    Installation Complete!
echo ========================================
echo.
echo The plugin will auto-start the detection service on next OpenCode launch.
echo To start manually: cd core ^& python openshield-detect.py
echo.
echo To uninstall, run: uninstall.bat
echo.
pause
