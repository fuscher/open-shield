#!/bin/bash

echo "========================================"
echo "   OpenShield - Installation Script"
echo "========================================"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$HOME/.config/opencode/plugins"
SKILL_DIR="$HOME/.config/opencode/skills/openshield-safety"
RULES_DIR="$HOME/.openshield/rules"
LOGS_DIR="$HOME/.openshield/logs"
DATA_DIR="$HOME/.openshield/captures"
PLUGIN_SRC="$SCRIPT_DIR/src/plugin/open_shield.ts"
RULES_SRC="$SCRIPT_DIR/core/rules"

echo "[0/9] Checking environment..."

PYTHON_CMD=""
for cmd in python3 python; do
    if "$cmd" --version >/dev/null 2>&1; then
        PYTHON_CMD="$cmd"
        break
    fi
done
if [ -z "$PYTHON_CMD" ]; then
    echo "      ERROR: Python not found. Install Python 3.9+ first."
    exit 1
fi
$PYTHON_CMD -c "import sys; print(f'      Python {sys.version.split()[0]}')"

if ! $PYTHON_CMD -c "import sys; exit(0 if sys.version_info >= (3, 9) else 1)" 2>/dev/null; then
    PY_VER=$($PYTHON_CMD -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
    echo "      ERROR: Python 3.9+ required. Found: $PY_VER"
    exit 1
fi

# Create virtual environment for PEP 668 compatibility
VENV_DIR="$SCRIPT_DIR/.venv"
if [ ! -d "$VENV_DIR" ]; then
    echo "      Creating virtual environment..."
    $PYTHON_CMD -m venv "$VENV_DIR"
    if [ ! -f "$VENV_DIR/bin/python3" ] && [ ! -f "$VENV_DIR/Scripts/python.exe" ]; then
        echo "      ERROR: venv creation failed."
        echo "      On Debian/Ubuntu, run: sudo apt install python3-venv"
        exit 1
    fi
fi
if [ -f "$VENV_DIR/bin/python3" ]; then
    PYTHON_CMD="$VENV_DIR/bin/python3"
elif [ -f "$VENV_DIR/Scripts/python.exe" ]; then
    PYTHON_CMD="$VENV_DIR/Scripts/python.exe"
fi
echo "      Using venv: $VENV_DIR"

if [ -d "$PLUGIN_DIR" ]; then
    echo "      OpenCode config found."
else
    echo "      NOTE: OpenCode config not found. Will be created on first OpenCode launch."
fi

echo "[1/9] Installing Python dependencies..."
cd "$SCRIPT_DIR" || exit 1
$PYTHON_CMD -m pip install -r core/requirements.txt
if [ $? -ne 0 ]; then
    echo "      Retrying with Tsinghua mirror..."
    $PYTHON_CMD -m pip install -r core/requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple
    if [ $? -ne 0 ]; then
        echo "      WARNING: pip install failed. Install manually:"
        echo "        $PYTHON_CMD -m pip install -r core/requirements.txt"
    else
        echo "      Dependencies installed via mirror."
    fi
else
    echo "      Dependencies ready."
fi

echo "[2/9] Copying detection rules..."
mkdir -p "$RULES_DIR/custom"
if [ -f "$RULES_SRC/pii.yaml" ]; then
    cp "$RULES_SRC/pii.yaml" "$RULES_DIR/"
    echo "      pii.yaml installed."
fi
if [ -f "$RULES_SRC/keywords.yaml" ]; then
    cp "$RULES_SRC/keywords.yaml" "$RULES_DIR/"
    echo "      keywords.yaml installed."
fi
if [ -f "$RULES_SRC/injection.yaml" ]; then
    cp "$RULES_SRC/injection.yaml" "$RULES_DIR/"
    echo "      injection.yaml installed."
fi
if [ -f "$RULES_SRC/response_guard.yaml" ]; then
    cp "$RULES_SRC/response_guard.yaml" "$RULES_DIR/"
    echo "      response_guard.yaml installed."
fi
if [ -f "$RULES_SRC/output_sensitivity.yaml" ]; then
    cp "$RULES_SRC/output_sensitivity.yaml" "$RULES_DIR/"
    echo "      output_sensitivity.yaml installed."
fi
if [ -n "$(find "$RULES_SRC/custom" -maxdepth 1 -name "*.yaml" 2>/dev/null)" ]; then
    cp "$RULES_SRC/custom/"*.yaml "$RULES_DIR/custom/"
    echo "      custom rules installed."
fi

echo "[3/9] Installing plugin..."
mkdir -p "$PLUGIN_DIR"
if [ -f "$PLUGIN_SRC" ]; then
    cp "$PLUGIN_SRC" "$PLUGIN_DIR/open_shield.ts"
    echo "      Plugin installed to: $PLUGIN_DIR/open_shield.ts"
else
    echo "      ERROR: Plugin source not found at $PLUGIN_SRC"
    exit 1
fi

echo "[4/9] Installing Skill..."
mkdir -p "$SKILL_DIR"
if [ -f "$SCRIPT_DIR/.opencode/skills/openshield-safety/SKILL.md" ]; then
    cp "$SCRIPT_DIR/.opencode/skills/openshield-safety/SKILL.md" "$SKILL_DIR/"
    echo "      Skill installed to: $SKILL_DIR"
else
    echo "      Skill file not found, skipping."
fi

echo "[5/9] Creating directories and config..."
mkdir -p "$DATA_DIR"
mkdir -p "$LOGS_DIR"
CONFIG_FILE="$HOME/.openshield/config.json"
if [ -f "$CONFIG_FILE" ]; then
    BACKUP_FILE="$CONFIG_FILE.backup.$(date +%Y%m%d%H%M%S)"
    cp "$CONFIG_FILE" "$BACKUP_FILE"
    echo "      Backed up existing config to: $BACKUP_FILE"
fi
printf '{"project_dir":"%s","webhooks":[]}\n' "$SCRIPT_DIR" > "$CONFIG_FILE"
echo "      Data dir: $DATA_DIR"
echo "      Logs dir: $LOGS_DIR"
echo "      Config written: $HOME/.openshield/config.json"

echo "[6/9] Generating security files..."
POLICY_FILE="$HOME/.openshield/path_policy.json"
if [ ! -f "$POLICY_FILE" ]; then
    cat > "$POLICY_FILE" << 'EOF'
{
  "blacklist": [
    "/etc/**",
    "/boot/**",
    "~/.ssh/**",
    "~/.gnupg/**",
    "C:\\Windows\\**",
    "C:\\Program Files\\**",
    "**/.env",
    "**/credentials",
    "**/id_rsa",
    "**/*.pem"
  ],
  "whitelist": [
    "/tmp/**",
    "/home/*/projects/**",
    "~/work/**",
    "D:\\Git\\**",
    "C:\\Users\\*\\Documents\\**"
  ],
  "sensitive_read_patterns": [
    "~/.ssh/**",
    "~/.aws/**",
    "**/.env",
    "**/config.json",
    "/etc/passwd",
    "/etc/shadow"
  ],
  "learning_mode": true,
  "browser_passwords": {
    "enabled": true,
    "rules": [
      {
        "browser": "Chrome",
        "patterns": {
          "win32": "%LOCALAPPDATA%\\Google\\Chrome\\User Data\\*\\Login Data",
          "darwin": "~/Library/Application Support/Google/Chrome/*/Login Data",
          "linux": "~/.config/google-chrome/*/Login Data"
        },
        "action": "block",
        "description": "Chrome 浏览器密码数据库"
      },
      {
        "browser": "Edge",
        "patterns": {
          "win32": "%LOCALAPPDATA%\\Microsoft\\Edge\\User Data\\*\\Login Data",
          "darwin": "~/Library/Application Support/Microsoft Edge/*/Login Data",
          "linux": "~/.config/microsoft-edge/*/Login Data"
        },
        "action": "block",
        "description": "Edge 浏览器密码数据库"
      },
      {
        "browser": "Firefox",
        "patterns": {
          "win32": "%APPDATA%\\Mozilla\\Firefox\\Profiles\\*\\logins.json",
          "darwin": "~/Library/Application Support/Firefox/Profiles/*/logins.json",
          "linux": "~/.mozilla/firefox/*/logins.json"
        },
        "action": "block",
        "description": "Firefox 浏览器密码文件"
      }
    ]
  }
}
EOF
    echo "      Path policy written: $POLICY_FILE"
else
    echo "      Path policy already exists: $POLICY_FILE"
fi

# Generate service token
TOKEN_FILE="$HOME/.openshield/service.token"
if [ ! -f "$TOKEN_FILE" ]; then
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex 32 > "$TOKEN_FILE"
    else
        head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$TOKEN_FILE"
    fi
    chmod 600 "$TOKEN_FILE"
    echo "      Service token generated: $TOKEN_FILE"
else
    echo "      Service token already exists: $TOKEN_FILE"
fi

echo "[7/9] Dashboard configuration"
read -rp "Enter Dashboard port (default 9528): " dashboard_port
dashboard_port=${dashboard_port:-9528}
if ! [[ "$dashboard_port" =~ ^[0-9]+$ ]]; then
    echo "      WARNING: Invalid port \"$dashboard_port\", using default 9528."
    dashboard_port=9528
fi
# Write dashboard_config.json (port passed as string, converted via int() to prevent injection)
$PYTHON_CMD -c "
import json
from pathlib import Path
p = Path.home() / '.openshield' / 'dashboard_config.json'
d = json.load(open(p)) if p.exists() else {}
d['server_port'] = int('$dashboard_port')
json.dump(d, open(p, 'w'), indent=2)
"
echo "      Dashboard port: $dashboard_port"

echo "[8/9] Installing Dashboard dependencies"
$PYTHON_CMD -m pip install -r "$SCRIPT_DIR/dashboard/requirements.txt" -q
if [ $? -ne 0 ]; then
    echo "      Retrying with Tsinghua mirror..."
    $PYTHON_CMD -m pip install -r "$SCRIPT_DIR/dashboard/requirements.txt" -i https://pypi.tuna.tsinghua.edu.cn/simple -q
    if [ $? -ne 0 ]; then
        echo "[WARNING] Dependencies installation failed."
        echo "Please run manually: pip install -r dashboard/requirements.txt"
    else
        echo "      Dashboard dependencies installed via mirror."
    fi
else
    echo "      Dashboard dependencies installed."
fi

echo ""
echo "========================================"
echo "   Installation Complete!"
echo "========================================"
echo ""
echo "The plugin will auto-start the detection service on next OpenCode launch."
echo "To start manually: cd core && $PYTHON_CMD openshield-detect.py"
echo ""
echo "========================================"
echo "   IMPORTANT: Permission Configuration"
echo "========================================"
echo ""
echo "OpenShield requires bash permission set to \"ask\" for security checks."
echo ""
echo "Please add the following to your opencode.json:"
echo ""
echo '{'
echo '  "permission": {'
echo '    "bash": {'
echo '      "*": "ask",'
echo '      "git *": "allow",'
echo '      "git status*": "allow",'
echo '      "git diff*": "allow",'
echo '      "git log*": "allow",'
echo '      "ls *": "allow",'
echo '      "ls": "allow",'
echo '      "cat *": "allow",'
echo '      "npm *": "allow",'
echo '      "yarn *": "allow",'
echo '      "pnpm *": "allow",'
echo '      "bun *": "allow",'
echo '      "node *": "allow",'
echo '      "python *": "allow",'
echo '      "pip *": "allow",'
echo '      "tsc *": "allow",'
echo '      "eslint *": "allow",'
echo '      "prettier *": "allow",'
echo '      "docker *": "allow"'
echo '    }'
echo '  }'
echo '}'
echo ""
echo "Location:"
echo "  Global: ~/.config/opencode/opencode.json"
echo "  Project: ./opencode.json"
echo ""
echo "To uninstall, run: ./uninstall.sh"
echo ""

echo "[9/9] Generating project opencode.json..."
PROJECT_OPENCODE_JSON="$SCRIPT_DIR/opencode.json"
if [ ! -f "$PROJECT_OPENCODE_JSON" ]; then
    cat > "$PROJECT_OPENCODE_JSON" << 'EOF'
{
  "permission": {
    "bash": {
      "*": "ask",
      "git *": "allow",
      "git status*": "allow",
      "git diff*": "allow",
      "git log*": "allow",
      "ls *": "allow",
      "ls": "allow",
      "cat *": "allow",
      "npm *": "allow",
      "yarn *": "allow",
      "pnpm *": "allow",
      "bun *": "allow",
      "node *": "allow",
      "python *": "allow",
      "pip *": "allow",
      "tsc *": "allow",
      "eslint *": "allow",
      "prettier *": "allow",
      "docker *": "allow"
    }
  }
}
EOF
    echo "      Created: $PROJECT_OPENCODE_JSON"
    echo "      Permission config will be merged with global config."
else
    echo "      NOTE: opencode.json already exists at $PROJECT_OPENCODE_JSON"
    echo "      Please add permission config manually (see above)."
fi
