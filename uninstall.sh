#!/bin/bash

echo "========================================"
echo "   OpenShield - Uninstall Script"
echo "========================================"
echo ""

PLUGIN_DIR="$HOME/.config/opencode/plugins"
DATA_DIR="$HOME/.openshield"
PLUGIN_FILE="$PLUGIN_DIR/open_shield.ts"

echo "[1/3] Removing plugin..."
if [ -f "$PLUGIN_FILE" ]; then
    rm -f "$PLUGIN_FILE"
    echo "      Removed: $PLUGIN_FILE"
else
    echo "      Plugin not found, skipping."
fi

echo "[1.5/3] Removing Skill..."
SKILL_DIR="$HOME/.config/opencode/skills/openShield-safety"
if [ -d "$SKILL_DIR" ]; then
    rm -rf "$SKILL_DIR"
    echo "      Removed: $SKILL_DIR"
else
    echo "      Skill not found, skipping."
fi

echo "[2/3] Removing plugin config..."
if [ -f "$DATA_DIR/config.json" ]; then
    rm -f "$DATA_DIR/config.json"
    echo "      Removed: $DATA_DIR/config.json"
else
    echo "      Config not found, skipping."
fi

echo "[3/3] Cleaning up data directory..."
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
