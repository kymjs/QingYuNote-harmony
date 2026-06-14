import type { CreateNoteInput, Note, UpdateNoteInput } from '../common/model/Note'
import { Logger } from '../common/utils/Logger'
import { HtmlToMarkdown } from '../common/utils/HtmlToMarkdown'
import { SyncConstants, YinxiangImportToastPayload } from '../common/constants/SyncConstants'
import { AppContextHolder } from './AppContextHolder'
import { NoteRepository } from './NoteRepository'
import { PreferencesService } from './PreferencesService'
import {
  EvernoteNoteStoreClient,
  EvernoteNoteStoreException,
  EvernoteResource
} from './EvernoteNoteStoreClient'
import fs from '@ohos.file.fs'

const YINXIANG_NOTE_TAG = '印象笔记'
const YINXIANG_USER_DATA_KEY_GUID = 'yinxiangGuid'
const YINXIANG_IMAGES_DIR = 'qingyu-note-image'

export class YinxiangImportProgress {
  processedNotes: number = 0
  totalNotes: number = 0
  currentNoteTitle: string = ''
}

export class YinxiangImportResult {
  importedCount: number = 0
  skippedCount: number = 0
}

export class YinxiangImportException extends Error {
  constructor(message: string) {
    super(message)
    this.name = 'YinxiangImportException'
  }
}

/** 内部哨兵异常：由 YinxiangImportService.cancelImport 触发（例如登出），
 *  由外层 try/catch 静默吞掉，不弹 toast、不向上抛。 */
export class YinxiangImportCancelledException extends Error {
  constructor() {
    super('yinxiang_import_cancelled')
    this.name = 'YinxiangImportCancelledException'
  }
}

interface YinxiangNoteMeta {
  guid: string
  title: string
}

interface YinxiangUserDataMeta {
  guid: string
}

class YinxiangImportIndex {
  private byGuid: Map<string, Note> = new Map()

  register(note: Note, guid: string): void {
    this.byGuid.set(guid, this.preferNewer(this.byGuid.get(guid), note))
  }

  findNoteId(guid: string): string {
    const note = this.byGuid.get(guid)
    return note !== undefined ? note.id : ''
  }

  noteCount(): number {
    return this.byGuid.size
  }

  private preferNewer(existing: Note | undefined, candidate: Note): Note {
    if (existing === undefined) {
      return candidate
    }
    return candidate.updatedAt >= existing.updatedAt ? candidate : existing
  }
}

export class YinxiangImportService {
  private static instance: YinxiangImportService = new YinxiangImportService()
  private inFlight: Promise<YinxiangImportResult> | null = null
  private running: boolean = false
  private currentProgress: YinxiangImportProgress | null = null
  private cancelled: boolean = false
  private noteStoreClient: EvernoteNoteStoreClient = new EvernoteNoteStoreClient()
  private noteStoreUrl: string = ''

  static getInstance(): YinxiangImportService {
    return YinxiangImportService.instance
  }

  isImportRunning(): boolean {
    return this.running
  }

  getProgress(): YinxiangImportProgress | null {
    return this.currentProgress
  }

  importAllNotes(
    apiKey: string,
    onProgress?: (progress: YinxiangImportProgress) => void
  ): Promise<YinxiangImportResult> {
    Logger.info('YinxiangImport', `importAllNotes: 收到导入请求, keyLen=${apiKey.trim().length}, keyPrefix=${apiKey.trim().substring(0, Math.min(4, apiKey.trim().length))}…`)
    if (this.inFlight !== null) {
      Logger.info('YinxiangImport', 'importAllNotes: 已有任务在跑, 复用旧 Promise')
      return this.inFlight
    }
    this.running = true
    this.cancelled = false
    this.inFlight = this.importAllNotesImpl(apiKey, onProgress).finally(() => {
      this.running = false
      this.inFlight = null
      this.currentProgress = null
      this.cancelled = false
    })
    return this.inFlight
  }

