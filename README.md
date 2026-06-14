# OpenShield

中文 | [English](README_en.md)

为 AI Agent 设计的安全中间件，专为 [OpenCode](https://opencode.ai/) 平台打造。通过双重检测机制（输入预处理 + 执行拦截），在不影响 Agent 正常工作的前提下提供全方位安全防护。

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

安装脚本自动完成：pip 依赖安装 → 规则文件复制 → 插件注册 → Skill 注册 → 配置初始化。

### 配置

安装脚本会自动创建 `~/.openshield/config.json` 和 `opencode.json`（bash 权限配置）。如需手动配置，请参考[权限配置说明](doc/OpenShield_doc.md#权限配置)。

**关键配置文件：**
- `~/.openshield/config.json` — 主配置
- `~/.openshield/path_policy.json` — 路径黑白名单
- `~/.openshield/service.token` — 服务认证令牌

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

## 核心功能

| 功能 | 说明 | 延迟 |
|------|------|------|
| **PII 检测与脱敏** | 手机号、身份证、邮箱、API Key、IP 地址自动检测并脱敏 | < 30ms |
| **提示词注入检测** | 指令覆盖、角色劫持、分隔符攻击、信息提取、编码绕过 | < 30ms |
| **危险命令拦截** | bash 命令白名单分级，高危操作触发用户确认 | < 1ms |
| **文件操作沙箱** | 路径黑白名单，阻止对系统关键文件的篡改/读取 | < 1ms |
| **工具输出脱敏** | SSH 密钥、数据库连接串、JWT Token 等敏感信息实时脱敏 | < 30ms |
| **响应内容监控** | 检测 LLM 回复中的钓鱼链接、社会工程攻击 | < 500ms |
| **会话异常检测** | 高危工具频率、敏感路径访问等行为模式分析 | 异步 |
| **规则热加载** | YAML 规则文件修改后自动生效，无需重启 | ~0.1ms |
| **多渠道通知** | Windows Toast / Linux notify-send / Webhook（Slack/钉钉/飞书） | 异步 |

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
┌────────────────────────────────────────────┐
│  Skill (消息预处理层)                       │
│  LLM 自检 PII / 危险关键词 / 恶意指令       │
└─────────────────┬──────────────────────────┘
                  ↓
┌────────────────────────────────────────────┐
│  Plugin (执行检测层 + MITM 防御)            │
│                                            │
│  tool.execute.before → 命令分级 + 路径沙箱  │
│  tool.execute.after  → 输出脱敏            │
│  permission.ask      → Python 引擎判定     │
│  message.updated     → 响应内容监控         │
│  session.idle        → 会话异常检测         │
└─────────────────┬──────────────────────────┘
                  ↓
┌────────────────────────────────────────────┐
│  Python 检测引擎 (localhost:9527)           │
│  FastAPI + Bearer Token 认证               │
│  PII/注入/关键词/输出敏感信息 检测           │
│  桌面通知 + Webhook + JSONL 日志            │
└────────────────────────────────────────────┘
```

**设计原则**：Python 引擎是增强层，本地规则（< 1ms）始终可用。即使 Python 服务不可用，核心防护能力不降级。

---

## 文档

完整技术文档：[OpenShield_doc.md](doc/OpenShield_doc.md)

---

## License

[Apache 2.0](LICENSE)
