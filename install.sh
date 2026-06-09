#!/bin/bash

echo "========================================"
echo "   OpenShield - Installation Script"
echo "========================================"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$HOME/.config/opencode/plugins"
SKILL_DIR="$HOME/.config/opencode/skills/openShield-safety"
RULES_DIR="$HOME/.openshield/rules"
LOGS_DIR="$HOME/.openshield/logs"
DATA_DIR="$HOME/.openshield/captures"
PLUGIN_SRC="$SCRIPT_DIR/src/plugin/open_shield.ts"
RULES_SRC="$SCRIPT_DIR/core/rules"

echo "[0/5] Checking environment..."

if ! python3 --version >/dev/null 2>&1; then
    echo "      ERROR: Python 3 not found. Install Python 3.9+ first."
    exit 1
fi
python3 -c "import sys; print(f'      Python {sys.version.split()[0]}')"

if ! python3 -m pip --version >/dev/null 2>&1; then
    echo "      ERROR: pip not found. Run: python3 -m ensurepip"
    exit 1
fi
echo "      pip OK"

if [ -d "$PLUGIN_DIR" ]; then
    echo "      OpenCode config found."
else
    echo "      NOTE: OpenCode config not found. Will be created on first OpenCode launch."
fi

echo "[1/5] Installing Python dependencies..."
cd "$SCRIPT_DIR"
pip install -r core/requirements.txt
if [ $? -ne 0 ]; then
    echo "      Retrying with Tsinghua mirror..."
    pip install -r core/requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple
    if [ $? -ne 0 ]; then
        echo "      WARNING: pip install failed. Install manually:"
        echo "        pip install -r core/requirements.txt"
    else
        echo "      Dependencies installed via mirror."
    fi
else
    echo "      Dependencies ready."
fi

echo "[2/5] Copying detection rules..."
mkdir -p "$RULES_DIR/custom"
if [ -f "$RULES_SRC/pii.yaml" ]; then
    cp "$RULES_SRC/pii.yaml" "$RULES_DIR/"
    echo "      pii.yaml installed."
fi
if [ -f "$RULES_SRC/keywords.yaml" ]; then
    cp "$RULES_SRC/keywords.yaml" "$RULES_DIR/"
    echo "      keywords.yaml installed."
fi

echo "[3/5] Installing plugin..."
mkdir -p "$PLUGIN_DIR"
if [ -f "$PLUGIN_SRC" ]; then
    cp "$PLUGIN_SRC" "$PLUGIN_DIR/open_shield.ts"
    echo "      Plugin installed to: $PLUGIN_DIR/open_shield.ts"
else
    echo "      ERROR: Plugin source not found at $PLUGIN_SRC"
    exit 1
fi

echo "[4/5] Installing Skill..."
mkdir -p "$SKILL_DIR"
if [ -f "$SCRIPT_DIR/.opencode/skills/openShield-safety/SKILL.md" ]; then
    cp "$SCRIPT_DIR/.opencode/skills/openShield-safety/SKILL.md" "$SKILL_DIR/"
    echo "      Skill installed to: $SKILL_DIR"
else
    echo "      Skill file not found, skipping."
fi

echo "[5/5] Creating directories and config..."
mkdir -p "$DATA_DIR"
mkdir -p "$LOGS_DIR"
echo "{\"project_dir\":\"$SCRIPT_DIR\"}" > "$HOME/.openshield/config.json"
echo "      Data dir: $DATA_DIR"
echo "      Logs dir: $LOGS_DIR"
echo "      Config written: $HOME/.openshield/config.json"

echo ""
echo "========================================"
echo "   Installation Complete!"
echo "========================================"
echo ""
echo "The plugin will auto-start the detection service on next OpenCode launch."
echo "To start manually: cd core && python openshield-detect.py"
echo ""
echo "To uninstall, run: ./uninstall.sh"
echo ""
