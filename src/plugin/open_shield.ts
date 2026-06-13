import { mkdirSync, writeFile, existsSync, readFileSync, copyFileSync } from "node:fs"
import { join } from "node:path"
import { homedir } from "node:os"
import { spawn, execSync } from "node:child_process"

// ==================== 类型定义 ====================

interface CapturedText {
  messageID: string
  role: "user" | "assistant"
  content: string
  timestamp: string
}

interface CapturedToolCall {
  tool: string
  callID: string
  args: Record<string, unknown>
  output: unknown
  timestamp: string
}

interface CaptureSession {
  sessionID: string
  capturedAt: string
  texts: CapturedText[]
  toolCalls: CapturedToolCall[]
}

// ==================== 配置 ====================

const OPENSHIELD_DIR = join(homedir(), ".openshield")
const DATA_DIR = join(OPENSHIELD_DIR, "captures")
const CONFIG_PATH = join(OPENSHIELD_DIR, "config.json")
const PYTHON_SERVICE_URL = "http://localhost:9527"
const AUTO_START_SERVICE = true

// ==================== 风险检测 ====================

const HIGH_RISK_PATTERNS = [
  "rm -rf", "rm -r", "format", "reboot", "shutdown",
  "dd if=", "mkfs", "drop table", "drop database", "truncate table",
]

const MEDIUM_RISK_TOOLS = [
  "curl", "wget", "chmod", "chown",
  "write", "edit", "overwrite",
  "delete", "remove", "unlink",
]

const HIGH_RISK_TOOLS = [
  "database", "query", "execute",
]

const SAFE_COMMAND_PREFIXES = [
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
  "code", "vim", "nano",
]

function detectToolRisk(tool: string, args: Record<string, unknown>): "low" | "medium" | "high" {
  const toolName = (tool || "").toLowerCase()

  if (toolName === "bash" || toolName === "shell" || toolName === "exec") {
    const command = String(args.command || args.script || args.cmd || "").toLowerCase().trim()
    if (!command) return "low"

    for (const pattern of HIGH_RISK_PATTERNS) {
      if (command.includes(pattern)) return "high"
    }

    const firstToken = command.split(/\s+/)[0]
    if (SAFE_COMMAND_PREFIXES.includes(firstToken)) return "low"

    return "medium"
  }

  const argsStr = JSON.stringify(args).toLowerCase()
  const command = `${toolName} ${argsStr}`

  for (const pattern of HIGH_RISK_PATTERNS) {
    if (command.includes(pattern)) return "high"
  }

  if (HIGH_RISK_TOOLS.includes(toolName)) return "high"
  if (MEDIUM_RISK_TOOLS.includes(toolName)) return "medium"

  return "low"
}

// ==================== 缓冲区管理 ====================

const buffers = new Map<string, { texts: CapturedText[]; toolCalls: CapturedToolCall[] }>()

function getBuffer(sessionID: string) {
  if (!buffers.has(sessionID)) {
    buffers.set(sessionID, { texts: [], toolCalls: [] })
  }
  return buffers.get(sessionID)!
}

function getTimestamp(): string {
  return new Date().toISOString()
}

