import { AppContextHolder } from './AppContextHolder'
import { AiNoteService } from './AiNoteService'
import { LinkExtractClient } from './LinkExtractClient'
import { NoteRepository } from './NoteRepository'
import { SyncService } from './SyncService'
import { VoiceTranscribeClient } from './VoiceTranscribeClient'
import { AudioConstants } from '../common/constants/AudioConstants'
import { EditorUiStrings } from '../common/utils/EditorUiStrings'
import { MarkdownUtils } from '../common/utils/MarkdownUtils'
import { NoteStateCodec } from '../common/utils/NoteStateCodec'
import { VoiceSegmentSplitter } from '../common/utils/VoiceSegmentSplitter'
import { UserFacingMessage } from '../common/utils/UserFacingMessage'
import { Logger } from '../common/utils/Logger'
import { fileIo as fs } from '@kit.CoreFileKit'

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

  static readonly PENDING_EXTRACT_BUSY_MESSAGE_ZH: string = '已经有进行中的AI提取任务'

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
  shouldSkipEditorAutoSave(noteId: string, editorContent: string, editorTitle?: string): boolean {
    const id = noteId.trim()
    if (id.length === 0) {
      return false
    }
    if (this.isBusyForNote(id)) {
      return true
    }
    const result = this.lastResultInternal
    if (result === null || result.noteId !== id || !result.success) {
      return false
    }
    if (result.content !== undefined && result.content !== editorContent) {
      return true
    }
    if (editorTitle !== undefined && result.title !== undefined && result.title !== editorTitle) {
      return true
    }
    return false
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

  /** 若已有进行中的链接提取任务，弹 Toast 并返回 false。 */
  async ensureNoPendingExtractOrNotify(): Promise<boolean> {
    if (!(await NoteRepository.getInstance().hasAnyPendingExtract())) {
      return true
    }
    this.showGlobalToast(EditorUiStrings.loc(
      AiNoteBackgroundTaskService.PENDING_EXTRACT_BUSY_MESSAGE_ZH,
      'An AI link extraction task is already in progress',
      '進行中のAIリンク抽出タスクがあります'
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
    switchToPreviewOnSuccess: boolean = false,
    prompt: string = ''
  ): Promise<boolean> {
    const trimmedUrl = url.trim()
    if (trimmedUrl.length === 0) {
      return false
    }
    if (!(await this.ensureNoPendingExtractOrNotify())) {
      return false
    }
    const isVideo = LinkExtractClient.isVideoPlatformUrl(trimmedUrl)
    if (isVideo) {
      const ok = await SyncService.getInstance().isQingyuCloudAvailableForVideoExtract()
      if (!ok) {
        this.showGlobalToast(EditorUiStrings.loc(
          '视频链接提取需要登录并启用轻羽云同步',
          'Video link extract requires login and Qingyu Cloud sync',
          '動画リンク抽出にはログインとQingyu Cloud同期が必要です'
        ))
        return false
      }
    }
    return this.runLocked(
      noteId,
      EditorUiStrings.loc('AI 提交中…', 'Submitting…', '送信中…'),
      async (): Promise<AiNoteBackgroundTaskResult> => {
        // 占位笔记的标题与正文统一固定为「AI提取链接中」/「已提交链接摘要，提取完成后会自动更新笔记」，
        // 让首页列表以可识别的占位卡片呈现，提取完成后由 updateExtractInfo 覆盖 title/content。
        //
        // 如果当前笔记已经有用户编辑过的标题或正文，则只更新 sourceUrl + 提取状态，
        // 保留用户的标题/正文，避免覆盖用户已写的内容。
        const placeholderTitleZh = 'AI提取链接中'
        const placeholderTitleEn = 'AI is extracting the link'
        const placeholderTitleJa = 'AIリンク抽出中'
        const placeholderContentZh = '已提交链接摘要，提取完成后会自动更新笔记'
        const placeholderContentEn = 'Submitted; the note will update when extraction finishes.'
        const placeholderContentJa = '送信しました。抽出が完了するとノートが自動的に更新されます。'

        let appliedTitle: string | undefined = undefined
        let appliedContent: string | undefined = undefined
        let contentBefore: string | undefined = undefined

        let id = noteId.trim()
        if (id.length === 0) {
          // 从首页「更多方式」发起：先建占位笔记。
          const placeholder = await NoteRepository.getInstance().createNote({
            title: EditorUiStrings.loc(placeholderTitleZh, placeholderTitleEn, placeholderTitleJa),
            content: EditorUiStrings.loc(placeholderContentZh, placeholderContentEn, placeholderContentJa),
            tags: [],
            skipTitleAutoFill: true,
            sourceUrl: trimmedUrl
          })
          id = placeholder.id
          appliedTitle = EditorUiStrings.loc(placeholderTitleZh, placeholderTitleEn, placeholderTitleJa)
          appliedContent = EditorUiStrings.loc(placeholderContentZh, placeholderContentEn, placeholderContentJa)
          contentBefore = ''
        } else {
          // 从编辑器内发起：只有原笔记处于空状态才覆写为占位，否则保留用户内容。
          const existing = await NoteRepository.getInstance().getNote(id)
          if (existing !== null &&
            (existing.extractStatus === 'none' ||
              existing.extractStatus === 'failed' ||
              existing.extractStatus === 'partial')) {
            const hasUserContent = existing.title.trim().length > 0 ||
              existing.content.trim().length > 0
            contentBefore = existing.content
            if (hasUserContent) {
              // 已有编辑内容：保留 title/content，只补 sourceUrl 让 retry 与首页状态行可用。
              await NoteRepository.getInstance().saveDraft(id, {
                sourceUrl: trimmedUrl
              })
            } else {
              // 编辑器为空：写入占位标题/正文。
              await NoteRepository.getInstance().saveDraft(id, {
                title: EditorUiStrings.loc(placeholderTitleZh, placeholderTitleEn, placeholderTitleJa),
                content: EditorUiStrings.loc(placeholderContentZh, placeholderContentEn, placeholderContentJa),
                sourceUrl: trimmedUrl,
                skipTitleAutoFill: true
              })
              appliedTitle = EditorUiStrings.loc(placeholderTitleZh, placeholderTitleEn, placeholderTitleJa)
              appliedContent = EditorUiStrings.loc(placeholderContentZh, placeholderContentEn, placeholderContentJa)
            }
          }
        }

        if (isVideo) {
          await NoteRepository.getInstance().saveDraft(id, {
            audioId: AudioConstants.audioFileNameForVideoNote(id),
            voiceTranscribeStatus: 'running'
          })
        }

        await NoteRepository.getInstance().updateExtractInfo({
          noteId: id,
          status: 'queued'
        })

        const finalPrompt = prompt.length > 0
          ? prompt
          : EditorUiStrings.loc(
            '请根据链接内容生成结构化的 Markdown 笔记摘要。',
            'Generate a structured Markdown note summary from the link.',
            'リンク内容から構造化されたMarkdownノート要約を生成してください。'
          )

        const job = await LinkExtractClient.getInstance().submitJob(
          trimmedUrl,
          finalPrompt,
          summarize,
          id
        )
        Logger.info('LinkExtractDebug', `FLOW step=SUBMITJOB_OK noteId=${id} jobId=${job.jobId} status=${job.status} deduped=${job.deduped}`)

        await NoteRepository.getInstance().updateExtractInfo({
          noteId: id,
          jobId: job.jobId,
          status: 'running'
        })
        Logger.info('LinkExtractDebug', `FLOW step=SUBMITJOB_FLIPPED noteId=${id} status=running jobId=${job.jobId}`)

        const result = new AiNoteBackgroundTaskResult()
        result.noteId = id
        result.kind = 'extractLink'
        result.success = true
        result.message = EditorUiStrings.loc(
          summarize !== 0 ? '已提交链接摘要，提取完成后会自动更新笔记' : '已提交链接提取，提取完成后会自动更新笔记',
          summarize !== 0 ? 'Submitted; the note will update when extraction finishes.' : 'Submitted; the note will update when extraction finishes.',
          '送信しました。抽出が完了するとノートが自動的に更新されます。'
        )
        result.title = appliedTitle
        result.content = appliedContent
        result.contentBefore = contentBefore
        result.switchToPreviewOnSuccess = switchToPreviewOnSuccess
        return result
      },
      (e: Object): AiNoteBackgroundTaskResult => {
        const result = new AiNoteBackgroundTaskResult()
        result.noteId = noteId
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
        const localPath = outputPath.trim()
        if (localPath.length === 0) {
          throw new Error(EditorUiStrings.loc(
            '录音文件未找到，请稍后重试',
            'Recording file not found; please try again',
            '録音ファイルが見つかりません。後でもう一度お試しください'
          ))
        }
        try {
          if (!fs.accessSync(localPath) || fs.statSync(localPath).size <= 44) {
            throw new Error(EditorUiStrings.loc(
              '录音文件未找到，请稍后重试',
              'Recording file not found; please try again',
              '録音ファイルが見つかりません。後でもう一度お試しください'
            ))
          }
        } catch (e) {
          if (e instanceof Error &&
            (e.message.indexOf('录音文件') >= 0 || e.message.indexOf('Recording file') >= 0)) {
            throw e
          }
          throw new Error(EditorUiStrings.loc(
            '录音文件未找到，请稍后重试',
            'Recording file not found; please try again',
            '録音ファイルが見つかりません。後でもう一度お試しください'
          ))
        }

        await NoteRepository.getInstance().saveDraft(id, { voiceTranscribeStatus: 'running' })

        try {
          const audioId = AudioConstants.audioFileNameForNote(id)
          const note = await NoteRepository.getInstance().saveDraft(id, {
            audioId: audioId
          })
          const syncResult = await SyncService.getInstance().syncNote(id)
          if (!syncResult.success) {
            throw new Error(EditorUiStrings.loc('同步失败，请稍后重试', 'Sync failed; try again', '同期に失敗しました。後でもう一度お試しください'))
          }
          await SyncService.getInstance().uploadAudioForNoteOrThrow(id)
          const transcribeResult = await VoiceTranscribeClient.getInstance().transcribeLocalFile(localPath)
          const durationMs = AiNoteBackgroundTaskService.readAudioDurationMs(localPath)
          const segmentsJson = VoiceSegmentSplitter.encodeJson(
            VoiceSegmentSplitter.split(transcribeResult.text, durationMs)
          )
          const existing = await NoteRepository.getInstance().getNote(id)
          const contentBefore = existing?.content ?? ''
          await NoteRepository.getInstance().saveDraft(id, {
            content: transcribeResult.text,
            audioId: note.audioId,
            voiceSummary: transcribeResult.summary,
            voiceSegmentsJson: segmentsJson,
            voiceTranscribeStatus: 'succeeded'
          })
          const result = new AiNoteBackgroundTaskResult()
          result.noteId = id
          result.kind = 'voiceTranscribe'
          result.success = true
          result.message = ''
          result.content = transcribeResult.text
          result.contentBefore = contentBefore
          result.audioId = note.audioId
          return result
        } catch (e) {
          try {
            await NoteRepository.getInstance().saveDraft(id, { voiceTranscribeStatus: 'failed' })
          } catch (saveErr) {
            Logger.warn('AiNoteBgTask', `save failed voice status: ${JSON.stringify(saveErr)}`)
          }
          if (e instanceof Error) {
            throw e
          }
          throw new Error(`${e}`)
        }
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

  async runVoiceSummarize(noteId: string, text: string, notifyUser: boolean = true): Promise<boolean> {
    const id = noteId.trim()
    if (id.length === 0) {
      return false
    }
    return this.runLocked(
      id,
      EditorUiStrings.loc('AI 生成摘要中…', 'Generating summary…', 'AI要約生成中…'),
      async (): Promise<AiNoteBackgroundTaskResult> => {
        const summary = await VoiceTranscribeClient.getInstance().summarizeText(text)
        await NoteRepository.getInstance().saveDraft(id, { voiceSummary: summary })
        const result = new AiNoteBackgroundTaskResult()
        result.noteId = id
        result.kind = 'voiceTranscribe'
        result.success = true
        result.message = (notifyUser && summary.trim().length > 0)
          ? EditorUiStrings.loc('摘要已生成', 'Summary generated', '要約を生成しました')
          : ''
        return result
      },
      (e: Object): AiNoteBackgroundTaskResult => {
        const result = new AiNoteBackgroundTaskResult()
        result.noteId = id
        result.kind = 'voiceTranscribe'
        result.success = false
        result.message = notifyUser
          ? UserFacingMessage.forAi(
            e instanceof Error ? e.message : undefined,
            EditorUiStrings.loc('生成摘要失败，请稍后重试', 'Summary generation failed; try again', '要約生成に失敗しました。後でもう一度お試しください')
          )
          : ''
        return result
      }
    )
  }

  /** Best-effort WAV duration from local file header; returns 0 when unknown. */
  private static readAudioDurationMs(path: string): number {
    try {
      const size = fs.statSync(path).size
      if (size < 44) {
        return 0
      }
      const readLen = Math.min(size, 8192)
      const buf = new ArrayBuffer(readLen)
      const file = fs.openSync(path, fs.OpenMode.READ_ONLY)
      try {
        fs.readSync(file.fd, buf)
      } finally {
        fs.closeSync(file)
      }
      const view = new DataView(buf)
      if (AiNoteBackgroundTaskService.readAscii(view, 0, 4) !== 'RIFF' ||
        AiNoteBackgroundTaskService.readAscii(view, 8, 4) !== 'WAVE') {
        return 0
      }
      let offset = 12
      let sampleRate = 0
      let numChannels = 0
      let bitsPerSample = 0
      let dataSize = 0
      while (offset + 8 <= readLen) {
        const chunkId = AiNoteBackgroundTaskService.readAscii(view, offset, 4)
        const chunkSize = view.getUint32(offset + 4, true)
        if (chunkId === 'fmt ' && offset + 24 <= readLen) {
          numChannels = view.getUint16(offset + 10, true)
          sampleRate = view.getUint32(offset + 12, true)
          bitsPerSample = view.getUint16(offset + 22, true)
        } else if (chunkId === 'data') {
          dataSize = chunkSize
          break
        }
        offset += 8 + chunkSize + (chunkSize % 2)
      }
      if (sampleRate <= 0 || numChannels <= 0 || bitsPerSample <= 0 || dataSize <= 0) {
        return 0
      }
      const bytesPerSample = bitsPerSample / 8
      const numSamples = dataSize / (numChannels * bytesPerSample)
      return Math.floor((numSamples / sampleRate) * 1000)
    } catch (e) {
      Logger.warn('AiNoteBgTask', `readAudioDurationMs failed: ${JSON.stringify(e)}`)
      return 0
    }
  }

  private static readAscii(view: DataView, offset: number, length: number): string {
    let out = ''
    for (let i = 0; i < length; i++) {
      out += String.fromCharCode(view.getUint8(offset + i))
    }
    return out
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
    return result.success && (noteId.trim().length === 0 || result.noteId === noteId.trim())
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
