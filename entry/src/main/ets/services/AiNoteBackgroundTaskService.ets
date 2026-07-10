import { AppContextHolder } from './AppContextHolder'
import { AiNoteService, type AiLinkSummaryResult, AiLinkExtractTitle } from './AiNoteService'
import { NoteRepository } from './NoteRepository'
import { SyncService } from './SyncService'
import { VoiceTranscribeClient } from './VoiceTranscribeClient'
import { AudioConstants } from '../common/constants/AudioConstants'
import { EditorUiStrings } from '../common/utils/EditorUiStrings'
import { MarkdownUtils } from '../common/utils/MarkdownUtils'
import { NoteStateCodec } from '../common/utils/NoteStateCodec'
import { UserFacingMessage } from '../common/utils/UserFacingMessage'
import { Logger } from '../common/utils/Logger'

/** AI 后台任务类型（编辑页离开后仍继续）。 */
export type AiNoteBackgroundJobKind = 'optimize' | 'extractLink' | 'voiceTranscribe'

/** 任务完成后供打开中的编辑页灌回 UI 的结果快照。 */
export class AiNoteBackgroundTaskResult {
  noteId: string = ''
  kind: AiNoteBackgroundJobKind = 'optimize'
  success: boolean = false
  message: string = ''
  title?: string
  content?: string
  /** 写入前正文，供「撤回 AI」基线。 */
  contentBefore?: string
  audioId?: string
  switchToPreviewOnSuccess: boolean = false
}

type AiTaskListener = () => void

/**
 * 全局单飞：链接提取 / 优化生成 / 录音 ASR；离页后继续，完成后 saveDraft + 全局 Toast。
 */
export class AiNoteBackgroundTaskService {
  private static instance: AiNoteBackgroundTaskService = new AiNoteBackgroundTaskService()

  static getInstance(): AiNoteBackgroundTaskService {
    return AiNoteBackgroundTaskService.instance
  }

  static readonly BUSY_WAIT_MESSAGE_ZH: string = '请等待上一个 AI 任务完成'

  private inFlight: boolean = false
  private activeNoteIdInternal: string = ''
  private overlayMessageInternal: string = EditorUiStrings.loc('AI 处理中…', 'AI processing…', 'AI処理中…')
  private lastResultInternal: AiNoteBackgroundTaskResult | null = null
  private listeners: AiTaskListener[] = []

  get isBusy(): boolean {
    return this.inFlight
  }

  get activeNoteId(): string {
    return this.activeNoteIdInternal
  }

  get overlayMessage(): string {
    return this.overlayMessageInternal
  }

  get lastResult(): AiNoteBackgroundTaskResult | null {
    return this.lastResultInternal
  }

  isBusyForNote(noteId: string): boolean {
    const id = noteId.trim()
    return this.inFlight && id.length > 0 && this.activeNoteIdInternal === id
  }

  /** 后台 AI 已写入草稿且编辑区尚未同步时，跳过自动保存以防旧内容覆盖。 */
  shouldSkipEditorAutoSave(noteId: string, editorContent: string): boolean {
    const id = noteId.trim()
    if (id.length === 0) {
      return false
    }
    if (this.isBusyForNote(id)) {
      return true
    }
    const result = this.lastResultInternal
    if (result === null || result.noteId !== id || !result.success || result.content === undefined) {
      return false
    }
    return result.content !== editorContent
  }

