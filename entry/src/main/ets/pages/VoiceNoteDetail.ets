import { common } from '@kit.AbilityKit'
import { AudioConstants } from '../common/constants/AudioConstants'
import { Note, isExtractStatusPending } from '../common/model/Note'
import { ensureAiMembershipAccess } from '../common/utils/AiMembershipGateNavigation'
import { EditorUiStrings } from '../common/utils/EditorUiStrings'
import { Logger } from '../common/utils/Logger'
import { MarkdownUtils, type MarkdownBlock } from '../common/utils/MarkdownUtils'
import {
  saveShareCachePngToGallery,
  sharePngFromCachePath,
  updateSharePreviewImageLayoutVp
} from '../common/utils/NoteEditShareHelper'
import { NoteShareExportFlow, type ShareExportDelegate } from '../common/utils/NoteShareExportFlow'
import { PageCloseGuard } from '../common/utils/PageCloseGuard'
import { PageLifecycle } from '../common/utils/PageLifecycle'
import { VoiceSegmentSplitter, VoiceTranscriptSegment } from '../common/utils/VoiceSegmentSplitter'
import { NoteEditShareExportMount } from '../components/NoteEditShareExportMount'
import { NoteEditSharePreviewOverlay } from '../components/NoteEditSharePreviewOverlay'
import { NoteEditTagChip, NoteEditTagDropdown } from '../components/NoteEditTagDropdown'
import {
  AiNoteBackgroundTaskService,
  AiNoteBackgroundTaskResult
} from '../services/AiNoteBackgroundTaskService'
import { AiTagService } from '../services/AiTagService'
import { AppContextHolder } from '../services/AppContextHolder'
import { AudioPlaybackService } from '../services/AudioPlaybackService'
import { FileService } from '../services/FileService'
import { ImageCacheService } from '../services/ImageCacheService'
import { APP_LOCALE_REVISION_KEY, LocaleService } from '../services/LocaleService'
import { NoteApiClient, type ProfileBody } from '../services/NoteApiClient'
import { NoteRepository } from '../services/NoteRepository'
import { PreferencesService } from '../services/PreferencesService'
import { SyncService } from '../services/SyncService'
import { NoteShareExportCard } from '../share/NoteShareExportCard'
import { NoteSharePreviewSheetParams } from '../share/NoteSharePreviewSheet'
import { ShareCardTheme, ShareCardTone, ShareThemeColors } from '../share/ShareTheme'

interface VoiceNoteDetailParams {
  noteId?: string
  pendingVoicePath?: string
}

@Entry
@Component
struct VoiceNoteDetail {
  @StorageProp(APP_LOCALE_REVISION_KEY) localeRevision: number = 0

  /** 进程内已尝试静默补摘要的笔记，避免每次进页失败弹 Toast。 */
  private static summaryBackfillAttempted: Set<string> = new Set<string>()

  @State private loading: boolean = true
  @State private note: Note | null = null
  @State private title: string = ''
  @State private titleEditing: boolean = false
  @State private noteTags: string[] = []
  @State private tagPool: string[] = []
  @State private tagMenuVisible: boolean = false
  @State private aiTagCreating: boolean = false
  @State private tagBarX: number = 0
  @State private tagBarY: number = 0
  @State private tagBarWidth: number = 120
  @State private tagBarHeight: number = 32
  @State private tagBarInitialized: boolean = false
  @State private pageWidth: number = 0
  @State private pageHeight: number = 0

  @State private positionMs: number = 0
  @State private durationMs: number = 0
  @State private playing: boolean = false
  /** 因播完而停止（非中途暂停）。 */
  @State private playbackCompleted: boolean = false
  @State private audioLoading: boolean = true
  @State private audioFailed: boolean = false
  @State private wavePhase: number = 0

  @State private contentTabIndex: number = 0
  @State private aiWorking: boolean = false
  @State private aiWorkingOverlayMessage: string = 'AI 处理中…'

  @State private shareProfile: ProfileBody | null = null
  @State private previewBlocksState: MarkdownBlock[] = []
  @State private shareBodyMd: string = ''
  @State private shareExportColumnVp: number = 0
  @State private shareTheme: ShareCardTheme = ShareCardTheme.CLASSIC
  @State private shareTone: ShareCardTone = ShareCardTone.DARK
  @State private sharePreviewVisible: boolean = false
  @State private sharePreviewPath: string = ''
  @State private sharePreviewRegenerating: boolean = false
  @State private sharePreviewPreparing: boolean = false
  @State private shareOptionsSheetVisible: boolean = false
  @State private shareSheetRevision: number = 0
  @State private shareCardCaptureKey: number = 0
  @State private sharePreviewImageHeightVp: number = 0
  @State private shareExportScrollBg: string = '#FF1A1A1C'
  @State private shareExportActive: boolean = false
  @State private shareExportTheme: ShareCardTheme = ShareCardTheme.CLASSIC
  @State private shareExportTone: ShareCardTone = ShareCardTone.DARK
  @State private shareExportSnapshotCompatMode: boolean = false
  @State private shareExportSnapshotSkipQr: boolean = false
  @State private shareShowAppIcon: boolean = false

  private noteId: string = ''
  private pendingVoicePath: string = ''
  private bootstrapStarted: boolean = false
  private pendingVoiceHandled: boolean = false
  private lastPanOffsetX: number = 0
  private lastPanOffsetY: number = 0
  private waveTimer: number = -1
  private initGeneration: number = 0
  private loadedAudioId: string = ''
  private lastAppliedAiBgResult: AiNoteBackgroundTaskResult | null = null
  private shareScroller: Scroller = new Scroller()
  private shareCardHeight: number = 0
  private filesDirCache: string = ''
  private extractPollTimer: number = -1
  private lastAudioSyncAttemptMs: number = 0

  private lifecycle = new PageLifecycle()
  private closeGuard = new PageCloseGuard()
  private playbackService: AudioPlaybackService = AudioPlaybackService.getInstance()
  private onAiBackgroundTaskChanged = (): void => {
    this.handleAiBackgroundTaskChanged()
  }

  private swiperController: SwiperController = new SwiperController()

  private shouldBlockForExtractOrAudio(): boolean {
    const n = this.note
    if (n === null) {
      return false
    }
    if (isExtractStatusPending(n.extractStatus)) {
      return true
    }
    if (n.extractStatus === 'failed') {
      return false
    }
    if ((n.audioId ?? '').trim().length === 0) {
      return false
    }
    return this.audioFailed
  }

  private showBlockingOverlay(): boolean {
    return this.aiWorking || this.shouldBlockForExtractOrAudio()
  }