  /** 中止正在进行的导入任务（如登出场景）。多次调用安全；无正在进行的任务时为 no-op。 */
  async cancelImport(): Promise<void> {
    const inFlight = this.inFlight
    if (inFlight === null) {
      return
    }
    this.cancelled = true
    try {
      await inFlight
    } catch (_) {
      // 取消引发的异常已在 importAllNotesImpl 内部吞掉，这里再兜一层；
      // 其余导入失败本身就是该任务的预期返回路径，不在 cancel 流程里处理。
    }
  }

  private throwIfCancelled(): void {
    if (this.cancelled) {
      throw new YinxiangImportCancelledException()
    }
  }

  private async importAllNotesImpl(
    apiKey: string,
    onProgress?: (progress: YinxiangImportProgress) => void
  ): Promise<YinxiangImportResult> {
    const token = apiKey.trim()
    if (token.length === 0) {
      Logger.warn('YinxiangImport', 'importAllNotesImpl: token 为空, 抛错')
      throw new YinxiangImportException('请输入印象笔记 Developer Token')
    }

    try {
      Logger.info('YinxiangImport', 'importAllNotesImpl: 持久化 Developer Token')
      await PreferencesService.getInstance().setYinxiangApiKey(token)
      const noteStoreUrl = PreferencesService.getInstance().getYinxiangNoteStoreUrl().trim()
      if (noteStoreUrl.length === 0) {
        throw new YinxiangImportException('缺少 NoteStore URL，请重新获取 API Key')
      }
      this.noteStoreUrl = noteStoreUrl
      Logger.info('YinxiangImport',
        `importAllNotesImpl: noteStoreUrl=${this.noteStoreUrl} tokenLen=${token.length}`)
      const notes: YinxiangNoteMeta[] = []
      await this.fetchAllNotes(token, notes)
      Logger.info('YinxiangImport', `importAllNotesImpl: 拉取完成, rawNotes=${notes.length}`)
      notes.forEach((n) => {
        Logger.info('YinxiangImport', `  raw note: guid=${n.guid} title=${n.title}`)
      })

      if (notes.length === 0) {
        Logger.warn('YinxiangImport', 'importAllNotesImpl: 笔记列表为空, 认为没有可导入内容')
        const empty = new YinxiangImportResult()
        this.emitToast(this.completionMessage(empty))
        return empty
      }

      Logger.info('YinxiangImport', 'importAllNotesImpl: 初始化仓库, 构建去重索引')
      await NoteRepository.getInstance().init()
      const importIndex = await this.buildImportIndex()
      Logger.info('YinxiangImport', `importAllNotesImpl: 索引已建立, 已导入 note=${importIndex.noteCount()}`)
      NoteRepository.getInstance().beginBulkNotification()
      let imported = 0
      let skipped = 0
      try {
        Logger.info('YinxiangImport', `importAllNotesImpl: 总笔记数 totalNotes=${notes.length}`)
        this.emitProgress({
          processedNotes: 0,
          totalNotes: notes.length,
          currentNoteTitle: ''
        }, onProgress)

        for (let i = 0; i < notes.length; i++) {
          this.throwIfCancelled()
          const note = notes[i]
          this.emitProgress({
            processedNotes: i,
            totalNotes: notes.length,
            currentNoteTitle: note.title
          }, onProgress)
          const count = await this.importSingleNote(token, note, importIndex)
          if (count === 0) {
            skipped += 1
            Logger.info('YinxiangImport', `importAllNotesImpl: 内容为空, 跳过 guid=${note.guid}`)
          } else {
            imported += count
            Logger.info('YinxiangImport', `importAllNotesImpl: 累计 imported=${imported}, skipped=${skipped}`)
          }
        }
        Logger.info('YinxiangImport', `importAllNotesImpl: 遍历完成, 最终 imported=${imported}, skipped=${skipped}`)

        this.emitProgress({
          processedNotes: notes.length,
          totalNotes: notes.length,
          currentNoteTitle: ''
        }, onProgress)
      } finally {
        NoteRepository.getInstance().endBulkNotification()
      }

      const result = new YinxiangImportResult()
      result.importedCount = imported
      result.skippedCount = skipped
      Logger.info('YinxiangImport', `importAllNotesImpl: 返回结果 imported=${result.importedCount}, skipped=${result.skippedCount}`)
      this.emitToast(this.completionMessage(result))
      return result
    } catch (error) {
      if (error instanceof YinxiangImportCancelledException) {
        Logger.info('YinxiangImport', 'importAllNotesImpl: 任务被取消')
        return new YinxiangImportResult()
      }
      if (error instanceof EvernoteNoteStoreException) {
        Logger.error('YinxiangImport', `importAllNotesImpl: NoteStore error: ${error.message}`)
        const message = error.message.includes('401') || error.message.includes('403')
          ? 'Developer Token 无效或已过期，请重新获取'
          : error.message
        this.emitToast(message)
        throw new YinxiangImportException(message)
      }
      if (error instanceof YinxiangImportException) {
        Logger.error('YinxiangImport', `importAllNotesImpl: YinxiangImportException: ${error.message}`)
        this.emitToast(error.message)
        throw error
      }
      Logger.error('YinxiangImport', `importAllNotesImpl: 未捕获异常: ${JSON.stringify(error)}`)
      this.emitToast('导入失败，请稍后重试')
      throw error instanceof Error ? error : new YinxiangImportException('导入失败，请稍后重试')
    }
  }

