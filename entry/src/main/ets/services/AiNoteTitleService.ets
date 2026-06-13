import { http } from '@kit.NetworkKit'
import { AiNoteTitlePrompt } from './AiNoteTitlePrompt'
import { AiTagService } from './AiTagService'
import { NoteApiClient, buildChatCompletionRequestBody } from './NoteApiClient'

interface ChatMessage {
  role: string
  content: string
}

interface MiniMaxAssistantPayload {
  content: string
  reasoningContent: string
}

export class AiNoteTitleService {
  private static instance: AiNoteTitleService = new AiNoteTitleService()
  private static readonly MAX_ATTEMPTS: number = 2

  static getInstance(): AiNoteTitleService {
    return AiNoteTitleService.instance
  }

  async suggestTitle(content: string): Promise<string> {
    const trimmed = content.trim()
    if (trimmed.length === 0) {
      throw new Error('笔记正文为空')
    }

    const config = await NoteApiClient.getInstance().fetchAiTagConfig()
    if (config === null) {
      throw new Error('未登录或服务不可用')
    }

    const base = config.base_url.replace(/\/+$/, '')
    const url = `${base}/chat/completions`
    const messages: ChatMessage[] = [
      { role: 'system', content: AiNoteTitlePrompt.SYSTEM },
      { role: 'user', content: AiNoteTitlePrompt.buildUserMessage(trimmed) }
    ]

    let lastParsed = ''
    let lastRaw = ''
    for (let attempt = 0; attempt < AiNoteTitleService.MAX_ATTEMPTS; attempt++) {
      const body = buildChatCompletionRequestBody(
        config.model,
        0.25,
        256,
        attempt === 0,
        messages as Object[],
        config
      )
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
        } catch (_) {
          throw new Error('AI 响应解析失败')
        }
        AiNoteTitleService.ensureMiniMaxResponseOk(obj)
        const assistant = AiNoteTitleService.extractAssistantPayload(obj)
        let bodyText = AiTagService.extractAnswerBody(assistant.content)
        if (bodyText.length === 0 && assistant.reasoningContent.length > 0) {
          bodyText = AiTagService.extractAnswerBody(assistant.reasoningContent)
        }
        lastRaw = bodyText
        lastParsed = AiNoteTitleService.finalizeTitle(
          AiNoteTitleService.parseTitleFromModelOutput(
            bodyText,
            `${assistant.content}\n${assistant.reasoningContent}`
          )
        )
        if (lastParsed.length > 0 && lastParsed !== '笔记') {
          return lastParsed
        }
      } catch (e) {
        if (e instanceof Error) {
          throw e
        }
        throw new Error('AI 请求失败，请稍后重试')
      } finally {
        req.destroy()
      }

      if (attempt + 1 < AiNoteTitleService.MAX_ATTEMPTS) {
        messages.push({
          role: 'user',
          content: AiNoteTitlePrompt.buildRetryUserMessage(
            lastParsed.length > 0 ? lastParsed : lastRaw
          )
        })
      }
    }

    throw new Error('未能生成合适标题，请稍后重试')
  }

  static parseTitleFromModelOutput(bodyText: string, fullRaw: string): string {
    const fromBody = AiNoteTitleService.parseTitleJson(bodyText)
    if (fromBody.length > 0) {
      return fromBody
    }
    const fromRaw = AiNoteTitleService.parseTitleJson(fullRaw)
    if (fromRaw.length > 0) {
      return fromRaw
    }
    const lines = bodyText.split('\n')
    for (let i = 0; i < lines.length; i++) {
      const cleaned = AiNoteTitleService.cleanTitleText(lines[i])
      if (cleaned.length > 0) {
        return cleaned
      }
    }
    return ''
  }

  static finalizeTitle(raw: string): string {
    const title = AiNoteTitleService.cleanTitleText(raw)
    if (title.length === 0) {
      return ''
    }
    if (title.length <= AiNoteTitlePrompt.MAX_TITLE_CHARS) {
      return title
    }
    return title.substring(0, AiNoteTitlePrompt.MAX_TITLE_CHARS)
  }

  private static parseTitleJson(text: string): string {
    const match = text.match(/\{\s*"title"\s*:\s*"((?:\\.|[^"\\])*)"\s*\}/)
    if (match === null || match[1] === undefined) {
      return ''
    }
    try {
      const decoded = JSON.parse(match[0]) as Record<string, Object>
      const title = decoded['title']
      if (typeof title === 'string') {
        return AiNoteTitleService.cleanTitleText(title)
      }
    } catch (_) {
      return AiNoteTitleService.cleanTitleText(match[1].replace(/\\"/g, '"').replace(/\\\\/g, '\\'))
    }
    return ''
  }

  private static cleanTitleText(raw: string): string {
    let text = raw.trim()
    if (text.length === 0) {
      return ''
    }
    text = text.replace(/[\r\n\t]+/g, '')
    text = text.replace(/^[#【\[（「《"']+|[#】\]）」》"']+$/g, '')
    text = text.replace(/^(标题|title)[:：]\s*/i, '')
    return text.trim()
  }

  private static extractAssistantPayload(obj: Object): MiniMaxAssistantPayload {
    const empty: MiniMaxAssistantPayload = { content: '', reasoningContent: '' }
    const rec = obj as Record<string, Object>
    const choices = rec['choices']
    if (!Array.isArray(choices) || choices.length === 0) {
      return empty
    }
    const first = choices[0] as Record<string, Object>
    const message = first['message'] as Record<string, Object> | undefined
    if (message === undefined) {
      return empty
    }
    return {
      content: AiNoteTitleService.normalizeMessageContent(message['content']),
      reasoningContent: AiNoteTitleService.normalizeMessageContent(message['reasoning_content'])
    }
  }

  private static ensureMiniMaxResponseOk(data: Object): void {
    const rec = data as Record<string, Object>
    const baseResp = rec['base_resp'] as Record<string, Object> | undefined
    if (baseResp !== undefined) {
      const code = baseResp['status_code']
      let codeNum = 0
      if (typeof code === 'number') {
        codeNum = Math.trunc(code)
      } else if (typeof code === 'string') {
        const n = Number.parseInt(code, 10)
        codeNum = Number.isNaN(n) ? 0 : n
      }
      if (codeNum !== 0) {
        throw new Error('AI 服务暂时不可用，请稍后重试')
      }
    }
    if (rec['error'] !== undefined && rec['error'] !== null) {
      throw new Error('AI 服务暂时不可用，请稍后重试')
    }
    const choices = rec['choices']
    if (!Array.isArray(choices) || choices.length === 0) {
      throw new Error('AI 未返回有效内容')
    }
  }

  private static normalizeMessageContent(content: Object | undefined): string {
    if (content === undefined || content === null) {
      return ''
    }
    if (typeof content === 'string') {
      return content
    }
    return `${content}`
  }
}