  private shouldShowTranscribeFailure(): boolean {
    const failed = this.note?.voiceTranscribeStatus === 'failed'
    const content = this.note?.content.trim() ?? ''
    return failed && content.length === 0
  }

  private transcriptPlainText(): string {
    return this.note?.content.trim() ?? ''
  }

  aboutToAppear(): void {
    this.lifecycle.appear()
    this.closeGuard.reset()
    const params = this.getUIContext().getRouter().getParams() as VoiceNoteDetailParams
    this.noteId = `${params?.noteId ?? ''}`.trim()
    this.pendingVoicePath = `${params?.pendingVoicePath ?? ''}`.trim()
    this.pendingVoiceHandled = false
    this.aiWorkingOverlayMessage = EditorUiStrings.loc('AI 处理中…', 'AI processing…', 'AI処理中…')
    const ctx = this.obtainUiAbilityContext()
    if (ctx !== undefined) {
      this.filesDirCache = ctx.filesDir
    }
    AiNoteBackgroundTaskService.getInstance().addListener(this.onAiBackgroundTaskChanged)
    this.syncAiWorkingFromBackgroundTask()
    void this.bootstrap()
  }

  aboutToDisappear(): void {
    this.lifecycle.disappear()
    this.clearExtractPollTimer()
    AiNoteBackgroundTaskService.getInstance().removeListener(this.onAiBackgroundTaskChanged)
    this.clearWaveTimer()
    this.playbackService.setCallbacks(undefined, undefined)
    void this.playbackService.pause()
  }

  onBackPress(): boolean {
    this.handleToolbarBack()
    return true
  }

  private handleToolbarBack(): void {
    this.closeGuard.runBack(() => {
      this.getUIContext().getRouter().back()
    }, 'VoiceNoteDetail')
  }

  private clearWaveTimer(): void {
    if (this.waveTimer >= 0) {
      clearInterval(this.waveTimer)
      this.waveTimer = -1
    }
  }

  private startWaveTimer(): void {
    this.clearWaveTimer()
    this.waveTimer = setInterval((): void => {
      if (this.playing) {
        this.wavePhase = (this.wavePhase + 0.04) % 1.0
      }
    }, 50)
  }

  private hasSummary(): boolean {
    return (this.note?.voiceSummary.trim() ?? '').length > 0
  }

  private segments(): VoiceTranscriptSegment[] {
    return VoiceSegmentSplitter.decodeJson(this.note?.voiceSegmentsJson ?? '')
  }

  private async bootstrap(): Promise<void> {
    await this.reloadNote(true)
    if (!this.lifecycle.isActive() || this.bootstrapStarted) {
      return
    }
    this.bootstrapStarted = true
    await this.refreshTagPool()
    await this.ensureVoicePipeline()
    this.ensureExtractOrAudioPoll()
  }

  private clearExtractPollTimer(): void {
    if (this.extractPollTimer >= 0) {
      clearInterval(this.extractPollTimer)
      this.extractPollTimer = -1
    }
  }

  private ensureExtractOrAudioPoll(): void {
    if (!this.shouldBlockForExtractOrAudio()) {
      this.clearExtractPollTimer()
      return
    }
    if (this.extractPollTimer >= 0) {
      return
    }
    this.extractPollTimer = setInterval((): void => {
      void this.pollExtractOrAudio()
    }, 3000)
    void this.pollExtractOrAudio()
  }

  private async pollExtractOrAudio(): Promise<void> {
    if (!this.lifecycle.isActive()) {
      return
    }
    const current = this.note
    if (current === null) {
      return
    }
    if (isExtractStatusPending(current.extractStatus)) {
      await NoteRepository.getInstance().refreshExtractJobForNote(this.noteId)
      if (!this.lifecycle.isActive()) {
        return
      }
      await this.reloadNote(true)
    } else if (this.audioFailed && (current.audioId ?? '').trim().length > 0) {
      const now = Date.now()
      if (now - this.lastAudioSyncAttemptMs < 3000) {
        return
      }
      this.lastAudioSyncAttemptMs = now
      await SyncService.getInstance().syncNote(this.noteId)
      if (!this.lifecycle.isActive()) {
        return
      }
      await this.initPlayer(current.audioId)
    }
    if (!this.shouldBlockForExtractOrAudio()) {
      this.clearExtractPollTimer()
      await this.ensureVoicePipeline()
    }
  }

  private async reloadNote(refreshAudio: boolean): Promise<void> {
    if (this.noteId.length === 0) {
      this.loading = false
      return
    }
    const loaded = await NoteRepository.getInstance().getNote(this.noteId)
    if (!this.lifecycle.isActive()) {
      return
    }
    this.note = loaded
    this.loading = false
    if (loaded !== null) {
      this.noteTags = this.normalizeTags(loaded.tags)
      if (!this.titleEditing) {
        this.title = loaded.title
      }
    }
    if (refreshAudio && (loaded?.audioId.trim().length ?? 0) > 0) {
      await this.initPlayer(loaded!.audioId)
    }
    if (this.bootstrapStarted) {
      this.ensureExtractOrAudioPoll()
    }
  }

  private async ensureVoicePipeline(): Promise<void> {
    const current = this.note
    if (current === null || this.noteId.length === 0) {
      return
    }
    if (isExtractStatusPending(current.extractStatus)) {
      return
    }
    const pending = this.pendingVoicePath.trim()
    if (pending.length > 0 && !this.pendingVoiceHandled) {
      this.pendingVoiceHandled = true
      this.pendingVoicePath = ''
      if (!(await ensureAiMembershipAccess(this.getUIContext()))) {
        return
      }
      this.aiWorking = true
      this.aiWorkingOverlayMessage = EditorUiStrings.loc('AI 处理中…', 'AI processing…', 'AI処理中…')
      const svc = AiNoteBackgroundTaskService.getInstance()
      await svc.runVoiceTranscribe(this.noteId, pending)
      if (!this.lifecycle.isActive()) {
        return
      }
      await this.reloadNote(true)
      return
    }

    const durationMs = this.durationMs > 0 ? this.durationMs : 0
    const content = current.content.trim()
    const existingSegments = VoiceSegmentSplitter.decodeJson(current.voiceSegmentsJson)
    if (content.length > 0 &&
      existingSegments.length === 0 &&
      durationMs > VoiceSegmentSplitter.minDurationMsForSlices) {
      const segmentsJson = VoiceSegmentSplitter.encodeJson(
        VoiceSegmentSplitter.split(content, durationMs)
      )
      await NoteRepository.getInstance().saveDraft(this.noteId, {
        voiceSegmentsJson: segmentsJson
      })
      if (!this.lifecycle.isActive()) {
        return
      }
      await this.reloadNote(false)
    }

    const latest = await NoteRepository.getInstance().getNote(this.noteId)
    if (!this.lifecycle.isActive() || latest === null) {
      return
    }
    if (latest.content.trim().length > 0 &&
      latest.voiceSummary.trim().length === 0 &&
      !VoiceNoteDetail.summaryBackfillAttempted.has(this.noteId)) {
      VoiceNoteDetail.summaryBackfillAttempted.add(this.noteId)
      this.aiWorking = true
      this.aiWorkingOverlayMessage = EditorUiStrings.loc('AI 处理中…', 'AI processing…', 'AI処理中…')
      // 列表进入历史笔记补摘要：失败不弹「语音转文字失败」。
      await AiNoteBackgroundTaskService.getInstance().runVoiceSummarize(
        this.noteId,
        latest.content,
        false
      )
      if (!this.lifecycle.isActive()) {
        return
      }
      await this.reloadNote(false)
    }
  }

