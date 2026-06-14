import { http } from '@kit.NetworkKit'
import { util } from '@kit.ArkTS'
import { Logger } from '../common/utils/Logger'

/** 有道云笔记 MCP-over-SSE 客户端(参考 `youdaonote` CLI 抓出的实际协议)。
 *  真实接口是 [Model Context Protocol](https://modelcontextprotocol.io) over SSE:
 *  1. GET 拿到 `text/event-stream` 长连接,等待服务端推送 `event: endpoint` 事件,
 *     事件 `data` 字段为后续 `POST` JSON-RPC 消息的目标 URL。
 *  2. 在长连接上持续读 `event: message`,事件 `data` 字段是 JSON-RPC 响应。
 *  3. 向 step1 拿到的 POST URL 发 JSON-RPC 请求:
 *     - `initialize`: 协议握手
 *     - `tools/call { name, arguments }`: 调用具体工具
 *  4. 工具调用结果在 `result.content[]` 和 `result.structuredContent` 中。
 *
 *  导入只用到两个工具:
 *  - `listNotes({ parentId, lastId? })`: 列条目；根目录 `parentId` 为 `"0"`（CLI `list -f` 默认）。
 *  - `getNoteTextContent({ fileId })`: 读内容,`result.structuredContent.content`
 *    为 Markdown 字符串,`rawFormat`(`md` / `note` / `txt`)和 `isRaw` 同 SKILL.md 描述。
 */
const YOUDAO_MCP_SSE_URL = 'https://open.mail.163.com/api/ynote/mcp/sse'
const MCP_PROTOCOL_VERSION = '2024-11-05'
const CLIENT_NAME = 'qingyu-note-harmony'
const CLIENT_VERSION = '1.0.0'

export class YoudaoMcpException extends Error {
  code: number = 0
  constructor(message: string, code: number = 0) {
    super(message)
    this.name = 'YoudaoMcpException'
    this.code = code
  }
}

