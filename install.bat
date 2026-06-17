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

echo [0/9] Checking environment...

set "PYTHON_CMD="
for %%c in (py python python3) do (
    if "%%c"=="py" (
        py -3 --version >nul 2>&1
        if not errorlevel 1 (
            set "PYTHON_CMD=py -3"
        )
    ) else (
        %%c --version >nul 2>&1
        if not errorlevel 1 (
            set "PYTHON_CMD=%%c"
        )
    )
)
if "!PYTHON_CMD!"=="" (
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

set "VENV_DIR=%PROJECT_DIR%.venv"
if not exist "%VENV_DIR%\Scripts\python.exe" (
    echo       Creating virtual environment...
    %PYTHON_CMD% -m venv "%VENV_DIR%"
    if exist "%VENV_DIR%\Scripts\python.exe" (
        echo       venv created: %VENV_DIR%
    ) else (
        echo       WARNING: venv creation failed, falling back to global Python.
    )
)
if exist "%VENV_DIR%\Scripts\python.exe" (
    set "PYTHON_CMD=%VENV_DIR%\Scripts\python.exe"
    echo       Using venv: %VENV_DIR%
)

echo [1/9] Installing Python dependencies...
cd /d "%PROJECT_DIR%"
!PYTHON_CMD! -m pip install -r core\requirements.txt
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

echo [2/9] Copying detection rules...
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
    set "_dir_err=!errorlevel!"
    if "!_dir_err!"=="0" (
        xcopy /Y /Q "%RULES_SRC%\custom\*.yaml" "%RULES_DIR%\custom\" >nul
        echo       custom rules installed.
    )
)

echo [3/9] Installing plugin...
if not exist "%PLUGIN_DIR%" mkdir "%PLUGIN_DIR%"
if exist "%PLUGIN_SRC%" (
    copy /Y "%PLUGIN_SRC%" "%PLUGIN_DIR%\open_shield.ts" >nul
    echo       Plugin installed to: %PLUGIN_DIR%\open_shield.ts
) else (
    echo       ERROR: Plugin source not found at %PLUGIN_SRC%
    pause
    exit /b 1
)

echo [4/9] Installing Skill...
if not exist "%SKILL_DIR%" mkdir "%SKILL_DIR%"
if exist "%PROJECT_DIR%.opencode\skills\openshield-safety\SKILL.md" (
    copy /Y "%PROJECT_DIR%.opencode\skills\openshield-safety\SKILL.md" "%SKILL_DIR%" >nul
    echo       Skill installed to: %SKILL_DIR%
) else (
    echo       Skill file not found, skipping.
)

echo [5/9] Creating directories and config...
if not exist "%DATA_DIR%" mkdir "%DATA_DIR%"
if not exist "%LOGS_DIR%" mkdir "%LOGS_DIR%"
set "CONFIG_FILE=%USERPROFILE%\.openshield\config.json"
if exist "%CONFIG_FILE%" (
    for /f "tokens=2 delims==" %%t in ('wmic os get localdatetime /value ^| find "="') do set "DT=%%t"
    set "BACKUP_TS=!DT:~0,14!"
    copy /Y "%CONFIG_FILE%" "%CONFIG_FILE%.backup.!BACKUP_TS!" >nul
    echo       Backed up existing config to: %CONFIG_FILE%.backup.!BACKUP_TS!
)
set "PROJECT_DIR_FWD=%PROJECT_DIR:\=/%"
set "PROJECT_DIR_FWD=%PROJECT_DIR_FWD:~0,-1%"
> "%CONFIG_FILE%" echo {"project_dir":"%PROJECT_DIR_FWD%","webhooks":[]}
echo       Data dir: %DATA_DIR%
echo       Logs dir: %LOGS_DIR%
echo       Config written: %USERPROFILE%\.openshield\config.json

echo [6/9] Dashboard configuration
set /p dashboard_port="Enter Dashboard port (default 9528): "
if "!dashboard_port!"=="" set dashboard_port=9528
echo !dashboard_port!| findstr /r "^[0-9][0-9]*$" >nul
if errorlevel 1 (
    echo       WARNING: Invalid port "!dashboard_port!", using default 9528.
    set dashboard_port=9528
)
:: Write dashboard_config.json (port passed as string, converted via int() to prevent injection)
%PYTHON_CMD% -c "import json; from pathlib import Path; p=Path.home()/'.openshield'/'dashboard_config.json'; d=json.load(open(p)) if p.exists() else {}; d['server_port']=int('!dashboard_port!'); json.dump(d, open(p,'w'), indent=2)"
echo       Dashboard port: %dashboard_port%

echo [7/9] Installing Dashboard dependencies
%PYTHON_CMD% -m pip install -r "%PROJECT_DIR%dashboard\requirements.txt" -q
if errorlevel 1 (
    echo       Retrying with Tsinghua mirror...
    %PYTHON_CMD% -m pip install -r "%PROJECT_DIR%dashboard\requirements.txt" -i https://pypi.tuna.tsinghua.edu.cn/simple -q
    if errorlevel 1 (
        echo [WARNING] Dependencies installation failed.
        echo Please run manually: pip install -r dashboard\requirements.txt
    ) else (
        echo       Dashboard dependencies installed via mirror.
    )
) else (
    echo       Dashboard dependencies installed.
)

echo [8/9] Generating security files...
set "POLICY_FILE=%USERPROFILE%\.openshield\path_policy.json"
if not exist "%POLICY_FILE%" (
    %PYTHON_CMD% -c "import json; from pathlib import Path; p=Path(r'%POLICY_FILE%'); p.write_text(json.dumps({'blacklist':['/etc/**','/boot/**','~/.ssh/**','~/.gnupg/**','C:\\Windows\\**','C:\\Program Files\\**','**/.env','**/credentials','**/id_rsa','**/*.pem'],'whitelist':['/tmp/**','/home/*/projects/**','~/work/**','D:\\Git\\**','C:\\Users\\*\\Documents\\**'],'sensitive_read_patterns':['~/.ssh/**','~/.aws/**','**/.env','**/config.json','/etc/passwd','/etc/shadow'],'learning_mode':True},indent=2))"
    echo       Path policy written: %POLICY_FILE%
) else (
    echo       Path policy already exists: %POLICY_FILE%
)

REM Generate service token
set "TOKEN_FILE=%USERPROFILE%\.openshield\service.token"
if not exist "%TOKEN_FILE%" (
    REM Generate random token using cryptographically secure PRNG
    powershell -Command "$bytes = New-Object byte[] 32; [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes); $token = -join ($bytes | ForEach-Object { '{0:x2}' -f $_ }); Set-Content -Path '%TOKEN_FILE%' -Value $token -NoNewline"
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

echo [9/9] Generating project opencode.json...
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