  private localAudioPath(audioId: string): string {
    const ctx = AppContextHolder.tryGetContext()
    const base = ctx?.filesDir ?? ''
    return `${base}/${AudioConstants.audioDirectory}/${audioId}`
  }

  private async initPlayer(audioId: string): Promise<void> {
    const generation = ++this.initGeneration
    const trimmed = audioId.trim()
    if (trimmed.length === 0 || this.noteId.length === 0) {
      this.audioLoading = false
      this.audioFailed = true
      return
    }
    if (this.loadedAudioId === trimmed && !this.audioLoading && !this.audioFailed) {
      return
    }
    this.audioLoading = true
    this.audioFailed = false
    this.playbackCompleted = false
    this.playing = false
    this.positionMs = 0
    this.playbackService.setCallbacks(
      (position: number, duration: number): void => {
        this.positionMs = position
        this.durationMs = duration
      },
      (isPlaying: boolean, completed: boolean): void => {
        this.playing = isPlaying
        this.playbackCompleted = completed
        if (completed && this.durationMs > 0) {
          this.positionMs = this.durationMs
        }
        if (isPlaying) {
          this.startWaveTimer()
        } else {
          this.clearWaveTimer()
        }
      }
    )
    let path = this.localAudioPath(trimmed)
    if (!FileService.fileExists(path)) {
      await SyncService.getInstance().syncNote(this.noteId)
      path = this.localAudioPath(trimmed)
    }
    if (generation !== this.initGeneration) {
      return
    }
    if (!FileService.fileExists(path)) {
      Logger.warn('VoiceNoteDetail', `audio missing: ${path}`)
      this.audioLoading = false
      this.audioFailed = true
      return
    }
    try {
      await this.playbackService.load(path)
      if (generation !== this.initGeneration) {
        return
      }
      this.durationMs = this.playbackService.getDurationMs()
      this.loadedAudioId = trimmed
      this.audioLoading = false
      this.audioFailed = false
    } catch (error) {
      Logger.warn('VoiceNoteDetail', `initPlayer failed: ${JSON.stringify(error)}`)
      if (generation !== this.initGeneration) {
        return
      }
      this.audioLoading = false
      this.audioFailed = true
    }
  }

  private formatClock(ms: number): string {
    const totalSec = Math.max(0, Math.floor(ms / 1000))
    const m = Math.floor(totalSec / 60).toString().padStart(2, '0')
    const s = (totalSec % 60).toString().padStart(2, '0')
    return `${m}:${s}`
  }

  private formatRecordedAt(ms: number): string {
    if (ms <= 0) {
      return '--'
    }
    const dt = new Date(ms)
    const two = (n: number): string => n.toString().padStart(2, '0')
    return `${dt.getFullYear()}-${two(dt.getMonth() + 1)}-${two(dt.getDate())} ` +
      `${two(dt.getHours())}:${two(dt.getMinutes())}`
  }

  private waveNoise(x: number, y: number): number {
    const v = Math.sin(x * 12.9898 + y * 78.233) * 43758.5453
    return v - Math.floor(v)
  }

  private waveAmplitudes(): number[] {
    const count = 48
    const result: number[] = []
    const t = this.wavePhase
    const posSeed = this.positionMs / 80.0
    for (let i = 0; i < count; i++) {
      if (!this.playing) {
        const n = this.waveNoise(i * 1.7, 0.37)
        result.push(Math.min(0.95, Math.max(0.12, 0.22 + n * 0.7)))
      } else {
        const n1 = this.waveNoise(i * 2.1, t * 6.0 + posSeed)
        const n2 = this.waveNoise(i * 5.3 + 1.2, t * 11.0 + posSeed * 0.5)
        result.push(Math.min(1.0, Math.max(0.12, 0.18 + n1 * 0.55 + n2 * 0.27)))
      }
    }
    return result
  }

  private playbackProgress(): number {
    if (this.playbackCompleted) {
      return 1.0
    }
    if (this.durationMs <= 0) {
      return 0.0
    }
    // 暂停时也按当前进度切分绿/灰，勿在未播放态强制全绿。
    return Math.min(1.0, Math.max(0.0, this.positionMs / this.durationMs))
  }

  private playerTimeLabel(): string {
    const showElapsed =
      !this.playbackCompleted && (this.playing || this.positionMs > 0)
    if (showElapsed) {
      return `${this.formatClock(this.positionMs)} / ${this.formatClock(this.durationMs)}`
    }
    return this.formatClock(this.durationMs)
  }

  private activeSegmentIndex(): number {
    const segs = this.segments()
    if (segs.length === 0) {
      return -1
    }
    const pos = this.positionMs
    let active = 0
    for (let i = 0; i < segs.length; i++) {
      if (segs[i].startMs <= pos) {
        active = i
      } else {
        break
      }
    }
    return active
  }

  private togglePlay(): void {
    const targetPlaying = !this.playing
    if (targetPlaying && this.playbackCompleted) {
      this.playbackCompleted = false
      this.positionMs = 0
      void this.playbackService.seekTo(0).then((): void => {
        this.playing = true
        void this.playbackService.play().catch((): void => {
          this.playing = false
        })
      })
      return
    }
    this.playing = targetPlaying
    void this.playbackService.setPlaying(targetPlaying).catch((): void => {
      this.playing = !targetPlaying
    })
  }

  private onSegmentTap(segment: VoiceTranscriptSegment): void {
    const segs = this.segments()
    const index = segs.findIndex((s: VoiceTranscriptSegment) =>
      s.startMs === segment.startMs && s.text === segment.text)
    const active = this.playing ? this.activeSegmentIndex() : -1
    if (this.playing && index === active) {
      void this.playbackService.pause()
      return
    }
    void this.playbackService.seekTo(segment.startMs).then((): void => {
      this.playbackCompleted = false
      void this.playbackService.play()
    })
  }

