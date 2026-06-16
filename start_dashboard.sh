#!/bin/bash

echo "========================================"
echo "  OpenShield Dashboard"
echo "========================================"
echo ""

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV_DIR="$SCRIPT_DIR/.venv"

# Detect venv python path (Linux/macOS or Git Bash/Windows)
if [ -f "$VENV_DIR/bin/python3" ]; then
    VENV_PYTHON="$VENV_DIR/bin/python3"
elif [ -f "$VENV_DIR/Scripts/python.exe" ]; then
    VENV_PYTHON="$VENV_DIR/Scripts/python.exe"
else
    echo "[ERROR] Virtual environment not found."
    echo "Please run install.sh first: ./install.sh"
    exit 1
fi

# Install dependencies if flask not available
if ! "$VENV_PYTHON" -c "import flask" &> /dev/null; then
    echo "[INFO] Installing Dashboard dependencies..."
    "$VENV_PYTHON" -m pip install -r "$SCRIPT_DIR/dashboard/requirements.txt" -q
    if [ $? -ne 0 ]; then
        echo "[ERROR] Dependencies installation failed."
        echo "Please run manually: $VENV_PYTHON -m pip install -r dashboard/requirements.txt"
        exit 1
    fi
fi

# Start service
echo "[START] Starting Dashboard service..."
echo "[ACCESS] http://localhost:9528 (actual port shown in server.py output)"
echo ""
echo "Press Ctrl+C to stop the service"
echo ""
"$VENV_PYTHON" "$SCRIPT_DIR/dashboard/server.py"