function getFileName(): string {
  const now = new Date()
  const pad = (n: number) => String(n).padStart(2, "0")
  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}T${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}.json`
}

function ensureDirSync(dir: string) {
  if (!existsSync(dir)) {
    mkdirSync(dir, { recursive: true })
  }
}

function flushSync(sessionID: string): void {
  const buffer = getBuffer(sessionID)
  if (buffer.texts.length === 0 && buffer.toolCalls.length === 0) {
    buffers.delete(sessionID)
    return
  }

  const sessionDir = join(DATA_DIR, sessionID)
  ensureDirSync(sessionDir)

  const session: CaptureSession = {
    sessionID,
    capturedAt: getTimestamp(),
    texts: [...buffer.texts],
    toolCalls: [...buffer.toolCalls],
  }

  buffer.texts.length = 0
  buffer.toolCalls.length = 0
  buffers.delete(sessionID)

  const filePath = join(sessionDir, getFileName())
  writeFile(filePath, JSON.stringify(session, null, 2), "utf-8", (err) => {
    if (err) {
      const buffer = getBuffer(sessionID)
      buffer.texts.push(...session.texts)
      buffer.toolCalls.push(...session.toolCalls)
      console.error("[OpenShield] Failed to write capture file:", err)
    }
  })
}

// ==================== 工具函数 ====================

function pickSessionID(obj: any): string {
  return obj?.sessionID ?? obj?.sessionId ?? obj?.session_id ?? ""
}

function pickMessageID(obj: any): string {
  return obj?.messageID ?? obj?.messageId ?? obj?.id ?? ""
}

function extractMessageContent(info: any): string {
  if (typeof info.content === "string") return info.content
  if (typeof info.text === "string") return info.text
  if (Array.isArray(info.parts)) {
    return info.parts
      .filter((p: any) => p.type === "text" && typeof p.text === "string")
      .map((p: any) => p.text)
      .join("")
  }
  return ""
}

// ==================== Python检测服务 ====================

let serviceReady = false

function getPythonServicePath(): string | null {
  try {
    if (!existsSync(CONFIG_PATH)) return null
    const config = JSON.parse(readFileSync(CONFIG_PATH, "utf-8"))
    const pyPath = join(config.project_dir, "core", "openshield-detect.py")
    return existsSync(pyPath) ? pyPath : null
  } catch {
    return null
  }
}

function ensureRules(projectDir: string): void {
  const rulesDir = join(OPENSHIELD_DIR, "rules")
  const customDir = join(rulesDir, "custom")
  ensureDirSync(customDir)

  const srcDir = join(projectDir, "core", "rules")
  for (const file of ["pii.yaml", "keywords.yaml", "injection.yaml"]) {
    const dest = join(rulesDir, file)
    const src = join(srcDir, file)
    if (!existsSync(dest) && existsSync(src)) {
      copyFileSync(src, dest)
    }
  }
}

function getPythonCommand(): string | null {
  for (const cmd of ["python", "python3"]) {
    try {
      execSync(`"${cmd}" --version`, { stdio: "ignore" })
      return cmd
    } catch {
      // try next
    }
  }
  return null
}

async function waitForService(ms: number = 500, retries: number = 20): Promise<boolean> {
  for (let i = 0; i < retries; i++) {
    try {
      const resp = await fetch(`${PYTHON_SERVICE_URL}/api/v1/health`, { signal: AbortSignal.timeout(1000) })
      if (resp.ok) return true
    } catch {
      // not ready yet
    }
    await new Promise((r) => setTimeout(r, ms))
  }
  return false
}

function startPythonService(projectDir: string): boolean {
  try {
    const pyPath = getPythonServicePath()
    if (!pyPath) return false

    ensureRules(projectDir)

    const python = getPythonCommand()
    if (!python) return false

    spawn(python, [pyPath], { stdio: "ignore" })
    return true
  } catch {
    return false
  }
}

async function sendToDetectService(sessionID: string, data: any): Promise<any> {
  if (!(await checkServiceHealth())) return null

  try {
    const response = await fetch(`${PYTHON_SERVICE_URL}/api/v1/detect/execute`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        session_id: sessionID,
        tool_name: data.tool,
        tool_args: data.args,
        timestamp: new Date().toISOString(),
      }),
      signal: AbortSignal.timeout(5000),
    })

    if (!response.ok) {
      serviceReady = false
      return null
    }

    return await response.json()
  } catch (err) {
    serviceReady = false
    return null
  }
}

// ==================== 服务健康检查 ====================

const HEALTH_CHECK_INTERVAL = 60000
let lastHealthCheck = 0

async function checkServiceHealth(): Promise<boolean> {
  const now = Date.now()
  if (now - lastHealthCheck < HEALTH_CHECK_INTERVAL) {
    return serviceReady
  }
  lastHealthCheck = now

  try {
    const resp = await fetch(`${PYTHON_SERVICE_URL}/api/v1/health`, {
      signal: AbortSignal.timeout(3000),
    })
    const wasReady = serviceReady
    serviceReady = resp.ok
    if (wasReady && !serviceReady) {
      console.error("[OpenShield] Python service became unavailable")
    }
    return serviceReady
  } catch {
    if (serviceReady) {
      console.error("[OpenShield] Python service health check failed")
    }
    serviceReady = false
    return false
  }
}

async function sendToCaptureService(
  sessionID: string,
  content: string,
  contentType: string
// 注：Python 端响应中还包含 reason 字段（预留），当前未消费
): Promise<{ status: string; action: string; alerts: any[]; sanitized_content?: string } | null> {
  if (!(await checkServiceHealth())) return null

  try {
    const response = await fetch(`${PYTHON_SERVICE_URL}/api/v1/capture`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        session_id: sessionID,
        content,
        content_type: contentType,
        timestamp: new Date().toISOString(),
      }),
      signal: AbortSignal.timeout(5000),
    })

    if (!response.ok) {
      serviceReady = false
      return null
    }

    return await response.json()
  } catch {
    serviceReady = false
    return null
  }
}

// ==================== 主插件 ====================

export const OpenShield = async ({ project }: { project: any }) => {
  ensureDirSync(DATA_DIR)

  // 运行时验证标志位（方案 D）
  let permissionAskTriggered = false
  let firstBashChecked = false

  const log = async (level: string, message: string, extra?: any) => {
    try {
      await project.client.app.log({
        body: {
          service: "openshield",
          level,
          message,
          ...(extra ? { extra } : {}),
        },
      })
    } catch {
      // Log failures are non-critical
    }
  }

  await log("info", `Plugin loaded. Data directory: ${DATA_DIR}`)

  // 自动启动 Python 检测服务
  if (AUTO_START_SERVICE) {
    const projectDir = (() => {
      try {
        if (!existsSync(CONFIG_PATH)) return null
        return JSON.parse(readFileSync(CONFIG_PATH, "utf-8")).project_dir
      } catch {
        return null
      }
    })()

    if (projectDir && startPythonService(projectDir)) {
      await log("info", "Python detection service spawning...")
      const ready = await waitForService()
      if (ready) {
        serviceReady = true
        await log("info", "Python detection service ready")
      } else {
        await log("warn", "Detection service not responding, using local rules only")
      }
    } else {
      await log("warn", "Detection service not found, run install script first")
    }
  }

  return {
    // ==================== event — 事件钩子 ====================

    event: async ({ event }: { event: any }) => {
      // message.updated — 捕获 LLM 文本回复
      // 修复：从命名hook改为通过 event hook 投递，使用 info.role 区分消息来源
      if (event.type === "message.updated") {
        const info = event.properties?.info
        if (!info) return

        const sessionID = info.sessionID || ""
        const role: "user" | "assistant" = info.role || "assistant"
        const content = extractMessageContent(info)
        if (!content) return

        const buffer = getBuffer(sessionID)
        buffer.texts.push({
          messageID: info.id || "",
          role,
          content,
          timestamp: getTimestamp(),
        })
        await log("debug", "message.updated captured", { sessionID, role, len: content.length })
        return
      }

      // session.idle — 会话空闲时持久化数据
      if (event.type === "session.idle") {
        const sessionID = pickSessionID(event.properties || event)
        if (sessionID) {
          const buffer = buffers.get(sessionID)
          const textCount = buffer?.texts.length ?? 0
          const toolCount = buffer?.toolCalls.length ?? 0
          await log("info", "session.idle", { sessionID, textCount, toolCount })
          flushSync(sessionID)
        }
        return
      }

      // session 生命周期事件
      if (event.type === "session.created" || event.type === "session.deleted") {
        await log("info", `session event: ${event.type}`, {
          sessionID: pickSessionID(event.properties || event),
        })
        return
      }
    },

    // ==================== chat.message — 用户输入捕获 ====================

    "chat.message": async (input: any, output: any) => {
      const sessionID = pickSessionID(input)
      if (!sessionID) return

      const content = output?.content || ""
      if (!content) return

      const buffer = getBuffer(sessionID)
      buffer.texts.push({
        messageID: pickMessageID(input),
        role: "user",
        content,
        timestamp: getTimestamp(),
      })
      await log("debug", "chat.message captured", { sessionID, len: content.length })
    },

    // ==================== tool.execute.before — 执行前日志记录 ====================

    "tool.execute.before": async (input: any, output: any) => {
      const { tool, sessionID } = input
      const toolName = (tool || "").toLowerCase()
      const args = output?.args || {}
      const riskLevel = detectToolRisk(tool, args)

      // 运行时验证：首次 bash 调用后检查 permission.ask 是否触发
      if (!firstBashChecked && (toolName === "bash" || toolName === "shell")) {
        firstBashChecked = true
        if (!permissionAskTriggered) {
          await log("warn", [
            "[OpenShield] 确认：permission.ask hook 未被触发，bash 权限可能为 'allow'。",
            "安全检测流程未激活，请配置 permission.bash 为 'ask'"
          ].join(" "))
        } else {
          await log("info", "[OpenShield] 权限配置正确，permission.ask hook 已生效")
        }
      }

      if (riskLevel === "high" || riskLevel === "medium") {
        await log("info", `tool.execute.before ${riskLevel} risk detected`, {
          sessionID, tool,
        })
      }
    },

    // ==================== permission.ask — 权限请求处理 ====================

    "permission.ask": async (input: any, output: any) => {
      permissionAskTriggered = true

      const toolName = (input.type || input.tool || "").toLowerCase()
      const sessionID = pickSessionID(input)
      const args = input.args || input.arguments || {}

      const riskLevel = detectToolRisk(toolName, args)
      if (riskLevel === "low") return

      const result = await sendToDetectService(sessionID, {
        tool: toolName, args,
      })

      if (result?.action === "block") {
        output.status = "deny"
        await log("warn", "permission.ask blocked", {
          tool: toolName, reason: result.reason,
        })
        return
      }

      if (result?.action === "manual") {
        output.status = "ask"
        await log("warn", "permission.ask requiring user confirmation", {
          tool: toolName, reason: result.reason,
        })
        return
      }

      if (!result) {
        if (riskLevel === "high") {
          const argsStr = JSON.stringify(args).toLowerCase()
          const hasCriticalPattern = HIGH_RISK_PATTERNS.some(p => argsStr.includes(p))
          if (hasCriticalPattern) {
            output.status = "deny"
            await log("warn", "permission.ask fallback block (service unavailable)", { tool: toolName })
          } else {
            output.status = "ask"
            await log("warn", "permission.ask fallback ask (service unavailable)", { tool: toolName })
          }
        }
      }
    },

    // ==================== tool.execute.after — 工具执行后捕获 ====================

    "tool.execute.after": async (input: any, output: any) => {
      const sessionID = pickSessionID(input)
      if (!sessionID) return

      const buffer = getBuffer(sessionID)
      const toolOutput = output?.output ?? output?.result ?? output ?? null

      let contentToStore = toolOutput
      if (toolOutput && typeof toolOutput === "string") {
        const riskLevel = detectToolRisk(input.tool, input.args || {})
        if (riskLevel === "high" || riskLevel === "medium") {
          const result = await sendToCaptureService(sessionID, toolOutput, "tool_output")
          if (result?.sanitized_content) {
            contentToStore = result.sanitized_content
          }
          if (result?.action === "block" || result?.action === "manual") {
            await log("warn", "tool output risk detected", {
              sessionID, tool: input.tool, action: result.action,
              alertCount: result.alerts?.length,
            })
          }
        }
      }

      buffer.toolCalls.push({
        tool: input.tool || "unknown",
        callID: input.callID || input.callId || input.id || "",
        args: input.args || input.arguments || {},
        output: contentToStore,
        timestamp: getTimestamp(),
      })
      await log("debug", "tool.execute.after captured", {
        sessionID,
        tool: input.tool,
      })
    },
  }
}

export default OpenShield
