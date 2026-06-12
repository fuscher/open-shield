#!/bin/bash

echo "========================================"
echo "   OpenShield - Uninstall Script"
echo "========================================"
echo ""

PLUGIN_DIR="$HOME/.config/opencode/plugins"
SKILL_DIR="$HOME/.config/opencode/skills/openshield-safety"
DATA_DIR="$HOME/.openshield"
PLUGIN_FILE="$PLUGIN_DIR/open_shield.ts"
RULES_DIR="$DATA_DIR/rules"
LOGS_DIR="$DATA_DIR/logs"
CAPTURES_DIR="$DATA_DIR/captures"

echo "[1/7] Removing plugin..."
if [ -f "$PLUGIN_FILE" ]; then
    rm -f "$PLUGIN_FILE"
    echo "      Removed: $PLUGIN_FILE"
else
    echo "      Plugin not found, skipping."
fi

echo "[2/7] Removing Skill..."
if [ -d "$SKILL_DIR" ]; then
    rm -rf "$SKILL_DIR"
    echo "      Removed: $SKILL_DIR"
else
    echo "      Skill not found, skipping."
fi

echo "[3/7] Removing plugin config..."
if [ -f "$DATA_DIR/config.json" ]; then
    rm -f "$DATA_DIR/config.json"
    echo "      Removed: $DATA_DIR/config.json"
else
    echo "      Config not found, skipping."
fi

echo "[4/7] Cleaning up detection rules..."
echo ""
read -p "Do you want to delete custom rules? (y/N): " DELETE_RULES
if [ "$DELETE_RULES" = "y" ] || [ "$DELETE_RULES" = "Y" ]; then
    if [ -d "$RULES_DIR" ]; then
        rm -rf "$RULES_DIR"
        echo "      Removed: $RULES_DIR"
    else
        echo "      Rules directory not found, skipping."
    fi
else
    echo "      Rules preserved at: $RULES_DIR"
fi

echo "[5/7] Cleaning up log files..."
echo ""
read -p "Do you want to delete log files? (y/N): " DELETE_LOGS
if [ "$DELETE_LOGS" = "y" ] || [ "$DELETE_LOGS" = "Y" ]; then
    if [ -d "$LOGS_DIR" ]; then
        rm -rf "$LOGS_DIR"
        echo "      Removed: $LOGS_DIR"
    else
        echo "      Logs directory not found, skipping."
    fi
else
    echo "      Logs preserved at: $LOGS_DIR"
fi

echo "[6/7] Cleaning up captured data..."
echo ""
read -p "Do you want to delete captured data? (y/N): " DELETE_CAPTURES
if [ "$DELETE_CAPTURES" = "y" ] || [ "$DELETE_CAPTURES" = "Y" ]; then
    if [ -d "$CAPTURES_DIR" ]; then
        rm -rf "$CAPTURES_DIR"
        echo "      Removed: $CAPTURES_DIR"
    else
        echo "      Captures directory not found, skipping."
    fi
else
    echo "      Captured data preserved at: $CAPTURES_DIR"
fi

echo "[7/7] Uninstalling Python dependencies..."
echo ""
echo "      Affected packages: fastapi uvicorn pydantic pyyaml"
echo "      NOTE: These are common dependencies that other projects may use."
echo ""
read -p "Do you want to uninstall them? (y/N): " PIP_UNINSTALL
if [ "$PIP_UNINSTALL" = "y" ] || [ "$PIP_UNINSTALL" = "Y" ]; then
    pip uninstall -y fastapi uvicorn pydantic pyyaml 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "      Dependencies uninstalled."
    else
        echo "      Some dependencies may not have been installed."
    fi
else
    echo "      Dependencies preserved."
fi

echo ""
echo "========================================"
echo "   Uninstall Complete!"
echo "========================================"
echo ""
echo "To reinstall, run: ./install.sh"
echo ""
