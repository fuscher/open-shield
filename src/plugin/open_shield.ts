import { mkdirSync, writeFile, existsSync, readFileSync, copyFileSync } from "node:fs"
import { join, resolve, normalize } from "node:path"
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
const PATH_POLICY_PATH = join(OPENSHIELD_DIR, "path_policy.json")
const SERVICE_TOKEN_PATH = join(OPENSHIELD_DIR, "service.token")
const PYTHON_SERVICE_URL = "http://localhost:9527"
const AUTO_START_SERVICE = true

// ==================== 服务 Token ====================

let serviceToken: string | null = null

function loadServiceToken(): string | null {
  if (serviceToken !== null) return serviceToken

  try {
    if (existsSync(SERVICE_TOKEN_PATH)) {
      serviceToken = readFileSync(SERVICE_TOKEN_PATH, "utf-8").trim()
      return serviceToken
    }
  } catch (err) {
    console.error("[OpenShield] Failed to load service.token:", err)
  }

  return null
}

// ==================== 路径策略 ====================

interface PathPolicy {
  blacklist: string[]
  whitelist: string[]
  sensitive_read_patterns: string[]
  learning_mode: boolean
}

let pathPolicy: PathPolicy | null = null

function loadPathPolicy(): PathPolicy {
  if (pathPolicy) return pathPolicy

  try {
    if (existsSync(PATH_POLICY_PATH)) {
      pathPolicy = JSON.parse(readFileSync(PATH_POLICY_PATH, "utf-8"))
      return pathPolicy!
    }
  } catch (err) {
    console.error("[OpenShield] Failed to load path_policy.json:", err)
  }

  // 默认策略
  pathPolicy = {
    blacklist: [
      "/etc/**",
      "/boot/**",
      "~/.ssh/**",
      "~/.gnupg/**",
      "C:\\Windows\\**",
      "C:\\Program Files\\**",
      "**/.env",
      "**/credentials",
      "**/id_rsa",
      "**/*.pem"
    ],
    whitelist: [
      "/tmp/**",
      "/home/*/projects/**",
      "~/work/**",
      "D:\\Git\\**",
      "C:\\Users\\*\\Documents\\**"
    ],
    sensitive_read_patterns: [
      "~/.ssh/**",
      "~/.aws/**",
      "**/.env",
      "**/config.json",
      "/etc/passwd",
      "/etc/shadow"
    ],
    learning_mode: true
  }

  return pathPolicy!
}

function matchPattern(pattern: string, filePath: string): boolean {
  // 简化的通配符匹配
  const normalizedPattern = pattern.replace(/\\/g, "/").toLowerCase()
  const normalizedPath = filePath.replace(/\\/g, "/").toLowerCase()

  // 处理 ~ 展开
  const homeDir = homedir().replace(/\\/g, "/").toLowerCase()
  const expandedPattern = normalizedPattern.replace(/^~/, homeDir)

  // 简单的通配符匹配
  const regexPattern = expandedPattern
    .replace(/\./g, "\\.")
    .replace(/\*/g, ".*")
    .replace(/\?/g, ".")

  const regex = new RegExp(`^${regexPattern}$`, "i")
  return regex.test(normalizedPath)
}

function extractPath(toolName: string, args: any): string | null {
  // 仅处理有明确 filePath 参数的工具
  if (["write", "edit", "read", "apply_patch"].includes(toolName)) {
    return args?.filePath || args?.file_path || null
  }
  // shell 等工具不提取路径
  return null
}

function checkPathPolicy(filePath: string): { allowed: boolean; reason: string } {
  const policy = loadPathPolicy()

  // 规范化路径
  const normalizedPath = normalize(filePath)

  // 检查黑名单
  for (const pattern of policy.blacklist) {
    if (matchPattern(pattern, normalizedPath)) {
      return { allowed: false, reason: `Blacklisted: ${pattern}` }
    }
  }

  // 检查白名单
  for (const pattern of policy.whitelist) {
    if (matchPattern(pattern, normalizedPath)) {
      return { allowed: true, reason: `Whitelisted: ${pattern}` }
    }
  }

  // 学习模式：记录但允许
  if (policy.learning_mode) {
    return { allowed: true, reason: "Learning mode: allowed" }
  }

  // 保守策略：未知路径阻断
  return { allowed: false, reason: "Unknown path (not in whitelist)" }
}

function isSensitiveRead(filePath: string): boolean {
  const policy = loadPathPolicy()
  const normalizedPath = normalize(filePath)

  for (const pattern of policy.sensitive_read_patterns) {
    if (matchPattern(pattern, normalizedPath)) {
      return true
    }
  }

  return false
}

