#!/bin/bash

echo "========================================"
echo "  OpenShield Dashboard"
echo "========================================"
echo ""

# Check Python
if ! command -v python3 &> /dev/null; then
    echo "[ERROR] Python3 not found. Please install Python first."
    exit 1
fi

# Check Flask
if ! python3 -c "import flask" &> /dev/null; then
    echo "[INFO] Installing Dashboard dependencies..."
    python3 -m pip install -r "$(dirname "$0")/dashboard/requirements.txt" -q
    if [ $? -ne 0 ]; then
        echo "[ERROR] Dependencies installation failed."
        echo "Please run manually: python3 -m pip install -r dashboard/requirements.txt"
        exit 1
    fi
fi

# Start service
echo "[START] Starting Dashboard service..."
echo "[ACCESS] http://localhost:9528 (actual port shown in server.py output)"
echo ""
echo "Press Ctrl+C to stop the service"
echo ""
python3 "$(dirname "$0")/dashboard/server.py"
