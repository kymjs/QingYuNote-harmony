import type { CreateNoteInput, Note, UpdateNoteInput } from '../common/model/Note'
import { Logger } from '../common/utils/Logger'
import { YoudaoImportExportLogger } from '../common/utils/YoudaoImportExportLogger'
import { YoudaoNoteContentConverter } from '../common/utils/YoudaoNoteContentConverter'
import { SyncConstants, YoudaoImportToastPayload } from '../common/constants/SyncConstants'
import { AppContextHolder } from './AppContextHolder'
import { NoteRepository } from './NoteRepository'
import { PreferencesService } from './PreferencesService'
import { YoudaoMcpClient, YoudaoMcpException, YoudaoMcpToolResult } from './YoudaoMcpClient'
import { http } from '@kit.NetworkKit'
import fs from '@ohos.file.fs'

const YOUDAO_NOTE_TAG = '有道云笔记'
const YOUDAO_FOLDER_TAG = '有道云笔记'
const YOUDAO_KIND_FOLDER = 'folder'
const YOUDAO_KIND_NOTE = 'note'
const YOUDAO_USER_DATA_KEY_KIND = 'youdaoKind'
const YOUDAO_USER_DATA_KEY_REMOTE_ID = 'youdaoRemoteId'
const YOUDAO_USER_DATA_KEY_PARENT_REMOTE_ID = 'youdaoParentRemoteId'

/** 有道云 MCP 工具名（参考 youdaonote CLI 抓出的实际接口）。 */
const MCP_TOOL_LIST_NOTES = 'listNotes'
const MCP_TOOL_GET_NOTE_TEXT_CONTENT = 'getNoteTextContent'

export class YoudaoImportProgress {
  processedNotes: number = 0
  totalNotes: number = 0
  currentNoteTitle: string = ''
}

export class YoudaoImportResult {
  importedCount: number = 0
  skippedCount: number = 0
  plainTextNoteCount: number = 0
}

export class YoudaoImportException extends Error {
  constructor(message: string) {
    super(message)
    this.name = 'YoudaoImportException'
  }
}

/** 内部哨兵异常：由 YoudaoImportService.cancelImport 触发（例如登出），
 *  由外层 try/catch 静默吞掉，不弹 toast、不向上抛。 */
export class YoudaoImportCancelledException extends Error {
  constructor() {
    super('youdao_import_cancelled')
    this.name = 'YoudaoImportCancelledException'
  }
}

/** MCP `listNotes` 工具入参（与 youdaonote CLI `list -f` / `help --json` 一致）。 */
interface YoudaoListNotesArgs {
  parentId: string
  lastId?: string
}

/** 有道云根目录 parentId（CLI 默认 `-f 0`）。 */
const YOUDAO_ROOT_PARENT_ID = '0'
const YOUDAO_IMAGES_DIR = 'qingyu-note-image'
const YOUDAO_MARKDOWN_IMG_REGEX = /!\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g

/** 导入 `.note` 富文本笔记后向用户展示的说明（MCP 仅返回纯文本）。 */
export const YOUDAO_PLAIN_TEXT_NOTE_HINT =
  '有道API限制，只能返回纯文本，建议在有道云笔记中将笔记转为.md后再导入'

/** MCP `getNoteTextContent` 工具入参。 */
interface YoudaoGetNoteArgs {
  fileId: string
  convert?: boolean
  version?: number
  editorType?: number
}

interface YoudaoEntry {
  remoteId: string
  parentRemoteId: string
  title: string
  isFolder: boolean
}

interface YoudaoNode {
  remoteId: string
  parentRemoteId: string
  title: string
  isFolder: boolean
  children: YoudaoNode[]
}

interface YoudaoUserDataMeta {
  kind: string
  remoteId: string
}

/** `readNote` 的返回值类型。 */
interface ReadNoteResult {
  content: string
  rawFormat: string
  isRaw: boolean
}

interface YoudaoSingleImportOutcome {
  count: number
  plainTextNote: boolean
}

class YoudaoImportIndex {
  private byFolder: Map<string, Note> = new Map()
  private byNote: Map<string, Note> = new Map()

  registerFolder(note: Note, remoteFolderId: string): void {
    this.byFolder.set(remoteFolderId, this.preferNewer(this.byFolder.get(remoteFolderId), note))
  }

  registerNote(note: Note, remoteNoteId: string): void {
    this.byNote.set(remoteNoteId, this.preferNewer(this.byNote.get(remoteNoteId), note))
  }

  findFolderId(remoteFolderId: string): string {
    const note = this.byFolder.get(remoteFolderId)
    return note !== undefined ? note.id : ''
  }

  findNoteId(remoteId: string): string {
    const note = this.byNote.get(remoteId)
    return note !== undefined ? note.id : ''
  }

  folderCount(): number {
    return this.byFolder.size
  }

  noteCount(): number {
    return this.byNote.size
  }

  private preferNewer(existing: Note | undefined, candidate: Note): Note {
    if (existing === undefined) {
      return candidate
    }
    return candidate.updatedAt >= existing.updatedAt ? candidate : existing
  }
}

