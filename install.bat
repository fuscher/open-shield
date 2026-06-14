@echo off
setlocal enabledelayedexpansion

echo ========================================
echo    OpenShield - Installation Script
echo ========================================
echo.

net session >nul 2>&1
if errorlevel 1 (
    echo NOTE: Running without administrator privileges.
    echo If installation fails, try running as administrator.
    echo.
)

set "PROJECT_DIR=%~dp0"
set "PLUGIN_DIR=%USERPROFILE%\.config\opencode\plugins"
set "SKILL_DIR=%USERPROFILE%\.config\opencode\skills\openshield-safety"
set "RULES_DIR=%USERPROFILE%\.openshield\rules"
set "LOGS_DIR=%USERPROFILE%\.openshield\logs"
set "DATA_DIR=%USERPROFILE%\.openshield\captures"
set "PLUGIN_SRC=%PROJECT_DIR%src\plugin\open_shield.ts"
set "RULES_SRC=%PROJECT_DIR%core\rules"

echo [0/5] Checking environment...

set "PYTHON_CMD="
for %%c in (python python3) do (
    %%c --version >nul 2>&1
    if not errorlevel 1 (
        set "PYTHON_CMD=%%c"
    )
)
if "%PYTHON_CMD%"=="" (
    echo       ERROR: Python not found. Install Python 3.9+ first.
    pause
    exit /b 1
)
%PYTHON_CMD% -c "import sys; print('      Python', sys.version.split()[0])"

%PYTHON_CMD% -c "import sys; exit(0 if sys.version_info >= (3, 9) else 1)" >nul 2>&1
if errorlevel 1 (
    %PYTHON_CMD% -c "import sys; print('      ERROR: Python 3.9+ required. Found:', f'{sys.version_info.major}.{sys.version_info.minor}')"
    pause
    exit /b 1
)

