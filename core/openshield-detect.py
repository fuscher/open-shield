#!/usr/bin/env python3
"""OpenShield Detect Service - 单文件检测服务"""

import os
import re
import json
import asyncio
import platform
import urllib.request
from pathlib import Path
from datetime import datetime
from typing import List, Dict, Any, Optional
from enum import Enum

import yaml
from fastapi import FastAPI, HTTPException, BackgroundTasks
from fastapi.responses import JSONResponse
from pydantic import BaseModel

# ==================== 配置管理 ====================

class Config:
    """配置管理器"""

    def __init__(self):
        self.base_dir = Path.home() / ".openshield"
        self.rules_dir = self.base_dir / "rules"
        self.logs_dir = self.base_dir / "logs"
        self.service_port = 9527

        self.rules_dir.mkdir(parents=True, exist_ok=True)
        self.logs_dir.mkdir(parents=True, exist_ok=True)

        self._rule_mtimes = {}
        self.webhooks = self._load_webhooks()
        self._load_all_rules()

    def _load_yaml(self, filename: str) -> Dict:
        filepath = self.rules_dir / filename
        if filepath.exists():
            with open(filepath, "r", encoding="utf-8") as f:
                return yaml.safe_load(f) or {}
        return {}

    def _load_all_rules(self):
        self.pii_rules = self._load_yaml("pii.yaml")
        self.keyword_rules = self._load_yaml("keywords.yaml")
        self.injection_rules = self._load_yaml("injection.yaml")
        self.custom_rules = self._load_custom_rules()

    def _check_and_reload(self) -> bool:
        """检查文件变更，自动重载。返回是否已重载"""
        changed = False
        for name in ["pii.yaml", "keywords.yaml", "injection.yaml"]:
            filepath = self.rules_dir / name
            if filepath.exists():
                mt = filepath.stat().st_mtime
                if self._rule_mtimes.get(name) != mt:
                    self._rule_mtimes[name] = mt
                    changed = True
        # 检查 custom/ 目录下的 YAML 文件（含删除感知）
        custom_dir = self.rules_dir / "custom"
        if custom_dir.exists():
            current_files = set()
            for yaml_file in custom_dir.glob("*.yaml"):
                key = f"custom/{yaml_file.name}"
                current_files.add(key)
                mt = yaml_file.stat().st_mtime
                if self._rule_mtimes.get(key) != mt:
                    self._rule_mtimes[key] = mt
                    changed = True
            # 清理已删除文件的 stale 条目
            for key in list(self._rule_mtimes.keys()):
                if key.startswith("custom/") and key not in current_files:
                    del self._rule_mtimes[key]
                    changed = True
        if changed:
            self._load_all_rules()
        return changed

    def _load_webhooks(self) -> List[Dict]:
        config_file = self.base_dir / "config.json"
        if config_file.exists():
            try:
                with open(config_file, "r", encoding="utf-8") as f:
                    data = json.load(f)
                return data.get("webhooks", [])
            except Exception:
                return []
        return []

    def _load_custom_rules(self) -> List[Dict]:
        custom_dir = self.rules_dir / "custom"
        rules = []
        if not custom_dir.exists():
            return rules

        for yaml_file in custom_dir.glob("*.yaml"):
            try:
                with open(yaml_file, "r", encoding="utf-8") as f:
                    data = yaml.safe_load(f)
                if data and "rules" in data:
                    rules.extend(data["rules"])
            except Exception as e:
                print(f"Warning: Failed to load custom rule {yaml_file.name}: {e}")

        for py_file in custom_dir.glob("*.py"):
            print(f"Warning: Python custom rules are disabled for security. File: {py_file.name}")

        return rules


# ==================== 数据模型 ====================