  addListener(listener: AiTaskListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener)
    }
  }

  removeListener(listener: AiTaskListener): void {
    this.listeners = this.listeners.filter((item: AiTaskListener) => item !== listener)
  }

  /** 若已有任务，弹 Toast 并返回 false。 */
  ensureIdleOrNotifyBusy(): boolean {
    if (!this.inFlight) {
      return true
    }
    this.showGlobalToast(EditorUiStrings.loc(
      AiNoteBackgroundTaskService.BUSY_WAIT_MESSAGE_ZH,
      'Please wait for the previous AI task to finish',
      '前のAIタスクが完了するまでお待ちください'
    ))
    return false
  }

  async runOptimize(
    noteId: string,
    content: string,
    title: string = '',
    filesBasePath: string = '',
    overlayMessage: string = '',
    switchToPreviewOnSuccess: boolean = false
  ): Promise<boolean> {
    const id = noteId.trim()
    if (id.length === 0) {
      return false
    }
    const hasImageRefs = NoteStateCodec.extractImageRefs(content).length > 0
    const noteHasText = NoteStateCodec.hasSubstantiveNoteText(content)
    const message = overlayMessage.trim().length > 0
      ? overlayMessage.trim()
      : EditorUiStrings.loc(
        !noteHasText && hasImageRefs ? 'AI 生成笔记中…' : 'AI 处理中…',
        !noteHasText && hasImageRefs ? 'AI generating note…' : 'AI processing…',
        !noteHasText && hasImageRefs ? 'AIがノートを生成中…' : 'AI処理中…'
      )
    return this.runLocked(id, message, async (): Promise<AiNoteBackgroundTaskResult> => {
      const contentBefore = content
      await NoteRepository.getInstance().saveDraft(id, {
        title: title,
        content: content,
        skipTitleAutoFill: title.trim().length === 0
      })
      const optimized = await AiNoteService.getInstance().optimizeContent(content, filesBasePath)
      const parts = MarkdownUtils.splitLinkSummary(optimized)
      let nextTitle = title
      let nextContent = optimized
      if (hasImageRefs && parts.title.trim().length > 0) {
        nextTitle = parts.title.trim()
        nextContent = parts.body
      }
      await NoteRepository.getInstance().saveDraft(id, {
        title: nextTitle,
        content: nextContent,
        skipTitleAutoFill: nextTitle.trim().length === 0
      })
      const successText = EditorUiStrings.loc(
        noteHasText ? 'AI 已优化笔记正文' : 'AI 已根据图片生成笔记',
        noteHasText ? 'AI polished the note' : 'AI generated note from image',
        noteHasText ? 'AIがノート本文を最適化しました' : 'AIが画像からノートを生成しました'
      )
      const result = new AiNoteBackgroundTaskResult()
      result.noteId = id
      result.kind = 'optimize'
      result.success = true
      result.message = successText
      result.title = nextTitle
      result.content = nextContent
      result.contentBefore = contentBefore
      result.switchToPreviewOnSuccess = switchToPreviewOnSuccess
      return result
    }, (e: Object): AiNoteBackgroundTaskResult => {
      const result = new AiNoteBackgroundTaskResult()
      result.noteId = id
      result.kind = 'optimize'
      result.success = false
      result.message = UserFacingMessage.forAi(
        e instanceof Error ? e.message : undefined,
        EditorUiStrings.loc('AI 优化失败，请稍后重试', 'AI optimization failed; try again', 'AI最適化に失敗しました。後でもう一度お試しください')
      )
      result.switchToPreviewOnSuccess = switchToPreviewOnSuccess
      return result
    })
  }

  async runExtractLink(
    noteId: string,
    url: string,
    summarize: number,
    currentTitle: string = '',
    currentContent: string = '',
    switchToPreviewOnSuccess: boolean = false
  ): Promise<boolean> {
    const id = noteId.trim()
    const trimmedUrl = url.trim()
    if (id.length === 0 || trimmedUrl.length === 0) {
      return false
    }
    return this.runLocked(
      id,
      EditorUiStrings.loc('AI 处理中…', 'AI processing…', 'AI処理中…'),
      async (): Promise<AiNoteBackgroundTaskResult> => {
        const extracted: AiLinkSummaryResult =
          await AiNoteService.getInstance().summarizeLink(trimmedUrl, summarize)
        if (extracted.body.trim().length === 0) {
          throw new Error('AI 未返回有效内容')
        }
        const existing = await NoteRepository.getInstance().getNote(id)
        const existingContent = currentContent.length > 0
          ? currentContent
          : (existing?.content ?? '')
        const contentBefore = existingContent
        const separator = existingContent.trim().length === 0 ? '' : '\n\n'
        const linkLine = EditorUiStrings.loc(
          `完整文章链接为：[${trimmedUrl}](${trimmedUrl})`,
          `Full article link: [${trimmedUrl}](${trimmedUrl})`,
          `全文リンク：[${trimmedUrl}](${trimmedUrl})`
        )
        const nextContent = `${existingContent}${separator}${extracted.body}\n\n${linkLine}`
        let nextTitle = (existing?.title ?? currentTitle).trim()
        const extractedTitle = AiLinkExtractTitle.resolve(extracted.title, extracted.body)
        if (AiLinkExtractTitle.isPlaceholderNoteTitle(nextTitle) &&
          extractedTitle.trim().length > 0) {
          nextTitle = extractedTitle.trim()
        }
        await NoteRepository.getInstance().saveDraft(id, {
          title: nextTitle,
          content: nextContent,
          skipTitleAutoFill: nextTitle.length === 0
        })
        const result = new AiNoteBackgroundTaskResult()
        result.noteId = id
        result.kind = 'extractLink'
        result.success = true
        result.message = EditorUiStrings.loc(
          summarize !== 0 ? 'AI 已生成链接摘要并写入正文' : 'AI 已提取全文并写入正文',
          summarize !== 0 ? 'AI added link summary to the note' : 'AI extracted full text into the note',
          summarize !== 0 ? 'AIがリンク要約を本文に追加しました' : 'AIが全文を本文に追加しました'
        )
        result.title = nextTitle
        result.content = nextContent
        result.contentBefore = contentBefore
        result.switchToPreviewOnSuccess = switchToPreviewOnSuccess
        return result
      },
      (e: Object): AiNoteBackgroundTaskResult => {
        const result = new AiNoteBackgroundTaskResult()
        result.noteId = id
        result.kind = 'extractLink'
        result.success = false
        result.message = UserFacingMessage.forAi(
          e instanceof Error ? e.message : undefined,
          EditorUiStrings.loc('AI 提取链接失败，请稍后重试', 'AI link extract failed; try again', 'AIリンク抽出に失敗しました。後でもう一度お試しください')
        )
        result.switchToPreviewOnSuccess = switchToPreviewOnSuccess
        return result
      }
    )
  }

  async runVoiceTranscribe(noteId: string, outputPath: string): Promise<boolean> {
    const id = noteId.trim()
    if (id.length === 0) {
      return false
    }
    return this.runLocked(
      id,
      EditorUiStrings.loc('AI 处理中…', 'AI processing…', 'AI処理中…'),
      async (): Promise<AiNoteBackgroundTaskResult> => {
        const audioId = AudioConstants.audioFileNameForNote(id)
        const note = await NoteRepository.getInstance().saveDraft(id, {
          audioId: audioId
        })
        const syncResult = await SyncService.getInstance().syncNote(id)
        if (!syncResult.success) {
          throw new Error(EditorUiStrings.loc('同步失败，请稍后重试', 'Sync failed; try again', '同期に失敗しました。後でもう一度お試しください'))
        }
        await SyncService.getInstance().uploadAudioForNoteOrThrow(id)
        const text = await VoiceTranscribeClient.getInstance().transcribeLocalFile(outputPath)
        const existing = await NoteRepository.getInstance().getNote(id)
        const contentBefore = existing?.content ?? ''
        await NoteRepository.getInstance().saveDraft(id, {
          content: text,
          audioId: note.audioId
        })
        const result = new AiNoteBackgroundTaskResult()
        result.noteId = id
        result.kind = 'voiceTranscribe'
        result.success = true
        result.message = ''
        result.content = text
        result.contentBefore = contentBefore
        result.audioId = note.audioId
        return result
      },
      (e: Object): AiNoteBackgroundTaskResult => {
        const result = new AiNoteBackgroundTaskResult()
        result.noteId = id
        result.kind = 'voiceTranscribe'
        result.success = false
        result.message = UserFacingMessage.forAi(
          e instanceof Error ? e.message : undefined,
          EditorUiStrings.loc('语音转文字失败，请稍后重试', 'Speech-to-text failed; try again', '音声認識に失敗しました。後でもう一度お試しください')
        )
        return result
      }
    )
  }

  private async runLocked(
    noteId: string,
    overlayMessage: string,
    job: () => Promise<AiNoteBackgroundTaskResult>,
    onError: (e: Object) => AiNoteBackgroundTaskResult
  ): Promise<boolean> {
    if (this.inFlight) {
      this.showGlobalToast(EditorUiStrings.loc(
        AiNoteBackgroundTaskService.BUSY_WAIT_MESSAGE_ZH,
        'Please wait for the previous AI task to finish',
        '前のAIタスクが完了するまでお待ちください'
      ))
      return false
    }
    this.inFlight = true
    this.activeNoteIdInternal = noteId
    this.overlayMessageInternal = overlayMessage
    this.lastResultInternal = null
    this.notifyListeners()
    let result: AiNoteBackgroundTaskResult
    try {
      result = await job()
    } catch (e) {
      Logger.error('AiNoteBgTask', `job failed: ${e instanceof Error ? e.message : JSON.stringify(e)}`)
      result = onError(e as Object)
    }
    this.lastResultInternal = result
    this.showGlobalToast(result.message)
    this.notifyListeners()
    this.inFlight = false
    this.activeNoteIdInternal = ''
    this.notifyListeners()
    return result.success && result.noteId === noteId
  }

  private notifyListeners(): void {
    const snapshot = this.listeners.slice()
    for (let i = 0; i < snapshot.length; i++) {
      try {
        snapshot[i]()
      } catch (e) {
        Logger.warn('AiNoteBgTask', `listener failed: ${JSON.stringify(e)}`)
      }
    }
  }

  private showGlobalToast(message: string): void {
    const trimmed = message.trim()
    if (trimmed.length === 0) {
      return
    }
    try {
      const ui = AppContextHolder.tryGetLastUiContext()
      if (ui === undefined) {
        return
      }
      ui.getPromptAction().showToast({ message: trimmed, duration: 2000 })
    } catch (e) {
      Logger.warn('AiNoteBgTask', `showToast failed: ${JSON.stringify(e)}`)
    }
  }
}