export class YoudaoImportService {
  private static instance: YoudaoImportService = new YoudaoImportService()
  private inFlight: Promise<YoudaoImportResult> | null = null
  private running: boolean = false
  private currentProgress: YoudaoImportProgress | null = null
  private cancelled: boolean = false
  private importApiKey: string = ''
  private activeClient: YoudaoMcpClient | null = null

  static getInstance(): YoudaoImportService {
    return YoudaoImportService.instance
  }

  isImportRunning(): boolean {
    return this.running
  }

  getProgress(): YoudaoImportProgress | null {
    return this.currentProgress
  }

  importAllNotes(
    apiKey: string,
    onProgress?: (progress: YoudaoImportProgress) => void
  ): Promise<YoudaoImportResult> {
    Logger.info('YoudaoImport', `importAllNotes: 收到导入请求, keyLen=${apiKey.trim().length}, keyPrefix=${apiKey.trim().substring(0, Math.min(4, apiKey.trim().length))}…`)
    if (this.inFlight !== null) {
      Logger.info('YoudaoImport', 'importAllNotes: 已有任务在跑, 复用旧 Promise')
      return this.inFlight
    }
    this.running = true
    this.cancelled = false
    this.inFlight = this.importAllNotesImpl(apiKey, onProgress).finally(() => {
      this.running = false
      this.inFlight = null
      this.currentProgress = null
      this.activeClient = null
      this.cancelled = false
    })
    return this.inFlight
  }

  /** 中止正在进行的导入任务（如登出场景）。多次调用安全；无正在进行的任务时为 no-op。
   *  会 await 内部 Promise 走完 finally 收尾，确保返回时 isImportRunning() === false。 */
  async cancelImport(): Promise<void> {
    const inFlight = this.inFlight
    if (inFlight === null) {
      return
    }
    this.cancelled = true
    const client = this.activeClient
    if (client) {
      try {
        await client.close()
      } catch (_) {
      }
    }
    try {
      await inFlight
    } catch (_) {
      // 取消引发的异常已在 importAllNotesImpl 内部吞掉，这里再兜一层；
      // 其余导入失败本身就是该任务的预期返回路径，不在 cancel 流程里处理。
    }
  }

  private throwIfCancelled(): void {
    if (this.cancelled) {
      throw new YoudaoImportCancelledException()
    }
  }

  private async importAllNotesImpl(
    apiKey: string,
    onProgress?: (progress: YoudaoImportProgress) => void
  ): Promise<YoudaoImportResult> {
    const token = apiKey.trim()
    if (token.length === 0) {
      Logger.warn('YoudaoImport', 'importAllNotesImpl: token 为空, 抛错')
      throw new YoudaoImportException('请输入有道云笔记 API Key')
    }

    let mcp: YoudaoMcpClient | null = null
    try {
      Logger.info('YoudaoImport', 'importAllNotesImpl: 持久化 API Key')
      await PreferencesService.getInstance().setYoudaoApiKey(token)
      this.importApiKey = token
      // 1. 连接 MCP server（SSE 长连接 + initialize 握手）
      mcp = new YoudaoMcpClient(token)
      this.activeClient = mcp
      try {
        await mcp.connect()
      } catch (e) {
        const err = e as Error
        Logger.error('YoudaoImport', `importAllNotesImpl: MCP connect 失败: ${err.message}`)
        throw err
      }

      const flatEntries: YoudaoEntry[] = []
      Logger.info('YoudaoImport', 'importAllNotesImpl: 开始拉取所有条目 (MCP listNotes)')
      await this.walk(mcp, '', flatEntries)
      Logger.info('YoudaoImport', `importAllNotesImpl: 拉取完成, rawEntries=${flatEntries.length}`)
      flatEntries.forEach((e) => {
        Logger.info('YoudaoImport', `  raw entry: id=${e.remoteId} isFolder=${e.isFolder} title=${e.title} parent=${e.parentRemoteId}`)
      })
      const tree = this.buildTree(flatEntries)
      Logger.info('YoudaoImport', `importAllNotesImpl: 树构建完成, rootNodes=${tree.length}`)

      if (tree.length === 0) {
        Logger.warn('YoudaoImport', 'importAllNotesImpl: 树为空, 认为没有可导入内容')
        const empty = new YoudaoImportResult()
        this.emitToast(this.completionMessage(empty))
        return empty
      }

      Logger.info('YoudaoImport', 'importAllNotesImpl: 初始化仓库, 构建去重索引')
      await NoteRepository.getInstance().init()
      const importIndex = await this.buildImportIndex()
      Logger.info('YoudaoImport', `importAllNotesImpl: 索引已建立, 已导入 folder=${importIndex.folderCount()}, note=${importIndex.noteCount()}`)
      NoteRepository.getInstance().beginBulkNotification()
      let imported = 0
      let skipped = 0
      let plainTextNotes = 0
      try {
        const totalNotes = this.countNotes(tree)
        Logger.info('YoudaoImport', `importAllNotesImpl: 总笔记数 totalNotes=${totalNotes}`)
        const processed = this.newMutableCounter()
        this.emitProgress({
          processedNotes: processed.value,
          totalNotes: totalNotes,
          currentNoteTitle: ''
        }, onProgress)

        await this.importTree(
          mcp,
          tree,
          '',
          importIndex,
          totalNotes,
          processed,
          onProgress,
          (count: number) => {
            imported += count
            Logger.info('YoudaoImport', `importAllNotesImpl: 累计 imported=${imported}, skipped=${skipped}`)
          },
          (count: number) => {
            skipped += count
            Logger.info('YoudaoImport', `importAllNotesImpl: 累计 imported=${imported}, skipped=${skipped}`)
          },
          () => {
            plainTextNotes += 1
          }
        )
        Logger.info('YoudaoImport', `importAllNotesImpl: 遍历完成, 最终 imported=${imported}, skipped=${skipped}`)

        this.emitProgress({
          processedNotes: totalNotes,
          totalNotes: totalNotes,
          currentNoteTitle: ''
        }, onProgress)
      } finally {
        NoteRepository.getInstance().endBulkNotification()
      }

      const result = new YoudaoImportResult()
      result.importedCount = imported
      result.skippedCount = skipped
      result.plainTextNoteCount = plainTextNotes
      Logger.info('YoudaoImport', `importAllNotesImpl: 返回结果 imported=${result.importedCount}, skipped=${result.skippedCount}`)
      this.emitToast(this.completionMessage(result))
      return result
    } catch (error) {
      if (error instanceof YoudaoImportCancelledException) {
        Logger.info('YoudaoImport', 'importAllNotesImpl: 任务被取消')
        return new YoudaoImportResult()
      }
      if (error instanceof YoudaoImportException) {
        Logger.error('YoudaoImport', `importAllNotesImpl: YoudaoImportException: ${error.message}`)
        this.emitToast(error.message)
        throw error
      }
      if (error instanceof YoudaoMcpException) {
        Logger.error('YoudaoImport', `importAllNotesImpl: YoudaoMcpException: ${error.message}`)
        const msg = (error.code === 401 || error.code === 403)
          ? error.message
          : '导入失败，请检查网络或 API Key 后重试'
        this.emitToast(msg)
        throw new YoudaoImportException(msg)
      }
      Logger.error('YoudaoImport', `importAllNotesImpl: 未捕获异常: ${JSON.stringify(error)}`)
      this.emitToast('导入失败，请稍后重试')
      throw error instanceof Error ? error : new YoudaoImportException('导入失败，请稍后重试')
    } finally {
      const client = mcp
      if (client) {
        try {
          await client.close()
        } catch (e) {
          const err = e as Error
          Logger.error('YoudaoImport', `importAllNotesImpl: 关闭 MCP 客户端失败: ${err.message}`)
        }
      }
      if (this.activeClient === mcp) {
        this.activeClient = null
      }
    }
  }

