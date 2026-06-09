import { mkdirSync, writeFile, existsSync, readFileSync } from "node:fs"
import { join } from "node:path"
import { homedir } from "node:os"
import { spawn } from "node:child_process"

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

const MEDIUM_RISK_TOOLS = ["curl", "wget", "chmod", "chown"]

function detectToolRisk(tool: string, args: Record<string, unknown>): "low" | "medium" | "high" {
  const toolName = (tool || "").toLowerCase()
  const argsStr = JSON.stringify(args).toLowerCase()
  const command = `${toolName} ${argsStr}`

  for (const pattern of HIGH_RISK_PATTERNS) {
    if (command.includes(pattern)) return "high"
  }

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
      console.error("[openShield] Failed to write capture file:", err)
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

function startPythonService(): boolean {
  const pyPath = getPythonServicePath()
  if (!pyPath) return false

  try {
    spawn("python", [pyPath], { stdio: "ignore", detached: true })
    return true
  } catch {
    return false
  }
}

async function sendToDetectService(sessionID: string, data: any): Promise<any> {
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
    })
    return await response.json()
  } catch (err) {
    return null
  }
}

// ==================== 主插件 ====================

export const OpenShield = async ({ project }: { project: any }) => {
  ensureDirSync(DATA_DIR)

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
    if (startPythonService()) {
      await log("info", "Python detection service auto-started")
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

    // ==================== tool.execute.before — 执行前风险检测 ====================

    "tool.execute.before": async (input: any, output: any) => {
      const { tool, sessionID } = input
      const args = output?.args || {}
      const riskLevel = detectToolRisk(tool, args)

      if (riskLevel === "high" || riskLevel === "medium") {
        await log("warn", "tool.execute.before risk detected", {
          sessionID,
          tool,
          riskLevel,
        })
      }
    },

    // ==================== permission.ask — 权限请求处理 ====================

    "permission.ask": async (input: any, output: any) => {
      const toolName = (input.tool || "").toLowerCase()

      if (toolName === "bash" || toolName === "shell") {
        const sessionID = pickSessionID(input)
        const result = await sendToDetectService(sessionID, {
          tool: toolName,
          args: input.args || {},
        })
        if (result?.action === "block") {
          output.status = "deny"
          await log("warn", "permission.ask blocked by Python service", {
            tool: toolName,
          })
        }
      }
    },

    // ==================== tool.execute.after — 工具执行后捕获 ====================

    "tool.execute.after": async (input: any, output: any) => {
      const sessionID = pickSessionID(input)
      if (!sessionID) return

      const buffer = getBuffer(sessionID)
      buffer.toolCalls.push({
        tool: input.tool || "unknown",
        callID: input.callID || input.callId || input.id || "",
        args: input.args || input.arguments || {},
        output: output?.output ?? output?.result ?? output ?? null,
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
