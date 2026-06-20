# OpenShield 项目完整文档

> **文档版本**: v3.1  
> **最后更新**: 2026-06-20  
> **项目状态**: Stage 1-11 已完成

---

## 一、项目概述

### 1.1 项目定位

**OpenShield** 是一个**为 AI Agent 设计的安全中间件**，专门针对 [OpenCode](https://opencode.ai/) 平台。它通过双重检测机制，在用户输入阶段和工具执行阶段分别拦截安全风险，为 AI Agent 提供全方位的安全防护。

### 1.2 核心价值

| 价值点 | 说明 |
|--------|------|
| **双重防护** | 输入阶段（Skill）+ 执行阶段（Plugin）两层检测，覆盖完整攻击面 |
| **即插即用** | 单文件插件 + 一键安装脚本，快速集成到 OpenCode |
| **规则驱动** | 正则 + 关键词，无需 AI 模型，低延迟、可解释、易扩展 |
| **渐进增强** | 本地轻量规则（< 1ms）→ Python 精确引擎（< 30ms）按需升级 |
| **开源开放** | Apache 2.0 协议，企业友好 |

### 1.3 解决的问题

| 问题类型 | 具体场景 | 后果 |
|----------|---------|------|
| 敏感信息泄露 | 用户输入或 LLM 输出身份证、手机号、API Key | 数据泄露、合规风险 |
| 危险操作执行 | Agent 执行 rm -rf、DROP TABLE、shutdown | 真实世界损失 |
| 提示词注入 | 用户输入恶意指令绕过安全限制 | Agent 行为失控 |
| 审计缺失 | 无法追溯 Agent 做了什么 | 合规与排障困难 |

### 1.4 目标用户

- **AI Agent 开发者**: 使用 OpenCode 平台进行开发的工程师
- **企业安全团队**: 关注数据安全和合规的企业用户
- **运维人员**: 需要审计 AI Agent 操作行为的技术人员

---

## 二、项目架构

### 2.1 整体架构（四层）

```
用户输入
  ↓
┌─────────────────────────────────────────────┐
│  Skill (消息预处理检测层)                     │
│  纯 Markdown 指导 LLM 自我检测 PII /         │
│  危险关键词 / 恶意指令 → 告知用户风险          │
└──────────────────┬──────────────────────────┘
                   ↓
┌─────────────────────────────────────────────┐
│  Plugin (执行模式检测层)                      │
│  TypeScript 插件，拦截工具调用                 │
│  tool.execute.before → 本地分级 + 路径沙箱    │
│  tool.execute.after  → 输出脱敏 + PII 检测   │
│  permission.ask      → Python 引擎精确判定    │
│  message.updated     → 响应内容防火墙         │
│  session.idle        → 会话异常检测           │
└──────────────────┬──────────────────────────┘
                   ↓
┌─────────────────────────────────────────────┐
│  MITM 纵深防御层 (Stage 6)                    │
│  Phase A: 响应内容监控（社会工程/钓鱼检测）     │
│  Phase B: 文件操作沙箱（路径黑白名单）          │
│  Phase C: 工具输出脱敏（敏感信息实时脱敏）      │
│  Phase D: 会话异常检测（行为模式分析）          │
└──────────────────┬──────────────────────────┘
                   ↓
┌─────────────────────────────────────────────┐
│  Python 检测引擎 (localhost:9527)             │
│  FastAPI 单文件服务 + Bearer Token 认证       │
│  PII 检测/脱敏 + 注入检测 + 关键词匹配        │
│  输出敏感信息检测 + 响应内容扫描               │
│  桌面通知 + Webhook + JSONL 日志              │
│  规则热加载（YAML mtime 监控）                │
└─────────────────────────────────────────────┘
```

### 2.2 组件分工

| 组件 | 位置 | 职责 | 延迟 |
|------|------|------|------|
| **Skill** | `.opencode/skills/openshield-safety/SKILL.md` | LLM 消息预处理检测 PII/关键词/恶意指令 | — |
| **Plugin** | `src/plugin/open_shield.ts` | 数据捕获 + 执行前分级 + 路径沙箱 + 权限控制 + 输出脱敏 + 响应监控 + 会话分析 + 服务自启动 | < 1ms |
| **Python 引擎** | `core/openshield-detect.py` | PII 检测/脱敏 + 注入检测 + 关键词匹配 + 输出敏感信息检测 + 通知 + 日志 + 规则热加载 + Bearer Token 认证 | < 30ms |

### 2.3 技术选型

| 技术 | 用途 | 选择理由 |
|------|------|---------|
| TypeScript | OpenCode 插件 | OpenCode 原生插件语言，零外部依赖 |
| Python + FastAPI | 检测引擎 | 异步支持，Pydantic 数据校验，单文件部署 |
| FastAPI BackgroundTasks | 非阻塞通知 | 内置机制，零依赖，响应返回后执行通知 |
| YAML | 规则配置 | 可读性好，安全加载 (safe_load) |
| JSONL | 日志存储 | 结构化、可追加、便于 grep/jq 分析 |

### 2.4 Hook 体系

| Hook | 类型 | 触发时机 | 用途 |
|------|------|---------|------|
| `chat.message` | 命名 hook | 用户消息到达 | 捕获用户输入 |
| `event` (message.updated) | 事件 | 消息更新 | 捕获 LLM 回复 + Phase A 响应内容监控 |
| `tool.execute.before` | 命名 hook | 工具执行前 | 本地风险分级 + Phase B 路径沙箱 |
| `tool.execute.after` | 命名 hook | 工具执行后 | Phase C 输出脱敏 + 捕获执行结果 |
| `permission.ask` | 命名 hook | 权限检查 | 调用 Python 引擎精确判定（bash 白名单分级） |
| `event` (permission.asked) | 事件 | 权限确认后 | 只读事件，日志记录 |
| `event` (session.idle) | 事件 | 会话空闲 | Phase D 会话异常检测 + 持久化捕获数据 |
| `event` (session.*) | 事件 | 会话生命周期 | 会话状态日志 |

---

## 三、重要里程碑

### 3.1 Stage 1 — 数据捕获插件 (v1.1)

| 项目 | 内容 |
|------|------|
| **完成时间** | 2026-06-07 |
| **交付成果** | 自包含插件 + 一键安装/卸载脚本 |
| **代码量** | 约 220 行 TypeScript |

**核心成果**:
- 实现了 OpenCode 插件，通过 7 个 Hook 机制实时捕获 LLM 输出和用户输入
- 修复了 `message.updated` Hook 签名错误（v1.0 bug），改由 `event` 钩子投递
- 新增 `chat.message` 钩子捕获用户输入，支持 `role` 字段区分消息来源
- 预留 `tool.execute.before` 和 `permission.ask` 钩子供后续阶段使用
- 数据统一存储在 `~/.openshield/captures/` 目录

### 3.2 Stage 2 — 双重检测机制

| 项目 | 内容 |
|------|------|
| **完成时间** | 2026-06-09 |
| **E2E 测试** | 15/15 通过 |
| **代码量** | Plugin 529 行 + Python 419 行 |

**核心成果**:
- 设计并实现双重安全检测架构：消息预处理检测（Skill）+ 执行模式检测（Plugin）
- Python 检测服务（单文件 FastAPI，4 个 HTTP 端点）
- 5 条 PII 规则（手机号/身份证/邮箱/API Key/IP）+ 4 个关键词类别
- Windows/Linux 桌面通知 + 结构化 JSONL 日志
- 自定义规则插件框架（custom/ 目录）

### 3.3 Stage 3 — 增强检测与脱敏

| 项目 | 内容 |
|------|------|
| **完成时间** | 2026-06-10 |
| **E2E 测试** | 24/24 全部通过 |
| **代码量** | Python 607 行 + Plugin 529 行 |

**6 个 Phase 全部完成**:

| Phase | 目标 | 关键实现 |
|-------|------|---------|
| 1 | 扩展工具拦截范围 | HIGH/MEDIUM_RISK_TOOLS 拆分 + 两阶段兜底（Python 不可达时本地阻断） |
| 2 | 提示词注入检测 | `InjectionDetector` + `injection.yaml`（5 类注入攻击） |
| 3 | API 返回值检测 | `sendToCaptureService()` 将工具输出送 Python 引擎分析 |
| 4 | PII 脱敏替换 | `mask()` 按规则类型区分策略，脱敏内容回写 buffer |
| 5 | 规则热加载 | `_check_and_reload()` 监控 YAML mtime，含删除感知 |
| 6 | Webhook 通知 | 支持 Slack/钉钉/飞书 HTTP Webhook 告警推送 |

### 3.4 Stage 4 — 降低误报率与用户交互优化

| 项目 | 内容 |
|------|------|
| **完成时间** | 2026-06-12 |
| **E2E 测试** | 30/30 全部通过 |

**核心成果**:
- PII 检测误报优化：`tool.execute.after` 仅对高/中风险工具输出送检，低风险工具（read/grep/glob 等）跳过 PII 检测
- 卸载脚本粒度优化：7 步交互式卸载，用户可选择保留规则/日志/数据
- Skill 检测精度提升：结构化输出格式 + 分场景检测指南 + 误报判断指南
- 阻断后用户感知优化：`throw Error` 替代静默 deny，用户可见阻断原因
- Skill 命名规范化：统一为小写命名

### 3.5 Stage 5 — 降低误报率与权限交互

| 项目 | 内容 |
|------|------|
| **完成时间** | 2026-06-13 |
| **E2E 测试** | 30/30 全部通过 |

**核心成果**:
- Bash 命令白名单分级：`git status`、`npm install`、`ls` 等无害命令直接放行，消除高频误报
- `permission.ask` hook 集成：高风险操作触发 OpenCode 权限确认 UI（allow/deny/ask 三态）
- 关键词边界匹配优化：`delete`/`drop`/`fetch` 不再匹配变量名（如 `handleDelete`），使用正则边界 `\b`
- Service Token 认证：Python 引擎添加 Bearer Token 认证，防止本地未授权访问
- 安装脚本生成 `~/.openshield/service.token`，Plugin 端自动加载 Token

### 3.6 Stage 6 — MITM 纵深防御

| 项目 | 内容 |
|------|------|
| **完成时间** | 2026-06-14 |
| **E2E 测试** | 30 用例全部通过 |
| **实现状态** | Phase B/C 完整实现，Phase A/D 简化版本地实现 |

**四层纵深防御**:

| Phase | 功能 | 实现方式 | 状态 |
|-------|------|---------|------|
| **A** | 响应内容监控 | 拦截 `message.updated` (assistant)，累积内容后送检，检测钓鱼/社会工程/注入 | ✅ 简化实现 |
| **B** | 文件操作沙箱 | `checkPathPolicy()` 路径黑白名单 + `throw Error` 阻断，防止关键文件被篡改/读取 | ✅ 完整实现 |
| **C** | 工具输出脱敏 | `sendToOutputGuard()` + `/api/v1/detect/output`，实时脱敏敏感信息写回 output | ✅ 完整实现 |
| **D** | 会话异常检测 | 本地计数器 + 阈值判断（高危工具数、敏感路径数），`session.idle` 时评估 | ✅ 简化实现 |

**关键验证发现**:
- `permission.asked` 是只读事件，不能用于阻断操作
- `output.output` 写回有效，Phase C 实时脱敏路径可行
- `message.updated` 流式高频触发（3-5ms 间隔），Phase A 需 throttle 机制

### 3.7 Stage 10 — 自定义敏感字符串过滤 + 浏览器密码目录保护

| 项目 | 内容 |
|------|------|
| **完成时间** | 2026-06-20 |
| **实现状态** | 完整实现 |

**核心变更**:

| 功能 | 说明 |
|------|------|
| **移除高误报正则** | 彻底移除 `phone_number` 和 `id_card` 正则规则 |
| **自定义敏感字符串** | Dashboard 手动输入需保护的字符串（手机号/身份证/地址），精确子串匹配 → `***` 替换 |
| **精确替换策略** | 告警不计入 alerts（避免误阻断），按 item 长度降序，短串日志中不泄露 |
| **浏览器密码目录保护** | 预设 Chrome/Edge/Firefox 三平台密码路径，支持 allow/block 动作 |
| **跨平台路径解析** | `expandEnvVariables()`：%VAR% / ${VAR} / $VAR(仅大写) / ~ 全平台展开 |
| **热加载修复** | `loadPathPolicy()` mtime 检测，文件变更时重新读取；`matchPattern` 移除冗余 `"i"` 标志 |

### 3.8 Stage 11 — 规则编辑/添加/删除功能实现 + i18n 全面修复

| 项目 | 内容 |
|------|------|
| **完成时间** | 2026-06-20 |
| **实现状态** | 完整实现 |

**核心变更**:

| 功能 | 说明 |
|------|------|
| **规则 CRUD** | 编辑/添加/删除规则，支持 PII、关键词、注入、输出敏感、响应监控、自定义六种类型 |
| **通用动态表单** | 一个模态框根据 `currentTab` 动态渲染字段，output_sensitivity 按 strategy 条件显示 |
| **response_guard 精确编辑** | `editRule(index, group)` 传递分组参数，支持 phishing/leak_detection 分组切换 |
| **自定义规则多文件写入** | 后端 `_source` 字段标记来源，PUT 时按源文件分组写回，导出时剥离内部字段 |
| **还原默认** | `POST /api/rules/<type>/reset` 按当前 Tab 从 `core/rules/` 恢复默认规则 |
| **i18n 全面修复** | 修复 11 处纯中文硬编码 + 15 处内联三元表达式，新增 50 个中英翻译 key |
| **输入验证** | 正则表达式合法性校验 + 名称非空 + 数组非空 + XSS 转义 |

---

## 四、功能模块详解

### 4.1 检测能力矩阵

#### PII 检测规则 (pii.yaml)

| 规则 | 正则模式 | 等级 | 脱敏结果示例 |
|------|---------|------|-------------|
| 邮箱地址 | `[a-zA-Z0-9._%+-]+@...` | medium | `test@example.com` → `te***@example.com` |
| API 密钥 | `(sk-\|ak-\|key-)[a-zA-Z0-9]{20,}` | critical | `sk-abc123...` → `sk-***ghi` |
| IP 地址 | `\b([0-9]{1,3}\.){3}[0-9]{1,3}\b` | low | `192.168.1.1` → `192.168***1` |
| 自定义敏感字符串 | 用户输入的子串（非正则） | — | 精确子串 → `***` |

#### 关键词规则 (keywords.yaml)

| 类别 | 关键词 | 等级 |
|------|--------|------|
| 数据库 | delete, drop, truncate, 删除, 清空 | high |
| 财务 | 转账, 汇款, payment, transfer | critical |
| 系统 | rm -rf, format, reboot, shutdown, 重启, 关机 | critical |
| 网络 | curl, wget, fetch | low |

#### 注入检测规则 (injection.yaml)

| 类型 | 模式示例 | 等级 |
|------|---------|------|
| 指令覆盖 | `ignore previous instructions`, `忽略之前的所有指令` | critical |
| 角色劫持 | `you are now`, `从现在起你是` | critical |
| 分隔符攻击 | `### SYSTEM:`, `<|im_start|>` | high |
| 信息提取 | `print your system prompt`, `输出你的系统提示词` | high |
| 编码绕过 | `base64:`, `rot13:`, `解码以下内容` | medium |

#### 响应内容监控规则 (response_guard.yaml) — Stage 6

| 类别 | 模式示例 | 等级 |
|------|---------|------|
| 社会工程 — 关闭防护 | `关闭防护`, `disable shield`, `绕过检测` | critical |
| 社会工程 — 权威冒充 | `我是管理员`, `系统要求你`, `这是紧急更新` | high |
| 社会工程 — 紧迫感 | `不执行会`, `后果自负`, `你只有一次机会` | high |
| 钓鱼 — 可疑域名 | `free-gpt.tk`, `secure-openai.xyz` | critical |
| 钓鱼 — 凭证收集 | `请输入密码`, `输入API密钥`, `验证你的身份信息` | critical |
| 内网泄露 | `10.x.x.x`, `172.16-31.x.x`, `192.168.x.x` | medium |

#### 输出敏感信息规则 (output_sensitivity.yaml) — Stage 6

| 规则 | 模式 | 等级 | 动作 |
|------|------|------|------|
| SSH 私钥 | `-----BEGIN (RSA\|DSA\|EC\|OPENSSH) PRIVATE KEY-----` | critical | strip |
| AWS 凭证 | `aws_access_key_id`, `AKIA[0-9A-Z]{16}` | critical | strip |
| 数据库连接串 | `mongodb://`, `mysql://`, `postgresql://` | high | sanitize |
| JWT Token | `eyJ...` (三段式) | high | sanitize |
| API Key 泄露 | `sk-`, `api_key=`, `token=` + 20+ 字符 | critical | block_chain |

#### 本地命令分级

```typescript
// 高风险 — 系统级/外部命令，有真实破坏风险
const HIGH_RISK_TOOLS = [
    "bash", "shell", "exec", "spawn",
    "database", "query", "execute",
]

// 中风险 — 内部文件操作工具，频率高但需关注
const MEDIUM_RISK_TOOLS = [
    "curl", "wget", "chmod", "chown",
    "write", "edit", "overwrite",
    "delete", "remove", "unlink",
]
```

#### 路径黑白名单 (path_policy.json) — Stage 6

| 类型 | 路径模式 | 说明 |
|------|---------|------|
| 黑名单 | `/etc/**`, `/boot/**`, `~/.ssh/**`, `C:\Windows\**` | 系统关键路径，禁止写入 |
| 黑名单 | `**/.env`, `**/credentials`, `**/*.pem` | 敏感文件，禁止操作 |
| 白名单 | `/tmp/**`, `~/projects/**`, `D:\Git\**` | 工作目录，允许操作 |
| 敏感读取 | `~/.ssh/**`, `~/.aws/**`, `/etc/passwd` | 读取时触发告警 |
| 浏览器密码 | `%LOCALAPPDATA%\...\Login Data`, `~/.mozilla/.../logins.json` 等 | Chrome/Edge/Firefox 密码存储目录 |

### 4.2 判定动作

| 最高等级 | 动作 | 含义 |
|----------|------|------|
| critical | **BLOCK** | 直接阻断 |
| high | **MANUAL** | 请求用户确认 |
| medium/low | **ALLOW** | 放行 |

### 4.3 PII 脱敏策略

Python 引擎的 `mask()` 方法实现脱敏：

```python
def mask(self, content: str) -> tuple:
    """返回 (脱敏后内容, 替换数)"""
    masked = content
    count = 0
    for pattern in self.patterns:
        for match in reversed(list(pattern["regex"].finditer(content))):
            original = match.group()
            replacement = original[:2] + "***" + original[-2:] if len(original) > 4 else "***"
            masked = masked[:match.start()] + replacement + masked[match.end():]
            count += 1
    return masked, count
```

### 4.4 HTTP API

| 端点 | 方法 | 说明 | 阶段 |
|------|------|------|------|
| `/api/v1/capture` | POST | 通用内容检测（text/tool_output），返回 `sanitized_content` 脱敏字段 | Stage 2 |
| `/api/v1/detect/execute` | POST | 工具调用前精确检测（含注入检测） | Stage 2 |
| `/api/v1/detect/output` | POST | 工具输出敏感信息检测（SSH 密钥、Token、连接串等） | Stage 6 |
| `/api/v1/detect/response` | POST | 响应内容防火墙（钓鱼/社会工程/内网泄露） | Stage 6 |
| `/api/v1/session/analyze` | POST | 会话行为异常分析 | Stage 6 |
| `/api/v1/policy/path` | GET | 路径策略查询 | Stage 6 |
| `/api/v1/health` | GET | 健康检查 | Stage 2 |
| `/api/v1/rules` | GET | 当前规则查询（含 custom_rules） | Stage 2 |
| `/api/rules/<type>/reset` | POST | 还原默认规则（从 core/rules/ 恢复） | Stage 11 |
| `/api/sensitive-strings` | GET/PUT | 自定义敏感字符串配置 | Stage 10 |
| `/api/browser-passwords` | GET/PUT | 浏览器密码目录保护配置 | Stage 10 |
| `/api/verify` | GET | 系统配置校验 + 平台信息（sys.platform） | Stage 7 |

> **认证**: Stage 5 起所有端点需 Bearer Token 认证（Token 存储于 `~/.openshield/service.token`）

### 4.5 通知机制

| 渠道 | 实现 | 阻塞特性 |
|------|------|---------|
| Windows Toast | PowerShell `ToastNotificationManager` | 后台执行（BackgroundTasks） |
| Linux notify-send | `notify-send` 命令 | 后台执行（BackgroundTasks） |
| Webhook | HTTP POST 到 Slack/钉钉/飞书 | 后台执行 |

### 4.6 规则热加载

| 机制 | 说明 |
|------|------|
| mtime 监控 | `_check_and_reload()` 每次请求检测主 YAML + `custom/` 目录文件 mtime |
| 变更类型 | 新增 / 修改 / 删除 三种变更均感知（含 stale key 清理） |
| 触发条件 | 任一规则文件 mtime 变化 → `_load_all_rules()` + `_reload_detectors()` |
| 性能影响 | 每次请求增加 3 次 stat() 调用（~0.1ms），仅在文件变更时重新加载（~1ms） |

---

## 五、业务逻辑流程

### 5.1 消息预处理流程

```
用户输入消息
    ↓
LLM 接收用户输入
    ↓
Skill 指导 LLM 进行基础安全检测
    ├── PII 信息：手机号、身份证、邮箱、API Key
    ├── 危险关键词：delete, rm -rf, 转账 等
    └── 恶意指令：提示词注入、角色覆盖
    ↓
├─ 无风险 ─→ LLM 正常处理，生成响应
    ↓
└─ 有风险 ─→ LLM 告知用户潜在风险 → 用户决定是否继续
```

### 5.2 执行模式检测流程

```
Agent 准备执行工具调用
    ↓
Plugin: tool.execute.before Hook 触发
    ↓
detectToolRisk() 本地命令分级  < 1ms
    ├── low   → 放行
    ├── medium → 记录日志，放行
    └── high  → 触发 permission.ask
                 ↓
Plugin: permission.ask Hook 触发
    ↓
sendToDetectService() 调用 Python 引擎
    ├── serviceReady = true
    │   ├── POST /api/v1/detect/execute
    │   ├── Python: PII 正则 + 关键词匹配 + 注入检测
    │   ├── 返回 { action: "allow" | "block" | "manual", alerts: [...] }
    │   └── block → output.status = "deny"（终端阻止执行）
    │
    └── serviceReady = false
        └── 本地兜底阻断（高风险操作不放行）

判定结果：
  ALLOW  → 放行执行
  BLOCK  → 阻断 + Toast 通知 + JSONL 日志
  MANUAL → 用户在终端确认后执行
```

### 5.3 工具输出检测流程

```
工具执行完成
    ↓
Plugin: tool.execute.after Hook 触发
    ↓
捕获工具输出内容
    ↓
sendToCaptureService() → Python 引擎
    ↓
PII + 关键词 + 注入检测
    ↓
mask() PII 脱敏 → 返回 sanitized_content
    ↓
Plugin 使用脱敏版本写入 buffer.toolCalls
    ↓
检测到告警时：
    background_tasks.add_task(send_alert)
    → 响应立即返回
    → 后台并行执行桌面通知 + Webhook 推送
```

### 5.4 服务自启动流程

```
OpenCode 启动
    ↓
Plugin 加载 open_shield.ts
    ↓
读取 ~/.openshield/config.json
    ├── 获取 project_dir
    └── 拼接: {project_dir}/core/openshield-detect.py
    ↓
ensureRules() — 检查 ~/.openshield/rules/
    ├── pii.yaml 缺失？从 core/rules/ 复制
    ├── keywords.yaml 缺失？从 core/rules/ 复制
    └── injection.yaml 缺失？从 core/rules/ 复制
    ↓
getPythonCommand() — 依次尝试 python → python3
    ├── 成功 → 获取命令
    └── 失败 → 服务不可用
    ↓
spawn(python, [pyPath])
    ↓
waitForService() — 轮询 GET /api/v1/health
    ├── 就绪 (最多 10s) → serviceReady = true
    └── 超时 (10s) → serviceReady = false，使用本地规则兜底
```

### 5.5 规则热加载流程

```
每次检测请求到达
    ↓
Config._check_and_reload()
    ├── 检查 pii.yaml mtime
    ├── 检查 keywords.yaml mtime
    ├── 检查 injection.yaml mtime
    └── 检查 custom/ 目录文件 mtime
    ↓
├─ 无变化 ─→ 使用现有规则
    ↓
└─ 有变化 ─→ _load_all_rules()
    ├── 重新加载所有 YAML 文件
    ├── 重建检测器实例
    └── 清理 stale key（已删除的规则）
```

### 5.6 MITM 纵深防御流程 (Stage 6)

```
┌── Phase A: 响应内容监控 ──────────────────────┐
│                                               │
│  LLM 回复到达 → message.updated (assistant)   │
│      ↓                                        │
│  累积内容（throttle: 500ms / 100字符）          │
│      ↓                                        │
│  sendToResponseGuard() → Python 引擎           │
│      ├── 钓鱼链接检测                           │
│      ├── 社会工程检测                           │
│      └── 注入攻击检测                           │
│      ↓                                        │
│  allow / sanitize / warn                      │
└───────────────────────────────────────────────┘

┌── Phase B: 文件操作沙箱 ──────────────────────┐
│                                               │
│  write/edit/delete 工具调用                    │
│      ↓                                        │
│  tool.execute.before → extractPath(args)      │
│      ↓                                        │
│  checkPathPolicy(path)                        │
│      ├── 黑名单命中 → throw Error (block)     │
│      ├── 敏感读取 → 告警 + 日志               │
│      └── 白名单内 → allow                     │
└───────────────────────────────────────────────┘

┌── Phase C: 工具输出脱敏 ──────────────────────┐
│                                               │
│  工具执行完成 → tool.execute.after             │
│      ↓                                        │
│  sendToOutputGuard() → /api/v1/detect/output  │
│      ├── allow → output 不变                  │
│      ├── sanitize → 脱敏写回 output.output    │
│      ├── strip → 截断为 [内容已移除]          │
│      └── block_chain → 阻止进入 LLM 上下文    │
└───────────────────────────────────────────────┘

┌── Phase D: 会话异常检测 ──────────────────────┐
│                                               │
│  session.idle 触发                            │
│      ↓                                        │
│  本地计数器聚合                                │
│      ├── 高危工具调用数 > 阈值？               │
│      ├── 敏感路径访问数 > 阈值？               │
│      └── 异常分数 > 0.7？                     │
│      ↓                                        │
│  超阈值 → 桌面通知 + 日志告警                  │
└───────────────────────────────────────────────┘
```

---

## 六、项目文件结构

```
open-shield/
├── core/                              ← Python 检测引擎
│   ├── openshield-detect.py           # FastAPI 单文件服务 + Bearer Token 认证
│   ├── requirements.txt               # Python 依赖
│   ├── test_e2e.py                    # 端到端测试（30 用例）
│   └── rules/
│       ├── pii.yaml                   # 5 条 PII 检测规则（含脱敏策略）
│       ├── injection.yaml             # 5 类提示词注入规则
│       ├── keywords.yaml              # 4 类关键词检测规则（边界匹配）
│       ├── response_guard.yaml        # Stage 6: 响应内容监控规则
│       ├── output_sensitivity.yaml    # Stage 6: 输出敏感信息规则
│       └── custom/
│           └── url_detector.yaml      # 自定义 URL 检测规则示例
├── .opencode/                         # OpenCode 插件生态配置
│   └── skills/
│       └── openshield-safety/
│           └── SKILL.md               # 双重安全指导 + 阻断后处理指引
├── src/
│   └── plugin/
│       └── open_shield.ts             # TypeScript 插件（数据捕获+检测+MITM防御）
├── doc/
│   └── OpenShield_doc.md              # 项目完整文档（本文件）
├── data/
│   └── captures/                      # 捕获数据存储目录
├── report/                            # 项目报告与分析文档
│   ├── Stage_1.md                     # Stage 1 完成报告
│   ├── Stage_2.md                     # Stage 2 设计方案与完成报告
│   ├── Stage_3.md                     # Stage 3 开发计划
│   ├── Stage_4.md                     # Stage 4 安全增强开发计划
│   ├── Stage_5.md                     # Stage 5 误报率优化与权限交互
│   ├── Stage_6.md                     # Stage 6 MITM 纵深防御方案
│   ├── Stage_7.md                     # Stage 7 Web 控制面板设计方案
│   ├── Stage_8.md                     # Stage 8 PEP 668 兼容性与 UI 优化
│   ├── Stage_8_review.md              # Stage 8 方案审查报告
│   ├── Stage_9.md                     # Stage 9 安装/卸载脚本审计报告
│   ├── Stage_9_fix_report.md          # Stage 9 修复报告
│   ├── Stage_10.md                    # Stage 10 自定义敏感字符串+浏览器密码保护方案
│   ├── Stage_10_review.md             # Stage 10 方案审查报告
│   └── analysis/                      # 分析与修复报告
├── Stage_11.md                            # Stage 11 规则编辑/添加/删除功能实现方案
├── install.bat                        # Windows 安装脚本
├── install.sh                         # Linux/macOS 安装脚本
├── uninstall.bat                      # Windows 7 步交互式卸载脚本
├── uninstall.sh                       # Linux/macOS 卸载脚本
├── package.json                       # NPM 包配置
├── LICENSE                            # Apache 2.0
└── PLAN.md                            # 项目总计划文档

~/.openshield/                         ← 运行时数据目录
├── config.json                        # 项目路径 + webhook 配置
├── service.token                      # Stage 5: Bearer Token 认证文件
├── path_policy.json                   # Stage 6: 路径黑白名单配置
├── rules/                             # 规则文件（从 core/rules/ 复制）
├── captures/                          # 会话捕获数据
└── logs/                              # JSONL 结构化日志
```

---

## 七、部署流程

### 7.1 系统要求

| 项目 | 要求 |
|------|------|
| 操作系统 | Windows 10+ / Linux / macOS |
| Python | 3.9+ |
| Node.js | 18.0+（OpenCode 运行环境） |
| OpenCode | 已安装并配置 |

### 7.2 Windows 安装

```cmd
install.bat
```

**安装流程**（5 步）：

| 步骤 | 操作 | 说明 |
|------|------|------|
| [0/5] | 环境检测 | 检查 Python、pip 是否可用 |
| [1/5] | pip install | 安装 fastapi, uvicorn, pydantic, pyyaml（失败时尝试清华镜像） |
| [2/5] | 复制规则 | pii.yaml + keywords.yaml + injection.yaml + custom/*.yaml |
| [3/5] | 复制插件 | open_shield.ts → `~/.config/opencode/plugins/` |
| [4/5] | 复制 Skill | SKILL.md → `~/.config/opencode/skills/openshield-safety/` |
| [5/5] | 创建目录和配置 | 创建 captures/、logs/ 目录，写入 config.json |

### 7.3 Linux/macOS 安装

```bash
chmod +x install.sh
./install.sh
```

### 7.4 验证安装

1. 重启 OpenCode（TUI、Web 或 Desktop）
2. 进行一次对话，触发 LLM 文本回复和工具调用
3. 检查 OpenCode 日志，确认 Hook 触发记录
4. 检查 `~/.openshield/captures/{sessionID}/` 目录下是否存在 JSON 文件

---

## 八、卸载流程

### 8.1 Windows 卸载

```cmd
uninstall.bat
```

**卸载流程**（7 步）：

| 步骤 | 操作 | 交互 |
|------|------|------|
| [1/7] | 删除插件 | 自动删除 `~/.config/opencode/plugins/open_shield.ts` |
| [2/7] | 删除 Skill | 自动删除 `~/.config/opencode/skills/openshield-safety/` |
| [3/7] | 删除配置 | 自动删除 `~/.openshield/config.json` |
| [4/7] | 删除规则 | 询问是否删除 `~/.openshield/rules/`（y/N） |
| [5/7] | 删除日志 | 询问是否删除 `~/.openshield/logs/`（y/N） |
| [6/7] | 删除捕获数据 | 询问是否删除 `~/.openshield/captures/`（y/N） |
| [7/7] | 卸载 pip 依赖 | 询问是否卸载 fastapi uvicorn pydantic pyyaml（y/N），提示共享依赖风险 |

### 8.2 Linux/macOS 卸载

```bash
./uninstall.sh
```

### 8.3 注意事项

- 卸载脚本**不会**清理 pip 依赖（fastapi/uvicorn 为通用依赖）
- 卸载脚本**不会**清理 `~/.openshield/rules/` 目录（规则文件可保留）
- 已捕获的数据默认保留，可在步骤 [3/3] 中选择删除

---

## 九、降级策略

| 场景 | 行为 |
|------|------|
| config.json 不存在 | 日志警告，服务不启动，本地检测可用 |
| Python 未安装 | getPythonCommand() 返回 null，服务不启动 |
| Python 服务 spawn 失败 | startPythonService() 返回 false |
| 服务 10s 内未就绪 | waitForService() 超时，serviceReady 保持 false |
| 服务不可用时高风险操作 | 本地兜底阻断，不盲目放行 |
| 规则文件缺失 | ensureRules() 从项目自动复制 |
| 服务运行中崩溃 | serviceReady = false + 60s 健康检查自动恢复 |
| service.token 缺失 | Python 引擎拒绝请求，本地检测兜底 |
| path_policy.json 缺失 | Phase B 使用内置默认黑名单 |
| Phase A throttle 超时 | 跳过响应检测，不阻塞 LLM 回复显示 |

**核心原则**: Python 引擎是增强层，任何环节失败不阻塞 Agent 核心功能。本地 `detectToolRisk()` + `checkPathPolicy()` 始终可用。

---

## 十、性能指标

| 路径 | 耗时 | 说明 |
|------|------|------|
| 本地命令分级 | < 1ms | `String.includes()` 纯内存操作 |
| Python 引擎检测 | 10–30ms | HTTP localhost 往返 + 正则匹配 |
| 服务启动等待 | 最多 10s | 首次启动，后续免等待 |
| Toast 通知 | 异步 | PowerShell / notify-send 不阻塞 |
| JSONL 日志 | 异步 | 文件追加不阻塞 |
| 规则热加载检查 | ~0.1ms | 3 次 stat() 调用 |

---

## 十一、兼容性

| 平台 | 插件 | Python 服务 | 通知方式 |
|------|------|------------|---------|
| Windows | ✅ | ✅ | PowerShell Toast |
| Linux | ✅ | ✅ | notify-send |
| macOS | ✅ 插件可用 | ✅ | 待适配 |

---

## 十二、Web 控制面板（Stage 7）

### 12.1 概述

Stage 7 实现了 Web 控制面板，让用户可以通过可视化界面调整配置参数，无需手动编辑 YAML/JSON 文件。

**核心特性**：
- 遥控器式工具，非常驻服务
- 单 HTML 文件 + Flask 轻量服务
- 默认深色模式，支持中英文切换
- Bearer Token 安全认证

### 12.2 架构

```
浏览器 http://localhost:9528
    │ fetch API (with Authorization)
    ▼
Flask 配置服务 (dashboard/server.py)
    │ 文件读写
    ▼
~/.openshield/
├── dashboard_config.json  (阈值/TS参数)
├── path_policy.json       (路径策略)
├── config.json            (webhook)
└── rules/                 (规则YAML)
```

### 12.3 启动方式

```bash
# Windows
start_dashboard.bat

# Linux/macOS
chmod +x start_dashboard.sh && ./start_dashboard.sh
```

启动后浏览器自动打开 http://localhost:9528，按 Ctrl+C 停止服务。

### 12.4 功能模块

| 模块 | 功能 |
|------|------|
| **概览** | 服务状态、规则统计、配置摘要 |
| **基础设置** | 检测开关、全局阈值、通知开关 |
| **高级设置** | 分类阈值、TS 插件参数（带 TTL 缓存热更新） |
| **路径策略** | 黑白名单管理、浏览器密码目录保护、学习模式开关 |
| **规则管理** | PII/关键词/注入/输出/响应监控/自定义规则 CRUD（编辑/添加/删除/还原默认）、自定义敏感字符串管理 |
| **通知管理** | Webhook CRUD、测试发送 |
| **日志查看** | 检测日志/通知日志、按日期/级别筛选、清理功能 |

### 12.5 配置生效机制

| 配置类型 | 生效方式 |
|----------|----------|
| 阈值配置 | 保存后自动生效（检测引擎监控 dashboard_config.json） |
| TS 参数 | 保存后自动生效（5 秒 TTL 缓存） |
| 规则文件 | 保存后自动生效（热重载） |
| 路径策略 | 需重启 OpenCode |
| Webhook | 保存后自动生效（检测引擎监控 config.json） |

### 12.6 安全设计

- 默认绑定 `127.0.0.1`，仅本机访问
- Bearer Token 认证（复用 `service.token`）
- 配置文件原子写入（tempfile + os.replace）
- 规则 API 白名单校验（防止路径遍历）

---

## 十三、已知限制

| 限制 | 说明 |
|------|------|
| Skill 检测依赖 LLM 理解能力 | 精度有限，Stage 4 已新增结构化输出格式、分场景检测指南和误报判断指南提升精度 |
| Python 服务需手动安装依赖 | 不在插件中自动 `pip install`（避免权限与延迟问题） |
| Windows Toast 需 PowerShell | 零依赖代价：弹窗需一次轻量进程 |
| PII 检测可能误报 | Stage 4/5 优化：仅高/中风险工具输出送检 + 关键词边界匹配；Stage 10 移除 phone/id_card 正则，改为自定义敏感字符串精确匹配 |
| macOS 通知待适配 | 需要 `osascript` 或 `terminal-notifier` 方案 |
| Phase A 存在 300-500ms 延迟 | 流式触发需 throttle，用户可能先看到原始内容再看到脱敏内容 |
| Phase C 不覆盖所有工具 | `shell` 部分场景不触发 `tool.execute.after`，核心工具（read/write/edit/bash）均覆盖 |
| Phase D 初期误报率较高 | 需基线数据积累，当前仅告警不阻断 |
| `permission.asked` 是只读事件 | 不能用于阻断，所有阻断逻辑必须在 `tool.execute.before` 中实现 |
| 中转站窃听不可防 | 传输层问题，超出客户端插件架构能力范围 |
| 浏览器密码仅路径拦截 | 仅拦截通过 Read/Write/Edit 工具的直接路径访问，不阻止 Bash shell 命令直接读取 |

---

## 十三、相关文档索引

| 文档 | 位置 | 说明 |
|------|------|------|
| Stage 1 完成报告 | `report/Stage_1.md` | 数据捕获插件详细设计与实现 |
| Stage 2 设计方案 | `report/Stage_2.md` | 双重检测机制架构设计 |
| Stage 3 开发计划 | `report/Stage_3.md` | 增强检测与脱敏功能开发 |
| Stage 4 安全增强 | `report/Stage_4.md` | 降低误报率与用户交互优化 |
| Stage 5 权限交互 | `report/Stage_5.md` | bash 白名单分级 + permission.ask 集成 |
| Stage 6 MITM 防御 | `report/Stage_6.md` | 中间人攻击纵深防御方案（Phase A/B/C/D） |
| Stage 7 Web 面板 | `report/Stage_7.md` | Web 控制面板设计方案 |
| Stage 8 兼容性与 UI | `report/Stage_8.md` | PEP 668 兼容性与 UI 优化 |
| Stage 9 脚本审计 | `report/Stage_9.md` | 安装/卸载脚本审计报告 |
| Stage 10 敏感字符串 | `report/Stage_10.md` | 自定义敏感字符串+浏览器密码目录保护方案 |
| Stage 11 规则 CRUD | `Stage_11.md` | 规则编辑/添加/删除功能实现方案 |
| 数据持久化修复 | `report/flushSync_fix.md` | flushSync 函数 bug 修复记录 |
| Hook 签名分析 | `report/analysis/message-updated-hook-analysis.md` | message.updated Hook 机制分析 |
| Stage 2 回归修复 | `report/analysis/stage2-regression-fix-report.md` | 11 个问题修复详情 |
| Stage 3 缺口分析 | `report/analysis/stage3-gap-analysis.md` | 23 项审查结果 |
| 中转站威胁防护 | `report/analysis/relay-threat-defense-plan.md` | 威胁模型防护方案 |
| 项目总计划 | `PLAN.md` | 项目整体规划与进展 |

---

## 十四、总结

OpenShield 通过七个阶段的迭代开发，成功构建了一个完整的 AI Agent 安全中间件：

1. **Stage 1** 建立了数据捕获基础，通过 7 个 Hook 机制实时捕获 LLM 输出和用户输入
2. **Stage 2** 实现了双重检测架构，Skill 指导 LLM 进行消息预处理检测，Plugin 拦截工具调用进行执行模式检测
3. **Stage 3** 增强了检测能力，新增提示词注入检测、PII 脱敏替换、规则热加载和 Webhook 通知
4. **Stage 4** 降低误报率：PII 检测风险预筛、7 步交互式卸载、Skill 结构化输出精度提升、throw Error 用户感知优化
5. **Stage 5** 优化权限交互：bash 白名单命令分级消除高频误报、`permission.ask` 集成用户确认 UI、关键词边界匹配、Service Token 认证
6. **Stage 6** MITM 纵深防御：四层防御模型（响应防火墙 + 文件沙箱 + 输出脱敏 + 会话异常检测），覆盖中转站篡改回复、修改文件路径、数据外泄、长线渗透等攻击场景
7. **Stage 7** Web 控制面板：可视化配置管理，支持阈值调整、规则编辑、路径策略、Webhook 管理、日志查看，深色模式 + 中英文切换
8. **Stage 10** 自定义敏感字符串过滤 + 浏览器密码目录保护：移除高误报正则，改为精确子串匹配；预设 Chrome/Edge/Firefox 密码存储路径跨平台保护
9. **Stage 11** 规则编辑/添加/删除功能实现：Dashboard 规则管理完整 CRUD + 还原默认 + 自定义规则多文件写入 + i18n 全面修复（50 个新翻译 key + 26 处硬编码替换）

项目采用渐进式增强策略，本地规则始终可用，Python 引擎作为增强层按需调用。这种设计确保了即使在 Python 服务不可用的情况下，核心安全防护能力依然有效。

通过规则驱动的检测方式，OpenShield 实现了低延迟（< 1ms 本地 / < 30ms Python）、可解释、易扩展的安全防护能力，为 AI Agent 的安全运行提供了可靠保障。
