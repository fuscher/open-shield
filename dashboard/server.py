"""OpenShield Dashboard Server - 极简配置服务"""

from flask import Flask, jsonify, request, send_file, abort
from pathlib import Path
from datetime import datetime, timedelta
import json
import os
import sys
import tempfile
import shutil
import urllib.request
import yaml

app = Flask(__name__)
OPENSHIELD_DIR = Path.home() / ".openshield"
DASHBOARD_DIR = Path(__file__).parent
DEFAULT_RULES_DIR = Path(__file__).parent.parent / "core" / "rules"

# 检测服务端口（与openshield-detect.py一致）
DETECT_SERVICE_PORT = 9527

# 规则类型白名单（路径遍历防护）
VALID_RULE_TYPES = {"pii", "keywords", "injection", "output_sensitivity", "response_guard", "custom"}

# ==================== 认证 ====================

def get_service_token() -> str:
    """读取service.token"""
    token_file = OPENSHIELD_DIR / "service.token"
    if token_file.exists():
        return token_file.read_text().strip()
    return ""

def verify_token():
    """验证Bearer Token"""
    token = get_service_token()
    if not token:
        return  # 未配置token，跳过认证
    
    auth_header = request.headers.get("Authorization", "")
    if not auth_header.startswith("Bearer "):
        abort(401, description="Missing authorization token")
    
    if auth_header[7:] != token:
        abort(401, description="Invalid authorization token")

@app.before_request
def before_request():
    """请求前认证"""
    if request.path.startswith("/api/"):
        verify_token()

# ==================== 页面路由 ====================

@app.route("/")
def index():
    """返回dashboard页面，注入API Token（使用json.dumps确保安全转义）"""
    token = get_service_token()
    html = (DASHBOARD_DIR / "index.html").read_text(encoding="utf-8")
    html = html.replace('"{{API_TOKEN}}"', json.dumps(token))
    return html

# ==================== 配置API ====================

@app.route("/api/config", methods=["GET"])
def get_config():
    config = load_json("dashboard_config.json", {})
    return jsonify({
        "thresholds": config.get("thresholds", default_thresholds()),
        "ts_params": config.get("ts_params", default_ts_params()),
        "notifications": config.get("notifications", {"system_enabled": True}),
        "server_port": get_port()
    })

@app.route("/api/config", methods=["PUT"])
def update_config():
    data = request.json
    current = load_json("dashboard_config.json", {})
    current.update(data)
    save_json("dashboard_config.json", current)
    return jsonify({"status": "ok"})

@app.route("/api/config/reset", methods=["POST"])
def reset_config():
    defaults = {
        "thresholds": default_thresholds(),
        "ts_params": default_ts_params(),
        "notifications": {"system_enabled": True},
        "server_port": get_port()
    }
    save_json("dashboard_config.json", defaults)
    return jsonify({"status": "ok", "config": defaults})

# ==================== 规则API ====================

@app.route("/api/rules", methods=["GET"])
def get_all_rules():
    rules = {}
    for name in ["pii", "keywords", "injection", "output_sensitivity", "response_guard"]:
        rules[name] = load_yaml(f"rules/{name}.yaml")
    rules["custom"] = load_custom_rules()
    return jsonify(rules)

@app.route("/api/rules/<rule_type>", methods=["GET"])
def get_rules(rule_type):
    if rule_type not in VALID_RULE_TYPES:
        return jsonify({"status": "error", "message": "Invalid rule type"}), 400
    if rule_type == "custom":
        return jsonify(load_custom_rules())
    return jsonify(load_yaml(f"rules/{rule_type}.yaml"))

@app.route("/api/rules/<rule_type>", methods=["PUT"])
def update_rules(rule_type):
    if rule_type not in VALID_RULE_TYPES:
        return jsonify({"status": "error", "message": "Invalid rule type"}), 400
    
    data = request.json
    try:
        if rule_type == "custom":
            file_groups = {}
            for rule in data.get("rules", []):
                source = rule.pop("_source", "dashboard_custom.yaml")
                file_groups.setdefault(source, []).append(rule)
            for filename, rules_list in file_groups.items():
                save_yaml(f"rules/custom/{filename}", {"rules": rules_list})
            custom_dir = OPENSHIELD_DIR / "rules" / "custom"
            if custom_dir.exists():
                for yaml_file in custom_dir.glob("*.yaml"):
                    if yaml_file.name not in file_groups:
                        save_yaml(f"rules/custom/{yaml_file.name}", {"rules": []})
        else:
            save_yaml(f"rules/{rule_type}.yaml", data)
        return jsonify({"status": "ok"})
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 400