  private emitProgress(
    progress: YoudaoImportProgress,
    onProgress?: (progress: YoudaoImportProgress) => void
  ): void {
    this.currentProgress = progress
    onProgress?.(progress)
  }

  private completionMessage(result: YoudaoImportResult): string {
    if (result.importedCount === 0 && result.skippedCount === 0) {
      return '没有可导入的笔记'
    }
    const skipPart = result.skippedCount > 0 ? `，${result.skippedCount} 条为空` : ''
    const base = `已导入 ${result.importedCount} 条笔记${skipPart}`
    if (result.plainTextNoteCount <= 0) {
      return base
    }
    return `${base}\n${YOUDAO_PLAIN_TEXT_NOTE_HINT}`
  }

  private emitToast(message: string): void {
    if (message.trim().length === 0) {
      return
    }
    try {
      const hub = AppContextHolder.tryGetContext()?.eventHub
      hub?.emit(
        SyncConstants.youdaoImportToastEvent,
        new YoudaoImportToastPayload(message.trim())
      )
    } catch (_) {
    }
  }

  private newMutableCounter(): MutableCounter {
    return new MutableCounter()
  }

  private async importTree(
    mcp: YoudaoMcpClient,
    tree: YoudaoNode[],
    parentNoteId: string,
    index: YoudaoImportIndex,
    totalNotes: number,
    processed: MutableCounter,
    onProgress?: (progress: YoudaoImportProgress) => void,
    onImported?: (count: number) => void,
    onSkipped?: (count: number) => void,
    onPlainTextNote?: () => void
  ): Promise<void> {
    for (const node of tree) {
      this.throwIfCancelled()
      if (node.isFolder) {
        const folderNoteId = await this.upsertFolderNote(node, parentNoteId, index)
        if (node.children.length > 0) {
          await this.importTree(
            mcp,
            node.children,
            folderNoteId,
            index,
            totalNotes,
            processed,
            onProgress,
            onImported,
            onSkipped,
            onPlainTextNote
          )
        }
      } else {
        this.emitProgress({
          processedNotes: processed.value,
          totalNotes: totalNotes,
          currentNoteTitle: node.title
        }, onProgress)
        const outcome = await this.importSingleNote(mcp, node, parentNoteId, index)
        if (outcome.count === 0) {
          onSkipped?.(1)
        } else {
          onImported?.(outcome.count)
          if (outcome.plainTextNote) {
            onPlainTextNote?.()
          }
        }
        processed.value += 1
        this.emitProgress({
          processedNotes: processed.value,
          totalNotes: totalNotes,
          currentNoteTitle: ''
        }, onProgress)
      }
    }
  }

