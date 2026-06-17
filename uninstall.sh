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

echo "[0/11] Checking if OpenCode is running..."
if pgrep -x opencode >/dev/null 2>&1; then
    echo "      WARNING: OpenCode appears to be running."
    read -rp "      Continue with uninstall? (y/N): " CONTINUE
    if [ "$CONTINUE" != "y" ] && [ "$CONTINUE" != "Y" ]; then
        echo "      Uninstall cancelled."
        exit 0
    fi
fi

echo "[1/11] Removing plugin..."
if [ -f "$PLUGIN_FILE" ]; then
    rm -f "$PLUGIN_FILE"
    echo "      Removed: $PLUGIN_FILE"
else
    echo "      Plugin not found, skipping."
fi

echo "[2/11] Removing Skill..."
if [ -d "$SKILL_DIR" ]; then
    rm -rf "$SKILL_DIR"
    echo "      Removed: $SKILL_DIR"
else
    echo "      Skill not found, skipping."
fi

echo "[3/11] Removing plugin config..."
if [ -f "$DATA_DIR/config.json" ]; then
    rm -f "$DATA_DIR/config.json"
    echo "      Removed: $DATA_DIR/config.json"
else
    echo "      Config not found, skipping."
fi

echo "[4/11] Removing security files..."
if [ -f "$DATA_DIR/path_policy.json" ]; then
    rm -f "$DATA_DIR/path_policy.json"
    echo "      Removed: path_policy.json"
else
    echo "      path_policy.json not found, skipping."
fi
if [ -f "$DATA_DIR/service.token" ]; then
    rm -f "$DATA_DIR/service.token"
    echo "      Removed: service.token"
else
    echo "      service.token not found, skipping."
fi
shopt -s nullglob
for backup in "$DATA_DIR"/config.json.backup*; do
    rm -f "$backup"
    echo "      Removed: $(basename "$backup")"
done
shopt -u nullglob

echo "[5/11] Removing Dashboard files..."
for f in "$DATA_DIR/dashboard_config.json" "$DATA_DIR/dashboard_config.json.bak" "$DATA_DIR/config.json.bak"; do
    if [ -f "$f" ]; then
        rm -f "$f"
        echo "      Removed: $(basename "$f")"
    else
        echo "      $(basename "$f") not found, skipping."
    fi
done

echo "[6/11] Cleaning up detection rules..."
echo ""
read -rp "Do you want to delete detection rules? (y/N): " DELETE_RULES
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

echo "[7/11] Cleaning up log files..."
echo ""
read -rp "Do you want to delete log files? (y/N): " DELETE_LOGS
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

echo "[8/11] Cleaning up captured data..."
echo ""
read -rp "Do you want to delete captured data? (y/N): " DELETE_CAPTURES
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

echo "[9/11] Removing virtual environment..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV_DIR="$SCRIPT_DIR/.venv"
if [ -d "$VENV_DIR" ]; then
    read -rp "Do you want to delete the virtual environment (.venv)? (y/N): " DELETE_VENV
    if [ "$DELETE_VENV" = "y" ] || [ "$DELETE_VENV" = "Y" ]; then
        rm -rf "$VENV_DIR"
        echo "      Removed: $VENV_DIR"
    else
        echo "      Virtual environment preserved at: $VENV_DIR"
    fi
else
    echo "      Virtual environment not found, skipping."
fi

echo "[10/11] Removing project-level opencode.json..."
SCRIPT_DIR_CHECK="$(cd "$(dirname "$0")" && pwd)"
PROJECT_OPENCODE_JSON="$SCRIPT_DIR_CHECK/opencode.json"
if [ -f "$PROJECT_OPENCODE_JSON" ]; then
    read -rp "Do you want to delete project-level opencode.json? (y/N): " DELETE_OPENCODE_JSON
    if [ "$DELETE_OPENCODE_JSON" = "y" ] || [ "$DELETE_OPENCODE_JSON" = "Y" ]; then
        rm -f "$PROJECT_OPENCODE_JSON"
        echo "      Removed: $PROJECT_OPENCODE_JSON"
    else
        echo "      opencode.json preserved."
    fi
else
    echo "      opencode.json not found, skipping."
fi

echo "[11/11] Cleaning up empty directories..."
if [ -d "$DATA_DIR" ]; then
    rmdir "$DATA_DIR" 2>/dev/null && echo "      Removed empty directory: $DATA_DIR" || echo "      $DATA_DIR is not empty, preserved."
fi

echo ""
echo "========================================"
echo "   Uninstall Complete!"
echo "========================================"
echo ""
echo "To reinstall, run: ./install.sh"
echo ""