@app.route("/api/rules/<rule_type>/export", methods=["GET"])
def export_rules(rule_type):
    if rule_type not in VALID_RULE_TYPES:
        return jsonify({"status": "error", "message": "Invalid rule type"}), 400
    if rule_type == "custom":
        data = load_custom_rules()
        for rule in data.get("rules", []):
            rule.pop("_source", None)
    else:
        data = load_yaml(f"rules/{rule_type}.yaml")
    return jsonify({"filename": f"{rule_type}.yaml", "content": yaml.dump(data, allow_unicode=True)})

@app.route("/api/rules/<rule_type>/import", methods=["POST"])
def import_rules(rule_type):
    if rule_type not in VALID_RULE_TYPES:
        return jsonify({"status": "error", "message": "Invalid rule type"}), 400
    content = request.json.get("content", "")
    try:
        data = yaml.safe_load(content)
        if rule_type == "custom":
            save_yaml("rules/custom/dashboard_custom.yaml", data)
        else:
            save_yaml(f"rules/{rule_type}.yaml", data)
        return jsonify({"status": "ok", "data": data})
    except yaml.YAMLError as e:
        return jsonify({"status": "error", "message": f"YAML格式错误: {e}"}), 400

@app.route("/api/rules/<rule_type>/reset", methods=["POST"])
def reset_rules(rule_type):
    if rule_type not in VALID_RULE_TYPES:
        return jsonify({"status": "error", "message": "Invalid rule type"}), 400
    try:
        if rule_type == "custom":
            src_dir = DEFAULT_RULES_DIR / "custom"
            dest_dir = OPENSHIELD_DIR / "rules" / "custom"
            dest_dir.mkdir(parents=True, exist_ok=True)
            for f in dest_dir.glob("*.yaml"):
                f.unlink()
            if src_dir.exists():
                for f in src_dir.glob("*.yaml"):
                    shutil.copy2(f, dest_dir / f.name)
        else:
            src = DEFAULT_RULES_DIR / f"{rule_type}.yaml"
            if not src.exists():
                return jsonify({"status": "error", "message": "Default file not found"}), 404
            dest = OPENSHIELD_DIR / "rules" / f"{rule_type}.yaml"
            shutil.copy2(src, dest)
        return jsonify({"status": "ok"})
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500

# ==================== 路径策略API ====================

@app.route("/api/path-policy", methods=["GET"])
def get_path_policy():
    return jsonify(load_json("path_policy.json", default_path_policy()))

@app.route("/api/path-policy", methods=["PUT"])
def update_path_policy():
    save_json("path_policy.json", request.json)
    return jsonify({"status": "ok"})

# ==================== 敏感字符串API ====================

@app.route("/api/sensitive-strings", methods=["GET"])
def get_sensitive_strings():
    rules = load_yaml("rules/pii.yaml")
    return jsonify(rules.get("sensitive_strings", {"enabled": True, "items": []}))

@app.route("/api/sensitive-strings", methods=["PUT"])
def update_sensitive_strings():
    data = request.json
    if not isinstance(data, dict):
        return jsonify({"status": "error", "message": "Invalid data format"}), 400
    items = data.get("items", [])
    if not isinstance(items, list):
        return jsonify({"status": "error", "message": "items must be a list"}), 400
    if len(items) > 200:
        return jsonify({"status": "error", "message": "Maximum 200 items allowed"}), 400
    valid_items = list(dict.fromkeys(
        item.strip() for item in items if item and isinstance(item, str) and item.strip()
    ))
    data["items"] = valid_items

    rules = load_yaml("rules/pii.yaml")
    rules["sensitive_strings"] = data
    save_yaml("rules/pii.yaml", rules)
    return jsonify({"status": "ok"})

# ==================== 浏览器密码目录API ====================

@app.route("/api/browser-passwords", methods=["GET"])
def get_browser_passwords():
    policy = load_json("path_policy.json", default_path_policy())
    return jsonify(policy.get("browser_passwords", default_browser_passwords()))

@app.route("/api/browser-passwords", methods=["PUT"])
def update_browser_passwords():
    data = request.json
    if not isinstance(data, dict):
        return jsonify({"status": "error", "message": "Invalid data format"}), 400
    rules = data.get("rules", [])
    if not isinstance(rules, list):
        return jsonify({"status": "error", "message": "rules must be a list"}), 400
    valid_actions = {"allow", "block"}
    for rule in rules:
        if rule.get("action") not in valid_actions:
            return jsonify({"status": "error", "message": f"Invalid action: {rule.get('action')}"}), 400

    policy = load_json("path_policy.json", default_path_policy())
    policy["browser_passwords"] = data
    save_json("path_policy.json", policy)
    return jsonify({"status": "ok"})