  private async upsertFolderNote(
    node: YoudaoNode,
    parentNoteId: string,
    index: YoudaoImportIndex
  ): Promise<string> {
    Logger.info('YoudaoImport', `upsertFolderNote: 处理文件夹 title=${node.title} remoteId=${node.remoteId} parentNoteId=${parentNoteId}`)
    const existingId = index.findFolderId(node.remoteId)
    const tag = YOUDAO_FOLDER_TAG
    const title = node.title.trim().length > 0 ? node.title.trim() : '未命名文件夹'
    if (existingId.length > 0) {
      Logger.info('YoudaoImport', `upsertFolderNote: 文件夹已存在, 走更新 id=${existingId}`)
      const patch: UpdateNoteInput = {
        title: title,
        parentId: parentNoteId,
        tags: [tag]
      }
      await NoteRepository.getInstance().saveDraft(existingId, patch)
      return existingId
    }
    const input: CreateNoteInput = {
      title: title,
      content: '',
      tags: [tag],
      userData: this.youdaoUserData(YOUDAO_KIND_FOLDER, node.remoteId, node.parentRemoteId)
    }
    let note: Note
    try {
      note = await NoteRepository.getInstance().createNote(input)
    } catch (error) {
      Logger.error('YoudaoImport', `upsertFolderNote: createNote 失败 err=${JSON.stringify(error)}`)
      throw error instanceof Error ? error : new YoudaoImportException('导入失败，请稍后重试')
    }
    Logger.info('YoudaoImport', `upsertFolderNote: 文件夹创建 id=${note.id}`)
    index.registerFolder(note, node.remoteId)
    // createNote 不支持 parentId，建好之后再写一次。
    if (parentNoteId.length > 0) {
      const patch: UpdateNoteInput = {
        title: title,
        parentId: parentNoteId,
        tags: [tag]
      }
      try {
        await NoteRepository.getInstance().saveDraft(note.id, patch)
      } catch (error) {
        Logger.error('YoudaoImport', `upsertFolderNote: 关联父 saveDraft 失败 err=${JSON.stringify(error)}`)
        throw error instanceof Error ? error : new YoudaoImportException('导入失败，请稍后重试')
      }
    }
    return note.id
  }

  private async importSingleNote(
    mcp: YoudaoMcpClient,
    node: YoudaoNode,
    parentNoteId: string,
    index: YoudaoImportIndex
  ): Promise<YoudaoSingleImportOutcome> {
    Logger.info('YoudaoImport', `importSingleNote: 开始 remoteId=${node.remoteId} title=${node.title}`)
    let rawContent = ''
    let rawFormat = 'md'
    let isRaw = false
    try {
      const result = await this.readNote(mcp, node.remoteId, node.title)
      rawContent = result.content
      rawFormat = result.rawFormat
      isRaw = result.isRaw
    } catch (error) {
      Logger.error('YoudaoImport', `importSingleNote: 读内容失败 remoteId=${node.remoteId} err=${JSON.stringify(error)}`)
      throw error instanceof Error ? error : new YoudaoImportException('导入失败，请稍后重试')
    }
    const plainTextNote = this.isYoudaoPlainTextNote(rawFormat, node.title)
    const convertedMarkdown = this.convertContent(rawContent, rawFormat, isRaw)
    YoudaoImportExportLogger.logConversion(
      node.remoteId,
      node.title,
      rawContent,
      rawFormat,
      isRaw,
      convertedMarkdown
    )
    const content = await this.localizeRemoteImages(convertedMarkdown, mcp)
    Logger.info('YoudaoImport', `importSingleNote: 转换后内容长度=${content.length}, rawFormat=${rawFormat}, isRaw=${isRaw}`)
    if (content.trim().length === 0) {
      Logger.info('YoudaoImport', `importSingleNote: 内容为空, 跳过 remoteId=${node.remoteId}`)
      return { count: 0, plainTextNote: false }
    }

    const trimmedTitle = node.title.trim()
    const title = trimmedTitle.length > 0 ? trimmedTitle : this.fallbackTitleFromContent(content)
    const tag = YOUDAO_NOTE_TAG
    const existingId = index.findNoteId(node.remoteId)
    if (existingId.length > 0) {
      Logger.info('YoudaoImport', `importSingleNote: 已存在, 走更新 id=${existingId}, parentNoteId=${parentNoteId}`)
      const patch: UpdateNoteInput = {
        title: title,
        content: content,
        parentId: parentNoteId,
        tags: [tag]
      }
      try {
        await NoteRepository.getInstance().saveDraft(existingId, patch)
      } catch (error) {
        Logger.error('YoudaoImport', `importSingleNote: saveDraft 失败 err=${JSON.stringify(error)}`)
        throw error instanceof Error ? error : new YoudaoImportException('导入失败，请稍后重试')
      }
      return { count: 1, plainTextNote: plainTextNote }
    }
    Logger.info('YoudaoImport', `importSingleNote: 新建笔记 title=${title}, parentNoteId=${parentNoteId}`)
    const input: CreateNoteInput = {
      title: title,
      content: content,
      tags: [tag],
      userData: this.youdaoUserData(YOUDAO_KIND_NOTE, node.remoteId, node.parentRemoteId)
    }
    let note: Note
    try {
      note = await NoteRepository.getInstance().createNote(input)
    } catch (error) {
      Logger.error('YoudaoImport', `importSingleNote: createNote 失败 err=${JSON.stringify(error)}`)
      throw error instanceof Error ? error : new YoudaoImportException('导入失败，请稍后重试')
    }
    Logger.info('YoudaoImport', `importSingleNote: createNote 成功 id=${note.id}`)
    index.registerNote(note, node.remoteId)
    if (parentNoteId.length > 0) {
      Logger.info('YoudaoImport', `importSingleNote: 关联父文件夹 id=${note.id} -> ${parentNoteId}`)
      const patch: UpdateNoteInput = {
        title: title,
        parentId: parentNoteId,
        tags: [tag]
      }
      try {
        await NoteRepository.getInstance().saveDraft(note.id, patch)
      } catch (error) {
        Logger.error('YoudaoImport', `importSingleNote: 关联父 saveDraft 失败 err=${JSON.stringify(error)}`)
        throw error instanceof Error ? error : new YoudaoImportException('导入失败，请稍后重试')
      }
    }
    return { count: 1, plainTextNote: plainTextNote }
  }

