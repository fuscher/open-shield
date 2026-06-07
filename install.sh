#!/bin/bash

echo "========================================"
echo "   OpenShield - Installation Script"
echo "========================================"
echo ""

PLUGIN_DIR="$HOME/.config/opencode/plugins"
DATA_DIR="$HOME/.openshield/captures"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_SRC="$SCRIPT_DIR/src/plugin/openshield-capture.ts"

echo "[1/3] Checking OpenCode config directory..."
if [ ! -d "$PLUGIN_DIR" ]; then
    mkdir -p "$PLUGIN_DIR"
    echo "      Created: $PLUGIN_DIR"
else
    echo "      Found: $PLUGIN_DIR"
fi

echo "[2/3] Installing plugin..."
if [ -f "$PLUGIN_SRC" ]; then
    cp "$PLUGIN_SRC" "$PLUGIN_DIR/openshield-capture.ts"
    echo "      Plugin installed to: $PLUGIN_DIR/openshield-capture.ts"
else
    echo "      ERROR: Plugin source not found at $PLUGIN_SRC"
    echo "      Please run this script from the open-shield project directory."
    exit 1
fi

echo "[3/3] Creating data directory..."
if [ ! -d "$DATA_DIR" ]; then
    mkdir -p "$DATA_DIR"
    echo "      Created: $DATA_DIR"
else
    echo "      Found: $DATA_DIR"
fi

echo ""
echo "========================================"
echo "   Installation Complete!"
echo "========================================"
echo ""
echo "Next steps:"
echo "  1. Restart OpenCode (TUI, Web, or Desktop)"
echo "  2. The plugin will automatically capture LLM responses"
echo "  3. Captured data is stored in: $DATA_DIR"
echo ""
echo "To uninstall, run: ./uninstall.sh"
echo ""
