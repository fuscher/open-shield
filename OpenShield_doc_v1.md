# openShield 项目完整文档

> **文档版本**: v1.0  
> **最后更新**: 2026-06-11  
> **项目状态**: Stage 1-4 已完成

---

## 一、项目概述

### 1.1 项目定位

**openShield** 是一个**为 AI Agent 设计的安全中间件**，专门针对 [OpenCode](https://opencode.ai/) 平台。它通过双重检测机制，在用户输入阶段和工具执行阶段分别拦截安全风险，为 AI Agent 提供全方位的安全防护。

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

### 2.1 整体架构（三层）

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
│  tool.execute.before → 本地分级 < 1ms        │
│  tool.execute.after  → 输出送检 + PII 脱敏   │
│  permission.ask      → Python 引擎精确判定    │
└──────────────────┬──────────────────────────┘
                   ↓
┌─────────────────────────────────────────────┐
│  Python 检测引擎 (localhost:9527)             │
│  FastAPI 单文件服务（607 行）                  │
│  PII 检测/脱敏 + 注入检测 + 关键词匹配        │
│  桌面通知 + Webhook + JSONL 日志              │
│  规则热加载（YAML mtime 监控）                │
└─────────────────────────────────────────────┘
```

### 2.2 组件分工

| 组件 | 位置 | 职责 | 延迟 |
|------|------|------|------|
| **Skill** | `.opencode/skills/openshield-safety/SKILL.md` | LLM 消息预处理检测 PII/关键词/恶意指令 | — |
| **Plugin** | `src/plugin/open_shield.ts` (529 行) | 数据捕获 + 执行前分级 + 权限控制 + 服务自启动 + 脱敏存储 | < 1ms |
| **Python 引擎** | `core/openshield-detect.py` (607 行) | PII 检测/脱敏 + 注入检测 + 关键词匹配 + 通知 + 日志 + 规则热加载 | < 30ms |

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
| `event` (message.updated) | 事件 | 消息更新 | 捕获 LLM 回复 |
| `tool.execute.before` | 命名 hook | 工具执行前 | 本地风险分级 |
| `tool.execute.after` | 命名 hook | 工具执行后 | 捕获执行结果 + 送检 |
| `permission.ask` | 命名 hook | 权限检查 | 调用 Python 引擎精确判定 |
| `event` (session.idle) | 事件 | 会话空闲 | 持久化捕获数据 |
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

---

## 四、功能模块详解

### 4.1 检测能力矩阵

#### PII 检测规则 (pii.yaml)

| 规则 | 正则模式 | 等级 | 脱敏结果示例 |
|------|---------|------|-------------|
| 手机号码 | `1[3-9]\d{9}` | high | `13800138000` → `138***8000` |
| 身份证号码 | `[1-9]\d{5}(18\|19\|20)\d{2}...` | critical | `110101199001011234` → `110***1234` |
| 邮箱地址 | `[a-zA-Z0-9._%+-]+@...` | medium | `test@example.com` → `te***@example.com` |
| API 密钥 | `(sk-\|ak-\|key-)[a-zA-Z0-9]{20,}` | critical | `sk-abc123...` → `sk-***ghi` |
| IP 地址 | `\b([0-9]{1,3}\.){3}[0-9]{1,3}\b` | low | `192.168.1.1` → `192.168***1` |

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

| 端点 | 方法 | 说明 |
|------|------|------|
| `/api/v1/capture` | POST | 通用内容检测（text/tool_output），返回 `sanitized_content` 脱敏字段 |
| `/api/v1/detect/execute` | POST | 工具调用前精确检测（含注入检测） |
| `/api/v1/health` | GET | 健康检查 |
| `/api/v1/rules` | GET | 当前规则查询（含 custom_rules） |

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

---

## 六、项目文件结构

```
open-shield/
├── core/                              ← Python 检测引擎
│   ├── openshield-detect.py           # FastAPI 单文件服务（607 行）
│   ├── requirements.txt               # Python 依赖
│   ├── test_e2e.py                    # 端到端测试（24 用例）
│   └── rules/
│       ├── pii.yaml                   # 5 条 PII 检测规则
│       ├── injection.yaml             # 5 类提示词注入规则
│       ├── keywords.yaml              # 4 类关键词检测规则
│       └── custom/
│           └── url_detector.yaml      # 自定义 URL 检测规则示例
├── .opencode/                         # OpenCode 插件生态配置
│   └── skills/
│       └── openshield-safety/
│           └── SKILL.md               # 双重安全指导 + 阻断后处理指引
├── src/
│   └── plugin/
│       └── open_shield.ts             # TypeScript 插件（529 行）
├── data/
│   └── captures/                      # 捕获数据存储目录
├── report/                            # 项目报告与分析文档
│   ├── Stage_1.md                     # Stage 1 完成报告
│   ├── Stage_2.md                     # Stage 2 设计方案与完成报告
│   ├── Stage_3.md                     # Stage 3 开发计划
│   ├── Stage_4.md                     # Stage 4 安全增强开发计划
│   └── analysis/                      # 分析与修复报告
├── install.bat                        # Windows 安装脚本
├── install.sh                         # Linux/macOS 安装脚本
├── uninstall.bat                      # Windows 卸载脚本
├── uninstall.sh                       # Linux/macOS 卸载脚本
├── package.json                       # NPM 包配置（v0.1.0）
├── LICENSE                            # Apache 2.0
└── PLAN.md                            # 项目总计划文档
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

**核心原则**: Python 引擎是增强层，任何环节失败不阻塞 Agent 核心功能。本地 `detectToolRisk()` 始终可用。

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

## 十二、已知限制

| 限制 | 说明 |
|------|------|
| Skill 检测依赖 LLM 理解能力 | 精度有限，Stage 4 已新增结构化输出格式、分场景检测指南和误报判断指南提升精度 |
| Python 服务需手动安装依赖 | 不在插件中自动 `pip install`（避免权限与延迟问题） |
| Windows Toast 需 PowerShell | 零依赖代价：弹窗需一次轻量进程 |
| PII 检测可能误报 | Stage 4 已将 `tool.execute.after` 改为仅对高/中风险工具输出送检，低风险工具（read/grep/glob 等）跳过 PII 检测 |
| macOS 通知待适配 | 需要 `osascript` 或 `terminal-notifier` 方案 |

---

## 十三、相关文档索引

| 文档 | 位置 | 说明 |
|------|------|------|
| Stage 1 完成报告 | `report/Stage_1.md` | 数据捕获插件详细设计与实现 |
| Stage 2 设计方案 | `report/Stage_2.md` | 双重检测机制架构设计 |
| Stage 3 开发计划 | `report/Stage_3.md` | 增强检测与脱敏功能开发 |
| 数据持久化修复 | `report/flushSync_fix.md` | flushSync 函数 bug 修复记录 |
| Hook 签名分析 | `report/analysis/message-updated-hook-analysis.md` | message.updated Hook 机制分析 |
| Stage 2 回归修复 | `report/analysis/stage2-regression-fix-report.md` | 11 个问题修复详情 |
| Stage 3 缺口分析 | `report/analysis/stage3-gap-analysis.md` | 23 项审查结果 |
| 中转站威胁防护 | `report/analysis/relay-threat-defense-plan.md` | 威胁模型防护方案 |
| 项目总计划 | `PLAN.md` | 项目整体规划与进展 |

---

## 十四、总结

openShield 通过四个阶段的迭代开发，成功构建了一个完整的 AI Agent 安全中间件：

1. **Stage 1** 建立了数据捕获基础，通过 7 个 Hook 机制实时捕获 LLM 输出和用户输入
2. **Stage 2** 实现了双重检测架构，Skill 指导 LLM 进行消息预处理检测，Plugin 拦截工具调用进行执行模式检测
3. **Stage 3** 增强了检测能力，新增提示词注入检测、PII 脱敏替换、规则热加载和 Webhook 通知
4. **Stage 4** 修复了 5 个关键问题：PII 检测误报（after hook 风险预筛）、卸载脚本粒度不足（7 步交互式卸载）、Skill 检测精度（结构化输出+分场景+误报指南）、阻断后用户不知情（throw Error 替代静默 deny）、Skill 命名规范（小写化），并通过 Phase 0 运行时验证确认了 throw Error 阻断机制的可靠性

项目采用渐进式增强策略，本地规则始终可用，Python 引擎作为增强层按需调用。这种设计确保了即使在 Python 服务不可用的情况下，核心安全防护能力依然有效。

通过规则驱动的检测方式，openShield 实现了低延迟（< 1ms 本地 / < 30ms Python）、可解释、易扩展的安全防护能力，为 AI Agent 的安全运行提供了可靠保障。
