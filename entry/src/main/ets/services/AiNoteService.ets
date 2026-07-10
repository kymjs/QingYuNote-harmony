import { http } from '@kit.NetworkKit'
import { AiNoteImageLoader, AiNoteImagePayload } from './AiNoteImageLoader'
import { AiNotePrompt } from './AiNotePrompt'
import { AiTagService } from './AiTagService'
import { LinkExtractClient } from './LinkExtractClient'
import { NoteApiClient, AiTagConfigBody, buildChatCompletionRequestBody } from './NoteApiClient'
import { MarkdownUtils } from '../common/utils/MarkdownUtils'
import { NoteStateCodec } from '../common/utils/NoteStateCodec'

export interface AiLinkSummaryResult {
  title: string
  body: string
}

/** 链接提取后笔记标题：占位标题可被 API/正文解析结果覆盖。 */
export class AiLinkExtractTitle {
  static isPlaceholderNoteTitle(title: string): boolean {
    const trimmed = title.trim()
    return trimmed.length === 0 || trimmed === '未命名笔记'
  }

  static resolve(apiTitle: string, body: string): string {
    let title = apiTitle.trim()
    if (title.length === 0) {
      title = MarkdownUtils.splitLinkSummary(body).title.trim()
    }
    if (title.length === 0 && body.trim().length > 0) {
      title = MarkdownUtils.extractTitle(body)
    }
    if (title.length === 0 || title === '未命名笔记') {
      return '链接笔记'
    }
    return title
  }
}

interface MiniMaxAssistantPayload {
  content: string
  reasoningContent: string
  finishReason: string
}

interface ChatTextMessage {
  role: string
  content: string
}

interface ChatTextContentPart {
  type: string
  text: string
}

interface ChatImageUrlDetail {
  url: string
  detail: string
}

interface ChatImageContentPart {
  type: string
  image_url: ChatImageUrlDetail
}

type ChatUserContentPart = ChatTextContentPart | ChatImageContentPart

interface ChatMultimodalUserMessage {
  role: string
  content: ChatUserContentPart[]
}

type ChatMessage = ChatTextMessage | ChatMultimodalUserMessage

export class AiNoteService {
  private static instance: AiNoteService = new AiNoteService()

  static getInstance(): AiNoteService {
    return AiNoteService.instance
  }

  async optimizeContent(content: string, filesBasePath: string = ''): Promise<string> {
    const trimmed = content.trim()
    const hasImageRefs = NoteStateCodec.extractImageRefs(content).length > 0
    const noteHasText = NoteStateCodec.hasSubstantiveNoteText(content)
    if (!noteHasText && !hasImageRefs) {
      throw new Error('笔记正文为空，无法优化')
    }
    const images = AiNoteImageLoader.loadFromNote(content, filesBasePath)
    if (images.length === 0) {
      if (!noteHasText) {
        throw new Error('笔记图片未找到或无法读取，无法优化')
      }
      return AiNoteService.chatPlainText(
        AiNotePrompt.OPTIMIZE_SYSTEM,
        AiNotePrompt.buildOptimizeUserMessage(trimmed),
        0.3,
        8192,
        true
      )
    }
    const optimized = await AiNoteService.chatWithImages(
      AiNotePrompt.OPTIMIZE_WITH_IMAGES_SYSTEM,
      AiNotePrompt.buildOptimizeWithImagesUserMessage(content, images.length, noteHasText),
      images,
      0.35,
      8192
    )
    return NoteStateCodec.mergeOptimizedWithTrailingImages(content, optimized)
  }