# ==================== Webhook API ====================

@app.route("/api/webhooks", methods=["GET"])
def get_webhooks():
    config = load_json("config.json", {})
    return jsonify(config.get("webhooks", []))

@app.route("/api/webhooks", methods=["POST"])
def add_webhook():
    webhook = request.json
    config = load_json("config.json", {})
    if "webhooks" not in config:
        config["webhooks"] = []
    config["webhooks"].append(webhook)
    save_json("config.json", config)
    return jsonify({"status": "ok"})

@app.route("/api/webhooks/<int:index>", methods=["PUT"])
def update_webhook(index):
    webhook = request.json
    config = load_json("config.json", {})
    webhooks = config.get("webhooks", [])
    if 0 <= index < len(webhooks):
        webhooks[index] = webhook
        config["webhooks"] = webhooks
        save_json("config.json", config)
        return jsonify({"status": "ok"})
    return jsonify({"status": "error", "message": "Invalid index"}), 400

@app.route("/api/webhooks/<int:index>", methods=["DELETE"])
def delete_webhook(index):
    config = load_json("config.json", {})
    webhooks = config.get("webhooks", [])
    if 0 <= index < len(webhooks):
        webhooks.pop(index)
        config["webhooks"] = webhooks
        save_json("config.json", config)
        return jsonify({"status": "ok"})
    return jsonify({"status": "error", "message": "Invalid index"}), 400

@app.route("/api/webhooks/<int:index>/test", methods=["POST"])
def test_webhook(index):
    config = load_json("config.json", {})
    webhooks = config.get("webhooks", [])
    if 0 <= index < len(webhooks):
        webhook = webhooks[index]
        # 发送测试请求
        try:
            payload = json.dumps({"text": "OpenShield Dashboard 测试消息"}).encode("utf-8")
            req = urllib.request.Request(webhook["url"], data=payload, method="POST")
            req.add_header("Content-Type", "application/json")
            urllib.request.urlopen(req, timeout=5)
            return jsonify({"status": "ok", "message": "测试发送成功"})
        except Exception as e:
            return jsonify({"status": "error", "message": f"测试发送失败: {e}"}), 400
    return jsonify({"status": "error", "message": "Invalid index"}), 400

# ==================== 日志API ====================

@app.route("/api/logs", methods=["GET"])
def get_logs():
    date = request.args.get("date", "")
    level = request.args.get("level", "")
    log_type = request.args.get("type", "detect")  # detect 或 notify
    limit = int(request.args.get("limit", 200))
    logs = read_logs(date, level, limit, log_type)
    return jsonify(logs)

@app.route("/api/logs/clean", methods=["POST"])
def clean_logs():
    days = int(request.json.get("days", 30))
    cleaned = clean_old_logs(days)
    return jsonify({"status": "ok", "cleaned": cleaned})

@app.route("/api/logs/dates", methods=["GET"])
def get_log_dates():
    dates = []
    log_dir = OPENSHIELD_DIR / "logs"
    if log_dir.exists():
        for f in log_dir.glob("detect-*.jsonl"):
            date = f.stem.replace("detect-", "")
            dates.append(date)
        for f in log_dir.glob("notify-*.log"):
            date = f.stem.replace("notify-", "")
            if date not in dates:
                dates.append(date)
    return jsonify(sorted(dates, reverse=True))

# ==================== 验证API ====================

@app.route("/api/verify", methods=["GET"])
def verify():
    checks = {
        "config_exists": (OPENSHIELD_DIR / "config.json").exists(),
        "rules_dir": (OPENSHIELD_DIR / "rules").exists(),
        "pii_rules": (OPENSHIELD_DIR / "rules" / "pii.yaml").exists(),
        "keywords_rules": (OPENSHIELD_DIR / "rules" / "keywords.yaml").exists(),
        "injection_rules": (OPENSHIELD_DIR / "rules" / "injection.yaml").exists(),
        "output_rules": (OPENSHIELD_DIR / "rules" / "output_sensitivity.yaml").exists(),
        "response_guard_rules": (OPENSHIELD_DIR / "rules" / "response_guard.yaml").exists(),
        "service_token": (OPENSHIELD_DIR / "service.token").exists(),
    }
    return jsonify({
        "status": "ok" if all(checks.values()) else "incomplete",
        "checks": checks,
        "missing": [k for k, v in checks.items() if not v],
        "platform": sys.platform,
    })

