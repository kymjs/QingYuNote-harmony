import { http } from '@kit.NetworkKit'
import { AiTagPrompt } from './AiTagPrompt'
import { NoteApiClient, buildMiniMaxChatExtras } from './NoteApiClient'
interface ChatMessage {
  role: string
  content: string
}

interface TagJsonCandidate {
  tag: string
  json: string
}

interface MiniMaxAssistantPayload {
  content: string
  reasoningContent: string
  finishReason: string
}

export class AiTagService {
  private static instance: AiTagService = new AiTagService()
  private static readonly MAX_ATTEMPTS: number = 2

  static getInstance(): AiTagService {
    return AiTagService.instance
  }

  async suggestTag(title: string, content: string, existingTags: string[]): Promise<string> {
    const config = await NoteApiClient.getInstance().fetchAiTagConfig()
    if (config === null) {
      throw new Error('未登录或服务不可用')
    }
    const base = config.base_url.replace(/\/+$/, '')
    const url = `${base}/chat/completions`
    const messages: ChatMessage[] = [
      { role: 'system', content: AiTagPrompt.SYSTEM },
      { role: 'user', content: AiTagPrompt.buildUserMessage(title, content, existingTags) }
    ]

    let lastRaw: string = ''
    let lastParsed: string = ''
    let lastFinishReason: string = ''
    let lastBodyEmpty: boolean = true
    for (let attempt = 0; attempt < AiTagService.MAX_ATTEMPTS; attempt++) {
      const useReasoningSplit = attempt === 0
      const body: Record<string, Object> = {
        model: config.model,
        temperature: 0.2,
        max_tokens: 1024,
        reasoning_split: useReasoningSplit,
        messages: messages
      }
      Object.assign(body, buildMiniMaxChatExtras(config))
      const req = http.createHttp()
      try {
        const resp = await req.request(url, {
          method: http.RequestMethod.POST,
          header: {
            'Authorization': `Bearer ${config.token_plan_key}`,
            'Content-Type': 'application/json; charset=utf-8'
          },
          extraData: JSON.stringify(body),
          expectDataType: http.HttpDataType.STRING,
          connectTimeout: 20000,
          readTimeout: 60000
        })
        if (resp.responseCode < 200 || resp.responseCode >= 300) {
          throw new Error('AI 服务暂时不可用，请稍后重试')
        }
        const text = (resp.result as string) ?? ''
        let obj: Object | null = null
        try {
          obj = JSON.parse(text) as Object
        } catch (e) {
          throw new Error('AI 响应解析失败')
        }
        AiTagService.ensureMiniMaxResponseOk(obj, text)
        const assistant = AiTagService.extractAssistantPayload(obj)
        let bodyText = AiTagService.extractAnswerBody(assistant.content)
        if (bodyText.length === 0 && assistant.reasoningContent.length > 0) {
          bodyText = AiTagService.extractAnswerBody(assistant.reasoningContent)
        }
        lastFinishReason = assistant.finishReason
        lastBodyEmpty = bodyText.length === 0
        lastRaw = bodyText
        const parsedTag = AiTagService.parseTagFromModelOutput(
          bodyText,
          `${assistant.content}\n${assistant.reasoningContent}`
        )
        const finalized = AiTagService.finalizeParsedTag(parsedTag, existingTags)
        lastParsed = finalized
        if (finalized.length > 0) {
          return finalized
        }
      } catch (e) {
        if (e instanceof Error) {
          throw e
        }
        throw new Error('AI 请求失败，请稍后重试')
      } finally {
        req.destroy()
      }

      if (attempt + 1 < AiTagService.MAX_ATTEMPTS) {
        messages.push({
          role: 'user',
          content: lastFinishReason === 'length' && lastBodyEmpty
            ? '上次思考过长未生成标签。请勿输出分析，直接输出一行 JSON：{"tag":"标签名"}'
            : AiTagPrompt.buildRetryUserMessage(
              lastParsed.length > 0 ? lastParsed : lastRaw,
              AiTagService.isOverlongNewTag(lastParsed, existingTags)
            )
        })
      }
    }

    throw new Error('未能生成合适标签，请稍后重试')
  }

  static finalizeTag(raw: string, pool: string[]): string {
    return AiTagService.finalizeParsedTag(AiTagService.parseTagFromModelOutput(raw), pool)
  }

  static finalizeParsedTag(parsedTag: string, pool: string[]): string {
    let tag = AiTagService.cleanTagText(parsedTag)
    if (tag.length === 0) {
      return ''
    }
    const poolTag = AiTagService.findExactPoolTag(tag, pool)
    if (poolTag !== null) {
      return poolTag
    }
    if (AiTagService.unicodeLength(tag) <= AiTagPrompt.MAX_NEW_TAG_CHARS) {
      return tag
    }
    return AiTagService.truncateNewTag(tag)
  }

