#!/bin/bash

echo "========================================"
echo "   OpenShield - Uninstall Script"
echo "========================================"
echo ""

PLUGIN_DIR="$HOME/.config/opencode/plugins"
DATA_DIR="$HOME/.openshield"
PLUGIN_FILE="$PLUGIN_DIR/openshield-capture.ts"

echo "[1/2] Removing plugin..."
if [ -f "$PLUGIN_FILE" ]; then
    rm -f "$PLUGIN_FILE"
    echo "      Removed: $PLUGIN_FILE"
else
    echo "      Plugin not found, skipping."
fi

echo "[2/2] Cleaning up data directory..."
echo ""
read -p "Do you want to delete captured data? (y/N): " DELETE_DATA
if [ "$DELETE_DATA" = "y" ] || [ "$DELETE_DATA" = "Y" ]; then
    if [ -d "$DATA_DIR" ]; then
        rm -rf "$DATA_DIR"
        echo "      Removed: $DATA_DIR"
    else
        echo "      Data directory not found, skipping."
    fi
else
    echo "      Data directory preserved at: $DATA_DIR"
fi

echo ""
echo "========================================"
echo "   Uninstall Complete!"
echo "========================================"
echo ""
echo "To reinstall, run: ./install.sh"
echo ""