/** 将有道 MCP SSE 返回的 endpoint 补全为绝对 URL（Harmony http.request 不接受相对路径）。 */
function resolveMcpEndpointUrl(endpoint: string, sseUrl: string): string {
  const trimmed = endpoint.trim()
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed
  }
  const originMatch = sseUrl.match(/^(https?:\/\/[^/?#]+)/i)
  if (originMatch === null) {
    throw new YoudaoMcpException(`无法解析 MCP POST URL: ${trimmed}`)
  }
  const origin = originMatch[1]
  if (trimmed.startsWith('/')) {
    return `${origin}${trimmed}`
  }
  const slashIdx = sseUrl.lastIndexOf('/')
  const base = slashIdx >= 0 ? sseUrl.substring(0, slashIdx + 1) : `${origin}/`
  return `${base}${trimmed}`
}

function readHttpResponseCode(header: Object): number {
  const h = header as Record<string, string | number>
  const direct = h['responseCode'] ?? h['statusCode']
  if (typeof direct === 'number' && direct >= 100 && direct < 600) {
    return direct
  }
  const statusLineRaw = h['status-line'] ?? h['Status-Line'] ?? h[':status'] ?? h['status']
  const statusLine = `${statusLineRaw ?? ''}`.trim()
  if (statusLine.length > 0) {
    const parts = statusLine.split(/\s+/)
    for (let i = 0; i < parts.length; i++) {
      const code = parseInt(parts[i], 10)
      if (!Number.isNaN(code) && code >= 100 && code < 600) {
        return code
      }
    }
  }
  return 0
}

function summarizeHttpHeaders(header: Object): string {
  try {
    const text = JSON.stringify(header)
    return text.length > 800 ? `${text.substring(0, 800)}…` : text
  } catch (_) {
    return `${header}`
  }
}

interface SseHandshakeResult {
  respCode: number
  rawPostUrl: string
  statusSource: string
}

/** 等待 SSE 响应头/endpoint/requestInStream 任一给出可用握手结果。 */
function waitForSseHandshake(
  headersPromise: Promise<number>,
  streamCodePromise: Promise<number>,
  endpointPromise: Promise<string>,
  timeoutMs: number
): Promise<SseHandshakeResult> {
  return new Promise<SseHandshakeResult>((resolve, reject) => {
    let headerCode = 0
    let streamCode = 0
    let endpointUrl = ''
    let settled = false

    const finish = (source: string) => {
      if (settled) {
        return
      }
      const knownCode = headerCode > 0 ? headerCode : streamCode
      if (endpointUrl.length > 0) {
        settled = true
        clearTimeout(timer)
        const respCode = knownCode > 0 ? knownCode : 200
        resolve({ respCode, rawPostUrl: endpointUrl, statusSource: source })
        return
      }
      if (knownCode === 401 || knownCode === 403) {
        settled = true
        clearTimeout(timer)
        reject(new YoudaoMcpException('API Key 无效或已过期，请重新获取', knownCode))
        return
      }
      if (knownCode > 0 && knownCode !== 200) {
        settled = true
        clearTimeout(timer)
        reject(new YoudaoMcpException(`SSE 握手失败: HTTP ${knownCode}`, knownCode))
      }
    }

    const timer = setTimeout(() => {
      if (settled) {
        return
      }
      settled = true
      Logger.error('YoudaoMcp',
        `waitForSseHandshake timeout: headerCode=${headerCode}, streamCode=${streamCode}, hasEndpoint=${endpointUrl.length > 0}`)
      reject(new YoudaoMcpException('等待 SSE 握手超时'))
    }, timeoutMs) as number

    headersPromise.then((code: number) => {
      headerCode = code
      Logger.info('YoudaoMcp', `handshake: headers code=${code}`)
      finish('headers')
    }).catch((error: Object) => {
      Logger.error('YoudaoMcp', `handshake: headers error=${JSON.stringify(error)}`)
    })

    streamCodePromise.then((code: number) => {
      streamCode = code
      Logger.info('YoudaoMcp', `handshake: requestInStream code=${code}`)
      finish('requestInStream')
    }).catch((error: Object) => {
      Logger.error('YoudaoMcp', `handshake: requestInStream error=${JSON.stringify(error)}`)
    })

    endpointPromise.then((url: string) => {
      endpointUrl = url
      Logger.info('YoudaoMcp', `handshake: endpoint received len=${url.length}`)
      finish('endpoint')
    }).catch((error: Object) => {
      Logger.error('YoudaoMcp', `handshake: endpoint error=${JSON.stringify(error)}`)
    })
  })
}

/** MCP 工具返回的 `content[]` 中的一种条目。 */
interface McpContentEntry {
  type: string
  text?: string
  markdown?: string
  data?: Object
}

/** 一次 `tools/call` 解析后的结果。 */
export class YoudaoMcpToolResult {
  isError: boolean = false
  content: McpContentEntry[] = []
  structuredContent: Record<string, Object> | null = null

  /** 优先 `structuredContent`；否则解析 `content` 中 json/text 块（同 youdaonote CLI `createCallResult.json()`）。 */
  asJson(): Record<string, Object> | null {
    if (this.structuredContent !== null) {
      return this.structuredContent
    }
    for (const entry of this.content) {
      if (entry.type === 'json' && entry.data !== undefined) {
        const obj = YoudaoMcpToolResult.asRecord(entry.data)
        if (obj !== null) {
          return obj
        }
        if (typeof entry.data === 'string') {
          const parsed = YoudaoMcpToolResult.parseJsonRecord(entry.data as string)
          if (parsed !== null) {
            return parsed
          }
        }
      }
      if (entry.type === 'text' || entry.type === 'markdown') {
        const text = entry.text ?? entry.markdown
        if (text !== undefined && text.trim().length > 0) {
          const parsed = YoudaoMcpToolResult.parseJsonRecord(text)
          if (parsed !== null) {
            return parsed
          }
        }
      }
    }
    return null
  }

  /** 串联 `content` 中所有 text/markdown 块。 */
  asText(): string | null {
    const pieces: string[] = []
    for (const entry of this.content) {
      if (entry.type === 'text' && entry.text !== undefined && entry.text.length > 0) {
        pieces.push(entry.text)
      } else if (entry.type === 'markdown' && entry.markdown !== undefined && entry.markdown.length > 0) {
        pieces.push(entry.markdown)
      }
    }
    if (pieces.length === 0) {
      return null
    }
    return pieces.join('\n')
  }

  private static parseJsonRecord(text: string): Record<string, Object> | null {
    try {
      const obj = JSON.parse(text) as Object
      return YoudaoMcpToolResult.asRecord(obj)
    } catch (_) {
      return null
    }
  }

  private static asRecord(value: Object | undefined): Record<string, Object> | null {
    if (value === undefined || value === null || typeof value !== 'object' || Array.isArray(value)) {
      return null
    }
    return value as Record<string, Object>
  }
}

interface PendingCall {
  resolve: (value: Object | null) => void
  reject: (reason: Object) => void
  method: string
}

/** JSON-RPC 2.0 请求体结构。 */
interface JsonRpcRequestBody {
  jsonrpc: string
  id: number
  method: string
  params: Object
}

/** JSON-RPC 2.0 通知体结构（无 id,无 SSE 响应）。 */
interface JsonRpcNotificationBody {
  jsonrpc: string
  method: string
  params: Object
}

/** `initialize` 报文里 `clientInfo` 子对象。 */
interface McpClientInfo {
  name: string
  version: string
}

/** `initialize` 报文的 `params`。 */
interface McpInitParams {
  protocolVersion: string
  capabilities: Record<string, Object>
  clientInfo: McpClientInfo
}

/** `tools/call` 报文的 `params`。 */
interface McpToolCallParams {
  name: string
  arguments: Object
}

/** JSON-RPC 通知的空 params（如 `notifications/initialized`）。 */
const MCP_EMPTY_PARAMS: Record<string, Object> = {}

/** 长连接一个 MCP session,串行执行 JSON-RPC 调用。 */
export class YoudaoMcpClient {
  private apiKey: string = ''
  private httpClient: http.HttpRequest | null = null
  private sseReq: http.HttpRequest | null = null
  private postUrl: string = ''
  private nextId: number = 1
  private pending: Map<number, PendingCall> = new Map()
  private currentEvent: string = ''
  private initialized: boolean = false
  private closed: boolean = false
  private pendingEndpointResolve: ((value: string) => void) | null = null
  private pendingEndpointReject: ((reason: Object) => void) | null = null

  constructor(apiKey: string = '') {
    this.apiKey = apiKey
  }

  /** 有道 MCP 官方认证头（mcporter / youdaonote CLI 使用 `x-api-key`，非 Bearer）。 */
  private authHeaders(): Record<string, string> {
    if (this.apiKey.length === 0) {
      return {}
    }
    return { 'x-api-key': this.apiKey }
  }

  private mergeAuthHeaders(base: Record<string, string>): Record<string, string> {
    const merged: Record<string, string> = {}
    for (const key of Object.keys(base)) {
      merged[key] = base[key]
    }
    const auth = this.authHeaders()
    for (const key of Object.keys(auth)) {
      merged[key] = auth[key]
    }
    return merged
  }

  /** 打开 SSE,完成 `initialize` 握手,返回已就绪的 client。 */
  async connect(): Promise<void> {
    if (this.initialized) {
      return
    }
    Logger.info('YoudaoMcp', `connect: GET ${YOUDAO_MCP_SSE_URL}`)
    const req = http.createHttp()
    this.sseReq = req

    // requestInStream 必须在注册 dataReceive 之后调用,否则首批 SSE 块(含 endpoint)会丢失。
    const endpointPromise = new Promise<string>((resolve, reject) => {
      this.pendingEndpointResolve = resolve
      this.pendingEndpointReject = reject
    })
    const textDecoder = new util.TextDecoder('utf-8')
    let leftover = ''
    const onData = (data: ArrayBuffer) => {
      if (this.closed) {
        return
      }
      const text = textDecoder.decodeWithStream(new Uint8Array(data))
      if (text.length > 0) {
        Logger.info('YoudaoMcp', `sse: chunkLen=${text.length}`)
      }
      leftover += text
      let nlIdx = leftover.indexOf('\n')
      while (nlIdx >= 0) {
        let line = leftover.substring(0, nlIdx)
        if (line.endsWith('\r')) {
          line = line.substring(0, line.length - 1)
        }
        leftover = leftover.substring(nlIdx + 1)
        this.handleSseLine(line)
        nlIdx = leftover.indexOf('\n')
      }
    }
    const onDataEnd = () => {
      if (this.closed) {
        return
      }
      Logger.info('YoudaoMcp', 'parseSseStream: dataEnd')
      if (!this.initialized && this.postUrl.length === 0) {
        const rej = this.pendingEndpointReject
        if (rej) {
          this.pendingEndpointResolve = null
          this.pendingEndpointReject = null
          rej(new YoudaoMcpException('SSE 连接在拿到 endpoint 前就关闭了'))
        }
      }
      this.failAllPending(new YoudaoMcpException('SSE 连接已关闭'))
    }

    let headersResolved = false
    const headersPromise = new Promise<number>((resolve) => {
      req.on('headersReceive', (header: Object) => {
        if (headersResolved) {
          return
        }
        headersResolved = true
        Logger.info('YoudaoMcp', `connect: SSE headers raw=${summarizeHttpHeaders(header)}`)
        const code = readHttpResponseCode(header)
        Logger.info('YoudaoMcp', `connect: SSE headers parsedCode=${code}`)
        resolve(code)
      })
    })

    req.on('dataReceive', onData)
    req.on('dataEnd', onDataEnd)

    const streamCodePromise = new Promise<number>((resolve, reject) => {
      req.requestInStream(YOUDAO_MCP_SSE_URL, {
        method: http.RequestMethod.GET,
        header: this.mergeAuthHeaders({
          'Accept': 'text/event-stream',
          'Cache-Control': 'no-cache',
        }),
        connectTimeout: 20000,
        readTimeout: 60000,
        usingProtocol: http.HttpProtocol.HTTP1_1
      }).then((code: number) => {
        Logger.info('YoudaoMcp', `requestInStream settled: code=${code}`)
        resolve(code)
      }).catch((error: Object) => {
        Logger.error('YoudaoMcp', `requestInStream error: ${JSON.stringify(error)}`)
        reject(error)
      })
    })

    let handshake: SseHandshakeResult
    try {
      handshake = await waitForSseHandshake(headersPromise, streamCodePromise, endpointPromise, 20000)
      Logger.info('YoudaoMcp',
        `connect: handshake ok source=${handshake.statusSource}, respCode=${handshake.respCode}`)
    } catch (error) {
      const e = error as Error
      Logger.error('YoudaoMcp', `connect: SSE 打开失败: ${e.message}`)
      try {
        req.off('headersReceive')
        req.off('dataReceive')
        req.off('dataEnd')
        req.destroy()
      } catch (_) {
      }
      this.sseReq = null
      this.pendingEndpointResolve = null
      this.pendingEndpointReject = null
      throw e instanceof YoudaoMcpException ? e : new YoudaoMcpException(`SSE 握手失败: ${e.message}`)
    }

    this.postUrl = resolveMcpEndpointUrl(handshake.rawPostUrl, YOUDAO_MCP_SSE_URL)
    Logger.info('YoudaoMcp', `connect: 拿到 postUrl=${this.postUrl} (raw=${handshake.rawPostUrl})`)

    // 发送 initialize 握手
    Logger.info('YoudaoMcp', 'connect: 发送 initialize')
    const emptyCaps: Record<string, Object> = {}
    const clientInfo: McpClientInfo = { name: CLIENT_NAME, version: CLIENT_VERSION }
    const initParams: McpInitParams = {
      protocolVersion: MCP_PROTOCOL_VERSION,
      capabilities: emptyCaps,
      clientInfo: clientInfo
    }
    await this.call('initialize', initParams)
    Logger.info('YoudaoMcp', 'connect: 发送 notifications/initialized')
    await this.sendNotification('notifications/initialized')
    this.initialized = true
    Logger.info('YoudaoMcp', 'connect: initialize 完成, 准备就绪')
  }

  /** 发送 JSON-RPC 通知（不等待 SSE 响应）。 */
  private async sendNotification(method: string, params?: Record<string, Object>): Promise<void> {
    const body: JsonRpcNotificationBody = {
      jsonrpc: '2.0',
      method: method,
      params: params ?? MCP_EMPTY_PARAMS
    }
    await this.postJson(this.postUrl, body)
  }

  private handleSseLine(line: string): void {
    if (line.length > 0) {
      const preview = line.length > 120 ? `${line.substring(0, 120)}…` : line
      Logger.info('YoudaoMcp', `sse: line=${preview}`)
    }
    if (line.length === 0) {
      this.currentEvent = ''
      return
    }
    if (line.startsWith(':')) {
      return
    }
    const colon = line.indexOf(':')
    if (colon < 0) {
      return
    }
    const field = line.substring(0, colon)
    let value = line.substring(colon + 1)
    if (value.startsWith(' ')) {
      value = value.substring(1)
    }
    if (field === 'event') {
      this.currentEvent = value
    } else if (field === 'data') {
      this.handleSseData(this.currentEvent || 'message', value)
    }
  }

  private handleSseData(event: string, data: string): void {
    const preview = data.length > 200 ? `${data.substring(0, 200)}…` : data
    Logger.info('YoudaoMcp', `sse: event=${event} dataLen=${data.length} preview=${preview}`)
    if (event === 'endpoint') {
      const url = data.trim()
      const resolve = this.pendingEndpointResolve
      if (resolve) {
        this.pendingEndpointResolve = null
        this.pendingEndpointReject = null
        resolve(url)
      }
      return
    }
    let parsed: Record<string, Object> | null = null
    try {
      const obj = JSON.parse(data) as Object
      if (typeof obj === 'object' && obj !== null) {
        parsed = obj as Record<string, Object>
      }
    } catch (_) {
      return
    }
    if (parsed === null) {
      return
    }
    const idRaw = parsed['id']
    const id = typeof idRaw === 'number' ? idRaw : -1
    if (id < 0) {
      const method = `${parsed['method'] ?? ''}`
      if (method.length > 0) {
        Logger.info('YoudaoMcp', `sse: notification method=${method}`)
      }
      return
    }
    const pending = this.pending.get(id)
    if (pending === undefined) {
      Logger.info('YoudaoMcp', `sse: jsonrpc id=${id} ignored (no pending caller)`)
      return
    }
    this.pending.delete(id)
    const err = parsed['error']
    if (typeof err === 'object' && err !== null) {
      const e = err as Record<string, Object>
      const code = typeof e['code'] === 'number' ? (e['code'] as number) : 0
      const msg = `${e['message'] ?? 'JSON-RPC 错误'}`
      Logger.error('YoudaoMcp', `sse: jsonrpc id=${id} method=${pending.method} error=${msg}`)
      pending.reject(new YoudaoMcpException(msg, code))
      return
    }
    const result = parsed['result']
    Logger.info('YoudaoMcp', `sse: jsonrpc id=${id} method=${pending.method} resolved`)
    if (typeof result === 'object' && result !== null) {
      pending.resolve(result as Object)
    } else {
      pending.resolve(null)
    }
  }

  private parseToolResult(result: Object | null): YoudaoMcpToolResult {
    const out = new YoudaoMcpToolResult()
    if (result === null || typeof result !== 'object') {
      return out
    }
    const r = result as Record<string, Object>
    out.isError = r['isError'] === true
    const contentRaw = r['content']
    const contentArr: Object[] = Array.isArray(contentRaw) ? (contentRaw as Object[]) : []
    for (const raw of contentArr) {
      if (typeof raw !== 'object' || raw === null) {
        continue
      }
      const m = raw as Record<string, Object>
      const entry: McpContentEntry = {
        type: `${m['type'] ?? 'text'}`,
        text: typeof m['text'] === 'string' ? (m['text'] as string) : undefined,
        markdown: typeof m['markdown'] === 'string' ? (m['markdown'] as string) : undefined,
        data: m['data'] ?? m['json']
      }
      out.content.push(entry)
    }
    const structuredRaw = r['structuredContent']
    if (typeof structuredRaw === 'object' && structuredRaw !== null) {
      out.structuredContent = structuredRaw as Record<string, Object>
    }
    return out
  }

  /** 调一次 JSON-RPC 方法,返回 `result` 字段原值。 */
  async call(method: string, params: Object, timeoutMs: number = 60000): Promise<Object | null> {
    if (this.closed) {
      throw new YoudaoMcpException('客户端已关闭')
    }
    if (this.postUrl.length === 0) {
      throw new YoudaoMcpException('尚未 connect,无 POST URL')
    }
    const id = this.nextId++
    Logger.info('YoudaoMcp', `call: method=${method} id=${id} start`)
    const body: JsonRpcRequestBody = {
      jsonrpc: '2.0',
      id: id,
      method: method,
      params: params
    }
    const promise = new Promise<Object | null>((resolve, reject) => {
      const pc: PendingCall = { resolve, reject, method }
      this.pending.set(id, pc)
    })
    try {
      await this.postJson(this.postUrl, body)
      Logger.info('YoudaoMcp', `call: method=${method} id=${id} POST accepted, waiting SSE response`)
    } catch (e) {
      this.pending.delete(id)
      Logger.error('YoudaoMcp', `call: method=${method} id=${id} POST failed: ${e}`)
      throw e instanceof Error ? e : new YoudaoMcpException('POST 请求失败')
    }
    return await Promise.race([
      promise,
      new Promise<Object | null>((_, reject) => setTimeout(() => {
        this.pending.delete(id)
        Logger.error('YoudaoMcp', `call: method=${method} id=${id} SSE response timeout`)
        reject(new YoudaoMcpException(`JSON-RPC 调用 ${method} 超时`))
      }, timeoutMs))
    ])
  }

  /** 调 `tools/call` 并解析 result。 */
  async callTool(name: string, args: Object, timeoutMs: number = 60000): Promise<YoudaoMcpToolResult> {
    const toolCallParams: McpToolCallParams = {
      name: name,
      arguments: args
    }
    const raw = await this.call('tools/call', toolCallParams, timeoutMs)
    return this.parseToolResult(raw)
  }

  /** 关闭长连接,丢弃所有未完成请求。 */
  async close(): Promise<void> {
    if (this.closed) {
      return
    }
    this.closed = true
    this.initialized = false
    this.postUrl = ''
    this.failAllPending(new YoudaoMcpException('客户端已关闭'))
    const req = this.sseReq
    this.sseReq = null
    if (req) {
      try {
        req.off('headersReceive')
        req.off('dataReceive')
        req.off('dataEnd')
        req.destroy()
      } catch (_) {
      }
    }
  }

  private async postJson(url: string, body: Object, readTimeoutMs: number = 60000): Promise<void> {
    const bodyText = JSON.stringify(body)
    Logger.info('YoudaoMcp', `post: ${url} body=${bodyText}`)
    const req = http.createHttp()
    return new Promise<void>((resolve, reject) => {
      let settled = false
      const finishOk = (code: number, detail: string) => {
        if (settled) {
          return
        }
        settled = true
        Logger.info('YoudaoMcp', `post: accepted code=${code} ${detail}`)
        try {
          req.off('headersReceive')
          req.destroy()
        } catch (_) {
        }
        resolve()
      }
      const finishErr = (error: YoudaoMcpException) => {
        if (settled) {
          return
        }
        settled = true
        try {
          req.off('headersReceive')
          req.destroy()
        } catch (_) {
        }
        reject(error)
      }

      req.on('headersReceive', (header: Object) => {
        const code = readHttpResponseCode(header)
        Logger.info('YoudaoMcp', `post: headers parsedCode=${code} raw=${summarizeHttpHeaders(header)}`)
        if (code === 401 || code === 403) {
          finishErr(new YoudaoMcpException('API Key 无效或已过期，请重新获取', code))
          return
        }
        if (code >= 200 && code < 300) {
          finishOk(code, 'via headersReceive')
        }
      })

      req.request(url, {
        method: http.RequestMethod.POST,
        header: this.mergeAuthHeaders({
          'Content-Type': 'application/json',
          'Accept': 'application/json, text/event-stream',
        }),
        extraData: bodyText,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 20000,
        readTimeout: readTimeoutMs
      }).then((resp) => {
        if (settled) {
          return
        }
        const code = resp.responseCode
        const text = (resp.result as string) ?? ''
        Logger.info('YoudaoMcp', `post: responseCode=${code} body=${text.substring(0, 200)}`)
        if (code === 401 || code === 403) {
          finishErr(new YoudaoMcpException('API Key 无效或已过期，请重新获取', code))
          return
        }
        if (code >= 200 && code < 300) {
          finishOk(code, 'via request')
          return
        }
        finishErr(new YoudaoMcpException(`POST 失败: HTTP ${code}, body=${text}`, code))
      }).catch((error: Object) => {
        if (settled) {
          return
        }
        settled = true
        try {
          req.off('headersReceive')
          req.destroy()
        } catch (_) {
        }
        const e = error as Error
        finishErr(new YoudaoMcpException(`POST 请求失败: ${e.message}`))
      })
    })
  }

  private failAllPending(error: Object): void {
    if (this.pending.size === 0) {
      return
    }
    const values: PendingCall[] = []
    this.pending.forEach((v) => values.push(v))
    this.pending.clear()
    for (const p of values) {
      try {
        p.reject(error)
      } catch (_) {
      }
    }
  }

  private static readonly RESOURCE_DOWNLOAD_TOOLS: string[] = [
    'downloadWebResource',
    'downloadResource',
    'getWebResource',
    'getResourceContent',
    'fetchWebResource'
  ]

  /** 通过 MCP 下载有道云图床资源。 */
  async downloadResourceBytes(url: string): Promise<ArrayBuffer | null> {
    const trimmed = url.trim()
    if (trimmed.length === 0) {
      return null
    }
    for (const tool of YoudaoMcpClient.RESOURCE_DOWNLOAD_TOOLS) {
      const argVariants: Record<string, Object>[] = [
        { 'url': trimmed },
        { 'resourceUrl': trimmed },
        { 'resource': trimmed },
        { 'src': trimmed }
      ]
      for (const args of argVariants) {
        try {
          const result = await this.callTool(tool, args, 45000)
          if (result.isError) {
            continue
          }
          const bytes = this.extractBytesFromToolResult(result)
          if (bytes !== null && bytes.byteLength > 0) {
            Logger.info('YoudaoMcp', `downloadResourceBytes: tool=${tool} size=${bytes.byteLength}`)
            return bytes
          }
        } catch (_) {
        }
      }
    }
    return null
  }

  private extractBytesFromToolResult(result: YoudaoMcpToolResult): ArrayBuffer | null {
    const structured = result.asJson()
    if (structured !== null) {
      for (const key of ['data', 'bytes', 'content', 'body', 'base64']) {
        const parsed = this.parseBytes(structured[key])
        if (parsed !== null) {
          return parsed
        }
      }
    }
    for (const entry of result.content) {
      if (entry.type === 'json') {
        const parsed = this.parseBytes(entry.data)
        if (parsed !== null) {
          return parsed
        }
      }
      const text = entry.text ?? entry.markdown ?? ''
      if (text.length > 0) {
        const parsed = this.parseBytes(text)
        if (parsed !== null) {
          return parsed
        }
      }
    }
    return null
  }

  private parseBytes(value: Object | undefined): ArrayBuffer | null {
    if (value === undefined || value === null) {
      return null
    }
    if (value instanceof ArrayBuffer) {
      return value
    }
    if (Array.isArray(value)) {
      const items: Object[] = value as Object[]
      const view = new Uint8Array(items.length)
      for (let i = 0; i < items.length; i++) {
        const item: Object = items[i]
        if (typeof item !== 'number') {
          return null
        }
        view[i] = item
      }
      return view.buffer
    }
    if (typeof value === 'string') {
      const trimmed = value.trim()
      if (trimmed.length === 0) {
        return null
      }
      try {
        const helper = new util.Base64Helper()
        const decoded = helper.decodeSync(trimmed.replace(/\s+/g, ''), util.Type.BASIC)
        return decoded.buffer
      } catch (_) {
      }
    }
    return null
  }
}
