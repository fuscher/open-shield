@echo off
title OpenShield Dashboard

echo ========================================
echo   OpenShield Dashboard
echo ========================================
echo.

:: Check Python
python --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python not found. Please install Python first.
    pause
    exit /b 1
)

:: Check Flask
python -c "import flask" >nul 2>&1
if errorlevel 1 (
    echo [INFO] Installing Dashboard dependencies...
    python -m pip install -r "%~dp0dashboard\requirements.txt" -q
    if errorlevel 1 (
        echo [ERROR] Dependencies installation failed.
        echo Please run manually: python -m pip install -r dashboard\requirements.txt
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
python "%~dp0dashboard\server.py"

pause
