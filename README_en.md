<p align="center">
  <img src="doc/images/open-shield-origin-logo.png" width="240" alt="OpenShield Logo">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/version-0.1.0-blue.svg?style=for-the-badge" alt="Version">
  <img src="https://img.shields.io/badge/license-Apache_2.0-green.svg?style=for-the-badge" alt="License">
  <img src="https://img.shields.io/github/stars/fuscher/open-shield?style=for-the-badge" alt="Stars">
  <img src="https://img.shields.io/github/issues/fuscher/open-shield?style=for-the-badge" alt="Issues">
  <img src="https://img.shields.io/badge/PRs-welcome-brightgreen.svg?style=for-the-badge" alt="PRs Welcome">
</p>

# OpenShield

[中文](README.md) | English

Security middleware designed for AI Agents, built specifically for the [OpenCode](https://opencode.ai/) platform. Provides comprehensive protection through a dual-detection mechanism (input preprocessing + execution interception) without impacting normal Agent operations.

---

## Deployment

### Requirements

- Python 3.9+
- Node.js 18+ (OpenCode runtime)
- OpenCode installed and configured

### Install

**Windows:**

```cmd
install.bat
```

**Linux / macOS:**

```bash
chmod +x install.sh && ./install.sh
```

The installer automatically handles: pip dependencies → rule files → plugin registration → Skill registration → config initialization → Dashboard configuration.

### Configuration

The installer automatically creates `~/.openshield/config.json` and `opencode.json` (bash permission config). For manual configuration, see [Permission Interaction](doc/OpenShield_doc.md#35-stage-5--降低误报率与权限交互).

**Key configuration files:**
- `~/.openshield/config.json` — Main config
- `~/.openshield/dashboard_config.json` — Dashboard config (thresholds/TS params)
- `~/.openshield/path_policy.json` — Path blacklist/whitelist
- `~/.openshield/service.token` — Service auth token

### Web Dashboard

Dashboard provides visual configuration management with dark mode and i18n support (Chinese/English).

**Start:**

```cmd
start_dashboard.bat        # Windows
./start_dashboard.sh       # Linux / macOS
```

Browser opens http://localhost:9528 automatically. Press Ctrl+C to stop.

**Features:**
- Overview: Service status, rule statistics
- Basic Settings: Detection switches, global thresholds
- Advanced Settings: Category thresholds, TS plugin parameters
- Path Policy: Blacklist/whitelist management, browser password directory protection
- Rules: PII/keyword/injection/output rule editing, custom sensitive string management
- Notifications: Webhook CRUD
- Logs: Detection/notification log viewer

### Verify

Restart OpenCode and run any conversation. Check `~/.openshield/logs/` for generated JSONL logs.

**Troubleshooting:**
- Python service won't start: Run `cd core && python openshield-detect.py` to see errors
- Permission config not working: Confirm `opencode.json` location is correct, restart OpenCode

### Uninstall

```cmd
uninstall.bat        # Windows
./uninstall.sh       # Linux / macOS
```

---

<p align="center">
  <img src="https://skillicons.dev/icons?i=python,fastapi,flask,nodejs,pycharm" alt="Tech Stack">
</p>

## Core Features

| Feature | Description | Latency |
|---------|-------------|---------|
| **PII Detection & Masking** | Regex-based email, API key, IP address detection; custom sensitive string exact-match replacement | < 30ms |
| **Custom Sensitive Strings** | User-defined strings (phone numbers, addresses, etc.) matched exactly and replaced by descending length | < 30ms |
| **Prompt Injection Detection** | Instruction override, role hijacking, delimiter attacks, info extraction, encoding bypass | < 30ms |
| **Dangerous Command Interception** | Bash command whitelist grading; high-risk ops trigger user confirmation | < 1ms |
| **File Operation Sandbox** | Path blacklist/whitelist to prevent tampering/reading of critical system files | < 1ms |
| **Browser Password Directory Protection** | Preset Chrome/Edge/Firefox password storage paths, cross-platform block/allow | < 1ms |
| **Tool Output Sanitization** | Real-time masking of SSH keys, DB connection strings, JWT tokens, etc. | < 30ms |
| **Response Content Monitoring** | Detect phishing links and social engineering in LLM replies | < 500ms |
| **Session Anomaly Detection** | Behavioral pattern analysis: high-risk tool frequency, sensitive path access | Async |
| **Hot Rule Reloading** | YAML rule changes take effect automatically without restart | ~0.1ms |
| **Multi-channel Notifications** | Windows Toast / Linux notify-send / Webhook (Slack/DingTalk/Feishu) | Async |
| **Web Dashboard** | Visual config management, dark mode, Chinese/English i18n | — |

**Verdict Actions:**

```
ALLOW  → Pass through     (low/medium risk)
MANUAL → User confirmation (high risk, shows confirmation dialog)
BLOCK  → Immediate block   (critical risk, desktop notification + log)
```

---

## Architecture

```
User Input
  ↓
┌─────────────────────────────────────────────────────────────────┐
│  Skill (Message Preprocessing Layer)
│  Markdown guides LLM to self-check PII /
│  dangerous keywords / malicious instructions
└──────────────────┬──────────────────────────────────────────────┘
                   ↓
┌─────────────────────────────────────────────────────────────────┐
│  Plugin (Execution Detection Layer)
│  TypeScript plugin intercepts tool calls
│  tool.execute.before → local grading + path sandbox
│  tool.execute.after  → output sanitization + PII detection
│  permission.ask      → Python engine precise verdict
│  message.updated     → response content firewall
│  session.idle        → session anomaly detection
└──────────────────┬──────────────────────────────────────────────┘
                   ↓
┌─────────────────────────────────────────────────────────────────┐
│  MITM Defense Layer (Stage 6)
│  Phase A: Response monitoring (social engineering/phishing)
│  Phase B: File operation sandbox (path blacklist/whitelist)
│  Phase C: Tool output sanitization (real-time masking)
│  Phase D: Session anomaly detection (behavior analysis)
└──────────────────┬──────────────────────────────────────────────┘
                   ↓
┌─────────────────────────────────────────────────────────────────┐
│  Python Detection Engine (localhost:9527)
│  FastAPI single-file service + Bearer Token auth
│  PII detection/masking + injection detection + keyword matching
│  Output sensitive info detection + response content scanning
│  Desktop notifications + Webhook + JSONL logs
│  Hot rule reloading (YAML mtime monitoring)
└─────────────────────────────────────────────────────────────────┘
```

**Design Principle**: The Python engine is an enhancement layer. Local rules (< 1ms) are always available. Core protection remains effective even when the Python service is unavailable.

---

## Documentation

- Full technical documentation: [OpenShield_doc.md](doc/OpenShield_doc.md)

---

## License

[Apache 2.0](LICENSE)