  private emitProgress(
    progress: YinxiangImportProgress,
    onProgress?: (progress: YinxiangImportProgress) => void
  ): void {
    this.currentProgress = progress
    onProgress?.(progress)
  }

  private completionMessage(result: YinxiangImportResult): string {
    if (result.importedCount === 0 && result.skippedCount === 0) {
      return '没有可导入的笔记'
    }
    const skipPart = result.skippedCount > 0 ? `，${result.skippedCount} 条为空` : ''
    return `已导入 ${result.importedCount} 条笔记${skipPart}`
  }

  private emitToast(message: string): void {
    if (message.trim().length === 0) {
      return
    }
    try {
      const hub = AppContextHolder.tryGetContext()?.eventHub
      hub?.emit(
        SyncConstants.yinxiangImportToastEvent,
        new YinxiangImportToastPayload(message.trim())
      )
    } catch (_) {
    }
  }

  private async importSingleNote(
    token: string,
    note: YinxiangNoteMeta,
    index: YinxiangImportIndex
  ): Promise<number> {
    Logger.info('YinxiangImport', `importSingleNote: 开始 guid=${note.guid} title=${note.title}`)
    let payload: Record<string, Object>
    try {
      payload = await this.readNote(token, note.guid)
    } catch (error) {
      Logger.error('YinxiangImport', `importSingleNote: 读内容失败 guid=${note.guid} err=${JSON.stringify(error)}`)
      throw error instanceof Error ? error : new YinxiangImportException('导入失败，请稍后重试')
    }
    Logger.info('YinxiangImport', `importSingleNote: read 返回 keys=${Object.keys(payload).join(',')}`)
    const rawContent = `${payload['content'] ?? ''}`
    const hashToPath = payload['hashToPath'] as Map<string, string> | undefined
    const content = this.enmlToMarkdown(rawContent, hashToPath ?? new Map())
    Logger.info('YinxiangImport', `importSingleNote: 转换后内容长度=${content.length}`)
    if (content.trim().length === 0) {
      Logger.info('YinxiangImport', `importSingleNote: 内容为空, 跳过 guid=${note.guid}`)
      return 0
    }

    const trimmedTitle = note.title.trim()
    const title = trimmedTitle.length > 0 ? trimmedTitle : this.fallbackTitleFromContent(content)
    const tag = YINXIANG_NOTE_TAG
    const existingId = index.findNoteId(note.guid)
    if (existingId.length > 0) {
      Logger.info('YinxiangImport', `importSingleNote: 已存在, 走更新 id=${existingId}`)
      const patch: UpdateNoteInput = {
        title: title,
        content: content,
        tags: [tag]
      }
      try {
        await NoteRepository.getInstance().saveDraft(existingId, patch)
      } catch (error) {
        Logger.error('YinxiangImport', `importSingleNote: saveDraft 失败 err=${JSON.stringify(error)}`)
        throw error instanceof Error ? error : new YinxiangImportException('导入失败，请稍后重试')
      }
      return 1
    }
    Logger.info('YinxiangImport', `importSingleNote: 新建笔记 title=${title}, guid=${note.guid}`)
    const input: CreateNoteInput = {
      title: title,
      content: content,
      tags: [tag],
      userData: this.yinxiangUserData(note.guid)
    }
    let created: Note
    try {
      created = await NoteRepository.getInstance().createNote(input)
    } catch (error) {
      Logger.error('YinxiangImport', `importSingleNote: createNote 失败 err=${JSON.stringify(error)}`)
      throw error instanceof Error ? error : new YinxiangImportException('导入失败，请稍后重试')
    }
    Logger.info('YinxiangImport', `importSingleNote: createNote 成功 id=${created.id}`)
    index.register(created, note.guid)
    return 1
  }