  async summarizeLink(url: string, summarize: number = 0): Promise<AiLinkSummaryResult> {
    const link = url.trim()
    if (link.length === 0) {
      throw new Error('请输入有效链接')
    }
    try {
      const prompt = AiNotePrompt.buildLinkSummaryUserMessage(link, '')
      const extracted = await LinkExtractClient.getInstance().extractLink(link, prompt, summarize)
      console.info(`LinkExtract summarizeLink via server2 ok`)
      if (extracted.content.length === 0) {
        throw new Error('AI 未返回有效内容')
      }
      return {
        title: extracted.title,
        body: extracted.content
      }
    } catch (e) {
      const msg = (e instanceof Error) ? e.message : `${e}`
      if (e instanceof Error && e.message === '未登录或服务不可用') {
        console.error(`LinkExtract summarizeLink unauthorized, NOT falling back`)
        throw e
      }
      if (LinkExtractClient.isVideoPlatformUrl(link)) {
        console.error(`LinkExtract summarizeLink video platform failed, NOT falling back. reason=${msg}`)
        throw e instanceof Error ? e : new Error(msg)
      }
      console.error(`LinkExtract summarizeLink server2 failed, fallback to LOCAL. reason=${msg}`)
      return AiNoteService.summarizeLinkLocally(link, summarize)
    }
  }

  private static async summarizeLinkLocally(link: string, summarize: number = 0): Promise<AiLinkSummaryResult> {
    const excerpt = await AiNoteService.fetchPageExcerpt(link)
    if (summarize === 0) {
      const title = AiNoteService.titleFromExcerpt(excerpt) ?? '链接笔记'
      const body = excerpt.trim().length > 0 ? excerpt.trim() : link
      return { title, body }
    }
    const raw = await AiNoteService.chatPlainText(
      AiNotePrompt.LINK_SUMMARY_SYSTEM,
      AiNotePrompt.buildLinkSummaryUserMessage(link, excerpt),
      0.4,
      1024,
      true
    )
    const parts = MarkdownUtils.splitLinkSummary(raw)
    return {
      title: parts.title,
      body: parts.body.length > 0 ? parts.body : raw.trim()
    }
  }

