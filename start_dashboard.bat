@echo off
setlocal enabledelayedexpansion
title OpenShield Dashboard

echo ========================================
echo   OpenShield Dashboard
echo ========================================
echo.

:: Check venv Python first, then fall back to global
set "SCRIPT_DIR=%~dp0"
set "VENV_PYTHON=%SCRIPT_DIR%.venv\Scripts\python.exe"
set "PYTHON_CMD="
if exist "%VENV_PYTHON%" (
    set "PYTHON_CMD=%VENV_PYTHON%"
    echo [INFO] Using venv Python: %VENV_PYTHON%
) else (
    for %%c in (py python python3) do (
        if "%%c"=="py" (
            py -3 --version >nul 2>&1
            if not errorlevel 1 set "PYTHON_CMD=py -3"
        ) else (
            %%c --version >nul 2>&1
            if not errorlevel 1 set "PYTHON_CMD=%%c"
        )
    )
    if "!PYTHON_CMD!"=="" (
        echo [ERROR] Python not found. Please run install.bat first.
        pause
        exit /b 1
    )
    echo [WARNING] venv not found. Using global Python. Consider running install.bat.
)

:: Check Flask
!PYTHON_CMD! -c "import flask" >nul 2>&1
if errorlevel 1 (
    echo [INFO] Installing Dashboard dependencies...
    !PYTHON_CMD! -m pip install -r "%SCRIPT_DIR%dashboard\requirements.txt" -q
    if errorlevel 1 (
        echo [ERROR] Dependencies installation failed.
        echo Please run manually: !PYTHON_CMD! -m pip install -r dashboard\requirements.txt
        pause
        exit /b 1
    )
)

:: Start service
echo [START] Starting Dashboard service...
echo [ACCESS] http://localhost:9528 (actual port shown in server.py output)
echo.
echo Press Ctrl+C to stop the service
echo.
!PYTHON_CMD! "%SCRIPT_DIR%dashboard\server.py"

pause