  private isYoudaoPlainTextNote(rawFormat: string, title: string): boolean {
    const format = rawFormat.toLowerCase()
    if (format === 'md' || format === 'txt') {
      return false
    }
    if (format === 'note') {
      return true
    }
    const lowerTitle = title.toLowerCase()
    if (lowerTitle.endsWith('.md')) {
      return false
    }
    if (lowerTitle.endsWith('.txt')) {
      return false
    }
    return true
  }

  private convertContent(raw: string, rawFormat: string, isRaw: boolean): string {
    const format = rawFormat.toLowerCase()
    if (format === 'md' || format === 'txt') {
      return raw
    }
    return YoudaoNoteContentConverter.convertWithFallback(raw, rawFormat)
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
    return '有道云笔记'
  }

  private youdaoUserData(kind: string, remoteId: string, parentRemoteId: string): string {
    const payload: Record<string, string> = {}
    payload[YOUDAO_USER_DATA_KEY_KIND] = kind
    payload[YOUDAO_USER_DATA_KEY_REMOTE_ID] = remoteId
    payload[YOUDAO_USER_DATA_KEY_PARENT_REMOTE_ID] = parentRemoteId
    return JSON.stringify(payload)
  }

  private parseYoudaoUserData(userData: string): YoudaoUserDataMeta | undefined {
    const trimmed = userData.trim()
    if (trimmed.length === 0) {
      return undefined
    }
    try {
      const parsed = JSON.parse(trimmed) as Record<string, Object>
      const kind = `${parsed[YOUDAO_USER_DATA_KEY_KIND] ?? ''}`.trim()
      const remoteId = `${parsed[YOUDAO_USER_DATA_KEY_REMOTE_ID] ?? ''}`.trim()
      if (kind.length === 0 || remoteId.length === 0) {
        return undefined
      }
      const meta: YoudaoUserDataMeta = {
        kind: kind,
        remoteId: remoteId
      }
      return meta
    } catch (_) {
      return undefined
    }
  }

  private async buildImportIndex(): Promise<YoudaoImportIndex> {
    const index = new YoudaoImportIndex()
    const notes = await NoteRepository.getInstance().listAllNotes()
    for (const note of notes) {
      if (note.deleted || note.deletedTime > 0) {
        continue
      }
      const meta = this.parseYoudaoUserData(note.userData)
      if (meta === undefined) {
        continue
      }
      if (meta.kind === YOUDAO_KIND_FOLDER) {
        index.registerFolder(note, meta.remoteId)
      } else if (meta.kind === YOUDAO_KIND_NOTE) {
        index.registerNote(note, meta.remoteId)
      }
    }
    return index
  }

  /** 根目录传 `parentId: "0"`；子目录传具体 ID；分页可传 `lastId`。 */
  private buildListNotesArgs(parentRemoteId: string, lastId?: string): YoudaoListNotesArgs {
    const trimmed = parentRemoteId.trim()
    const args: YoudaoListNotesArgs = {
      parentId: trimmed.length === 0 ? YOUDAO_ROOT_PARENT_ID : trimmed
    }
    const cursor = `${lastId ?? ''}`.trim()
    if (cursor.length > 0) {
      args.lastId = cursor
    }
    return args
  }

  private mcpToolErrorMessage(result: YoudaoMcpToolResult, fallback: string): string {
    for (const entry of result.content) {
      const text = `${entry.text ?? ''}`.trim()
      if (text.length > 0) {
        return text
      }
    }
    return fallback
  }