// ==================== 风险检测 ====================

interface TsParams {
  high_risk_patterns: string[]
  medium_risk_tools: string[]
  high_risk_tools: string[]
  safe_command_prefixes: string[]
  phase_d_thresholds: {
    high_risk_tool_count: number
    sensitive_path_count: number
  }
  health_check_interval: number
}

// TTL缓存
let _cachedParams: TsParams | null = null
let _cacheTime = 0
const CACHE_TTL = 5000 // 5秒缓存

function loadTsParams(): TsParams {
  // 缓存命中则直接返回
  if (_cachedParams && Date.now() - _cacheTime < CACHE_TTL) {
    return _cachedParams
  }
  
  const configPath = join(OPENSHIELD_DIR, "dashboard_config.json")
  const defaults: TsParams = {
    high_risk_patterns: ["rm -rf", "rm -r", "format", "reboot", "shutdown", "dd if=", "mkfs", "drop table", "drop database", "truncate table"],
    medium_risk_tools: ["curl", "wget", "chmod", "chown", "write", "edit", "overwrite", "delete", "remove", "unlink"],
    high_risk_tools: ["database", "query", "execute"],
    safe_command_prefixes: [
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
      "code", "vim", "nano"
    ],
    phase_d_thresholds: { high_risk_tool_count: 10, sensitive_path_count: 3 },
    health_check_interval: 60000
  }
  
  try {
    if (existsSync(configPath)) {
      const config = JSON.parse(readFileSync(configPath, "utf-8"))
      const tsParams = config.ts_params || {}
      // 深合并：确保嵌套对象（如phase_d_thresholds）不丢失默认值
      _cachedParams = {
        ...defaults,
        ...tsParams,
        phase_d_thresholds: {
          ...defaults.phase_d_thresholds,
          ...(tsParams.phase_d_thresholds || {})
        }
      }
    } else {
      _cachedParams = defaults
    }
  } catch (err) {
    console.error("[OpenShield] Failed to load ts_params:", err)
    _cachedParams = defaults
  }
  
  _cacheTime = Date.now()
  return _cachedParams!
}

function detectToolRisk(tool: string, args: Record<string, unknown>): "low" | "medium" | "high" {
  const params = loadTsParams()
  const toolName = (tool || "").toLowerCase()

  if (toolName === "bash" || toolName === "shell" || toolName === "exec") {
    const command = String(args.command || args.script || args.cmd || "").toLowerCase().trim()
    if (!command) return "low"

    for (const pattern of params.high_risk_patterns) {
      if (command.includes(pattern)) return "high"
    }

    const firstToken = command.split(/\s+/)[0]
    if (params.safe_command_prefixes.includes(firstToken)) return "low"

    return "medium"
  }

  const argsStr = JSON.stringify(args).toLowerCase()
  const command = `${toolName} ${argsStr}`

  for (const pattern of params.high_risk_patterns) {
    if (command.includes(pattern)) return "high"
  }

  if (params.high_risk_tools.includes(toolName)) return "high"
  if (params.medium_risk_tools.includes(toolName)) return "medium"

  return "low"
}

// ==================== 会话统计 (Phase D) ====================

interface SessionStats {
  highRiskToolCount: number
  sensitivePathCount: number
}

const sessionStats = new Map<string, SessionStats>()

function getSessionStats(sessionID: string): SessionStats {
  if (!sessionStats.has(sessionID)) {
    sessionStats.set(sessionID, { highRiskToolCount: 0, sensitivePathCount: 0 })
  }
  return sessionStats.get(sessionID)!
}

function incrementHighRiskToolCount(sessionID: string): void {
  const stats = getSessionStats(sessionID)
  stats.highRiskToolCount++
}