  private async commitTitle(): Promise<void> {
    this.titleEditing = false
    const next = this.title.trim()
    const current = this.note?.title ?? ''
    if (next === current || this.noteId.length === 0) {
      return
    }
    await NoteRepository.getInstance().saveDraft(this.noteId, {
      title: next,
      skipTitleAutoFill: true
    })
    if (!this.lifecycle.isActive()) {
      return
    }
    await this.reloadNote(false)
  }

  private normalizeTags(tags?: string[]): string[] {
    const seen: Set<string> = new Set()
    const normalized: string[] = []
    for (const rawTag of tags ?? []) {
      const tag = `${rawTag ?? ''}`.trim()
      if (tag.length === 0 || seen.has(tag)) {
        continue
      }
      seen.add(tag)
      normalized.push(tag)
    }
    normalized.sort((left: string, right: string) => left.localeCompare(right, 'zh-Hans-CN'))
    return normalized
  }

  private async ensurePreferencesInitialized(): Promise<void> {
    const context = AppContextHolder.tryGetContext()
    if (context) {
      await PreferencesService.getInstance().init(context)
    }
  }

  private async refreshTagPool(): Promise<void> {
    await this.ensurePreferencesInitialized()
    const stored = await PreferencesService.getInstance().getNoteTags()
    const allNotes = await NoteRepository.getInstance().listNotes()
    const fromNotes: string[] = []
    for (const n of allNotes) {
      fromNotes.push(...n.tags)
    }
    if (!this.lifecycle.isActive()) {
      return
    }
    this.tagPool = this.normalizeTags(fromNotes.concat(stored).concat(this.noteTags))
  }

  private async onTagChecked(tag: string, selected: boolean): Promise<void> {
    const next: string[] = [...this.noteTags]
    if (selected) {
      if (!next.includes(tag)) {
        next.push(tag)
      }
    } else {
      const idx = next.indexOf(tag)
      if (idx >= 0) {
        next.splice(idx, 1)
      }
    }
    this.noteTags = this.normalizeTags(next)
    if (this.noteId.length === 0) {
      return
    }
    await NoteRepository.getInstance().saveDraft(this.noteId, { tags: this.noteTags })
    if (!this.lifecycle.isActive()) {
      return
    }
    await this.reloadNote(false)
    await this.refreshTagPool()
  }

  private async onAiCreateTag(): Promise<void> {
    if (this.aiTagCreating) {
      return
    }
    if (!(await ensureAiMembershipAccess(this.getUIContext()))) {
      return
    }
    this.aiTagCreating = true
    this.tagMenuVisible = false
    try {
      await this.refreshTagPool()
      const suggested = await AiTagService.getInstance().suggestTag(
        this.title,
        this.note?.content ?? '',
        this.tagPool
      )
      if (!this.lifecycle.isActive()) {
        return
      }
      const isNew = AiTagService.findExactPoolTag(suggested, this.tagPool) === null
      if (isNew) {
        const stored = await PreferencesService.getInstance().getNoteTags()
        await PreferencesService.getInstance().saveNoteTags(this.normalizeTags(stored.concat([suggested])))
        await this.refreshTagPool()
      }
      await this.onTagChecked(suggested, true)
    } catch (error) {
      Logger.error('VoiceNoteDetail', `onAiCreateTag failed: ${JSON.stringify(error)}`)
    } finally {
      if (this.lifecycle.isActive()) {
        this.aiTagCreating = false
      }
    }
  }

  private async openTagManage(): Promise<void> {
    this.tagMenuVisible = false
    try {
      await this.getUIContext().getRouter().pushUrl({ url: 'pages/TagManage' })
    } catch (error) {
      Logger.warn('VoiceNoteDetail', `openTagManage failed: ${JSON.stringify(error)}`)
    }
  }

  private obtainUiAbilityContext(): common.UIAbilityContext | undefined {
    return AppContextHolder.tryGetContext()
  }

  private showToast(message: string): void {
    if (message.trim().length === 0) {
      return
    }
    try {
      this.getUIContext().getPromptAction().showToast({
        message,
        duration: 1600
      })
    } catch (_) {
    }
  }

  private resolveShareBody(): string {
    const current = this.note
    if (current === null) {
      return ''
    }
    if (this.hasSummary() && this.contentTabIndex === 1) {
      return current.voiceSummary
    }
    return current.content
  }

  private refreshSharePreviewBlocks(content: string): void {
    this.shareBodyMd = content
    this.previewBlocksState = MarkdownUtils.parseBlocks(content)
  }

  private shareExportDelegate(): ShareExportDelegate {
    const delegate: ShareExportDelegate = {
      logTag: 'VoiceNoteDetail',
      getUIContext: (): UIContext => this.getUIContext(),
      obtainUiAbilityContext: (): common.UIAbilityContext | undefined => this.obtainUiAbilityContext(),
      getPageWidth: (): number => this.pageWidth,
      getPageHeight: (): number => this.pageHeight,
      getShareScroller: (): Scroller => this.shareScroller,
      getShareBody: (): string => this.shareBodyMd,
      getShareTitle: (): string => this.title,
      getNoteCreatedAt: (): number => this.note?.createdAt ?? 0,
      getFilesDirCache: (): string => this.filesDirCache,
      getShareProfile: (): ProfileBody | null => this.shareProfile,
      getPreviewBlocks: (): MarkdownBlock[] => this.previewBlocksState,
      refreshPreviewBlocks: (content: string): void => {
        this.refreshSharePreviewBlocks(content)
      },
      getShareTheme: (): ShareCardTheme => this.shareTheme,
      setShareTheme: (v: ShareCardTheme): void => {
        this.shareTheme = v
      },
      getShareTone: (): ShareCardTone => this.shareTone,
      setShareTone: (v: ShareCardTone): void => {
        this.shareTone = v
      },
      getShareExportTheme: (): ShareCardTheme => this.shareExportTheme,
      setShareExportTheme: (v: ShareCardTheme): void => {
        this.shareExportTheme = v
      },
      getShareExportTone: (): ShareCardTone => this.shareExportTone,
      setShareExportTone: (v: ShareCardTone): void => {
        this.shareExportTone = v
      },
      getShareExportSnapshotCompatMode: (): boolean => this.shareExportSnapshotCompatMode,
      setShareExportSnapshotCompatMode: (v: boolean): void => {
        this.shareExportSnapshotCompatMode = v
      },
      getShareExportSnapshotSkipQr: (): boolean => this.shareExportSnapshotSkipQr,
      setShareExportSnapshotSkipQr: (v: boolean): void => {
        this.shareExportSnapshotSkipQr = v
      },
      getShareShowAppIcon: (): boolean => this.shareShowAppIcon,
      getShareExportActive: (): boolean => this.shareExportActive,
      setShareExportActive: (v: boolean): void => {
        this.shareExportActive = v
      },
      getShareExportScrollBg: (): string => this.shareExportScrollBg,
      setShareExportScrollBg: (v: string): void => {
        this.shareExportScrollBg = v
      },
      getShareExportColumnVp: (): number => this.shareExportColumnVp,
      setShareExportColumnVp: (v: number): void => {
        this.shareExportColumnVp = v
      },
      getShareCardHeight: (): number => this.shareCardHeight,
      setShareCardHeight: (v: number): void => {
        this.shareCardHeight = v
      },
      getShareCardCaptureKey: (): number => this.shareCardCaptureKey,
      bumpShareCardCaptureKey: (): void => {
        this.shareCardCaptureKey++
      }
    }
    return delegate
  }