  private async walk(mcp: YoudaoMcpClient, parentRemoteId: string, into: YoudaoEntry[]): Promise<void> {
    this.throwIfCancelled()
    Logger.info('YoudaoImport', `walk: 拉取 parent=${parentRemoteId} 的子条目 (MCP listNotes)`)
    let lastId: string | undefined = undefined
    while (true) {
      this.throwIfCancelled()
      let result: YoudaoMcpToolResult
      try {
        const listArgs = this.buildListNotesArgs(parentRemoteId, lastId)
        Logger.info('YoudaoImport', `walk: listNotes args=${JSON.stringify(listArgs)}`)
        result = await mcp.callTool(MCP_TOOL_LIST_NOTES, listArgs)
      } catch (error) {
        const err = error as Error
        Logger.error('YoudaoImport', `walk: listNotes parent=${parentRemoteId} 失败: ${err.message}`)
        throw error instanceof Error ? error : new YoudaoImportException('导入失败，请稍后重试')
      }
      if (result.isError) {
        const msg = this.mcpToolErrorMessage(result, 'listNotes 返回错误')
        Logger.error('YoudaoImport', `walk: listNotes 返回 isError=true: ${msg}`)
        throw new YoudaoImportException(msg)
      }
      const data = result.asJson()
      if (data === null) {
        Logger.warn('YoudaoImport', `walk: parent=${parentRemoteId} 解析结果不是 Object`)
        return
      }
      const keys = Object.keys(data)
      Logger.info('YoudaoImport', `walk: parent=${parentRemoteId} 返回 keys=${keys.join(',')}`)
      const entries = data['entries']
      if (!Array.isArray(entries)) {
        Logger.warn('YoudaoImport', `walk: parent=${parentRemoteId} 的 entries 不是 Array, 跳过`)
        return
      }
      const page = entries as Object[]
      Logger.info('YoudaoImport', `walk: parent=${parentRemoteId} 本页 ${page.length} 条, lastId=${lastId ?? ''}`)
      if (page.length === 0) {
        break
      }
      let pageLastId = ''
      for (const raw of page) {
        const map = this.asMap(raw)
        if (map === null) {
          Logger.warn('YoudaoImport', `walk: 跳过非 Map 条目: ${JSON.stringify(raw)}`)
          continue
        }
        const id = `${map['id'] ?? ''}`.trim()
        if (id.length === 0) {
          Logger.warn('YoudaoImport', `walk: 跳过无 id 条目: ${JSON.stringify(raw)}`)
          continue
        }
        pageLastId = id
        const dir = map['dir']
        const name = `${map['name'] ?? map['title'] ?? ''}`.trim()
        const entry: YoudaoEntry = {
          remoteId: id,
          parentRemoteId: parentRemoteId,
          title: name.length > 0 ? name : '未命名',
          isFolder: dir === true
        }
        into.push(entry)
        if (entry.isFolder) {
          await this.walk(mcp, id, into)
        }
      }
      if (pageLastId.length === 0 || pageLastId === lastId) {
        break
      }
      lastId = pageLastId
    }
  }

  private buildTree(flatEntries: YoudaoEntry[]): YoudaoNode[] {
    const byParent: Map<string, YoudaoEntry[]> = new Map()
    for (const entry of flatEntries) {
      let list = byParent.get(entry.parentRemoteId)
      if (list === undefined) {
        list = []
        byParent.set(entry.parentRemoteId, list)
      }
      list.push(entry)
    }
    return this.buildNodes(byParent.get('') ?? [], byParent)
  }

  private buildNodes(
    entries: YoudaoEntry[],
    byParent: Map<string, YoudaoEntry[]>
  ): YoudaoNode[] {
    const nodes: YoudaoNode[] = []
    for (const entry of entries) {
      if (entry.isFolder) {
        const children = this.buildNodes(
          byParent.get(entry.remoteId) ?? [],
          byParent
        )
        const folder: YoudaoNode = {
          remoteId: entry.remoteId,
          parentRemoteId: entry.parentRemoteId,
          title: entry.title,
          isFolder: true,
          children: children
        }
        nodes.push(folder)
      } else {
        const note: YoudaoNode = {
          remoteId: entry.remoteId,
          parentRemoteId: entry.parentRemoteId,
          title: entry.title,
          isFolder: false,
          children: []
        }
        nodes.push(note)
      }
    }
    return nodes
  }

  private countNotes(tree: YoudaoNode[]): number {
    let count = 0
    for (const node of tree) {
      if (node.isFolder) {
        count += this.countNotes(node.children)
      } else {
        count += 1
      }
    }
    return count
  }

  private async readNote(mcp: YoudaoMcpClient, fileId: string, noteTitle: string = ''): Promise<ReadNoteResult> {
    this.throwIfCancelled()
    Logger.info('YoudaoImport', `readNote: 读取 fileId=${fileId} (MCP getNoteTextContent)`)
    let rawAttempt: ReadNoteResult | undefined = undefined
    try {
      rawAttempt = await this.fetchNoteContent(mcp, fileId, false, undefined, undefined, noteTitle, 'convert_false')
      Logger.info('YoudaoImport',
        `readNote: convert=false isRaw=${rawAttempt.isRaw}, structured=${YoudaoNoteContentConverter.looksStructured(rawAttempt.content)}`)
    } catch (error) {
      Logger.warn('YoudaoImport', `readNote: convert=false 失败(忽略): ${JSON.stringify(error)}`)
    }
    let desktopRawAttempt: ReadNoteResult | undefined = undefined
    try {
      desktopRawAttempt = await this.fetchNoteContent(mcp, fileId, false, -1, 1, noteTitle, 'editorType1_convert_false')
    } catch (error) {
      Logger.warn('YoudaoImport', `readNote: editorType=1 convert=false 失败(忽略): ${JSON.stringify(error)}`)
    }
    const defaultAttempt = await this.fetchNoteContent(mcp, fileId, undefined, undefined, undefined, noteTitle, 'default')
    const candidates: ReadNoteResult[] = []
    if (rawAttempt !== undefined) {
      candidates.push(rawAttempt)
    }
    if (desktopRawAttempt !== undefined) {
      candidates.push(desktopRawAttempt)
    }
    candidates.push(defaultAttempt)
    for (const candidate of candidates) {
      if (YoudaoNoteContentConverter.looksStructured(candidate.content) || candidate.isRaw) {
        Logger.info('YoudaoImport', `readNote: 选用结构化/原始内容 isRaw=${candidate.isRaw}`)
        return candidate
      }
    }
    if (rawAttempt !== undefined && this.shouldPreferRawAttempt(rawAttempt, defaultAttempt)) {
      Logger.info('YoudaoImport', 'readNote: 选用 convert=false 原始内容')
      return rawAttempt
    }
    Logger.info('YoudaoImport', `readNote: 选用 default 内容 isRaw=${defaultAttempt.isRaw}`)
    return defaultAttempt
  }