class AlertSeverity(str, Enum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    CRITICAL = "critical"


class Alert(BaseModel):
    type: str
    severity: AlertSeverity
    rule_name: str
    matched_content: str
    position: int
    description: str


class CaptureData(BaseModel):
    session_id: str
    content: str
    content_type: str
    timestamp: str
    metadata: Optional[Dict[str, Any]] = None


class DetectionResult(BaseModel):
    session_id: str
    timestamp: str
    alerts: List[Alert]
    action: str
    sanitized_content: Optional[str] = None


class ExecuteDetectionRequest(BaseModel):
    session_id: str
    tool_name: str
    tool_args: Dict[str, Any]
    timestamp: str


class ExecuteDetectionResponse(BaseModel):
    session_id: str
    timestamp: str
    action: str
    alerts: List[Alert]
    reason: Optional[str] = None


# ==================== PII检测器 ====================

class PIIDetector:
    """PII检测器"""

    def __init__(self, rules: Dict):
        self.patterns = []
        for rule in rules.get("pii_rules", []):
            mask_cfg = rule.get("mask", {})
            self.patterns.append({
                "name": rule["name"],
                "regex": re.compile(rule["pattern"]),
                "severity": AlertSeverity(rule["severity"]),
                "description": rule.get("description", ""),
                "mask_type": mask_cfg.get("type", "fixed"),
                "mask_prefix": mask_cfg.get("prefix", 2),
                "mask_suffix": mask_cfg.get("suffix", 2),
            })

    def detect(self, content: str) -> List[Alert]:
        alerts = []
        for pattern in self.patterns:
            for match in pattern["regex"].finditer(content):
                alerts.append(Alert(
                    type="pii_detected",
                    severity=pattern["severity"],
                    rule_name=pattern["name"],
                    matched_content=match.group(),
                    position=match.start(),
                    description=pattern["description"]
                ))
        return alerts

    def mask(self, content: str) -> tuple:
        """返回 (脱敏后内容, 替换数)"""
        masked = content
        count = 0
        for pattern in self.patterns:
            for match in reversed(list(pattern["regex"].finditer(masked))):
                original = match.group()
                if pattern["mask_type"] == "email":
                    groups = match.groups()
                    if groups and len(groups) >= 2:
                        replacement = groups[0][:pattern["mask_prefix"]] + "***@" + groups[1]
                    else:
                        p = pattern["mask_prefix"]
                        s = pattern["mask_suffix"]
                        replacement = original[:p] + "***" + original[-s:] if len(original) > p + s else "***"
                else:
                    p = pattern["mask_prefix"]
                    s = pattern["mask_suffix"]
                    replacement = original[:p] + "***" + original[-s:] if len(original) > p + s else "***"
                masked = masked[:match.start()] + replacement + masked[match.end():]
                count += 1
        return masked, count


# ==================== 关键词检测器 ====================

class KeywordDetector:
    """关键词检测器"""

    def __init__(self, rules: Dict):
        self.keyword_groups = []
        for rule in rules.get("keyword_rules", []):
            self.keyword_groups.append({
                "category": rule["category"],
                "keywords": [kw.lower() for kw in rule["keywords"]],
                "severity": AlertSeverity(rule["severity"]),
                "description": rule.get("description", "")
            })

    def detect(self, content: str) -> List[Alert]:
        alerts = []
        content_lower = content.lower()

        for group in self.keyword_groups:
            for keyword in group["keywords"]:
                if keyword in content_lower:
                    position = content_lower.find(keyword)
                    alerts.append(Alert(
                        type="keyword_detected",
                        severity=group["severity"],
                        rule_name=f"keyword_{group['category']}",
                        matched_content=content[max(0, position - 20):position + len(keyword) + 20],
                        position=position,
                        description=group["description"]
                    ))
                    break

        return alerts


# ==================== 注入检测器 ====================

class InjectionDetector:
    """提示词注入检测器"""

    def __init__(self, rules: Dict):
        self.compiled = []
        for rule in rules.get("injection_rules", []):
            patterns = [re.compile(p, re.IGNORECASE) for p in rule["patterns"]]
            self.compiled.append({
                "name": rule["name"],
                "patterns": patterns,
                "severity": AlertSeverity(rule["severity"]),
                "description": rule.get("description", ""),
            })

    def detect(self, content: str) -> List[Alert]:
        alerts = []
        for rule in self.compiled:
            for pattern in rule["patterns"]:
                match = pattern.search(content)
                if match:
                    start = max(0, match.start() - 20)
                    end = min(len(content), match.end() + 20)
                    alerts.append(Alert(
                        type="injection_detected",
                        severity=rule["severity"],
                        rule_name=rule["name"],
                        matched_content=content[start:end],
                        position=match.start(),
                        description=rule["description"],
                    ))
                    break
        return alerts


# ==================== 检测引擎 ====================

class DetectionEngine:
    """检测引擎"""

    def __init__(self, config: Config):
        self.config = config
        self.pii_detector = PIIDetector(config.pii_rules)
        self.keyword_detector = KeywordDetector(config.keyword_rules)
        self.injection_detector = InjectionDetector(config.injection_rules)

    def _reload_detectors(self):
        self.pii_detector = PIIDetector(self.config.pii_rules)
        self.keyword_detector = KeywordDetector(self.config.keyword_rules)
        self.injection_detector = InjectionDetector(self.config.injection_rules)

    async def analyze(self, data: CaptureData) -> DetectionResult:
        if self.config._check_and_reload():
            self._reload_detectors()

        alerts = []

        pii_alerts = self.pii_detector.detect(data.content)
        alerts.extend(pii_alerts)

        keyword_alerts = self.keyword_detector.detect(data.content)
        alerts.extend(keyword_alerts)

        injection_alerts = self.injection_detector.detect(data.content)
        alerts.extend(injection_alerts)

        for rule in self.config.custom_rules:
            try:
                rule_alerts = self._apply_custom_rule(rule, data.content)
                alerts.extend(rule_alerts)
            except Exception as e:
                print(f"Custom rule error: {e}")

        action = "allow"
        if any(a.severity == AlertSeverity.CRITICAL for a in alerts):
            action = "block"
        elif any(a.severity == AlertSeverity.HIGH for a in alerts):
            action = "manual"

        result = DetectionResult(
            session_id=data.session_id,
            timestamp=datetime.now().isoformat(),
            alerts=alerts,
            action=action,
        )

        if data.content_type in ("text", "tool_output"):
            sanitized, mask_count = self.pii_detector.mask(data.content)
            if mask_count > 0:
                result.sanitized_content = sanitized

        return result

    def _apply_custom_rule(self, rule: Dict, content: str) -> List[Alert]:
        alerts = []
        if rule.get("type") == "regex" and rule.get("pattern"):
            try:
                pattern = re.compile(rule["pattern"])
                for match in pattern.finditer(content):
                    alerts.append(Alert(
                        type="custom_rule",
                        severity=AlertSeverity(rule.get("severity", "low")),
                        rule_name=rule.get("name", "custom"),
                        matched_content=match.group(),
                        position=match.start(),
                        description=rule.get("description", ""),
                    ))
            except re.error as e:
                print(f"Custom rule regex error ({rule.get('name')}): {e}")
        return alerts


# ==================== 通知管理器 ====================

class NotificationManager:
    """跨平台通知管理器"""

    def __init__(self, config=None):
        self.system = platform.system()
        self.config = config

    async def send_alert(self, result: DetectionResult):
        if not result.alerts:
            return

        title = f"OpenShield [{result.alerts[0].severity.value.upper()}]"
        message = self._format_message(result)

        try:
            if self.system == "Windows":
                await self._send_windows(title, message)
            elif self.system == "Linux":
                await self._send_linux(title, message)
        except Exception as e:
            self._log_error(f"Notification failed: {e}")

        await self._send_webhooks(title, message, result)

    def _log_error(self, detail: str):
        log_dir = Path.home() / ".openshield" / "logs"
        log_dir.mkdir(parents=True, exist_ok=True)
        log_file = log_dir / f"notify-{datetime.now():%Y-%m-%d}.log"
        try:
            with open(log_file, "a", encoding="utf-8") as f:
                f.write(f"[{datetime.now().isoformat()}] {detail}\n")
        except Exception:
            pass

    def _format_message(self, result: DetectionResult) -> str:
        if not result.alerts:
            return "No alerts"

        alert = result.alerts[0]
        return f"[{alert.severity.value.upper()}] {alert.description}\nMatch: {alert.matched_content[:50]}..."

    async def _send_windows(self, title: str, message: str):
        ps_script = f'''
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null

        $template = @"
        <toast>
            <visual>
                <binding template="ToastText02">
                    <text id="1">{title}</text>
                    <text id="2">{message}</text>
                </binding>
            </visual>
        </toast>
"@

        $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        $xml.LoadXml($template)
        $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("OpenShield").Show($toast)
        '''

        proc = await asyncio.create_subprocess_exec(
            "powershell", "-WindowStyle", "Hidden", "-Command", ps_script,
            stdout=asyncio.subprocess.DEVNULL,
            stderr=asyncio.subprocess.DEVNULL,
            creationflags=0x08000000,
        )
        try:
            await asyncio.wait_for(proc.wait(), timeout=5)
        except asyncio.TimeoutError:
            pass

    async def _send_linux(self, title: str, message: str):
        proc = await asyncio.create_subprocess_exec(
            "notify-send", title, message,
            stdout=asyncio.subprocess.DEVNULL,
            stderr=asyncio.subprocess.DEVNULL,
        )
        try:
            await asyncio.wait_for(proc.wait(), timeout=5)
        except asyncio.TimeoutError:
            pass

    async def _send_webhooks(self, title: str, message: str, result: DetectionResult):
        for webhook in (self.config.webhooks if self.config else []):
            if not webhook.get("enabled", True):
                continue
            try:
                payload = {
                    "text": f"**{title}**\n{message}",
                    "alerts": [
                        {
                            "type": a.type,
                            "severity": a.severity.value,
                            "rule": a.rule_name,
                            "matched": a.matched_content[:100],
                        }
                        for a in result.alerts
                    ],
                    "action": result.action,
                    "timestamp": result.timestamp,
                }
                await self._post_webhook(webhook["url"], payload)
            except Exception as e:
                self._log_error(f"Webhook {webhook.get('name', 'unknown')} failed: {e}")

    async def _post_webhook(self, url: str, payload: Dict):
        data = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(url, data=data, method="POST")
        req.add_header("Content-Type", "application/json")
        loop = asyncio.get_event_loop()
        await loop.run_in_executor(
            None,
            lambda: urllib.request.urlopen(req, timeout=5)
        )


# ==================== 日志记录器 ====================

class DetectionLogger:
    """结构化日志记录器"""

    def __init__(self, log_dir: Path):
        self.log_dir = log_dir

    async def log_detection(self, result: DetectionResult):
        log_entry = {
            "timestamp": result.timestamp,
            "session_id": result.session_id,
            "alerts": [
                {
                    "type": alert.type,
                    "severity": alert.severity.value,
                    "rule": alert.rule_name,
                    "matched": alert.matched_content,
                    "position": alert.position,
                    "description": alert.description
                }
                for alert in result.alerts
            ],
            "action_taken": result.action
        }

        log_file = self.log_dir / f"detect-{datetime.now():%Y-%m-%d}.jsonl"
        with open(log_file, "a", encoding="utf-8") as f:
            f.write(json.dumps(log_entry, ensure_ascii=False) + "\n")


# ==================== FastAPI 服务器 ====================

app = FastAPI(title="OpenShield Detect Service")
config = Config()
engine = DetectionEngine(config)
notifier = NotificationManager(config)
logger = DetectionLogger(config.logs_dir)


@app.post("/api/v1/capture")
async def receive_capture(data: CaptureData, background_tasks: BackgroundTasks):
    """接收捕获数据并执行检测"""
    try:
        result = await engine.analyze(data)

        if result.alerts:
            background_tasks.add_task(notifier.send_alert, result)

        await logger.log_detection(result)

        return {
            "status": "ok",
            "alerts": len(result.alerts),
            "action": result.action,
            "sanitized_content": result.sanitized_content,
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/v1/detect/execute")
async def detect_execute(data: ExecuteDetectionRequest, background_tasks: BackgroundTasks):
    """执行模式检测 - 工具调用前风险检测"""
    try:
        content = f"Tool: {data.tool_name}\nArgs: {json.dumps(data.tool_args)}"

        detection_data = CaptureData(
            session_id=data.session_id,
            content=content,
            content_type="tool_call",
            timestamp=data.timestamp
        )

        result = await engine.analyze(detection_data)

        if result.alerts:
            background_tasks.add_task(notifier.send_alert, result)

        await logger.log_detection(result)

        return ExecuteDetectionResponse(
            session_id=data.session_id,
            timestamp=datetime.now().isoformat(),
            action=result.action,
            alerts=result.alerts,
            reason=f"Detected {len(result.alerts)} risk items" if result.alerts else None
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/v1/health")
async def health_check():
    return {"status": "healthy", "timestamp": datetime.now().isoformat()}


@app.get("/api/v1/rules")
async def get_rules():
    return {
        "pii_rules": config.pii_rules,
        "keyword_rules": config.keyword_rules,
        "injection_rules": config.injection_rules,
        "custom_rules": [r.get("name", "custom") for r in config.custom_rules]
    }


# ==================== 主入口 ====================

if __name__ == "__main__":
    import uvicorn

    print("OpenShield Detect Service starting...")
    print(f"  Rules directory: {config.rules_dir}")
    print(f"  Logs directory: {config.logs_dir}")
    print(f"  Server: http://localhost:{config.service_port}")

    uvicorn.run(app, host="127.0.0.1", port=config.service_port)