  private shareExportFlow(): NoteShareExportFlow {
    return new NoteShareExportFlow(this.shareExportDelegate())
  }

  private async runShareNote(): Promise<void> {
    if (this.sharePreviewPreparing || this.sharePreviewRegenerating || this.note === null) {
      return
    }
    this.sharePreviewPreparing = true
    this.showToast(EditorUiStrings.loc('正在生成长图…', 'Generating long image…', '長画像を生成中…'))
    try {
      this.refreshSharePreviewBlocks(this.resolveShareBody())
      this.shareProfile = await NoteApiClient.getInstance().fetchProfile()
      const avatarUrl = (this.shareProfile?.avatar_url ?? '').trim()
      if (avatarUrl.length > 0) {
        await ImageCacheService.getInstance().precache(avatarUrl)
      }
      await this.ensurePreferencesInitialized()
      const savedTheme = ShareThemeColors.parseTheme(
        await PreferencesService.getInstance().getShareCardTheme()
      )
      const savedTone = ShareThemeColors.parseTone(
        await PreferencesService.getInstance().getShareCardTone()
      )
      this.shareTheme = savedTheme
      this.shareTone = savedTone
      this.shareShowAppIcon = false
      const path = await this.shareExportFlow().exportShareImageToCache(savedTheme, savedTone)
      if (!path || path.length === 0) {
        this.showToast(EditorUiStrings.loc('生成长图失败', 'Failed to generate long image', '長画像の生成に失敗しました'))
        return
      }
      this.sharePreviewPath = path
      this.sharePreviewImageHeightVp = await updateSharePreviewImageLayoutVp(path, this.pageWidth)
      this.sharePreviewVisible = true
      this.shareOptionsSheetVisible = true
      this.shareSheetRevision++
    } finally {
      this.sharePreviewPreparing = false
    }
  }

  private async persistShareCardPreferences(theme: ShareCardTheme, tone: ShareCardTone): Promise<void> {
    await this.ensurePreferencesInitialized()
    await PreferencesService.getInstance().setShareCardTheme(`${theme}`)
    await PreferencesService.getInstance().setShareCardTone(`${tone}`)
  }

  private async regenerateSharePreview(
    captureTheme?: ShareCardTheme,
    captureTone?: ShareCardTone
  ): Promise<void> {
    const theme = captureTheme ?? this.shareTheme
    const tone = captureTone ?? this.shareTone
    this.shareTheme = theme
    this.shareTone = tone
    this.sharePreviewRegenerating = true
    this.refreshSharePreviewBlocks(this.resolveShareBody())
    const path = await this.shareExportFlow().exportShareImageToCache(theme, tone)
    this.sharePreviewRegenerating = false
    if (path && path.length > 0) {
      this.sharePreviewPath = path
      this.sharePreviewImageHeightVp = await updateSharePreviewImageLayoutVp(path, this.pageWidth)
    } else {
      this.showToast(EditorUiStrings.loc('切换主题失败', 'Failed to switch theme', 'テーマの切り替えに失敗しました'))
    }
  }

  private closeSharePreview(): void {
    this.sharePreviewVisible = false
    this.shareOptionsSheetVisible = false
    this.sharePreviewPath = ''
    this.sharePreviewImageHeightVp = 0
  }

  private async onSharePreviewSave(): Promise<void> {
    if (this.sharePreviewPath.length === 0) {
      return
    }
    const context = this.obtainUiAbilityContext()
    if (context === undefined) {
      return
    }
    const ok = await saveShareCachePngToGallery(context, this.sharePreviewPath)
    this.showToast(ok
      ? EditorUiStrings.loc('已保存到相册', 'Saved to album', 'アルバムに保存しました')
      : EditorUiStrings.loc('保存到相册失败', 'Failed to save to album', 'アルバムへの保存に失敗しました'))
    if (ok) {
      this.closeSharePreview()
    }
  }

  private async onSharePreviewShareOthers(): Promise<void> {
    if (this.sharePreviewPath.length === 0) {
      return
    }
    const context = this.obtainUiAbilityContext()
    if (context === undefined) {
      this.showToast(EditorUiStrings.loc('分享失败', 'Share failed', '共有に失敗しました'))
      return
    }
    const cachePath = this.sharePreviewPath
    this.closeSharePreview()
    const ok = await sharePngFromCachePath(context, cachePath)
    if (!ok) {
      this.showToast(EditorUiStrings.loc('分享失败', 'Share failed', '共有に失敗しました'))
    }
  }

  private sharePreviewSheetParams(): NoteSharePreviewSheetParams {
    return {
      onThemeChange: (theme: ShareCardTheme): void => {
        if (this.shareTheme !== theme) {
          this.shareTheme = theme
          this.shareSheetRevision++
          void this.persistShareCardPreferences(theme, this.shareTone)
          void this.regenerateSharePreview(theme, this.shareTone)
        }
      },
      onToneChange: (tone: ShareCardTone): void => {
        if (this.shareTone !== tone) {
          this.shareTone = tone
          this.shareSheetRevision++
          void this.persistShareCardPreferences(this.shareTheme, tone)
          void this.regenerateSharePreview(this.shareTheme, tone)
        }
      },
      onFooterImageToggle: (): void => {
        this.shareShowAppIcon = !this.shareShowAppIcon
        void this.regenerateSharePreview()
      },
      onSave: (): void => {
        void this.onSharePreviewSave()
      },
      onShare: (): void => {
        void this.onSharePreviewShareOthers()
      },
      onCancel: (): void => {
        this.closeSharePreview()
      }
    }
  }

  private shareExportMountKey(): string {
    return this.shareExportFlow().shareExportMountKey()
  }