  private shouldPreferRawAttempt(raw: ReadNoteResult, fallback: ReadNoteResult): boolean {
    if (raw.isRaw && !fallback.isRaw) {
      return true
    }
    if (YoudaoNoteContentConverter.looksStructured(raw.content) &&
      !YoudaoNoteContentConverter.looksStructured(fallback.content)) {
      return true
    }
    if (raw.content.trim().length > fallback.content.trim().length + 32 &&
      YoudaoNoteContentConverter.looksStructured(raw.content)) {
      return true
    }
    return false
  }

  private async fetchNoteContent(
    mcp: YoudaoMcpClient,
    fileId: string,
    convert?: boolean,
    version?: number,
    editorType?: number,
    noteTitle: string = '',
    attemptLabel: string = 'default'
  ): Promise<ReadNoteResult> {
    let result: YoudaoMcpToolResult
    try {
      const readArgs: YoudaoGetNoteArgs = { fileId: fileId }
      if (convert !== undefined) {
        readArgs.convert = convert
      }
      if (version !== undefined) {
        readArgs.version = version
      }
      if (editorType !== undefined) {
        readArgs.editorType = editorType
      }
      result = await mcp.callTool(MCP_TOOL_GET_NOTE_TEXT_CONTENT, readArgs)
    } catch (error) {
      const err = error as Error
      Logger.error('YoudaoImport',
        `fetchNoteContent: getNoteTextContent fileId=${fileId} convert=${convert} 失败: ${err.message}`)
      throw error instanceof Error ? error : new YoudaoImportException('导入失败，请稍后重试')
    }
    if (result.isError) {
      Logger.error('YoudaoImport', `fetchNoteContent: getNoteTextContent 返回 isError=true convert=${convert}`)
      throw new YoudaoImportException('getNoteTextContent 返回错误')
    }
    const parsed = this.parseReadNotePayload(result)
    Logger.info('YoudaoImport',
      `fetchNoteContent: fileId=${fileId} attempt=${attemptLabel} convert=${convert} 内容长度=${parsed.content.length}, rawFormat=${parsed.rawFormat}, isRaw=${parsed.isRaw}`)
    YoudaoImportExportLogger.logMcpAttempt(
      fileId,
      noteTitle.length > 0 ? noteTitle : fileId,
      attemptLabel,
      result,
      parsed.content,
      parsed.rawFormat,
      parsed.isRaw
    )
    return parsed
  }

  private parseReadNotePayload(result: YoudaoMcpToolResult): ReadNoteResult {
    let content = ''
    let rawFormat = 'note'
    let isRaw = false
    const structured = result.asJson()
    if (structured !== null) {
      const c = structured['content']
      if (typeof c === 'string') {
        content = c
      }
      const title = structured['title']
      const rf = structured['rawFormat']
      if (typeof rf === 'string' && rf.length > 0) {
        rawFormat = rf.toLowerCase()
      } else if (typeof title === 'string') {
        rawFormat = YoudaoNoteContentConverter.inferRawFormatFromTitle(title)
      }
      const r = structured['isRaw'] ?? structured['raw']
      if (typeof r === 'boolean') {
        isRaw = r
      } else if (typeof r === 'number') {
        isRaw = r !== 0
      }
    }
    if (content.length === 0) {
      const text = result.asText()
      if (text !== null && text.length > 0) {
        content = text
      }
    }
    const ret: ReadNoteResult = { content, rawFormat, isRaw }
    return ret
  }

  private asMap(value: Object | undefined): Record<string, Object> | null {
    if (value === undefined || value === null) {
      return null
    }
    if (typeof value !== 'object') {
      return null
    }
    return value as Record<string, Object>
  }

