#!/usr/bin/env python3
"""openShield Detect Service - 单文件检测服务"""

import os
import re
import json
import platform
import subprocess
from pathlib import Path
from datetime import datetime
from typing import List, Dict, Any, Optional
from enum import Enum

import yaml
from fastapi import FastAPI, HTTPException
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

        self.pii_rules = self._load_yaml("pii.yaml")
        self.keyword_rules = self._load_yaml("keywords.yaml")
        self.custom_rules = self._load_custom_rules()

    def _load_yaml(self, filename: str) -> Dict:
        filepath = self.rules_dir / filename
        if filepath.exists():
            with open(filepath, "r", encoding="utf-8") as f:
                return yaml.safe_load(f) or {}
        return {}

    def _load_custom_rules(self) -> List:
        custom_dir = self.rules_dir / "custom"
        if not custom_dir.exists():
            return []

        rules = []
        for py_file in custom_dir.glob("*.py"):
            try:
                import importlib.util
                spec = importlib.util.spec_from_file_location(py_file.stem, py_file)
                module = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(module)
                if hasattr(module, "CustomRule"):
                    rules.append(module.CustomRule())
            except Exception as e:
                print(f"Failed to load custom rule {py_file}: {e}")

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
            self.patterns.append({
                "name": rule["name"],
                "regex": re.compile(rule["pattern"]),
                "severity": AlertSeverity(rule["severity"]),
                "description": rule.get("description", "")
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


# ==================== 检测引擎 ====================

class DetectionEngine:
    """检测引擎"""

    def __init__(self, config: Config):
        self.config = config
        self.pii_detector = PIIDetector(config.pii_rules)
        self.keyword_detector = KeywordDetector(config.keyword_rules)

    async def analyze(self, data: CaptureData) -> DetectionResult:
        alerts = []

        pii_alerts = self.pii_detector.detect(data.content)
        alerts.extend(pii_alerts)

        keyword_alerts = self.keyword_detector.detect(data.content)
        alerts.extend(keyword_alerts)

        for rule in self.config.custom_rules:
            try:
                rule_alerts = await rule.detect(data)
                alerts.extend(rule_alerts)
            except Exception as e:
                print(f"Custom rule error: {e}")

        action = "allow"
        if any(a.severity == AlertSeverity.CRITICAL for a in alerts):
            action = "block"
        elif any(a.severity == AlertSeverity.HIGH for a in alerts):
            action = "manual"

        return DetectionResult(
            session_id=data.session_id,
            timestamp=datetime.now().isoformat(),
            alerts=alerts,
            action=action
        )


# ==================== 通知管理器 ====================

class NotificationManager:
    """跨平台通知管理器"""

    def __init__(self):
        self.system = platform.system()

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
            print(f"Notification failed: {e}")

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
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("openShield").Show($toast)
        '''

        subprocess.run(
            ["powershell", "-Command", ps_script],
            capture_output=True,
            timeout=10
        )

    async def _send_linux(self, title: str, message: str):
        subprocess.run(
            ["notify-send", title, message],
            capture_output=True,
            timeout=10
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

app = FastAPI(title="openShield Detect Service")
config = Config()
engine = DetectionEngine(config)
notifier = NotificationManager()
logger = DetectionLogger(config.logs_dir)


@app.post("/api/v1/capture")
async def receive_capture(data: CaptureData):
    """接收捕获数据并执行检测"""
    try:
        result = await engine.analyze(data)

        if result.alerts:
            await notifier.send_alert(result)

        await logger.log_detection(result)

        return {
            "status": "ok",
            "alerts": len(result.alerts),
            "action": result.action
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/v1/detect/execute")
async def detect_execute(data: ExecuteDetectionRequest):
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
            await notifier.send_alert(result)

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
        "custom_rules": [r.__class__.__name__ for r in config.custom_rules]
    }


# ==================== 主入口 ====================

if __name__ == "__main__":
    import uvicorn

    print("OpenShield Detect Service starting...")
    print(f"  Rules directory: {config.rules_dir}")
    print(f"  Logs directory: {config.logs_dir}")
    print(f"  Server: http://localhost:{config.service_port}")

    uvicorn.run(app, host="127.0.0.1", port=config.service_port)
