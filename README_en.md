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

The installer automatically handles: pip dependencies → rule files → plugin registration → Skill registration → config initialization.

### Configuration

The installer automatically creates `~/.openshield/config.json` and `opencode.json` (bash permission config). For manual configuration, see [Permission Configuration](doc/OpenShield_doc.md#permission-configuration).

**Key configuration files:**
- `~/.openshield/config.json` — Main config
- `~/.openshield/path_policy.json` — Path blacklist/whitelist
- `~/.openshield/service.token` — Service auth token

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

## Core Features

| Feature | Description | Latency |
|---------|-------------|---------|
| **PII Detection & Masking** | Auto-detect and mask phone numbers, ID cards, emails, API keys, IP addresses | < 30ms |
| **Prompt Injection Detection** | Instruction override, role hijacking, delimiter attacks, info extraction, encoding bypass | < 30ms |
| **Dangerous Command Interception** | Bash command whitelist grading; high-risk ops trigger user confirmation | < 1ms |
| **File Operation Sandbox** | Path blacklist/whitelist to prevent tampering/reading of critical system files | < 1ms |
| **Tool Output Sanitization** | Real-time masking of SSH keys, DB connection strings, JWT tokens, etc. | < 30ms |
| **Response Content Monitoring** | Detect phishing links and social engineering in LLM replies | < 500ms |
| **Session Anomaly Detection** | Behavioral pattern analysis: high-risk tool frequency, sensitive path access | Async |
| **Hot Rule Reloading** | YAML rule changes take effect automatically without restart | ~0.1ms |
| **Multi-channel Notifications** | Windows Toast / Linux notify-send / Webhook (Slack/DingTalk/Feishu) | Async |

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
┌────────────────────────────────────────────────┐
│  Skill (Message Preprocessing Layer)            │
│  LLM self-checks PII / dangerous keywords /    │
│  malicious instructions                         │
└──────────────────┬─────────────────────────────┘
                   ↓
┌────────────────────────────────────────────────┐
│  Plugin (Execution Detection + MITM Defense)    │
│                                                 │
│  tool.execute.before → command grading + sandbox│
│  tool.execute.after  → output sanitization      │
│  permission.ask      → Python engine verdict    │
│  message.updated     → response monitoring      │
│  session.idle        → anomaly detection        │
└──────────────────┬─────────────────────────────┘
                   ↓
┌────────────────────────────────────────────────┐
│  Python Detection Engine (localhost:9527)        │
│  FastAPI + Bearer Token Auth                    │
│  PII / Injection / Keywords / Output Sensitivity│
│  Desktop Notifications + Webhook + JSONL Logs   │
└────────────────────────────────────────────────┘
```

**Design Principle**: The Python engine is an enhancement layer. Local rules (< 1ms) are always available. Core protection remains effective even when the Python service is unavailable.

---

## Documentation

Full technical documentation: [OpenShield_doc.md](doc/OpenShield_doc.md)

---

## License

[Apache 2.0](LICENSE)