  @Builder
  private buildShareExportCard() {
    NoteShareExportCard({
      theme: this.shareExportTheme,
      tone: this.shareExportTone,
      snapshotCompatMode: this.shareExportSnapshotCompatMode,
      snapshotSkipQr: this.shareExportSnapshotSkipQr,
      showAppIcon: this.shareShowAppIcon,
      styleKey: `${this.shareCardCaptureKey}_${this.shareExportTheme}_${this.shareExportTone}`,
      title: this.title,
      content: this.shareBodyMd,
      previewBlocks: this.previewBlocksState,
      filesDirCache: this.filesDirCache,
      noteCreatedAt: this.note?.createdAt ?? 0,
      shareProfile: this.shareProfile,
      onLinkToast: (href: string): void => {
        this.showToast(href)
      },
      onAreaHeight: (h: number): void => {
        const prev = this.shareExportColumnVp
        if (prev > 0 && Math.abs(prev - h) < 0.5) {
          return
        }
        this.shareExportColumnVp = h
      }
    })
      .key(`share_export_${this.shareExportMountKey()}`)
  }

  private async handleShare(): Promise<void> {
    await this.runShareNote()
  }

  private syncAiWorkingFromBackgroundTask(): void {
    const svc = AiNoteBackgroundTaskService.getInstance()
    const busyHere = svc.isBusyForNote(this.noteId)
    if (busyHere) {
      this.aiWorking = true
      this.aiWorkingOverlayMessage = svc.overlayMessage
      return
    }
    if (this.aiWorking) {
      this.aiWorking = false
    }
  }

  private handleAiBackgroundTaskChanged(): void {
    if (!this.lifecycle.isActive()) {
      return
    }
    const svc = AiNoteBackgroundTaskService.getInstance()
    const result = svc.lastResult
    if (result !== null &&
      result.noteId === this.noteId &&
      result !== this.lastAppliedAiBgResult) {
      this.lastAppliedAiBgResult = result
      if (result.success) {
        void this.reloadNote(result.audioId !== undefined && result.audioId.trim().length > 0)
      }
    }
    this.syncAiWorkingFromBackgroundTask()
    if (!svc.isBusyForNote(this.noteId)) {
      void this.reloadNote(false)
    }
  }

  private floatMenuPosX(): number {
    const menuWidth = 154
    let x = this.tagBarX + this.tagBarWidth - menuWidth
    if (x < 0) {
      x = 0
    }
    if (x > this.pageWidth - menuWidth) {
      x = Math.max(0, this.pageWidth - menuWidth)
    }
    return x
  }

  private tagMenuPosY(): number {
    const itemHeight = 44
    const menuHeight = Math.min(320, 56 + this.tagPool.length * itemHeight)
    const buttonCenterY = this.tagBarY + this.tagBarHeight / 2
    if (buttonCenterY > this.pageHeight / 2) {
      return this.tagBarY - menuHeight - 8
    }
    return this.tagBarY + this.tagBarHeight + 8
  }

