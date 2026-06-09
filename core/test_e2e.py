#!/usr/bin/env python3
"""openShield Phase 5 - 端到端测试"""

import json
import time
import sys
import urllib.request
import urllib.error
from pathlib import Path

SERVICE_URL = "http://localhost:9527"
TEST_CASES = [
    ("高危: rm -rf", "bash", {"command": "rm -rf /data/backup"}, "block", 1),
    ("高危: DROP TABLE", "bash", {"command": "mysql -e 'DROP TABLE users'"}, "block", 1),
    ("高危: shutdown", "shell", {"command": "shutdown -h now"}, "block", 1),
    ("中危: curl", "bash", {"command": "curl https://example.com"}, "allow", 0),
    ("高危: API Key", "bash", {"command": "export KEY=sk-abc123def456ghi789jkl"}, "block", 1),
    ("正常: ls", "bash", {"command": "ls -la"}, "allow", 0),
    ("正常: echo", "bash", {"command": "echo hello world"}, "allow", 0),
    ("身份证号码", "write", {"filePath": "/test.txt", "content": "110101199001011234"}, "block", 1),
    ("手机号码", "write", {"filePath": "/test.txt", "content": "13800138000"}, "high", 1),
    ("邮箱地址", "write", {"filePath": "/test.txt", "content": "user@example.com"}, "medium", 1),
]

passed = 0
failed = 0

def call_api(endpoint, data=None, method="POST"):
    url = f"{SERVICE_URL}{endpoint}"
    body = json.dumps(data).encode("utf-8") if data else None
    req = urllib.request.Request(url, data=body, method=method)
    if body:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except Exception as e:
        print(f"  API Error: {e}")
        return None

print("=" * 60)
print("  openShield Phase 5 - E2E Tests")
print("=" * 60)

# Test 1: Health check
print("\n[Test] Health check...")
r = call_api("/api/v1/health", method="GET")
if r and r.get("status") == "healthy":
    print("  PASS: Health check OK")
    passed += 1
else:
    print(f"  FAIL: {r}")
    failed += 1

# Test 2: Rules endpoint
print("\n[Test] Rules endpoint...")
r = call_api("/api/v1/rules", method="GET")
if r and "pii_rules" in r:
    pii_count = len(r.get("pii_rules", {}).get("pii_rules", []))
    kw_count = len(r.get("keyword_rules", {}).get("keyword_rules", []))
    print(f"  PASS: {pii_count} PII rules, {kw_count} keyword categories")
    passed += 1
else:
    print(f"  FAIL: {r}")
    failed += 1

# Test 3: Capture endpoint (safe)
print("\n[Test] Capture endpoint (safe content)...")
data = {
    "session_id": "test-001",
    "content": "Normal message without sensitive info.",
    "content_type": "text",
    "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
}
r = call_api("/api/v1/capture", data)
if r and r.get("alerts") == 0:
    print("  PASS: 0 alerts for safe content")
    passed += 1
else:
    print(f"  FAIL: expected 0 alerts, got {r}")
    failed += 1

# Test 4: Capture endpoint (PII)
print("\n[Test] Capture endpoint (PII)...")
data["content"] = "ID: 110101199001011234, phone: 13800138000"
data["session_id"] = "test-002"
r = call_api("/api/v1/capture", data)
if r and r.get("alerts", 0) >= 1:
    print(f"  PASS: {r['alerts']} PII alert(s), action={r['action']}")
    passed += 1
else:
    print(f"  FAIL: {r}")
    failed += 1

# Test 5-14: Execute detection
print("\n[Test] Execute detection scenarios...")
for name, tool, args, expected_action, expected_alerts in TEST_CASES:
    data = {
        "session_id": f"test-{tool}",
        "tool_name": tool,
        "tool_args": args,
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    }
    r = call_api("/api/v1/detect/execute", data)
    if not r:
        print(f"  FAIL: {name} - no response")
        failed += 1
        continue

    actual_action = r.get("action", "?")
    actual_alerts = len(r.get("alerts", []))

    blk = actual_action in ("block", "manual")
    warn = actual_action != "allow"
    ok = actual_action == "allow"

    if expected_action == "block" and blk and actual_alerts >= expected_alerts:
        status = "PASS"
        passed += 1
    elif expected_action == "high" and warn and actual_alerts >= expected_alerts:
        status = "PASS"
        passed += 1
    elif expected_action == "medium" and actual_alerts >= expected_alerts:
        status = "PASS"
        passed += 1
    elif expected_action == "allow" and ok:
        status = "PASS"
        passed += 1
    else:
        status = "FAIL"
        failed += 1

    print(f"  {status}: {name} -> action={actual_action}, alerts={actual_alerts}")
    if status == "FAIL":
        for a in r.get("alerts", []):
            print(f"         [{a['severity']}] {a['description']}")

# Test 15: Log file
print("\n[Test] Log file...")
log_dir = Path.home() / ".openshield" / "logs"
log_files = sorted(log_dir.glob("detect-*.jsonl"))
if log_files:
    with open(log_files[-1], "r", encoding="utf-8") as f:
        lines = f.readlines()
    print(f"  PASS: {len(lines)} entries in {log_files[-1].name}")
    passed += 1
else:
    print("  FAIL: No log file")
    failed += 1

# Summary
print("\n" + "=" * 60)
total = passed + failed
print(f"  Results: {passed}/{total} passed, {failed} failed")
print("=" * 60)

sys.exit(0 if failed == 0 else 1)