function incrementSensitivePathCount(sessionID: string): void {
  const stats = getSessionStats(sessionID)
  stats.sensitivePathCount++
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
  for (const file of ["pii.yaml", "keywords.yaml", "injection.yaml", "output_sensitivity.yaml", "response_guard.yaml"]) {
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

  const token = loadServiceToken()
  const headers: Record<string, string> = { "Content-Type": "application/json" }
  if (token) {
    headers["Authorization"] = `Bearer ${token}`
  }

  try {
    const response = await fetch(`${PYTHON_SERVICE_URL}/api/v1/detect/execute`, {
      method: "POST",
      headers,
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

  const token = loadServiceToken()
  const headers: Record<string, string> = { "Content-Type": "application/json" }
  if (token) {
    headers["Authorization"] = `Bearer ${token}`
  }

  try {
    const response = await fetch(`${PYTHON_SERVICE_URL}/api/v1/capture`, {
      method: "POST",
      headers,
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

async function sendToOutputGuard(
  sessionID: string,
  toolName: string,
  outputContent: string
): Promise<{ action: string; alerts: any[]; sanitized_content?: string; was_modified?: boolean } | null> {
  if (!(await checkServiceHealth())) return null

  const token = loadServiceToken()
  const headers: Record<string, string> = { "Content-Type": "application/json" }
  if (token) {
    headers["Authorization"] = `Bearer ${token}`
  }

  try {
    const response = await fetch(`${PYTHON_SERVICE_URL}/api/v1/detect/output`, {
      method: "POST",
      headers,
      body: JSON.stringify({
        session_id: sessionID,
        tool_name: toolName,
        output_content: outputContent,
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

        // Phase A: 响应内容监控（仅对 assistant 消息）
        if (role === "assistant") {
          // 发送到 capture 服务进行安全扫描
          const result = await sendToCaptureService(sessionID, content, "response_text")
          if (result && (result.action === "block" || result.action === "manual")) {
            await log("warn", "Phase A: Response content alert", {
              sessionID,
              action: result.action,
              alertCount: result.alerts?.length,
            })
          }
        }

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

          // Phase D: 会话异常检测
          const stats = getSessionStats(sessionID)
          if (stats.highRiskToolCount > 10) {
            await log("warn", `[OpenShield] Phase D: High risk tool count exceeded threshold`, {
              sessionID,
              highRiskToolCount: stats.highRiskToolCount,
              threshold: 10,
            })
          }
          if (stats.sensitivePathCount > 3) {
            await log("warn", `[OpenShield] Phase D: Sensitive path access count exceeded threshold`, {
              sessionID,
              sensitivePathCount: stats.sensitivePathCount,
              threshold: 3,
            })
          }

          // 清除计数器
          sessionStats.delete(sessionID)

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

      // permission.asked — 权限请求监控（只读事件，不能阻断）
      if (event.type === "permission.asked") {
        permissionAskTriggered = true
        const info = event.properties || event
        const toolName = (info.type || info.tool || "").toLowerCase()
        await log("info", "permission.asked event", { toolName })
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

      // 运行时验证：首次 bash 调用后检查 permission.asked 是否触发
      if (!firstBashChecked && (toolName === "bash" || toolName === "shell")) {
        firstBashChecked = true
        if (!permissionAskTriggered) {
          await log("warn", [
            "[OpenShield] 确认：permission.asked hook 未被触发，bash 权限可能为 'allow'。",
            "安全检测流程未激活，请配置 permission.bash 为 'ask'"
          ].join(" "))
        } else {
          await log("info", "[OpenShield] 权限配置正确，permission.asked hook 已生效")
        }
      }

      // Phase B: 文件路径检查
      const filePath = extractPath(toolName, args)
      if (filePath) {
        const pathCheck = checkPathPolicy(filePath)
        if (!pathCheck.allowed) {
          await log("warn", `[OpenShield] Path blocked: ${pathCheck.reason}`, {
            tool: toolName,
            filePath,
          })
          throw new Error(`[OpenShield] Path blocked: ${pathCheck.reason}. File: ${filePath}`)
        }

        // 检查是否为敏感文件读取
        if (toolName === "read" && isSensitiveRead(filePath)) {
          incrementSensitivePathCount(sessionID)
          await log("warn", `[OpenShield] Sensitive file read detected`, {
            tool: toolName,
            filePath,
          })
        }
      }

      // Phase D: 高危工具调用计数
      if (riskLevel === "high") {
        incrementHighRiskToolCount(sessionID)
      }

      if (riskLevel === "high" || riskLevel === "medium") {
        await log("info", `tool.execute.before ${riskLevel} risk detected`, {
          sessionID, tool,
        })
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
        // Phase C: 输出敏感检测（路径 A：实时脱敏）
        const outputGuardResult = await sendToOutputGuard(sessionID, input.tool || "unknown", toolOutput)
        if (outputGuardResult?.was_modified && outputGuardResult.sanitized_content) {
          // 写回脱敏内容到 output.output
          output.output = outputGuardResult.sanitized_content
          contentToStore = outputGuardResult.sanitized_content
          await log("warn", "Phase C: Output sanitized", {
            sessionID,
            tool: input.tool,
            alertCount: outputGuardResult.alerts?.length,
          })
        }

        // 现有的风险检测逻辑
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
