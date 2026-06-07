import { mkdirSync, writeFile, existsSync } from "node:fs"
import { join } from "node:path"
import { homedir } from "node:os"

interface CapturedText {
  messageID: string
  partID: string
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

const DATA_DIR = join(homedir(), ".openshield", "captures")
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

function extractTextFromOutput(output: any): string {
  if (!output) return ""
  if (typeof output.text === "string") return output.text
  if (typeof output.content === "string") return output.content
  if (Array.isArray(output.parts)) {
    return output.parts
      .filter((p: any) => p.type === "text" && typeof p.text === "string")
      .map((p: any) => p.text)
      .join("")
  }
  return ""
}

function pickSessionID(obj: any): string {
  return obj?.sessionID ?? obj?.sessionId ?? obj?.session_id ?? ""
}

export const OpenShieldCapture = async ({ project }: { project: any }) => {
  ensureDirSync(DATA_DIR)

  const log = async (level: string, message: string, extra?: any) => {
    try {
      await project.client.app.log({
        body: {
          service: "openshield-capture",
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

  return {
    "message.updated": async (input: any, output: any) => {
      const sessionID = pickSessionID(input) || pickSessionID(output)
      if (!sessionID) return

      const text = extractTextFromOutput(output)
      if (!text) return

      const buffer = getBuffer(sessionID)
      buffer.texts.push({
        messageID: input.messageID || input.id || input.messageId || "",
        partID: input.partID || input.partId || "",
        content: text,
        timestamp: getTimestamp(),
      })
      await log("debug", "message.updated captured", { sessionID, len: text.length })
    },

    "experimental.text.complete": async (input: any, output: any) => {
      const sessionID = pickSessionID(input)
      if (!sessionID || typeof output?.text !== "string") return

      const buffer = getBuffer(sessionID)
      buffer.texts.push({
        messageID: input.messageID || input.id || "",
        partID: input.partID || input.partId || "",
        content: output.text,
        timestamp: getTimestamp(),
      })
      await log("debug", "experimental.text.complete captured", { sessionID, len: output.text.length })
    },

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
      await log("debug", "tool.execute.after captured", { sessionID, tool: input.tool })
    },

    event: async ({ event }: { event: any }) => {
      if (event.type === "session.idle") {
        const sessionID = pickSessionID(event.properties || event)
        if (sessionID) {
          const buffer = buffers.get(sessionID)
          const textCount = buffer?.texts.length ?? 0
          const toolCount = buffer?.toolCalls.length ?? 0
          await log("info", `session.idle`, { sessionID, textCount, toolCount })
          flushSync(sessionID)
        }
      } else if (event.type === "session.created" || event.type === "session.deleted") {
        await log("info", `session event: ${event.type}`, {
          sessionID: pickSessionID(event.properties || event),
        })
      }
    },
  }
}

export default OpenShieldCapture