  /** 下载 Markdown 中的远程图片到 `qingyu-note-image/` 并替换引用。 */
  private async localizeRemoteImages(markdown: string, mcp: YoudaoMcpClient): Promise<string> {
    if (markdown.length === 0) {
      return markdown
    }
    const ctx = AppContextHolder.tryGetContext()
    if (ctx === undefined) {
      return markdown
    }
    const imagesDir = `${ctx.filesDir ?? ''}/${YOUDAO_IMAGES_DIR}`
    try {
      if (!fs.accessSync(imagesDir)) {
        fs.mkdirSync(imagesDir, true)
      }
    } catch (_) {
      try {
        fs.mkdirSync(imagesDir, true)
      } catch (error) {
        Logger.warn('YoudaoImport', `localizeRemoteImages: mkdir failed: ${JSON.stringify(error)}`)
        return markdown
      }
    }
    const matches: RegExpExecArray[] = []
    YOUDAO_MARKDOWN_IMG_REGEX.lastIndex = 0
    let m: RegExpExecArray | null = YOUDAO_MARKDOWN_IMG_REGEX.exec(markdown)
    while (m !== null) {
      matches.push(m)
      m = YOUDAO_MARKDOWN_IMG_REGEX.exec(markdown)
    }
    if (matches.length === 0) {
      return markdown
    }
    let output = markdown
    for (let i = matches.length - 1; i >= 0; i -= 1) {
      const match = matches[i]
      const alt = match[1] ?? ''
      let src = (match[2] ?? '').trim()
      if (src.length === 0 || !this.isRemoteImageUrl(src)) {
        continue
      }
      if (src.startsWith('//')) {
        src = `https:${src}`
      }
      const localized = await this.downloadRemoteImage(src, imagesDir, mcp)
      if (localized === null) {
        continue
      }
      const replacement = `![${alt}](${localized})`
      output = output.substring(0, match.index) + replacement + output.substring(match.index + match[0].length)
    }
    return output
  }

  private isRemoteImageUrl(src: string): boolean {
    const lower = src.toLowerCase()
    return lower.startsWith('http://') || lower.startsWith('https://')
  }

  private isYoudaoImageHost(url: string): boolean {
    const lower = url.toLowerCase()
    return lower.includes('youdao.com') || lower.includes('ydnote.com')
  }

  private buildImageDownloadHeaders(url: string, withApiKey: boolean): Record<string, string> {
    const headers: Record<string, string> = {
      'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
    }
    if (this.isYoudaoImageHost(url)) {
      headers['Referer'] = 'https://note.youdao.com/'
      return headers
    }
    if (withApiKey && this.importApiKey.length > 0) {
      headers['x-api-key'] = this.importApiKey
    }
    return headers
  }

  private async downloadRemoteImage(url: string, imagesDir: string, mcp: YoudaoMcpClient): Promise<string | null> {
    const attempts = this.isYoudaoImageHost(url)
      ? [this.buildImageDownloadHeaders(url, false)]
      : [
        this.buildImageDownloadHeaders(url, false),
        this.buildImageDownloadHeaders(url, true)
      ]
    for (const headers of attempts) {
      const req = http.createHttp()
      try {
        const response = await req.request(url, {
          method: http.RequestMethod.GET,
          header: headers,
          expectDataType: http.HttpDataType.ARRAY_BUFFER,
          connectTimeout: 15000,
          readTimeout: 30000
        })
        if (response.responseCode < 200 || response.responseCode >= 400) {
          continue
        }
        if (!(response.result instanceof ArrayBuffer)) {
          continue
        }
        const bytes = response.result as ArrayBuffer
        if (bytes.byteLength <= 0) {
          continue
        }
        const contentType = `${response.header?.['content-type'] ?? response.header?.['Content-Type'] ?? ''}`
        const ext = this.guessImageExtension(url, contentType, bytes)
        const fileName = this.randomImageFileName(ext)
        const filePath = `${imagesDir}/${fileName}`
        const file = fs.openSync(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
        try {
          await fs.write(file.fd, bytes)
        } finally {
          fs.closeSync(file)
        }
        return `${YOUDAO_IMAGES_DIR}/${fileName}`
      } catch (error) {
        Logger.warn('YoudaoImport', `downloadRemoteImage failed url=${url}: ${JSON.stringify(error)}`)
      } finally {
        req.destroy()
      }
    }
    const mcpBytes = await mcp.downloadResourceBytes(url)
    if (mcpBytes !== null && mcpBytes.byteLength > 0) {
      const ext = this.guessImageExtension(url, '', mcpBytes)
      const fileName = this.randomImageFileName(ext)
      const filePath = `${imagesDir}/${fileName}`
      const file = fs.openSync(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
      try {
        await fs.write(file.fd, mcpBytes)
      } finally {
        fs.closeSync(file)
      }
      return `${YOUDAO_IMAGES_DIR}/${fileName}`
    }
    return null
  }

  private guessImageExtension(url: string, contentType: string, bytes: ArrayBuffer): string {
    const dot = url.lastIndexOf('.')
    if (dot >= 0) {
      const ext = url.substring(dot).split(/[?#]/)[0].toLowerCase()
      if (ext.length >= 2 && ext.length <= 5) {
        return ext
      }
    }
    const ct = contentType.toLowerCase()
    if (ct.includes('jpeg') || ct.includes('jpg')) {
      return '.jpg'
    }
    if (ct.includes('png')) {
      return '.png'
    }
    if (ct.includes('gif')) {
      return '.gif'
    }
    if (ct.includes('webp')) {
      return '.webp'
    }
    const view = new Uint8Array(bytes)
    if (view.length >= 3 && view[0] === 0xFF && view[1] === 0xD8 && view[2] === 0xFF) {
      return '.jpg'
    }
    if (view.length >= 8 && view[0] === 0x89 && view[1] === 0x50 && view[2] === 0x4E && view[3] === 0x47) {
      return '.png'
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

class MutableCounter {
  value: number = 0
}