%PYTHON_CMD% -m pip --version >nul 2>&1
if errorlevel 1 (
    echo       ERROR: pip not found. Run: %PYTHON_CMD% -m ensurepip
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
%PYTHON_CMD% -m pip install -r core\requirements.txt
if errorlevel 1 (
    echo       Retrying with Tsinghua mirror...
    %PYTHON_CMD% -m pip install -r core\requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple
    if errorlevel 1 (
        echo       WARNING: pip install failed. Install manually:
        echo         %PYTHON_CMD% -m pip install -r core\requirements.txt
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
if exist "%RULES_SRC%\response_guard.yaml" (
    copy /Y "%RULES_SRC%\response_guard.yaml" "%RULES_DIR%" >nul
    echo       response_guard.yaml installed.
)
if exist "%RULES_SRC%\output_sensitivity.yaml" (
    copy /Y "%RULES_SRC%\output_sensitivity.yaml" "%RULES_DIR%" >nul
    echo       output_sensitivity.yaml installed.
)
if exist "%RULES_SRC%\custom\" (
    dir /b "%RULES_SRC%\custom\*.yaml" >nul 2>&1
    if not errorlevel 1 (
        xcopy /Y /Q "%RULES_SRC%\custom\*.yaml" "%RULES_DIR%\custom\" >nul
        echo       custom rules installed.
    )
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
set "CONFIG_FILE=%USERPROFILE%\.openshield\config.json"
if exist "%CONFIG_FILE%" (
    copy /Y "%CONFIG_FILE%" "%CONFIG_FILE%.backup" >nul
    echo       Backed up existing config to: %CONFIG_FILE%.backup
)
set "PROJECT_DIR_FWD=%PROJECT_DIR:\=/%"
set "PROJECT_DIR_FWD=%PROJECT_DIR_FWD:~0,-1%"
> "%CONFIG_FILE%" echo {"project_dir":"%PROJECT_DIR_FWD%","webhooks":[]}
echo       Data dir: %DATA_DIR%
echo       Logs dir: %LOGS_DIR%
echo       Config written: %USERPROFILE%\.openshield\config.json

REM Phase B: Create path_policy.json
set "POLICY_FILE=%USERPROFILE%\.openshield\path_policy.json"
if not exist "%POLICY_FILE%" (
    > "%POLICY_FILE%" echo {
    >> "%POLICY_FILE%" echo   "blacklist": [
    >> "%POLICY_FILE%" echo     "/etc/**",
    >> "%POLICY_FILE%" echo     "/boot/**",
    >> "%POLICY_FILE%" echo     "~/.ssh/**",
    >> "%POLICY_FILE%" echo     "~/.gnupg/**",
    >> "%POLICY_FILE%" echo     "C:\\Windows\\**",
    >> "%POLICY_FILE%" echo     "C:\\Program Files\\**",
    >> "%POLICY_FILE%" echo     "**/.env",
    >> "%POLICY_FILE%" echo     "**/credentials",
    >> "%POLICY_FILE%" echo     "**/id_rsa",
    >> "%POLICY_FILE%" echo     "**/*.pem"
    >> "%POLICY_FILE%" echo   ],
    >> "%POLICY_FILE%" echo   "whitelist": [
    >> "%POLICY_FILE%" echo     "/tmp/**",
    >> "%POLICY_FILE%" echo     "/home/*/projects/**",
    >> "%POLICY_FILE%" echo     "~/work/**",
    >> "%POLICY_FILE%" echo     "D:\\Git\\**",
    >> "%POLICY_FILE%" echo     "C:\\Users\\*\\Documents\\**"
    >> "%POLICY_FILE%" echo   ],
    >> "%POLICY_FILE%" echo   "sensitive_read_patterns": [
    >> "%POLICY_FILE%" echo     "~/.ssh/**",
    >> "%POLICY_FILE%" echo     "~/.aws/**",
    >> "%POLICY_FILE%" echo     "**/.env",
    >> "%POLICY_FILE%" echo     "**/config.json",
    >> "%POLICY_FILE%" echo     "/etc/passwd",
    >> "%POLICY_FILE%" echo     "/etc/shadow"
    >> "%POLICY_FILE%" echo   ],
    >> "%POLICY_FILE%" echo   "learning_mode": true
    >> "%POLICY_FILE%" echo }
    echo       Path policy written: %POLICY_FILE%
) else (
    echo       Path policy already exists: %POLICY_FILE%
)

REM Phase 加固: Generate service token
set "TOKEN_FILE=%USERPROFILE%\.openshield\service.token"
if not exist "%TOKEN_FILE%" (
    REM Generate random token using PowerShell
    powershell -Command "$token = -join ((1..32) | ForEach-Object { '{0:x2}' -f (Get-Random -Max 256) }); Set-Content -Path '%TOKEN_FILE%' -Value $token -NoNewline"
    echo       Service token generated: %TOKEN_FILE%
) else (
    echo       Service token already exists: %TOKEN_FILE%
)

echo.
echo ========================================
echo    Installation Complete!
echo ========================================
echo.
echo The plugin will auto-start the detection service on next OpenCode launch.
echo To start manually: cd core ^& %PYTHON_CMD% openshield-detect.py
echo.
echo ========================================
echo    IMPORTANT: Permission Configuration
echo ========================================
echo.
echo OpenShield requires bash permission set to "ask" for security checks.
echo.
echo Please add the following to your opencode.json:
echo.
echo {
echo   "permission": {
echo     "bash": {
echo       "*": "ask",
echo       "git *": "allow",
echo       "git status*": "allow",
echo       "git diff*": "allow",
echo       "git log*": "allow",
echo       "ls *": "allow",
echo       "ls": "allow",
echo       "cat *": "allow",
echo       "npm *": "allow",
echo       "yarn *": "allow",
echo       "pnpm *": "allow",
echo       "bun *": "allow",
echo       "node *": "allow",
echo       "python *": "allow",
echo       "pip *": "allow",
echo       "tsc *": "allow",
echo       "eslint *": "allow",
echo       "prettier *": "allow",
echo       "docker *": "allow"
echo     }
echo   }
echo }
echo.
echo Location:
echo   Global: %%USERPROFILE%%\.config\opencode\opencode.json
echo   Project: .\opencode.json
echo.
echo To uninstall, run: uninstall.bat
echo.

REM Generate project-level opencode.json
set "PROJECT_OPENCODE_JSON=%PROJECT_DIR%opencode.json"
if not exist "%PROJECT_OPENCODE_JSON%" (
    (
        echo {
        echo   "permission": {
        echo     "bash": {
        echo       "*": "ask",
        echo       "git *": "allow",
        echo       "git status*": "allow",
        echo       "git diff*": "allow",
        echo       "git log*": "allow",
        echo       "ls *": "allow",
        echo       "ls": "allow",
        echo       "cat *": "allow",
        echo       "npm *": "allow",
        echo       "yarn *": "allow",
        echo       "pnpm *": "allow",
        echo       "bun *": "allow",
        echo       "node *": "allow",
        echo       "python *": "allow",
        echo       "pip *": "allow",
        echo       "tsc *": "allow",
        echo       "eslint *": "allow",
        echo       "prettier *": "allow",
        echo       "docker *": "allow"
        echo     }
        echo   }
        echo }
    ) > "%PROJECT_OPENCODE_JSON%"
    echo       Created: %PROJECT_OPENCODE_JSON%
    echo       Permission config will be merged with global config.
) else (
    echo       NOTE: opencode.json already exists at %PROJECT_OPENCODE_JSON%
    echo       Please add permission config manually (see above^).
)

pause