  private static titleFromExcerpt(excerpt: string): string | null {
    const lines = excerpt.split('\n')
    for (let i = 0; i < lines.length; i++) {
      let cleaned = lines[i].trim()
      if (cleaned.startsWith('#')) {
        cleaned = cleaned.replace(/^#+\s*/, '')
      }
      if (cleaned.length === 0) {
        continue
      }
      const runes = Array.from(cleaned)
      if (runes.length <= 40) {
        return cleaned
      }
      return runes.slice(0, 40).join('')
    }
    return null
  }

  private static async chatPlainText(
    system: string,
    user: string,
    temperature: number,
    maxTokens: number,
    reasoningSplit: boolean
  ): Promise<string> {
    const config = await AiNoteService.requireConfig()
    const messages: ChatTextMessage[] = [
      { role: 'system', content: system },
      { role: 'user', content: user }
    ]
    return AiNoteService.postChatCompletion(
      config,
      config.model,
      messages,
      temperature,
      maxTokens,
      reasoningSplit
    )
  }

  private static async chatWithImages(
    system: string,
    userText: string,
    images: AiNoteImagePayload[],
    temperature: number,
    maxTokens: number
  ): Promise<string> {
    const config = await AiNoteService.requireConfig()
    const userContent: ChatUserContentPart[] = [{ type: 'text', text: userText }]
    for (let i = 0; i < images.length; i++) {
      const imagePart: ChatImageContentPart = {
        type: 'image_url',
        image_url: {
          url: images[i].dataUrl,
          detail: 'default'
        }
      }
      userContent.push(imagePart)
    }
    const messages: ChatMessage[] = [
      { role: 'system', content: system },
      { role: 'user', content: userContent }
    ]
    return AiNoteService.postChatCompletion(
      config,
      config.model,
      messages,
      temperature,
      maxTokens,
      false
    )
  }

  private static async requireConfig(): Promise<AiTagConfigBody> {
    const config = await NoteApiClient.getInstance().fetchAiTagConfig()
    if (config === null) {
      throw new Error('未登录或服务不可用')
    }
    return config
  }

  private static async postChatCompletion(
    config: AiTagConfigBody,
    model: string,
    messages: ChatMessage[],
    temperature: number,
    maxTokens: number,
    reasoningSplit: boolean
  ): Promise<string> {
    const base = config.base_url.replace(/\/+$/, '')
    const url = `${base}/chat/completions`
    const body = buildChatCompletionRequestBody(
      model,
      temperature,
      maxTokens,
      reasoningSplit,
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
        readTimeout: 120000
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
      AiNoteService.ensureMiniMaxResponseOk(obj, text)
      const assistant = AiNoteService.extractAssistantPayload(obj)
      let bodyText = AiTagService.extractAnswerBody(assistant.content)
      if (bodyText.length === 0 && assistant.reasoningContent.length > 0) {
        bodyText = AiTagService.extractAnswerBody(assistant.reasoningContent)
      }
      const result = bodyText.trim()
      if (result.length === 0) {
        throw new Error('AI 未返回有效内容')
      }
      return result
    } finally {
      req.destroy()
    }
  }

  private static async fetchPageExcerpt(linkUrl: string): Promise<string> {
    const req = http.createHttp()
    try {
      const resp = await req.request(linkUrl, {
        method: http.RequestMethod.GET,
        header: {
          'User-Agent': 'QingyuNotes/1.0'
        },
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 12000,
        readTimeout: 20000
      })
      if (resp.responseCode < 200 || resp.responseCode >= 400) {
        return ''
      }
      const html = (resp.result as string) ?? ''
      if (html.length === 0) {
        return ''
      }
      let text = html
        .replace(/<script[\s\S]*?<\/script>/gi, ' ')
        .replace(/<style[\s\S]*?<\/style>/gi, ' ')
        .replace(/<[^>]+>/g, ' ')
        .replace(/\s+/g, ' ')
        .trim()
      const runes = Array.from(text)
      if (runes.length > 6000) {
        text = runes.slice(0, 6000).join('')
      }
      return text
    } catch (_) {
      return ''
    } finally {
      req.destroy()
    }
  }

  private static ensureMiniMaxResponseOk(data: Object, rawText: string): void {
    const record = data as Record<string, Object>
    const baseResp = record['base_resp']
    if (baseResp !== undefined && baseResp !== null) {
      const br = baseResp as Record<string, Object>
      const code = Number(br['status_code'] ?? 0)
      if (code !== 0) {
        throw new Error('AI 服务暂时不可用，请稍后重试')
      }
    }
    if (record['error'] !== undefined && record['error'] !== null) {
      throw new Error('AI 服务暂时不可用，请稍后重试')
    }
    const choices = record['choices']
    if (!Array.isArray(choices) || choices.length === 0) {
      throw new Error('AI 未返回有效内容')
    }
  }

  private static extractAssistantPayload(data: Object): MiniMaxAssistantPayload {
    const empty: MiniMaxAssistantPayload = { content: '', reasoningContent: '', finishReason: '' }
    const record = data as Record<string, Object>
    const choices = record['choices']
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
      content: AiNoteService.normalizeMessageContent(message['content']),
      reasoningContent: AiNoteService.normalizeMessageContent(message['reasoning_content']),
      finishReason: finishReason
    }
  }

  private static normalizeMessageContent(content: Object | undefined): string {
    if (content === undefined || content === null) {
      return ''
    }
    if (typeof content === 'string') {
      return content
    }
    if (Array.isArray(content)) {
      let buf = ''
      const parts = content as Object[]
      for (let i = 0; i < parts.length; i++) {
        const part = parts[i]
        if (typeof part === 'object' && part !== null) {
          const p = part as Record<string, Object>
          if (typeof p['text'] === 'string') {
            buf += p['text'] as string
          }
        }
      }
      return buf
    }
    return `${content}`
  }
}
