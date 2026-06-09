# message.updated Hook 分析报告

## 1. 核心结论

`message.updated` **不是** OpenCode `Hooks` 接口中的命名 hook，而是一个**核心事件类型**，通过通用的 `event` hook 投递。事件中包含 `role` 字段，可用于区分用户和 LLM 消息。

## 2. role 字段结构

`message.updated` 事件的 `properties.info` 是联合类型 `UserMessage | AssistantMessage`，判别字段为 `role`：

| role 值 | 含义 | 说明 |
|---------|------|------|
| `"user"` | 用户消息 | 由人类用户输入 |
| `"assistant"` | LLM 消息 | 由 AI 模型生成 |

## 3. 事件投递结构

```typescript
{
  event: {
    id: string,
    type: "message.updated",
    properties: {
      sessionID: string,
      info: {
        role: "user" | "assistant",
        id: string,
        sessionID: string,
        // ... 其余字段取决于 role
      }
    }
  }
}
```

## 4. 类型定义参考

**UserMessage** (`packages/sdk/js/src/v2/gen/types.gen.ts:238-261`):

```typescript
export type UserMessage = {
  id: string
  sessionID: string
  role: "user"
  time: { created: number }
  format?: OutputFormat
  agent: string
  model: { providerID: string; modelID: string; variant?: string }
  // ...
}
```

**AssistantMessage** (`packages/sdk/js/src/v2/gen/types.gen.ts:325-365`):

```typescript
export type AssistantMessage = {
  id: string
  sessionID: string
  role: "assistant"
  time: { created: number; completed?: number }
  parentID: string
  modelID: string
  providerID: string
  cost: number
  tokens: { input: number; output: number; reasoning: number; cache: { read: number; write: number } }
  // ...
}
```

## 5. 核心 Schema 定义

`packages/core/src/v1/session.ts:488`:

```typescript
export const Info = Schema.Union([User, Assistant]).annotate({
  discriminator: "role", identifier: "Message"
})
```

## 6. 当前插件问题

`src/plugin/openshield-capture.ts:123` 使用了错误的 hook 签名：

```typescript
// ❌ 错误：message.updated 不是命名 hook
"message.updated": async (input: any, output: any) => { ... }
```

## 7. 修复方案

将 `message.updated` 逻辑合并到 `event` hook 中，通过 `info.role` 区分消息来源：

```typescript
event: async ({ event }) => {
  if (event.type === "message.updated") {
    const info = event.properties.info
    const role = info.role  // "user" | "assistant"
    // ... 处理逻辑
  }
}
```

同时需要为 `CapturedText` 接口增加 `role` 字段：

```typescript
interface CapturedText {
  messageID: string
  partID: string
  content: string
  role: "user" | "assistant"  // 新增
  timestamp: string
}
```

## 8. 涉及的源码文件

| 文件 | 说明 |
|------|------|
| `packages/plugin/src/index.ts:222-335` | `Hooks` 接口定义 |
| `packages/core/src/v1/session.ts:488-601` | `Info` 联合类型与 `MessageUpdated` 事件定义 |
| `packages/sdk/js/src/v2/gen/types.gen.ts:238-365` | `UserMessage` / `AssistantMessage` 类型 |
| `packages/opencode/src/plugin/index.ts:258-265` | 事件投递到插件的代码 |
| `src/plugin/openshield-capture.ts` | 当前插件实现 |