  /** ENML → Markdown：先处理印象笔记专有标签，再用 HtmlToMarkdown 转换表格等 HTML 结构。 */
  private enmlToMarkdown(raw: string, hashToPath: Map<string, string>): string {
    if (raw.length === 0) {
      return ''
    }
    let html = this.decodeHtmlEntities(raw)
    html = html.replace(/<en-todo\s+checked="(true|false)"\s*\/?>/gi,
      (_match, checked: string) => checked === 'true' ? '[-] ' : '[ ] ')
    html = this.replaceEnMediaTags(html, hashToPath)
    html = this.replaceEvernoteCidImages(html, hashToPath)
    html = this.unwrapEnmlDocument(html)

    let markdown: string
    try {
      markdown = HtmlToMarkdown.convert(html.trim())
    } catch (_) {
      markdown = html.replace(/<[^>]+>/g, '')
    }
    markdown = this.replaceEvernoteCidImages(markdown, hashToPath)
    markdown = this.stripUrlEncodedGarbageLines(markdown)
    return this.collapseBlankLines(markdown)
  }

  private replaceEnMediaTags(html: string, hashToPath: Map<string, string>): string {
    return html.replace(/<en-media[^>]*hash=["']?([^"'\s>]+)["']?[^>]*(?:\/>|>\s*<\/en-media>)/gi,
      (_match, hash: string) => this.imageMarkdownForResource(hashToPath, hash, ''))
  }