# ==================== 检测服务状态API ====================

@app.route("/api/detect-service/status", methods=["GET"])
def detect_service_status():
    token = get_service_token()
    try:
        req = urllib.request.Request(f"http://localhost:{DETECT_SERVICE_PORT}/api/v1/health")
        if token:
            req.add_header("Authorization", f"Bearer {token}")
        resp = urllib.request.urlopen(req, timeout=2)
        return jsonify({"status": "running", "data": json.loads(resp.read())})
    except Exception:
        return jsonify({"status": "stopped"})

# ==================== 工具函数 ====================

def get_port() -> int:
    config = load_json("dashboard_config.json", {})
    return config.get("server_port", 9528)

def load_json(filename, default=None):
    filepath = OPENSHIELD_DIR / filename
    if filepath.exists():
        try:
            with open(filepath, "r", encoding="utf-8") as f:
                return json.load(f)
        except json.JSONDecodeError:
            # 尝试从备份恢复
            backup = filepath.with_suffix(".json.bak")
            if backup.exists():
                try:
                    with open(backup, "r", encoding="utf-8") as f:
                        return json.load(f)
                except json.JSONDecodeError:
                    pass
            return default if default is not None else {}
    return default if default is not None else {}

def save_json(filename, data):
    filepath = OPENSHIELD_DIR / filename
    filepath.parent.mkdir(parents=True, exist_ok=True)
    # 写入前备份（防止数据丢失）
    if filepath.exists():
        backup = filepath.with_suffix(".json.bak")
        shutil.copy2(filepath, backup)
    # 原子写入：先写临时文件，再rename（避免并发读写问题）
    tmp_fd, tmp_path = tempfile.mkstemp(dir=str(filepath.parent), suffix=".tmp")
    try:
        with os.fdopen(tmp_fd, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
        os.replace(tmp_path, str(filepath))  # 原子操作
    except Exception:
        os.unlink(tmp_path)
        raise

def load_yaml(filename):
    filepath = OPENSHIELD_DIR / filename
    if filepath.exists():
        try:
            with open(filepath, "r", encoding="utf-8") as f:
                return yaml.safe_load(f) or {}
        except yaml.YAMLError:
            return {"error": "YAML格式错误"}
    return {}

def save_yaml(filename, data):
    filepath = OPENSHIELD_DIR / filename
    filepath.parent.mkdir(parents=True, exist_ok=True)
    # 原子写入
    tmp_fd, tmp_path = tempfile.mkstemp(dir=str(filepath.parent), suffix=".tmp")
    try:
        with os.fdopen(tmp_fd, "w", encoding="utf-8") as f:
            yaml.dump(data, f, allow_unicode=True, default_flow_style=False)
        os.replace(tmp_path, str(filepath))
    except Exception:
        os.unlink(tmp_path)
        raise

def load_custom_rules():
    custom_dir = OPENSHIELD_DIR / "rules" / "custom"
    rules = []
    if custom_dir.exists():
        for yaml_file in sorted(custom_dir.glob("*.yaml")):
            data = load_yaml(f"rules/custom/{yaml_file.name}")
            if data and "rules" in data:
                for rule in data["rules"]:
                    rule["_source"] = yaml_file.name
                    rules.append(rule)
    return {"rules": rules}

def read_logs(date="", level="", limit=200, log_type="detect"):
    """
    读取日志文件。
    limit语义：优先返回最新的条目（每个文件从末尾读取，跨天时按文件日期降序）。
    返回结果按时间降序排列（最新在前）。
    """
    logs = []
    log_dir = OPENSHIELD_DIR / "logs"
    if not log_dir.exists():
        return logs
    
    if log_type == "notify":
        # 读取通知日志（从每个文件末尾读取最新条目，与detect类型一致）
        pattern = "notify-*.log"
        for f in sorted(log_dir.glob(pattern), reverse=True):
            if date and not f.name.startswith(f"notify-{date}"):
                continue
            remaining = limit - len(logs)
            if remaining <= 0:
                break
            with open(f, "r", encoding="utf-8") as fh:
                all_lines = fh.readlines()
                for line in reversed(all_lines):
                    logs.append({"message": line.strip(), "type": "notify"})
                    if len(logs) >= limit:
                        return logs
    else:
        # 读取检测日志（从每个文件末尾读取最新条目）
        pattern = "detect-*.jsonl"
        files = sorted(log_dir.glob(pattern), reverse=True)
        for f in files:
            if date and not f.name.startswith(f"detect-{date}"):
                continue
            remaining = limit - len(logs)
            if remaining <= 0:
                break
            with open(f, "r", encoding="utf-8") as fh:
                all_lines = fh.readlines()
                # 从文件末尾读取（最新的在最后）
                for line in reversed(all_lines):
                    try:
                        entry = json.loads(line)
                        if level and entry.get("alerts"):
                            if not any(a.get("severity") == level for a in entry["alerts"]):
                                continue
                        logs.append(entry)
                        if len(logs) >= limit:
                            return logs
                    except json.JSONDecodeError:
                        continue
    return logs

def clean_old_logs(days=30):
    log_dir = OPENSHIELD_DIR / "logs"
    if not log_dir.exists():
        return 0
    cutoff = datetime.now() - timedelta(days=days)
    cutoff_str = cutoff.strftime("%Y-%m-%d")
    cleaned = 0
    for f in log_dir.glob("detect-*.jsonl"):
        # 从文件名解析日期：detect-YYYY-MM-DD.jsonl
        date_str = f.stem.replace("detect-", "")
        if date_str < cutoff_str:
            f.unlink()
            cleaned += 1
    for f in log_dir.glob("notify-*.log"):
        date_str = f.stem.replace("notify-", "")
        if date_str < cutoff_str:
            f.unlink()
            cleaned += 1
    return cleaned

def default_thresholds():
    return {
        "pii": {"block_level": "critical", "manual_level": "high", "enabled": True},
        "keywords": {"block_level": "critical", "manual_level": "high", "enabled": True},
        "injection": {"block_level": "critical", "manual_level": "high", "enabled": True},
        "output": {"block_level": "critical", "manual_level": "high", "enabled": True}
    }

def default_ts_params():
    return {
        "high_risk_patterns": ["rm -rf", "rm -r", "format", "reboot", "shutdown", "dd if=", "mkfs", "drop table", "drop database", "truncate table"],
        "medium_risk_tools": ["curl", "wget", "chmod", "chown", "write", "edit", "overwrite", "delete", "remove", "unlink"],
        "high_risk_tools": ["database", "query", "execute"],
        "safe_command_prefixes": [
            "ls", "dir", "pwd", "cat", "head", "tail", "less", "more",
            "mkdir", "cp", "copy", "mv", "move", "touch", "ln",
            "grep", "find", "which", "where", "whoami",
            "date", "env", "printenv", "echo",
            "git",
            "npm", "npx", "yarn", "pnpm", "bun",
            "node", "deno", "python", "python3", "pip", "pip3",
            "cargo", "rustc", "go", "java", "javac", "tsc",
            "eslint", "prettier", "ruff", "biome",
            "pytest", "jest", "vitest", "mocha",
            "docker", "kubectl", "helm",
            "code", "vim", "nano"
        ],
        "phase_d_thresholds": {"high_risk_tool_count": 10, "sensitive_path_count": 3},
        "health_check_interval": 60000
    }

def default_path_policy():
    return {
        "blacklist": ["/etc/**", "/boot/**", "~/.ssh/**", "~/.gnupg/**", "C:\\Windows\\**", "C:\\Program Files\\**", "**/.env", "**/credentials", "**/id_rsa", "**/*.pem"],
        "whitelist": ["/tmp/**", "/home/*/projects/**", "~/work/**", "D:\\Git\\**", "C:\\Users\\*\\Documents\\**"],
        "sensitive_read_patterns": ["~/.ssh/**", "~/.aws/**", "**/.env", "**/config.json", "/etc/passwd", "/etc/shadow"],
        "learning_mode": True
    }

def default_browser_passwords():
    return {
        "enabled": True,
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

if __name__ == "__main__":
    port = get_port()
    print("=" * 50)
    print("  OpenShield Dashboard")
    print("=" * 50)
    print(f"  http://localhost:{port}")
    print(f"  Config: {OPENSHIELD_DIR}")
    print()
    print("  Press Ctrl+C to stop")
    print("=" * 50)
    
    # 自动打开浏览器
    import webbrowser
    webbrowser.open(f"http://localhost:{port}")
    
    # 默认绑定127.0.0.1，仅本机访问
    # 如需局域网访问，可改为 host="0.0.0.0"
    app.run(host="127.0.0.1", port=port, debug=False)