  @Builder
  private buildHeader() {
    // 与关于页一致：左侧圆角返回、标题区 layoutWeight；本页右侧保留分享。
    Row() {
      Row() {
        SymbolGlyph($r('sys.symbol.arrow_left'))
          .fontSize(18)
          .fontColor([$r('app.color.primary_text')])
      }
      .height('100%')
      .padding({
        left: $r('app.float.toolbar_icon_button_padding_h'),
        right: $r('app.float.toolbar_icon_button_padding_h')
      })
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r('app.color.surface_muted'))
      .borderRadius($r('app.float.pill_radius'))
      .onClick((): void => {
        this.handleToolbarBack()
      })

      Row() {
        Text(LocaleService.loc('语音笔记', 'Voice note', '音声ノート'))
          .fontSize($r('app.float.title_font_size'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
          .textAlign(TextAlign.Center)
      }
      .layoutWeight(1)
      .height('100%')
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Start)

      Row() {
        SymbolGlyph($r('sys.symbol.share'))
          .fontSize(18)
          .fontColor([$r('app.color.primary_text')])
      }
      .height('100%')
      .padding({
        left: $r('app.float.toolbar_icon_button_padding_h'),
        right: $r('app.float.toolbar_icon_button_padding_h')
      })
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .onClick((): void => {
        if (this.note !== null) {
          void this.handleShare()
        }
      })
    }
    .width('100%')
    .height($r('app.float.toolbar_height'))
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildTitleBlock() {
    if (this.titleEditing) {
      // 大号粗体标题 + 光标需要足够行盒高度；padding(0) 会裁切首字顶部与 caret。
      TextInput({ text: this.title })
        .width('100%')
        .height(48)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .backgroundColor(Color.Transparent)
        .padding({ left: 0, right: 0, top: 8, bottom: 8 })
        .border({ width: 0 })
        .borderRadius(0)
        .showUnderline(false)
        .caretColor($r('app.color.accent'))
        .clip(false)
        .onChange((value: string): void => {
          this.title = value
        })
        .onBlur((): void => {
          void this.commitTitle()
        })
        .onSubmit((): void => {
          void this.commitTitle()
        })
    } else {
      Text(this.title.trim().length > 0
        ? this.title
        : LocaleService.loc('新录音', 'New recording', '新規録音'))
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .width('100%')
        .lineHeight(30)
        .onClick((): void => {
          this.titleEditing = true
        })
    }
  }

  @Builder
  private buildTagChips() {
    if (this.noteTags.length === 0) {
      Blank()
    } else {
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Start }) {
        ForEach(this.noteTags, (tag: string) => {
          NoteEditTagChip({ tag: tag })
            .margin({ right: 8, bottom: 6 })
        }, (tag: string) => `voice_tag_${tag}`)
      }
      .width('100%')
      .margin({ top: 8 })
    }
  }

  @Builder
  private buildWaveBars() {
    Row({ space: 2 }) {
      ForEach(this.waveAmplitudes(), (amp: number, index: number) => {
        Column()
          .width(3)
          .height(Math.max(6, amp * 32))
          .backgroundColor(((index + 0.5) / 48.0) <= this.playbackProgress()
            ? $r('app.color.accent')
            : '#FFD1D5DB')
          .borderRadius(2)
      }, (_: number, index: number) =>
        `wave_${index}_${this.wavePhase.toFixed(2)}_${this.positionMs}_${this.playing}_${this.playbackCompleted}`)
    }
    .width('100%')
    .height(32)
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildPlayer() {
    if (this.audioLoading) {
      Row() {
        LoadingProgress()
          .width(24)
          .height(24)
      }
      .width('100%')
      .padding({ top: 20, bottom: 20 })
      .justifyContent(FlexAlign.Center)
    } else if (this.audioFailed) {
      Row({ space: 12 }) {
        Text(LocaleService.loc('音频加载失败', 'Failed to load audio', '音声の読み込みに失敗しました'))
          .fontSize(14)
          .fontColor($r('app.color.secondary_text'))
          .layoutWeight(1)
        Button(LocaleService.loc('重试', 'Retry', '再試行'))
          .type(ButtonType.Normal)
          .fontSize(13)
          .height(32)
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.primary_text'))
          .border({ width: 1, color: $r('app.color.divider') })
          .borderRadius(8)
          .onClick((): void => {
            const id = this.note?.audioId ?? ''
            if (id.length > 0) {
              this.loadedAudioId = ''
              void this.initPlayer(id)
            }
          })
      }
      .width('100%')
      .padding({ top: 12, bottom: 12 })
    } else {
      Row() {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph(this.playing ? $r('sys.symbol.pause') : $r('sys.symbol.play'))
            .fontSize(22)
            .fontColor([Color.White])
            .margin({ left: this.playing ? 0 : 2 })
        }
        .width(40)
        .height(40)
        .backgroundColor($r('app.color.accent'))
        .onClick((): void => {
          this.togglePlay()
        })

        Blank().width(10)

        Column() {
          this.buildWaveBars()
        }
        .layoutWeight(1)

        Blank().width(10)

        Text(this.playerTimeLabel())
          .fontSize(13)
          .fontColor($r('app.color.secondary_text'))
      }
      .width('100%')
      .padding({
        left: 12,
        right: 12,
        top: 10,
        bottom: 10
      })
      .backgroundColor($r('app.color.voice_player_bar'))
      .border({ width: 1, color: $r('app.color.voice_player_bar_border') })
      .borderRadius(14)
      .margin({ top: 16 })
      .alignItems(VerticalAlign.Center)
    }
  }

  @Builder
  private buildMeta() {
    Row() {
      Text(`${LocaleService.loc('录音时间', 'Recorded at', '録音日時')}: ` +
        `${this.formatRecordedAt(this.note?.createdAt ?? 0)}`)
        .fontSize(12)
        .fontColor($r('app.color.secondary_text'))
        .layoutWeight(1)
      Text(`${LocaleService.loc('时长', 'Duration', '長さ')} ${this.formatClock(this.durationMs)}`)
        .fontSize(12)
        .fontColor($r('app.color.secondary_text'))
    }
    .width('100%')
    .padding({ top: 10 })
  }

  @Builder
  private buildSegmentList() {
    Column() {
      ForEach(this.segments(), (segment: VoiceTranscriptSegment, index: number) => {
        Row() {
          Text(this.formatClock(segment.startMs))
            .fontSize(12)
            .fontColor($r('app.color.secondary_text'))
            .width(48)
          Text(segment.text)
            .fontSize(15)
            .fontColor(this.playing && index === this.activeSegmentIndex()
              ? $r('app.color.accent')
              : $r('app.color.primary_text'))
            .fontWeight(this.playing && index === this.activeSegmentIndex()
              ? FontWeight.Medium
              : FontWeight.Normal)
            .lineHeight(23)
            .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
        .padding({ top: 8, bottom: 8 })
        .onClick((): void => {
          this.onSegmentTap(segment)
        })
      }, (segment: VoiceTranscriptSegment, index: number) =>
        `seg_${index}_${segment.startMs}`)
    }
    .width('100%')
    .margin({ top: 12 })
  }

  @Builder
  private buildTranscriptBody() {
    if (this.shouldShowTranscribeFailure()) {
      Text(LocaleService.loc(
        '语音转文字失败，请稍后重试',
        'Speech-to-text failed; try again',
        '音声認識に失敗しました。後でもう一度お試しください'
      ))
        .fontSize(15)
        .fontColor($r('app.color.secondary_text'))
        .margin({ top: 20 })
    } else if (this.segments().length === 0) {
      Text(this.transcriptPlainText())
        .fontSize(15)
        .fontColor($r('app.color.primary_text'))
        .lineHeight(24)
        .margin({ top: 16 })
    } else {
      this.buildSegmentList()
    }
  }

  @Builder
  private buildSummaryBody() {
    Text(this.note?.voiceSummary ?? '')
      .fontSize(15)
      .fontColor($r('app.color.primary_text'))
      .lineHeight(24)
      .margin({ top: 16 })
  }

  @Builder
  private buildTabBar() {
    Row() {
      Column() {
        Text(LocaleService.loc('转写文字', 'Transcript', '文字起こし'))
          .fontSize(15)
          .fontWeight(this.contentTabIndex === 0 ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.contentTabIndex === 0 ? $r('app.color.accent') : $r('app.color.secondary_text'))
        Divider()
          .strokeWidth(this.contentTabIndex === 0 ? 2 : 0)
          .color($r('app.color.accent'))
          .margin({ top: 8 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)
      .onClick((): void => {
        this.contentTabIndex = 0
        this.swiperController.changeIndex(0, true)
      })

      Column() {
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.wand_and_stars'))
            .fontSize(14)
            .fontColor([$r('app.color.accent')])
          Text(LocaleService.loc('摘要', 'Summary', '要約'))
            .fontSize(15)
            .fontWeight(this.contentTabIndex === 1 ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.contentTabIndex === 1 ? $r('app.color.accent') : $r('app.color.secondary_text'))
        }
        Divider()
          .strokeWidth(this.contentTabIndex === 1 ? 2 : 0)
          .color($r('app.color.accent'))
          .margin({ top: 8 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)
      .onClick((): void => {
        this.contentTabIndex = 1
        this.swiperController.changeIndex(1, true)
      })
    }
    .width('100%')
    .margin({ top: 16 })
  }

  @Builder
  private buildTabbedContent() {
    Column() {
      this.buildTabBar()
      Swiper(this.swiperController) {
        Column() {
          this.buildTranscriptBody()
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        Column() {
          this.buildSummaryBody()
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .index(this.contentTabIndex)
      .indicator(false)
      .loop(false)
      .height(Math.max(280, this.pageHeight * 0.45))
      .onChange((index: number): void => {
        this.contentTabIndex = index
      })
    }
    .width('100%')
  }

  @Builder
  private buildAiWorkingOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.35)')
      Column({ space: 16 }) {
        LoadingProgress()
          .width(40)
          .height(40)
          .color(Color.White)
        Text(EditorUiStrings.loc(
          '关闭页面可在后台继续执行',
          'You can leave this page; the task continues in the background',
          'ページを閉じてもバックグラウンドで続行されます'
        ))
          .fontSize(13)
          .fontColor('#D9FFFFFF')
          .textAlign(TextAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .zIndex(10005)
  }

  @Builder
  private buildDraggableTagBar() {
    Stack() {
      Row({ space: 4 }) {
        Row() {
          if (this.aiTagCreating) {
            LoadingProgress()
              .width(22)
              .height(22)
              .color($r('app.color.accent'))
          } else {
            Row({ space: 4 }) {
              Text('#')
                .fontSize(14)
                .fontColor($r('app.color.secondary_text'))
                .fontWeight(FontWeight.Medium)
              if (this.noteTags.length === 0) {
                Text(EditorUiStrings.loc('标签', 'Tags', 'タグ'))
                  .fontSize(12)
                  .fontColor($r('app.color.secondary_text'))
              } else {
                NoteEditTagChip({ tag: this.noteTags[0] })
                if (this.noteTags.length > 1) {
                  Text('...')
                    .fontSize(12)
                    .fontColor($r('app.color.secondary_text'))
                }
              }
            }
            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(14)
              .fontColor([$r('app.color.secondary_text')])
          }
        }
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .backgroundColor($r('app.color.surface_muted'))
        .borderRadius(18)
        .onClick((): void => {
          if (this.aiTagCreating) {
            return
          }
          void this.refreshTagPool()
          this.tagMenuVisible = !this.tagMenuVisible
        })
        .shadow({
          radius: 18,
          color: '#2A000000',
          offsetX: 0,
          offsetY: 3
        })
      }
      .onAreaChange((_, currentArea: Area) => {
        this.tagBarWidth = Number.parseFloat(`${currentArea.width}`) || 120
        this.tagBarHeight = Number.parseFloat(`${currentArea.height}`) || 32
        if (!this.tagBarInitialized && this.pageWidth > 0) {
          this.tagBarX = Math.max(0, this.pageWidth - this.tagBarWidth - 26)
          this.tagBarY = Math.max(120, this.pageHeight - 160)
          this.tagBarInitialized = true
        }
      })
      .position({ x: this.tagBarX, y: this.tagBarY })
      .gesture(
        PanGesture()
          .onActionStart((event: GestureEvent) => {
            this.lastPanOffsetX = event.offsetX
            this.lastPanOffsetY = event.offsetY
          })
          .onActionUpdate((event: GestureEvent) => {
            const safeAreaTop = 44
            const safeAreaBottom = 34
            const screenHeight = this.pageHeight > 0 ? this.pageHeight : 780
            const deltaX = event.offsetX - this.lastPanOffsetX
            const deltaY = event.offsetY - this.lastPanOffsetY
            this.lastPanOffsetX = event.offsetX
            this.lastPanOffsetY = event.offsetY
            let newX = this.tagBarX + deltaX
            let newY = this.tagBarY + deltaY
            if (newX < 0) {
              newX = 0
            }
            if (newX > this.pageWidth - this.tagBarWidth) {
              newX = this.pageWidth - this.tagBarWidth
            }
            if (newY < safeAreaTop) {
              newY = safeAreaTop
            }
            if (newY > screenHeight - this.tagBarHeight - safeAreaBottom) {
              newY = screenHeight - this.tagBarHeight - safeAreaBottom
            }
            this.tagBarX = newX
            this.tagBarY = newY
          })
          .onActionEnd((_event: GestureEvent) => {
            this.lastPanOffsetX = 0
            this.lastPanOffsetY = 0
          })
      )

      if (this.tagMenuVisible) {
        Column() {
          NoteEditTagDropdown({
            tagPool: this.tagPool,
            noteTags: this.noteTags,
            aiTagCreating: this.aiTagCreating,
            onTagChecked: (tag: string, selected: boolean) => {
              void this.onTagChecked(tag, selected)
            },
            onAiCreateTag: () => {
              void this.onAiCreateTag()
            },
            onOpenTagManage: () => {
              void this.openTagManage()
            }
          })
        }
        .position({ x: this.floatMenuPosX(), y: this.tagMenuPosY() })
        .zIndex(999)
      }
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 外层左右 padding 与关于页一致；标题栏在滚动区上方。
      Column() {
        this.buildHeader()

        if (this.loading) {
          Column() {
            LoadingProgress()
              .width(32)
              .height(32)
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column() {
              this.buildTitleBlock()
              this.buildTagChips()
              this.buildPlayer()
              this.buildMeta()
              if (this.hasSummary()) {
                this.buildTabbedContent()
              } else {
                this.buildTranscriptBody()
              }
              Blank().height(120)
            }
            .width('100%')
            .padding({ top: 15 })
            .alignItems(HorizontalAlign.Start)
            .justifyContent(FlexAlign.Start)
          }
          .align(Alignment.TopStart)
          .layoutWeight(1)
          .width('100%')
          .scrollBar(BarState.Auto)
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: 16, right: 16 })
      .backgroundColor($r('app.color.app_background'))
      .onAreaChange((_, area: Area) => {
        this.pageWidth = Number.parseFloat(`${area.width}`) || 0
        this.pageHeight = Number.parseFloat(`${area.height}`) || 0
      })

      if (!this.loading) {
        this.buildDraggableTagBar()
      }

      if (this.showBlockingOverlay()) {
        this.buildAiWorkingOverlay()
      }

      NoteEditShareExportMount({
        active: this.shareExportActive,
        scrollBg: this.shareExportScrollBg,
        mountKey: this.shareExportMountKey(),
        shareScroller: this.shareScroller,
        onCardHeightChange: (height: number): void => {
          this.shareCardHeight = height
        },
        exportCard: (): void => {
          this.buildShareExportCard()
        }
      })

      NoteEditSharePreviewOverlay({
        preparing: this.sharePreviewPreparing,
        visible: this.sharePreviewVisible,
        regenerating: this.sharePreviewRegenerating,
        previewPath: this.sharePreviewPath,
        previewImageHeightVp: this.sharePreviewImageHeightVp,
        pageWidth: this.pageWidth,
        optionsSheetVisible: this.shareOptionsSheetVisible,
        shareTheme: this.shareTheme,
        shareTone: this.shareTone,
        shareShowAppIcon: this.shareShowAppIcon,
        sheetRevision: this.shareSheetRevision,
        sheetParams: this.sharePreviewSheetParams(),
        onPreviewImageComplete: (width: number, height: number): void => {
          const previewW = Math.max(1, this.pageWidth)
          this.sharePreviewImageHeightVp = (height / width) * previewW
        }
      })
    }
    .width('100%')
    .height('100%')
    .onClick((): void => {
      if (this.sharePreviewVisible || this.sharePreviewRegenerating || this.sharePreviewPreparing) {
        return
      }
      if (this.tagMenuVisible) {
        this.tagMenuVisible = false
      }
    })
  }
}