  private replaceEvernoteCidImages(text: string, hashToPath: Map<string, string>): string {
    let result = text.replace(/!\[([^\]]*)\]\((evernotecid:\/\/[^)]+)\)/gi,
      (_match, alt: string, url: string) =>
        this.imageMarkdownForResource(hashToPath, this.extractHashFromAlt(alt), this.extractGuidFromEvernoteCid(url)))
    result = result.replace(/<img[^>]+src=["']?(evernotecid:\/\/[^"'\s>]+)["']?[^>]*>/gi,
      (_match, url: string) =>
        this.imageMarkdownForResource(hashToPath, '', this.extractGuidFromEvernoteCid(url)))
    result = result.replace(/<a[^>]+href=["']?(evernotecid:\/\/[^"'\s>]+)["']?[^>]*>[\s\S]*?<\/a>/gi,
      (_match, url: string) =>
        this.imageMarkdownForResource(hashToPath, '', this.extractGuidFromEvernoteCid(url)))
    return result
  }

  private imageMarkdownForResource(
    hashToPath: Map<string, string>,
    hash: string,
    guid: string
  ): string {
    const rel = this.lookupResourcePath(hashToPath, hash, guid)
    if (rel !== undefined && rel.length > 0) {
      return `![图片](${rel})`
    }
    return '[图片]'
  }

  private lookupResourcePath(
    hashToPath: Map<string, string>,
    hash: string,
    guid: string
  ): string | undefined {
    const keys = this.resourceLookupKeys(hash, guid)
    for (let i = 0; i < keys.length; i++) {
      const rel = hashToPath.get(keys[i])
      if (rel !== undefined && rel.length > 0) {
        return rel
      }
    }
    return undefined
  }

  private resourceLookupKeys(hash: string, guid: string): string[] {
    const keys: string[] = []
    const normalizedHash = hash.trim().toLowerCase()
    if (normalizedHash.length > 0) {
      keys.push(normalizedHash)
    }
    const normalizedGuid = guid.trim().toLowerCase()
    if (normalizedGuid.length > 0) {
      keys.push(normalizedGuid)
      keys.push(normalizedGuid.replace(/-/g, ''))
    }
    return keys
  }

  private extractGuidFromEvernoteCid(url: string): string {
    const match = /evernotecid:\/\/([^/\s]+)/i.exec(url)
    return match !== null && match[1] !== undefined ? match[1].trim() : ''
  }

  private extractHashFromAlt(alt: string): string {
    const match = /([a-f0-9]{32})/i.exec(alt)
    return match !== null && match[1] !== undefined ? match[1].trim() : ''
  }

  private stripUrlEncodedGarbageLines(text: string): string {
    const lines = text.split('\n')
    const kept: string[] = []
    for (let i = 0; i < lines.length; i++) {
      const trimmed = lines[i].trim()
      if (trimmed.length === 0) {
        if (kept.length > 0 && kept[kept.length - 1].length > 0) {
          kept.push('')
        }
        continue
      }
      if (this.isMostlyUrlEncoded(trimmed)) {
        continue
      }
      kept.push(lines[i].replace(/\s+$/, ''))
    }
    while (kept.length > 0 && kept[kept.length - 1].length === 0) {
      kept.pop()
    }
    return kept.join('\n')
  }

  private isMostlyUrlEncoded(line: string): boolean {
    if (!line.includes('%')) {
      return false
    }
    const matches = line.match(/%[0-9A-Fa-f]{2}/g)
    const encodedLength = matches !== null ? matches.length * 3 : 0
    return encodedLength * 2 >= line.length
  }

  private unwrapEnmlDocument(raw: string): string {
    let html = raw
    html = html.replace(/<\?xml[^?]*\?>/, '')
    html = html.replace(/<!DOCTYPE[^>]*>/i, '')
    const match = /<en-note[^>]*>([\s\S]*)<\/en-note>/i.exec(html)
    if (match !== null && match[1] !== undefined) {
      html = match[1]
    }
    return html
  }

  private collapseBlankLines(text: string): string {
    const lines: string[] = []
    const rawLines = text.split('\n')
    for (let i = 0; i < rawLines.length; i++) {
      const t = rawLines[i].trim()
      if (t.length === 0) {
        if (lines.length > 0 && lines[lines.length - 1].length > 0) {
          lines.push('')
        }
        continue
      }
      lines.push(t)
    }
    while (lines.length > 0 && lines[lines.length - 1].length === 0) {
      lines.pop()
    }
    return lines.join('\n')
  }

  private decodeHtmlEntities(raw: string): string {
    return raw
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&apos;/g, "'")
      .replace(/&nbsp;/g, ' ')
  }

  private fallbackTitleFromContent(content: string): string {
    const lines = content.split('\n')
    for (const line of lines) {
      const t = line.trim()
      if (t.length === 0) {
        continue
      }
      if (t.startsWith('>')) {
        continue
      }
      if (t.length <= 20) {
        return t
      }
      return t.substring(0, 20)
    }
    return '印象笔记'
  }

  private yinxiangUserData(guid: string): string {
    const payload: Record<string, string> = {}
    payload[YINXIANG_USER_DATA_KEY_GUID] = guid
    return JSON.stringify(payload)
  }

  private parseYinxiangUserData(userData: string): YinxiangUserDataMeta | undefined {
    const trimmed = userData.trim()
    if (trimmed.length === 0) {
      return undefined
    }
    try {
      const parsed = JSON.parse(trimmed) as Record<string, Object>
      const guid = `${parsed[YINXIANG_USER_DATA_KEY_GUID] ?? ''}`.trim()
      if (guid.length === 0) {
        return undefined
      }
      const meta: YinxiangUserDataMeta = {
        guid: guid
      }
      return meta
    } catch (_) {
      return undefined
    }
  }

  private async buildImportIndex(): Promise<YinxiangImportIndex> {
    const index = new YinxiangImportIndex()
    const notes = await NoteRepository.getInstance().listAllNotes()
    for (const note of notes) {
      if (note.deleted || note.deletedTime > 0) {
        continue
      }
      const meta = this.parseYinxiangUserData(note.userData)
      if (meta === undefined) {
        continue
      }
      index.register(note, meta.guid)
    }
    return index
  }

  /** 分页拉取所有笔记的元信息（NoteStore.findNotesMetadata）。 */
  private async fetchAllNotes(token: string, into: YinxiangNoteMeta[]): Promise<void> {
    let offset: number = 0
    const pageSize: number = 100
    while (true) {
      this.throwIfCancelled()
      Logger.info('YinxiangImport', `fetchAllNotes: offset=${offset} noteStoreUrl=${this.noteStoreUrl}`)
      const page = await this.noteStoreClient.findNotesMetadata(
        this.noteStoreUrl,
        token,
        offset,
        pageSize
      )
      Logger.info('YinxiangImport',
        `fetchAllNotes: offset=${offset} got=${page.notes.length} totalNotes=${page.totalNotes}`)
      for (const note of page.notes) {
        const guid = note.guid.trim()
        if (guid.length === 0) {
          continue
        }
        into.push({ guid: guid, title: note.title.trim() })
      }
      offset += page.notes.length
      if (page.notes.length === 0 || offset >= page.totalNotes) {
        break
      }
    }
  }

  /** 读取单条笔记的 ENML 正文与附件资源。 */
  private async readNote(token: string, guid: string): Promise<Record<string, Object>> {
    this.throwIfCancelled()
    Logger.info('YinxiangImport', `readNote: 读取 guid=${guid}`)
    const note = await this.noteStoreClient.getNote(this.noteStoreUrl, token, guid)
    const resources = await this.collectResources(note.content, note.resources, token)
    const hashToPath = await this.saveResources(resources, token)
    Logger.info('YinxiangImport',
      `readNote: guid=${guid} contentLen=${note.content.length} inlineResources=${note.resources.length} fetchedResources=${resources.length} savedImages=${hashToPath.size}`)
    const result: Record<string, Object> = {}
    result['content'] = note.content
    result['hashToPath'] = hashToPath
    return result
  }

  /** 印象笔记 getNote 常不返回 resources，需从 ENML 里的 evernotecid GUID 单独拉取。 */
  private async collectResources(
    content: string,
    inlineResources: EvernoteResource[],
    token: string
  ): Promise<EvernoteResource[]> {
    const merged: EvernoteResource[] = []
    for (let i = 0; i < inlineResources.length; i++) {
      merged.push(inlineResources[i])
    }
    const knownGuids = new Set<string>()
    for (let i = 0; i < merged.length; i++) {
      const key = merged[i].guid.trim().toLowerCase()
      if (key.length > 0) {
        knownGuids.add(key)
      }
    }
    const refGuids = this.extractResourceGuidsFromContent(content)
    Logger.info('YinxiangImport',
      `collectResources: inline=${inlineResources.length} evernotecidRefs=${refGuids.length}`)
    for (let i = 0; i < refGuids.length; i++) {
      const guid = refGuids[i].trim()
      const key = guid.toLowerCase()
      if (guid.length === 0 || knownGuids.has(key)) {
        continue
      }
      knownGuids.add(key)
      try {
        const resource = await this.noteStoreClient.getResource(
          this.noteStoreUrl,
          token,
          guid
        )
        Logger.info('YinxiangImport',
          `collectResources: getResource guid=${guid} bodyLen=${resource.body.length} mime=${resource.mime}`)
        merged.push(resource)
      } catch (error) {
        Logger.warn('YinxiangImport',
          `collectResources: getResource failed guid=${guid} err=${JSON.stringify(error)}`)
      }
    }
    return merged
  }

  private extractResourceGuidsFromContent(content: string): string[] {
    const guids: string[] = []
    const seen = new Set<string>()
    const decoded = this.decodeHtmlEntities(content)
    const regex = /evernotecid:\/\/([^/\s"'<>]+)/gi
    let match: RegExpExecArray | null = regex.exec(decoded)
    while (match !== null) {
      const guid = (match[1] ?? '').trim()
      const key = guid.toLowerCase()
      if (guid.length > 0 && !seen.has(key)) {
        seen.add(key)
        guids.push(guid)
      }
      match = regex.exec(decoded)
    }
    return guids
  }

  private async saveResources(resources: EvernoteResource[], token: string): Promise<Map<string, string>> {
    const hashToPath = new Map<string, string>()
    if (resources.length === 0) {
      return hashToPath
    }
    const ctx = AppContextHolder.tryGetContext()
    if (ctx === undefined) {
      Logger.warn('YinxiangImport', 'saveResources: context unavailable')
      return hashToPath
    }
    const imagesDir = `${ctx.filesDir ?? ''}/${YINXIANG_IMAGES_DIR}`
    try {
      if (!fs.accessSync(imagesDir)) {
        fs.mkdirSync(imagesDir, true)
      }
    } catch (_) {
      fs.mkdirSync(imagesDir, true)
    }
    for (const resource of resources) {
      let body = resource.body
      if (body.length === 0 && resource.guid.trim().length > 0) {
        try {
          body = await this.noteStoreClient.getResourceData(
            this.noteStoreUrl,
            token,
            resource.guid.trim()
          )
          Logger.info('YinxiangImport',
            `saveResources: getResourceData guid=${resource.guid} len=${body.length}`)
        } catch (error) {
          Logger.warn('YinxiangImport',
            `saveResources: getResourceData failed guid=${resource.guid} err=${JSON.stringify(error)}`)
        }
      }
      if (body.length === 0) {
        continue
      }
      const hash = resource.bodyHashHex.trim().toLowerCase()
      if (hash.length > 0 && hashToPath.has(hash)) {
        continue
      }
      try {
        const ext = this.extFromMime(resource.mime, body)
        const fileName = this.randomImageFileName(ext)
        const destPath = `${imagesDir}/${fileName}`
        const file = fs.openSync(destPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC)
        fs.writeSync(file.fd, body.buffer.slice(body.byteOffset, body.byteOffset + body.byteLength))
        fs.closeSync(file)
        const relPath = `${YINXIANG_IMAGES_DIR}/${fileName}`
        this.registerResourcePath(hashToPath, relPath, hash, resource.guid)
      } catch (error) {
        Logger.warn('YinxiangImport',
          `saveResources: failed hash=${hash} guid=${resource.guid} err=${JSON.stringify(error)}`)
      }
    }
    return hashToPath
  }

  private registerResourcePath(
    map: Map<string, string>,
    relPath: string,
    hash: string,
    guid: string
  ): void {
    if (hash.length > 0) {
      map.set(hash, relPath)
    }
    const normalizedGuid = guid.trim().toLowerCase()
    if (normalizedGuid.length > 0) {
      map.set(normalizedGuid, relPath)
      map.set(normalizedGuid.replace(/-/g, ''), relPath)
    }
  }

  private extFromMime(mime: string, bytes: Uint8Array): string {
    const lower = mime.trim().toLowerCase()
    if (lower.includes('jpeg') || lower.includes('jpg')) {
      return '.jpg'
    }
    if (lower.includes('png')) {
      return '.png'
    }
    if (lower.includes('gif')) {
      return '.gif'
    }
    if (lower.includes('webp')) {
      return '.webp'
    }
    if (lower.includes('bmp')) {
      return '.bmp'
    }
    if (lower.includes('svg')) {
      return '.svg'
    }
    return this.guessExtFromBytes(bytes)
  }

  private guessExtFromBytes(bytes: Uint8Array): string {
    if (bytes.length >= 3 && bytes[0] === 0xFF && bytes[1] === 0xD8 && bytes[2] === 0xFF) {
      return '.jpg'
    }
    if (bytes.length >= 8 && bytes[0] === 0x89 && bytes[1] === 0x50 &&
      bytes[2] === 0x4E && bytes[3] === 0x47) {
      return '.png'
    }
    if (bytes.length >= 6 && bytes[0] === 0x47 && bytes[1] === 0x49 && bytes[2] === 0x46) {
      return '.gif'
    }
    return '.png'
  }

  private randomImageFileName(ext: string): string {
    const safeExt = ext.startsWith('.') ? ext : `.${ext}`
    const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789'
    let randomPart = ''
    for (let i = 0; i < 6; i += 1) {
      randomPart += alphabet.charAt(Math.floor(Math.random() * alphabet.length))
    }
    return `${Date.now()}_${randomPart}${safeExt}`
  }
}