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

中文 | [English](README_en.md)

为 AI Agent 设计的安全中间件，专为 [OpenCode](https://opencode.ai/) 平台打造。通过双重检测机制（输入预处理 + 执行拦截），在不影响 Agent 正常工作的前提下提供安全防护。

---

## 部署

### 系统要求

- Python 3.9+
- Node.js 18+（OpenCode 运行环境）
- OpenCode 已安装并配置

### 安装

**Windows:**

```cmd
install.bat
```

**Linux / macOS:**

```bash
chmod +x install.sh && ./install.sh
```

安装脚本自动完成：pip 依赖安装 → 规则文件复制 → 插件注册 → Skill 注册 → 配置初始化 → Dashboard 配置。

### 配置

安装脚本会自动创建 `~/.openshield/config.json` 和 `opencode.json`（bash 权限配置）。如需手动配置，请参考[权限交互说明](doc/OpenShield_doc.md#35-stage-5--降低误报率与权限交互)。

**关键配置文件：**
- `~/.openshield/config.json` — 主配置
- `~/.openshield/dashboard_config.json` — Dashboard 配置（阈值/TS参数）
- `~/.openshield/path_policy.json` — 路径黑白名单
- `~/.openshield/service.token` — 服务认证令牌

### Web 控制面板

Dashboard 提供可视化配置管理，支持深色模式和中英文切换。

**启动：**

```cmd
start_dashboard.bat        # Windows
./start_dashboard.sh       # Linux / macOS
```

浏览器自动打开 http://localhost:9528，按 Ctrl+C 停止服务。

**功能：**
- 概览：服务状态、规则统计
- 基础设置：检测开关、全局阈值
- 高级设置：分类阈值、TS 插件参数
- 路径策略：黑白名单管理、浏览器密码目录保护
- 规则管理：PII/关键词/注入/输出规则编辑、自定义敏感字符串管理
- 通知管理：Webhook CRUD
- 日志查看：检测日志/通知日志

### 验证

重启 OpenCode，执行任意对话。检查 `~/.openshield/logs/` 目录下是否生成 JSONL 日志。

**故障排除：**
- Python 服务无法启动：运行 `cd core && python openshield-detect.py` 查看错误
- 权限配置不生效：确认 `opencode.json` 位置正确，重启 OpenCode

### 卸载

```cmd
uninstall.bat        # Windows
./uninstall.sh       # Linux / macOS
```

---

<p align="center">
  <img src="https://skillicons.dev/icons?i=python,fastapi,flask,nodejs,pycharm" alt="Tech Stack">
</p>

## 核心功能

| 功能 | 说明 | 延迟 |
|------|------|------|
| **PII 检测与脱敏** | 邮箱、API Key、IP 地址等正则检测；自定义敏感字符串精确替换 | < 30ms |
| **自定义敏感字符串** | 用户指定需保护的内容（号码、地址等），精确匹配并按长度降序脱敏 | < 30ms |
| **提示词注入检测** | 指令覆盖、角色劫持、分隔符攻击、信息提取、编码绕过 | < 30ms |
| **危险命令拦截** | bash 命令白名单分级，高危操作触发用户确认 | < 1ms |
| **文件操作沙箱** | 路径黑白名单，阻止对系统关键文件的篡改/读取 | < 1ms |
| **浏览器密码目录保护** | 预设 Chrome/Edge/Firefox 密码存储路径，跨平台阻断或放行 | < 1ms |
| **工具输出脱敏** | SSH 密钥、数据库连接串、JWT Token 等敏感信息实时脱敏 | < 30ms |
| **响应内容监控** | 检测 LLM 回复中的钓鱼链接、社会工程攻击 | < 500ms |
| **会话异常检测** | 高危工具频率、敏感路径访问等行为模式分析 | 异步 |
| **规则热加载** | YAML 规则文件修改后自动生效，无需重启 | ~0.1ms |
| **多渠道通知** | Windows Toast / Linux notify-send / Webhook（Slack/钉钉/飞书） | 异步 |
| **Web 控制面板** | 可视化配置管理，深色模式，中英文切换 | — |

**判定动作**：

```
ALLOW  → 放行        （低/中风险）
MANUAL → 用户确认    （高风险，显示确认对话框）
BLOCK  → 直接阻断    （严重风险，桌面通知 + 日志）
```

---

## 架构

```
用户输入
  ↓
┌─────────────────────────────────────────────┐
│  Skill (消息预处理检测层)
│  纯 Markdown 指导 LLM 自我检测 PII /
│  危险关键词 / 恶意指令 → 告知用户风险
└──────────────────┬──────────────────────────┘
                   ↓
┌─────────────────────────────────────────────┐
│  Plugin (执行模式检测层)
│  TypeScript 插件，拦截工具调用
│  tool.execute.before → 本地分级 + 路径沙箱
│  tool.execute.after  → 输出脱敏 + PII 检测
│  permission.ask      → Python 引擎精确判定
│  message.updated     → 响应内容防火墙
│  session.idle        → 会话异常检测
└──────────────────┬──────────────────────────┘
                   ↓
┌─────────────────────────────────────────────┐
│  MITM 纵深防御层 (Stage 6)
│  Phase A: 响应内容监控（社会工程/钓鱼检测）
│  Phase B: 文件操作沙箱（路径黑白名单）
│  Phase C: 工具输出脱敏（敏感信息实时脱敏）
│  Phase D: 会话异常检测（行为模式分析）
└──────────────────┬──────────────────────────┘
                   ↓
┌─────────────────────────────────────────────┐
│  Python 检测引擎 (localhost:9527)
│  FastAPI 单文件服务 + Bearer Token 认证
│  PII 检测/脱敏 + 注入检测 + 关键词匹配
│  输出敏感信息检测 + 响应内容扫描
│  桌面通知 + Webhook + JSONL 日志
│  规则热加载（YAML mtime 监控）
└─────────────────────────────────────────────┘
```

**设计原则**：Python 引擎是增强层，本地规则（< 1ms）始终可用。即使 Python 服务不可用，核心防护能力不降级。

---

## 文档

- 完整技术文档：[OpenShield_doc.md](doc/OpenShield_doc.md)

---

## License

[Apache 2.0](LICENSE)