  static isOverlongNewTag(tag: string, pool: string[]): boolean {
    const t = tag.trim()
    if (t.length === 0) {
      return false
    }
    if (AiTagService.findExactPoolTag(t, pool) !== null) {
      return false
    }
    return AiTagService.unicodeLength(t) > AiTagPrompt.MAX_NEW_TAG_CHARS
  }

  /** 仅精确匹配库中已有标签（含大小写不敏感）；不做子串/正文匹配。 */
  static findExactPoolTag(tag: string, pool: string[]): string | null {
    const t = tag.trim()
    if (t.length === 0) {
      return null
    }
    if (pool.includes(t)) {
      return t
    }
    const lower = t.toLowerCase()
    for (const p of pool) {
      if (p.toLowerCase() === lower) {
        return p
      }
    }
    return null
  }

  static cleanTagText(tag: string): string {
    let t = tag.trim()
    if (t.length === 0) {
      return ''
    }
    t = t.replace(/[\s\r\n\t]+/g, '')
    t = t.replace(/^[#【\[\(「《"'']+|[#】\]\)」》"'']+$/g, '')
    t = t.replace(/^(标签|tag)[:：]\s*/i, '')
    return t.trim()
  }

  static truncateNewTag(tag: string): string {
    const chars = Array.from(tag)
    if (chars.length <= AiTagPrompt.MAX_NEW_TAG_CHARS) {
      return tag
    }
    return chars.slice(0, AiTagPrompt.MAX_NEW_TAG_CHARS).join('')
  }

  private static ensureMiniMaxResponseOk(data: Object, rawText: string): void {
    const record = data as Record<string, Object>
    const baseResp = record['base_resp'] as Record<string, Object> | undefined
    if (baseResp !== undefined) {
      const code = Number(baseResp['status_code'] ?? 0)
      if (code !== 0) {
        throw new Error('AI 服务暂时不可用，请稍后重试')
      }
    }
    const err = record['error']
    if (err !== undefined && err !== null) {
      throw new Error('AI 服务暂时不可用，请稍后重试')
    }
    const choices = record['choices']
    if (!Array.isArray(choices) || choices.length === 0) {
      throw new Error('AI 未返回有效内容')
    }
  }

  private static normalizeMessageContent(content: Object | string | null | undefined): string {
    if (content === null || content === undefined) {
      return ''
    }
    if (typeof content === 'string') {
      return content
    }
    if (Array.isArray(content)) {
      let out = ''
      for (const part of content as Object[]) {
        const p = part as Record<string, Object>
        const t = p['text']
        if (typeof t === 'string') {
          out += t
        }
      }
      return out
    }
    return `${content}`
  }

  private static extractAssistantPayload(data: Object): MiniMaxAssistantPayload {
    const record = data as Record<string, Object>
    const choices = record['choices']
    const empty: MiniMaxAssistantPayload = { content: '', reasoningContent: '', finishReason: '' }
    if (!Array.isArray(choices) || choices.length === 0) {
      return empty
    }
    const first = choices[0] as Record<string, Object>
    const finishReason = `${first['finish_reason'] ?? ''}`
    const message = first['message'] as Record<string, Object> | undefined
    if (message === undefined) {
      return { content: '', reasoningContent: '', finishReason: finishReason }
    }
    return {
      content: AiTagService.normalizeMessageContent(message['content']),
      reasoningContent: AiTagService.normalizeMessageContent(message['reasoning_content']),
      finishReason: finishReason
    }
  }

  /** 原始 message.content（含 thinking，仅用于调试日志）。 */
  private static extractRawAssistantContent(data: Object | null): string {
    if (data === null) {
      return ''
    }
    const record = data as Record<string, Object>
    const choices = record['choices']
    if (!Array.isArray(choices) || choices.length === 0) {
      return ''
    }
    const first = choices[0] as Record<string, Object>
    const message = first['message'] as Record<string, Object> | undefined
    if (message === undefined) {
      return ''
    }
    return AiTagService.normalizeMessageContent(message['content'])
  }

  /**
   * 提取模型最终答案正文：优先取最后一个 thinking 闭合标签之后的内容；
   * 避免未闭合 thinking 导致 strip 后正文为空。
   */
  static extractAnswerBody(raw: string): string {
    if (raw.length === 0) {
      return ''
    }
    const closeTags: string[] = [
      '</think>',
      '</' + 'think>',
      '</reasoning>'
    ]
    let lastCloseEnd = -1
    for (const close of closeTags) {
      let pos = 0
      while (pos < raw.length) {
        const idx = raw.toLowerCase().indexOf(close.toLowerCase(), pos)
        if (idx < 0) {
          break
        }
        const end = idx + close.length
        if (end > lastCloseEnd) {
          lastCloseEnd = end
        }
        pos = idx + close.length
      }
    }
    if (lastCloseEnd > 0) {
      const after = raw.substring(lastCloseEnd).trim()
      if (after.length > 0) {
        return AiTagService.stripMarkdownFence(AiTagService.stripMiniMaxThinking(after))
      }
    }
    const stripped = AiTagService.stripMiniMaxThinking(raw)
    if (stripped.length > 0) {
      return AiTagService.stripMarkdownFence(stripped)
    }
    const tagIdx = raw.toLowerCase().lastIndexOf('{"tag"')
    if (tagIdx >= 0) {
      return raw.substring(tagIdx).trim()
    }
    return ''
  }

  /**
   * 移除 MiniMax M2 的 thinking 块，只保留正文（如 {"tag":"..."}）。
   * 不使用 reasoning_details 字段。
   */
  static stripMiniMaxThinking(raw: string): string {
    let text = raw
    const tagNames: string[] = ['redacted_thinking', 'think', 'reasoning']
    for (const name of tagNames) {
      const open = `<${name}>`
      const close = `</${name}>`
      let start = text.toLowerCase().indexOf(open)
      while (start >= 0) {
        const endLower = text.toLowerCase().indexOf(close, start)
        if (endLower < 0) {
          text = text.substring(0, start)
          break
        }
        const end = endLower + close.length
        text = text.substring(0, start) + text.substring(end)
        start = text.toLowerCase().indexOf(open)
      }
    }
    return text.trim()
  }

  static describeError(error: Object): string {
    if (error instanceof Error) {
      return error.message
    }
    const raw = JSON.stringify(error)
    return raw.length > 0 && raw !== '{}' ? raw : `${error}`
  }

  static parseTagFromModelOutput(answerBody: string, rawFallback: string = ''): string {
    let body = answerBody.trim()
    if (body.length === 0 && rawFallback.length > 0) {
      body = AiTagService.extractAnswerBody(rawFallback)
    }
    const collected = AiTagService.collectAllTagCandidates(body)
    return collected.length > 0 ? collected[collected.length - 1].tag : ''
  }

  static stripMarkdownFence(text: string): string {
    let t = text.trim()
    const fenced = /^```(?:json)?\s*([\s\S]*?)```\s*$/i.exec(t)
    if (fenced !== null && fenced[1] !== undefined) {
      return fenced[1].trim()
    }
    return t
  }

  /** 扫描正文中所有 `{"tag":...}`，仅采用最后一个合法 JSON 的 tag 字段。 */
  static collectAllTagCandidates(body: string): TagJsonCandidate[] {
    const results: TagJsonCandidate[] = []
    if (body.length === 0) {
      return results
    }
    let searchFrom = 0
    while (searchFrom < body.length) {
      const idx = body.toLowerCase().indexOf('{"tag"', searchFrom)
      if (idx < 0) {
        break
      }
      searchFrom = idx + 6
      const jsonStr = AiTagService.readBalancedJsonObject(body, idx)
      if (jsonStr === null || jsonStr.length === 0) {
        continue
      }
      try {
        const decoded = JSON.parse(jsonStr) as Record<string, Object>
        const tagVal = decoded['tag']
        if (typeof tagVal !== 'string') {
          continue
        }
        const tag = tagVal.trim()
        if (tag.length === 0) {
          continue
        }
        const item: TagJsonCandidate = { tag: tag, json: jsonStr }
        results.push(item)
      } catch (_) {}
    }
    if (results.length > 0) {
      return results
    }
    const patterns: string[] = [
      '\\{\\s*"tag"\\s*:\\s*"((?:[^"\\\\]|\\\\.)*)"\\s*\\}',
      "\\{\\s*'tag'\\s*:\\s*'([^']*)'\\s*\\}",
      '\\{\\s*"tag"\\s*:\\s*\'([^\']*)\'\\s*\\}'
    ]
    for (const pattern of patterns) {
      const re = new RegExp(pattern, 'gi')
      let match = re.exec(body)
      while (match !== null) {
        const tag = (match[1] ?? '').replace(/\\"/g, '"').trim()
        if (tag.length > 0) {
          results.push({ tag: tag, json: match[0] ?? '' })
        }
        match = re.exec(body)
      }
      if (results.length > 0) {
        return results
      }
    }
    return results
  }

  private static readBalancedJsonObject(text: string, fromIndex: number): string | null {
    const begin = text.indexOf('{', fromIndex)
    if (begin < 0) {
      return null
    }
    let depth = 0
    for (let i = begin; i < text.length; i++) {
      const ch = text.charAt(i)
      if (ch === '{') {
        depth++
      } else if (ch === '}') {
        depth--
        if (depth === 0) {
          return text.substring(begin, i + 1)
        }
      }
    }
    return null
  }

  private static unicodeLength(s: string): number {
    return Array.from(s).length
  }
}
