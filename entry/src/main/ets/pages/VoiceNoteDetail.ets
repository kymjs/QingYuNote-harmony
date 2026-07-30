import { common } from '@kit.AbilityKit'
import { pasteboard } from '@kit.BasicServicesKit'
import { SymbolGlyphModifier } from '@kit.ArkUI'
import { AudioConstants } from '../common/constants/AudioConstants'
import { Note, isExtractStatusPending } from '../common/model/Note'
import { ensureAiMembershipAccess } from '../common/utils/AiMembershipGateNavigation'
import { AudioWaveEnvelope } from '../common/utils/AudioWaveEnvelope'
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
import { NoteEditMarkdownBlocksView } from './NoteEditMarkdownBlocksView'
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

interface TranscriptRowAnchor {
  x: number
  y: number
  width: number
  height: number
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
  @State private converting: boolean = false
  @State private noteTags: string[] = []
  @State private tagPool: string[] = []
  @State private tagMenuVisible: boolean = false
  @State private aiTagCreating: boolean = false
  @State private tagBarX: number = 0
  @State private tagBarY: number = 0
  @State private tagBarWidth: number = 36
  @State private tagBarHeight: number = 36
  @State private transcriptMenuVisible: boolean = false
  @State private transcriptMenuIndex: number = -1
  @State private transcriptMenuX: number = 0
  @State private transcriptMenuY: number = 0
  @State private editingSegmentIndex: number = -1
  @State private editingSegmentText: string = ''
  /** 进入编辑时锁定的段落高度，保证编辑框与原段落同高。 */
  @State private editingSegmentHeight: number = 0
  /** 段落编辑框相对页面顶部的 Y，用于点击外部结束编辑。 */
  @State private editingSegmentTop: number = 0
  @State private editingSegmentBottom: number = 0
  /** 标题编辑 dismiss 遮罩的顶部 Y（标题底边之下，不盖住标题）。 */
  @State private titleDismissTop: number = 120
  /** 笔记标题块高度，用于顶栏标题滚动淡入。 */
  @State private titleBlockH: number = 48
  /** 顶栏标题透明度：0 隐藏，1 完全显示，随外层滚动连续变化。 */
  @State private toolbarTitleOpacity: number = 0
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
  /** Display envelope when short WAV; empty → procedural bounce (mp3 / long wav). */
  @State private waveEnvelope: number[] = []
  /** Bars currently drawn; refreshed each anim tick so ArkUI updates heights. */
  @State private waveBars: number[] = []
  /** Bump to force ForEach/Column refresh (same pattern as VoiceNote.visualTick). */
  @State private waveVisualTick: number = 0

  @State private contentTabIndex: number = 0
  @State private aiWorking: boolean = false
  @State private aiWorkingOverlayMessage: string = 'AI 处理中…'
  /** 外层 Scroll 视口高；TabBar 高；吸顶后 Swiper = viewport - tabBar。 */
  @State private scrollViewportH: number = 0
  @State private tabBarH: number = 48
  @State private stickyHeaderH: number = 0

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
  private waveTimer: number = -1
  /** Last successful PCM envelope parse; display may discard when duration > 1 min. */
  private parsedEnvelope: number[] = []
  private initGeneration: number = 0
  private loadedAudioId: string = ''
  private lastAppliedAiBgResult: AiNoteBackgroundTaskResult | null = null
  private shareScroller: Scroller = new Scroller()
  private shareCardHeight: number = 0
  private filesDirCache: string = ''
  private extractPollTimer: number = -1
  private lastAudioSyncAttemptMs: number = 0
  private transcriptRowAnchors: Map<number, TranscriptRowAnchor> = new Map()

  private lifecycle = new PageLifecycle()
  private closeGuard = new PageCloseGuard()
  private playbackService: AudioPlaybackService = AudioPlaybackService.getInstance()
  private onAiBackgroundTaskChanged = (): void => {
    this.handleAiBackgroundTaskChanged()
  }

  private swiperController: SwiperController = new SwiperController()
  private outerScroller: Scroller = new Scroller()
  private lastOuterOffsetY: number = 0
  private lastStickyLogKey: string = ''

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

  private renderSegments(): VoiceTranscriptSegment[] {
    const timed = this.segments()
    if (timed.length > 0) {
      return timed
    }
    const content = this.transcriptPlainText()
    if (content.length === 0) {
      return []
    }
    const parts = content
      .split(/\n\s*\n|\n/g)
      .map((part: string) => part.trim())
      .filter((part: string) => part.length > 0)
    return parts.map((part: string, index: number): VoiceTranscriptSegment => ({
      startMs: index === 0 ? 0 : index * 1000,
      text: part
    }))
  }

  private transcriptMenuTarget(): VoiceTranscriptSegment | null {
    if (!this.transcriptMenuVisible || this.transcriptMenuIndex < 0) {
      return null
    }
    const segs = this.renderSegments()
    if (this.transcriptMenuIndex >= segs.length) {
      return null
    }
    return segs[this.transcriptMenuIndex]
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
    if (this.waveEnvelope.length > 0) {
      return
    }
    this.waveTimer = setInterval((): void => {
      if (this.playing && this.waveEnvelope.length === 0) {
        // Accumulate seconds; never wrap — avoids a seam every cycle.
        this.wavePhase = this.wavePhase + 0.05
        this.syncWaveBars()
      }
    }, 50)
  }

  private syncWaveBars(): void {
    this.waveBars = this.waveAmplitudes()
    // Force ForEach rebuild — stable keys alone do not refresh Column.height on Harmony.
    this.waveVisualTick = this.waveVisualTick + 1
  }

  private applyEnvelopeForCurrentDuration(): void {
    if (this.parsedEnvelope.length === 0) {
      return
    }
    const next = this.displayEnvelopeForDuration(this.parsedEnvelope, this.durationMs)
    if (next.length === this.waveEnvelope.length) {
      return
    }
    this.waveEnvelope = next
    this.syncWaveBars()
    if (this.playing) {
      if (this.waveEnvelope.length === 0) {
        this.startWaveTimer()
      } else {
        this.clearWaveTimer()
      }
    }
  }

  /** Real envelope only for WAV shorter than or equal to 1 minute. */
  private static readonly REAL_ENVELOPE_MAX_MS: number = 60 * 1000

  private displayEnvelopeForDuration(parsed: number[] | null, durationMs: number): number[] {
    if (parsed === null || parsed.length === 0) {
      return []
    }
    if (durationMs > VoiceNoteDetail.REAL_ENVELOPE_MAX_MS) {
      return []
    }
    return parsed
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

    const n = this.note
    if (n !== null && this.shouldOpenLinkExtractProgress(n)) {
      const kind = n.sourceUrl.trim().length === 0 &&
        !isExtractStatusPending(n.extractStatus) &&
        n.extractStatus !== 'failed'
        ? 'voiceTranscribe'
        : 'linkExtract'
      try {
        await this.getUIContext().getRouter().replaceUrl({
          url: 'pages/LinkExtractProgress',
          params: {
            noteId: this.noteId,
            kind: kind,
            url: n.sourceUrl.trim()
          }
        })
      } catch (error) {
        console.error(`redirect LinkExtractProgress: ${JSON.stringify(error)}`)
      }
      return
    }

    const pending = this.pendingVoicePath.trim()
    if (pending.length > 0 && !this.pendingVoiceHandled) {
      this.pendingVoiceHandled = true
      this.pendingVoicePath = ''
      if (!(await ensureAiMembershipAccess(this.getUIContext()))) {
        return
      }
      void AiNoteBackgroundTaskService.getInstance().runVoiceTranscribe(this.noteId, pending)
      try {
        await this.getUIContext().getRouter().replaceUrl({
          url: 'pages/LinkExtractProgress',
          params: {
            noteId: this.noteId,
            kind: 'voiceTranscribe',
            url: ''
          }
        })
      } catch (error) {
        console.error(`redirect voice progress: ${JSON.stringify(error)}`)
      }
      return
    }

    await this.refreshTagPool()
    await this.ensureVoicePipeline()
    this.ensureExtractOrAudioPoll()
  }

  private shouldOpenLinkExtractProgress(n: Note): boolean {
    if (isExtractStatusPending(n.extractStatus) || n.extractStatus === 'failed') {
      return true
    }
    if (n.voiceTranscribeStatus === 'running' || n.voiceTranscribeStatus === 'failed') {
      return true
    }
    return false
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
      // 新录音转写已在 bootstrap 中跳转进度页。
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
    this.waveEnvelope = []
    this.waveBars = []
    this.parsedEnvelope = []
    this.clearWaveTimer()
    this.playbackService.setCallbacks(
      (position: number, duration: number): void => {
        this.positionMs = position
        this.durationMs = duration
        this.applyEnvelopeForCurrentDuration()
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
          this.syncWaveBars()
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
      const parsed = AudioWaveEnvelope.extractFromFile(path)
      this.parsedEnvelope = parsed !== null ? parsed : []
      this.durationMs = this.playbackService.getDurationMs()
      this.waveEnvelope = this.displayEnvelopeForDuration(
        this.parsedEnvelope.length > 0 ? this.parsedEnvelope : null,
        this.durationMs
      )
      this.syncWaveBars()
      this.loadedAudioId = trimmed
      this.audioLoading = false
      this.audioFailed = false
      if (this.playing) {
        this.startWaveTimer()
      }
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
    if (this.waveEnvelope.length > 0) {
      return this.waveEnvelope
    }
    const count = AudioWaveEnvelope.barCount
    const result: number[] = []
    const t = this.wavePhase
    for (let i = 0; i < count; i++) {
      // Fixed-seed silhouette (hash only over bar index — not time).
      const base = Math.min(0.95, Math.max(0.12, 0.22 + this.waveNoise(i * 1.7, 0.37) * 0.7))
      if (!this.playing) {
        result.push(base)
      } else {
        // Continuous slow wobble for non-WAV / parse failure (no positional hash).
        const wobble =
          0.10 * Math.sin(t * Math.PI * 2 * 3.0 + i * 0.45) +
          0.05 * Math.sin(t * Math.PI * 2 * 1.5 + i * 1.1)
        result.push(Math.min(1.0, Math.max(0.12, base + wobble)))
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
    if (this.shouldHighlightActiveSegment()) {
      return `${this.formatClock(this.positionMs)} / ${this.formatClock(this.durationMs)}`
    }
    return this.formatClock(this.durationMs)
  }

  private shouldHighlightActiveSegment(): boolean {
    return !this.playbackCompleted && (this.playing || this.positionMs > 0)
  }

  private activeSegmentIndex(): number {
    const segs = this.renderSegments()
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

  private highlightedSegmentIndex(): number {
    if (!this.shouldHighlightActiveSegment()) {
      return -1
    }
    return this.activeSegmentIndex()
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

  private playFromSegment(segment: VoiceTranscriptSegment): void {
    this.closeTranscriptMenu()
    if (this.editingSegmentIndex >= 0) {
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

  private closeTranscriptMenu(): void {
    this.transcriptMenuVisible = false
    this.transcriptMenuIndex = -1
  }

  private showTranscriptMenu(index: number): void {
    const menuWidth = 300
    const menuHeight = 62
    const anchor = this.transcriptRowAnchors.get(index)
    const fallbackX = Math.max(12, (this.pageWidth - menuWidth) / 2)
    const fallbackY = Math.max(72, this.pageHeight * 0.24)
    this.transcriptMenuIndex = index
    this.transcriptMenuVisible = true
    this.transcriptMenuX = anchor
      ? Math.max(12, Math.min(anchor.x + (anchor.width - menuWidth) / 2, this.pageWidth - menuWidth - 12))
      : fallbackX
    this.transcriptMenuY = anchor
      ? Math.max(12, Math.min(anchor.y - menuHeight - 16, this.pageHeight - menuHeight - 18))
      : fallbackY
  }

  private recordTranscriptRowAnchor(index: number, area: Area): void {
    const width = Number.parseFloat(`${area.width}`)
    const height = Number.parseFloat(`${area.height}`)
    if (width <= 0 || height <= 0) {
      return
    }
    const globalX = Number.parseFloat(`${area.globalPosition?.x ?? Number.NaN}`)
    const globalY = Number.parseFloat(`${area.globalPosition?.y ?? Number.NaN}`)
    const localX = Number.parseFloat(`${area.position?.x ?? 0}`) || 0
    const localY = Number.parseFloat(`${area.position?.y ?? 0}`) || 0
    const anchor: TranscriptRowAnchor = {
      x: Number.isFinite(globalX) ? globalX : 16 + localX,
      y: Number.isFinite(globalY) ? globalY : localY,
      width: width,
      height: height
    }
    this.transcriptRowAnchors.set(index, anchor)
    if (this.editingSegmentIndex === index) {
      this.editingSegmentTop = anchor.y
      this.editingSegmentBottom = anchor.y + anchor.height
      if (this.editingSegmentHeight <= 0) {
        this.editingSegmentHeight = Math.max(48, anchor.height - 16)
      }
    }
  }

  private async copyTranscriptSegment(text: string): Promise<void> {
    const trimmed = text.trim()
    if (trimmed.length === 0) {
      this.showToast(LocaleService.loc('内容为空', 'Content is empty', '内容が空です'))
      return
    }
    try {
      const pasteData = pasteboard.createPlainTextData(trimmed)
      const systemPasteboard = pasteboard.getSystemPasteboard()
      await systemPasteboard.setData(pasteData)
      this.showToast(LocaleService.loc('已复制', 'Copied', 'コピーしました'))
    } catch (error) {
      Logger.warn('VoiceNoteDetail', `copyTranscriptSegment failed: ${JSON.stringify(error)}`)
      this.showToast(LocaleService.loc('复制失败', 'Copy failed', 'コピーに失敗しました'))
    }
  }

  private beginEditSegment(index: number): void {
    const segs = this.renderSegments()
    if (index < 0 || index >= segs.length) {
      return
    }
    const anchor = this.transcriptRowAnchors.get(index)
    this.closeTranscriptMenu()
    this.editingSegmentIndex = index
    this.editingSegmentText = segs[index].text
    this.editingSegmentHeight = Math.max(48, (anchor?.height ?? 0) - 16)
    this.editingSegmentTop = anchor?.y ?? 0
    this.editingSegmentBottom = (anchor?.y ?? 0) + (anchor?.height ?? 0)
    setTimeout((): void => {
      if (this.editingSegmentIndex !== index || !this.lifecycle.isActive()) {
        return
      }
      try {
        this.getUIContext().getFocusController().requestFocus('voice_note_segment_input')
      } catch (error) {
        Logger.warn('VoiceNoteDetail', `requestFocus segment failed: ${JSON.stringify(error)}`)
      }
    }, 32)
  }

  private async commitSegmentEdit(): Promise<void> {
    const index = this.editingSegmentIndex
    if (index < 0 || this.noteId.length === 0) {
      return
    }
    const segs = [...this.renderSegments()]
    if (index >= segs.length) {
      this.editingSegmentIndex = -1
      this.editingSegmentHeight = 0
      return
    }
    const nextText = this.editingSegmentText.trim()
    const previous = segs[index]
    this.editingSegmentIndex = -1
    this.editingSegmentHeight = 0
    if (nextText.length === 0) {
      this.showToast(LocaleService.loc('内容不能为空', 'Content cannot be empty', '内容は空にできません'))
      return
    }
    if (nextText === previous.text.trim()) {
      return
    }
    segs[index] = {
      startMs: previous.startMs,
      text: nextText
    }
    const content = segs.map((segment: VoiceTranscriptSegment) => segment.text.trim()).join('\n\n')
    await NoteRepository.getInstance().saveDraft(this.noteId, {
      content: content,
      voiceSegmentsJson: VoiceSegmentSplitter.encodeJson(segs),
      skipTitleAutoFill: true
    })
    if (!this.lifecycle.isActive()) {
      return
    }
    await this.reloadNote(false)
  }

  private dismissSegmentEditing(): void {
    if (this.editingSegmentIndex >= 0) {
      void this.commitSegmentEdit()
    }
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

  private resolveShareBody(bodyOverride?: string): string {
    const current = this.note
    if (current === null) {
      return ''
    }
    const override = (bodyOverride ?? '').trim()
    if (override.length > 0) {
      return override
    }
    if (this.hasSummary() && this.contentTabIndex === 1) {
      return current.voiceSummary
    }
    return current.content
  }

  /** 解析「转为普通笔记」正文：摘要 Tab 用摘要（空则回退全文）；否则用全文。空则返回 null。 */
  private resolveConvertBody(): string | null {
    const current = this.note
    if (current === null) {
      return null
    }
    if (this.hasSummary() && this.contentTabIndex === 1) {
      const summary = current.voiceSummary.trim()
      if (summary.length > 0) {
        return summary
      }
      const content = current.content.trim()
      if (content.length === 0) {
        return null
      }
      return content
    }
    const content = current.content.trim()
    if (content.length === 0) {
      return null
    }
    return content
  }

  private beginEditTitle(): void {
    this.titleEditing = true
    // defaultFocus 仅在页面首次创建时生效；动态切换编辑态需主动 requestFocus。
    setTimeout((): void => {
      if (!this.titleEditing || !this.lifecycle.isActive()) {
        return
      }
      try {
        this.getUIContext().getFocusController().requestFocus('voice_note_title_input')
      } catch (error) {
        Logger.warn('VoiceNoteDetail', `requestFocus title failed: ${JSON.stringify(error)}`)
      }
    }, 32)
  }

  private async handleConvertToNormalNote(): Promise<void> {
    if (this.converting) {
      return
    }
    const current = this.note
    if (current === null) {
      return
    }
    const body = this.resolveConvertBody()
    if (body === null) {
      this.showToast(LocaleService.loc('笔记内容为空', 'Note content is empty', 'ノート内容が空です'))
      return
    }
    this.converting = true
    try {
      const created = await NoteRepository.getInstance().createNote({
        title: current.title,
        content: body,
        tags: [...current.tags],
        skipTitleAutoFill: true
      })
      const parentId = (current.parentId ?? '').trim()
      if (parentId.length > 0) {
        await NoteRepository.getInstance().saveDraft(created.id, {
          parentId: parentId
        })
      }
      if (!this.lifecycle.isActive()) {
        return
      }
      this.showToast(LocaleService.loc('已创建新笔记', 'Note created', 'ノートを作成しました'))
    } catch (error) {
      Logger.error('VoiceNoteDetail', `convertToNormalNote failed: ${JSON.stringify(error)}`)
      if (this.lifecycle.isActive()) {
        this.showToast(LocaleService.loc('创建失败，请稍后重试', 'Create failed, please try again',
          '作成に失敗しました。後でもう一度お試しください'))
      }
    } finally {
      if (this.lifecycle.isActive()) {
        this.converting = false
      }
    }
  }

  private buildVoiceDetailMoreMenuItems(): Array<MenuElement> {
    const items: Array<MenuElement> = [
      {
        value: LocaleService.loc('分享', 'Share', '共有'),
        symbolIcon: new SymbolGlyphModifier($r('sys.symbol.share')),
        action: (): void => {
          if (this.note !== null) {
            void this.handleShare()
          }
        }
      },
      {
        value: LocaleService.loc('修改标题', 'Edit title', 'タイトルを変更'),
        symbolIcon: new SymbolGlyphModifier($r('sys.symbol.square_and_pencil')),
        action: (): void => {
          this.beginEditTitle()
        }
      },
      {
        value: LocaleService.loc('转为普通笔记', 'Convert to note', '通常ノートに変換'),
        symbolIcon: new SymbolGlyphModifier($r('sys.symbol.doc_text')),
        action: (): void => {
          if (!this.converting) {
            void this.handleConvertToNormalNote()
          }
        }
      }
    ]
    return items
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

  private async runShareNote(bodyOverride?: string): Promise<void> {
    if (this.sharePreviewPreparing || this.sharePreviewRegenerating || this.note === null) {
      return
    }
    this.sharePreviewPreparing = true
    this.showToast(EditorUiStrings.loc('正在生成长图…', 'Generating long image…', '長画像を生成中…'))
    try {
      this.refreshSharePreviewBlocks(this.resolveShareBody(bodyOverride))
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
    captureTone?: ShareCardTone,
    bodyOverride?: string
  ): Promise<void> {
    const theme = captureTheme ?? this.shareTheme
    const tone = captureTone ?? this.shareTone
    this.shareTheme = theme
    this.shareTone = tone
    this.sharePreviewRegenerating = true
    this.refreshSharePreviewBlocks(this.shareBodyMd.length > 0
      ? this.shareBodyMd
      : this.resolveShareBody(bodyOverride))
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

  private async handleShare(bodyOverride?: string): Promise<void> {
    await this.runShareNote(bodyOverride)
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
    // 顶栏按钮始终在上方，菜单默认向下展开。
    const below = this.tagBarY + this.tagBarHeight + 8
    if (below + menuHeight <= this.pageHeight) {
      return below
    }
    return Math.max(0, this.tagBarY - menuHeight - 8)
  }

  private toggleTagMenu(): void {
    if (this.aiTagCreating) {
      return
    }
    const opening = !this.tagMenuVisible
    this.tagMenuVisible = opening
    if (opening) {
      void this.refreshTagPool()
    }
  }

  @Builder
  private buildHeader() {
    // 与关于页一致：左侧圆角返回、标题区 layoutWeight；右侧标签图标 + 更多菜单。
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
        this.dismissTitleEditing()
        this.handleToolbarBack()
      })

      Row() {
        Text(this.title.trim().length > 0
          ? this.title
          : LocaleService.loc('新录音', 'New recording', '新規録音'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
          .width('100%')
          .opacity(this.toolbarTitleOpacity)
      }
      .layoutWeight(1)
      .height('100%')
      .padding({ left: 8, right: 8 })
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)

      Row() {
        if (this.aiTagCreating) {
          LoadingProgress()
            .width(18)
            .height(18)
            .color($r('app.color.accent'))
        } else {
          SymbolGlyph($r('sys.symbol.label'))
            .fontSize(18)
            .fontColor([$r('app.color.primary_text')])
        }
      }
      .height('100%')
      .padding({
        left: $r('app.float.toolbar_icon_button_padding_h'),
        right: $r('app.float.toolbar_icon_button_padding_h')
      })
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .enabled(this.note !== null && !this.aiTagCreating)
      .onClick((): void => {
        this.dismissTitleEditing()
        this.toggleTagMenu()
      })
      .onAreaChange((_oldArea: Area, area: Area): void => {
        this.tagBarWidth = Number.parseFloat(`${area.width}`) || 36
        this.tagBarHeight = Number.parseFloat(`${area.height}`) || 36
        // position 相对父布局；外层 Column 有左右 padding，叠加得到页内坐标。
        const localX = Number.parseFloat(`${area.position.x}`) || 0
        const localY = Number.parseFloat(`${area.position.y}`) || 0
        this.tagBarX = 16 + localX
        this.tagBarY = localY
      })

      Row() {
        SymbolGlyph($r('sys.symbol.more'))
          .fontSize(18)
          .fontColor([$r('app.color.primary_text')])
          .bindMenu(this.buildVoiceDetailMoreMenuItems())
      }
      .height('100%')
      .padding({
        left: $r('app.float.toolbar_icon_button_padding_h'),
        right: $r('app.float.toolbar_icon_button_padding_h')
      })
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .enabled(this.note !== null)
      .onClick((): void => {
        this.dismissTitleEditing()
      })
    }
    .width('100%')
    .height($r('app.float.toolbar_height'))
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildTitleBlock() {
    Column() {
      if (this.titleEditing) {
        // 浅色底 + 描边高亮；主动聚焦弹出键盘与光标。
        TextInput({ text: this.title })
          .id('voice_note_title_input')
          .width('100%')
          .height(48)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
          .backgroundColor($r('app.color.surface_muted'))
          .padding({ left: 10, right: 10, top: 8, bottom: 8 })
          .border({ width: 1.5, color: $r('app.color.accent') })
          .borderRadius(8)
          .showUnderline(false)
          .caretColor($r('app.color.accent'))
          .clip(false)
          .defaultFocus(true)
          .enableKeyboardOnFocus(true)
          .focusable(true)
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
            this.beginEditTitle()
          })
      }
    }
    .width('100%')
    .onAreaChange((_oldArea: Area, area: Area): void => {
      const h = Number.parseFloat(`${area.height}`) || 48
      this.titleBlockH = h
      // 顶栏 56 + sticky padding 15 + 标题高度；不盖住标题本身。
      this.titleDismissTop = 56 + 15 + h
      this.updateToolbarTitleOpacity(this.lastOuterOffsetY)
    })
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
      ForEach(this.waveBars, (amp: number, index: number) => {
        Column()
          .width(3)
          .height(Math.max(6, amp * 32))
          .backgroundColor(((index + 0.5) / 48.0) <= this.playbackProgress()
            ? $r('app.color.accent')
            : '#FFD1D5DB')
          .borderRadius(2)
      }, (_: number, index: number) => `wave_bar_${index}_${this.waveVisualTick}`)
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

  private swiperContentHeight(): number {
    const tabH = this.tabBarH > 0 ? this.tabBarH : 48
    const h = this.scrollViewportH - tabH
    return h > 120 ? h : 280
  }

  private logStickyMetrics(reason: string): void {
    const key =
      `${reason}|${Math.round(this.scrollViewportH)}|${Math.round(this.tabBarH)}|` +
      `${Math.round(this.stickyHeaderH)}|${Math.round(this.swiperContentHeight())}|` +
      `${Math.round(this.lastOuterOffsetY)}`
    if (key === this.lastStickyLogKey) {
      return
    }
    this.lastStickyLogKey = key
    Logger.info(
      'VoiceSticky',
      `${reason} viewportH=${this.scrollViewportH.toFixed(1)} tabBarH=${this.tabBarH.toFixed(1)} ` +
        `headerH=${this.stickyHeaderH.toFixed(1)} swiperH=${this.swiperContentHeight().toFixed(1)} ` +
        `offsetY=${this.lastOuterOffsetY.toFixed(1)} metaOff=${this.lastOuterOffsetY + 0.5 >= this.stickyHeaderH}`
    )
  }

  private onOuterScroll(): void {
    const y = this.outerScroller.currentOffset().yOffset
    this.lastOuterOffsetY = y
    this.updateToolbarTitleOpacity(y)
    this.logStickyMetrics('outerScroll')
  }

  /** sticky 顶 padding 15 之后标题开始滑出；按标题高度线性映射透明度。 */
  private updateToolbarTitleOpacity(scrollY: number): void {
    const fadeStart = 15
    const h = Math.max(1, this.titleBlockH)
    let opacity = (scrollY - fadeStart) / h
    if (opacity < 0) {
      opacity = 0
    } else if (opacity > 1) {
      opacity = 1
    }
    if (Math.abs(opacity - this.toolbarTitleOpacity) < 0.01) {
      return
    }
    this.toolbarTitleOpacity = opacity
  }

  private lastEarlyHandoffLogMs: number = 0

  private onInnerListScroll(source: string): void {
    if (this.stickyHeaderH <= 0 || this.lastOuterOffsetY + 0.5 >= this.stickyHeaderH) {
      return
    }
    const now = Date.now()
    if (now - this.lastEarlyHandoffLogMs < 800) {
      return
    }
    this.lastEarlyHandoffLogMs = now
    Logger.warn(
      'VoiceSticky',
      `earlyHandoff source=${source} offsetY=${this.lastOuterOffsetY.toFixed(1)} ` +
        `headerH=${this.stickyHeaderH.toFixed(1)} (meta still on screen)`
    )
  }

  @Builder
  private buildSegmentListItem(segment: VoiceTranscriptSegment, index: number) {
    Row() {
      if (this.segments().length > 0) {
        Text(this.formatClock(segment.startMs))
          .fontSize(12)
          .fontColor($r('app.color.secondary_text'))
          .width(48)
      }
      if (this.editingSegmentIndex === index) {
        TextArea({ text: this.editingSegmentText })
          .id('voice_note_segment_input')
          .layoutWeight(1)
          .height(Math.max(48, this.editingSegmentHeight))
          .fontSize(15)
          .fontColor($r('app.color.primary_text'))
          .backgroundColor($r('app.color.surface_muted'))
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .border({ width: 1.5, color: $r('app.color.accent') })
          .borderRadius(12)
          .caretColor($r('app.color.accent'))
          .defaultFocus(true)
          .enableKeyboardOnFocus(true)
          .focusable(true)
          .onChange((value: string): void => {
            this.editingSegmentText = value
          })
          .onBlur((): void => {
            void this.commitSegmentEdit()
          })
      } else {
        Column() {
          NoteEditMarkdownBlocksView({
            blocks: MarkdownUtils.parseBlocks(segment.text),
            filesDirCache: this.filesDirCache,
            forceAccentText: this.highlightedSegmentIndex() === index,
            onLinkToast: (href: string): void => {
              this.showToast(href)
            },
            onCheckboxToggle: (_lineIndex: number, _checked: boolean): void => {
            },
            onImageTap: (_src: string): void => {
            }
          })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ top: 8, bottom: 8 })
    .onAreaChange((_: Area, area: Area): void => {
      this.recordTranscriptRowAnchor(index, area)
    })
    .priorityGesture(
      LongPressGesture({ repeat: false, duration: 450 })
        .onAction((): void => {
          this.showTranscriptMenu(index)
        })
    )
  }

  @Builder
  private buildTranscriptList() {
    List() {
      if (this.shouldShowTranscribeFailure()) {
        ListItem() {
          Text(LocaleService.loc(
            '语音转文字失败，请稍后重试',
            'Speech-to-text failed; try again',
            '音声認識に失敗しました。後でもう一度お試しください'
          ))
            .fontSize(15)
            .fontColor($r('app.color.secondary_text'))
            .margin({ top: 20 })
        }
      } else {
        ForEach(this.renderSegments(), (segment: VoiceTranscriptSegment, index: number) => {
          ListItem() {
            this.buildSegmentListItem(segment, index)
          }
        }, (segment: VoiceTranscriptSegment, index: number) =>
          `seg_${index}_${segment.startMs}_${this.highlightedSegmentIndex() === index ? 1 : 0}`)
      }
      ListItem() {
        Column()
          .width('100%')
          .height(120)
      }
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .nestedScroll({
      scrollForward: NestedScrollMode.PARENT_FIRST,
      scrollBackward: NestedScrollMode.SELF_FIRST
    })
    .onDidScroll((_scrollOffset: number, _scrollState: ScrollState): void => {
      this.onInnerListScroll('transcript')
    })
  }

  @Builder
  private buildSummaryList() {
    List() {
      ListItem() {
        Column() {
          NoteEditMarkdownBlocksView({
            blocks: MarkdownUtils.parseBlocks(this.note?.voiceSummary ?? ''),
            filesDirCache: this.filesDirCache,
            onLinkToast: (href: string): void => {
              this.showToast(href)
            },
            onCheckboxToggle: (_lineIndex: number, _checked: boolean): void => {
            },
            onImageTap: (_src: string): void => {
            }
          })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .margin({ top: 16 })
      }
      ListItem() {
        Column()
          .width('100%')
          .height(120)
      }
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .nestedScroll({
      scrollForward: NestedScrollMode.PARENT_FIRST,
      scrollBackward: NestedScrollMode.SELF_FIRST
    })
    .onDidScroll((_scrollOffset: number, _scrollState: ScrollState): void => {
      this.onInnerListScroll('summary')
    })
  }

  @Builder
  private buildTabBar() {
    Row() {
      Column() {
        Text(LocaleService.loc('音频内容', 'Audio content', '音声内容'))
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
    .padding({ top: 16 })
    .backgroundColor($r('app.color.app_background'))
    .onAreaChange((_: Area, area: Area) => {
      const h = Number.parseFloat(`${area.height}`) || 0
      if (h > 0 && Math.abs(h - this.tabBarH) >= 1) {
        this.tabBarH = h
        this.logStickyMetrics('tabBarH')
      }
    })
  }

  @Builder
  private buildTabbedContent() {
    // TabBar 自然高 + Swiper 固定高(viewport-tabBar)；头部(含 meta)滚尽后仅 Tab 吸顶。
    Column() {
      this.buildTabBar()
      Swiper(this.swiperController) {
        this.buildTranscriptList()
        this.buildSummaryList()
      }
      .index(this.contentTabIndex)
      .indicator(false)
      .loop(false)
      .width('100%')
      .height(this.swiperContentHeight())
      .onChange((index: number): void => {
        this.contentTabIndex = index
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildStickyHeaderBlock() {
    Column() {
      this.buildTitleBlock()
      this.buildTagChips()
      this.buildPlayer()
      this.buildMeta()
    }
    .width('100%')
    .padding({ top: 15 })
    .alignItems(HorizontalAlign.Start)
    .onAreaChange((_: Area, area: Area) => {
      const h = Number.parseFloat(`${area.height}`) || 0
      if (h > 0 && Math.abs(h - this.stickyHeaderH) >= 1) {
        this.stickyHeaderH = h
        this.logStickyMetrics('headerH')
      }
    })
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
  private buildTagMenuOverlay() {
    if (this.tagMenuVisible) {
      // 全屏透明层：点击弹窗外先关闭菜单（需低于下拉 zIndex）。
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#00000000')
        .onClick((): void => {
          this.tagMenuVisible = false
          if (this.titleEditing) {
            void this.commitTitle()
          }
        })
        .zIndex(998)

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

  @Builder
  private buildTranscriptMenuOverlay() {
    if (this.transcriptMenuVisible && this.transcriptMenuIndex >= 0) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#00000000')
        .onClick((): void => {
          this.closeTranscriptMenu()
        })
        .zIndex(1000)

      if (this.transcriptMenuTarget() !== null) {
        Column() {
          Row() {
            Text(LocaleService.loc('复制', 'Copy', 'コピー'))
              .fontSize(16)
              .fontColor(Color.White)
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
              .padding({ top: 18, bottom: 18 })
              .onClick((): void => {
                // 先取出段落文本，再关菜单；closeTranscriptMenu 后 target 会变为 null。
                const text = this.transcriptMenuTarget()?.text ?? ''
                this.closeTranscriptMenu()
                void this.copyTranscriptSegment(text)
              })
            Column()
              .width(1)
              .height(22)
              .backgroundColor('#29FFFFFF')
            Text(LocaleService.loc('编辑', 'Edit', '編集'))
              .fontSize(16)
              .fontColor(Color.White)
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
              .padding({ top: 18, bottom: 18 })
              .onClick((): void => {
                this.beginEditSegment(this.transcriptMenuIndex)
              })
            Column()
              .width(1)
              .height(22)
              .backgroundColor('#29FFFFFF')
            Text(LocaleService.loc('分享', 'Share', '共有'))
              .fontSize(16)
              .fontColor(Color.White)
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
              .padding({ top: 18, bottom: 18 })
              .onClick((): void => {
                const text = (this.transcriptMenuTarget()?.text ?? '').trim()
                this.closeTranscriptMenu()
                void this.handleShare(text)
              })
            Column()
              .width(1)
              .height(22)
              .backgroundColor('#29FFFFFF')
            Text(LocaleService.loc('听当前', 'Listen', 'ここを聴く'))
              .fontSize(16)
              .fontColor(Color.White)
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
              .padding({ top: 18, bottom: 18 })
              .onClick((): void => {
                const target = this.transcriptMenuTarget()
                this.closeTranscriptMenu()
                if (target !== null) {
                  this.playFromSegment(target)
                }
              })
          }
          .width(300)
          .backgroundColor('#FF2B2B2D')
          .borderRadius(20)
          .border({ width: 1, color: '#10FFFFFF' })

          Column()
            .width(12)
            .height(12)
            .backgroundColor('#FF2B2B2D')
            .rotate({ angle: 45 })
            .margin({ top: -6 })
        }
        .position({ x: this.transcriptMenuX, y: this.transcriptMenuY })
        .zIndex(1001)
      }
    }
  }

  @Builder
  private buildTitleDismissOverlay() {
    // 仅覆盖标题以下区域，标题内可点击移动光标。
    if (this.titleEditing && !this.tagMenuVisible) {
      Column()
        .width('100%')
        .height(Math.max(0, this.pageHeight - Math.max(56, this.titleDismissTop)))
        .backgroundColor('#00000000')
        .position({ x: 0, y: Math.max(56, this.titleDismissTop) })
        .onClick((): void => {
          this.dismissTitleEditing()
        })
        .zIndex(50)
    }
  }

  @Builder
  private buildSegmentEditDismissOverlay() {
    // 分段覆盖编辑框上下方；中间留白不拦截点击，点外部结束编辑并保存。
    if (this.editingSegmentIndex >= 0 && !this.tagMenuVisible && !this.transcriptMenuVisible) {
      Column() {
        Column()
          .width('100%')
          .height(Math.max(0, this.editingSegmentTop))
          .backgroundColor('#00000000')
          .onClick((): void => {
            this.dismissSegmentEditing()
          })
        Column()
          .width('100%')
          .height(Math.max(0, this.editingSegmentBottom - this.editingSegmentTop))
          .hitTestBehavior(HitTestMode.None)
        Column()
          .width('100%')
          .layoutWeight(1)
          .backgroundColor('#00000000')
          .onClick((): void => {
            this.dismissSegmentEditing()
          })
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Transparent)
      .zIndex(50)
    }
  }

  private dismissTitleEditing(): void {
    if (this.titleEditing) {
      void this.commitTitle()
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
          // 外层 Scroll 滚完 header(含 meta) 后 Tab 吸顶；Swiper 高=viewport-tabBar。
          Scroll(this.outerScroller) {
            Column() {
              this.buildStickyHeaderBlock()
              if (this.hasSummary()) {
                this.buildTabbedContent()
              } else {
                List() {
                  // 无摘要：单 List 占满剩余视口，同样 PARENT_FIRST。
                  if (this.shouldShowTranscribeFailure()) {
                    ListItem() {
                      Text(LocaleService.loc(
                        '语音转文字失败，请稍后重试',
                        'Speech-to-text failed; try again',
                        '音声認識に失敗しました。後でもう一度お試しください'
                      ))
                        .fontSize(15)
                        .fontColor($r('app.color.secondary_text'))
                        .margin({ top: 20 })
                    }
                  } else if (this.segments().length === 0) {
                    ListItem() {
                      Text(this.transcriptPlainText())
                        .fontSize(15)
                        .fontColor($r('app.color.primary_text'))
                        .lineHeight(24)
                        .width('100%')
                        .margin({ top: 16 })
                    }
                  } else {
                    ForEach(this.segments(), (segment: VoiceTranscriptSegment, index: number) => {
                      ListItem() {
                        this.buildSegmentListItem(segment, index)
                      }
                    }, (segment: VoiceTranscriptSegment, index: number) =>
                      `seg_${index}_${segment.startMs}_${this.highlightedSegmentIndex() === index ? 1 : 0}`)
                  }
                  ListItem() {
                    Column()
                      .width('100%')
                      .height(120)
                  }
                }
                .width('100%')
                .height(this.scrollViewportH > 120 ? this.scrollViewportH : 280)
                .scrollBar(BarState.Off)
                .edgeEffect(EdgeEffect.Spring)
                .nestedScroll({
                  scrollForward: NestedScrollMode.PARENT_FIRST,
                  scrollBackward: NestedScrollMode.SELF_FIRST
                })
                .onDidScroll((_scrollOffset: number, _scrollState: ScrollState): void => {
                  this.onInnerListScroll('transcriptOnly')
                })
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .justifyContent(FlexAlign.Start)
          }
          .align(Alignment.TopStart)
          .layoutWeight(1)
          .width('100%')
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .onAreaChange((_: Area, area: Area) => {
            const h = Number.parseFloat(`${area.height}`) || 0
            if (h > 0 && Math.abs(h - this.scrollViewportH) >= 1) {
              this.scrollViewportH = h
              this.logStickyMetrics('viewportH')
            }
          })
          .onDidScroll((_scrollOffset: number, _scrollState: ScrollState): void => {
            this.onOuterScroll()
          })
          .onScrollStop((): void => {
            this.onOuterScroll()
            this.logStickyMetrics('outerScrollStop')
          })
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
        this.buildTitleDismissOverlay()
        this.buildSegmentEditDismissOverlay()
        this.buildTagMenuOverlay()
        this.buildTranscriptMenuOverlay()
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
      if (this.transcriptMenuVisible) {
        this.closeTranscriptMenu()
      }
      this.dismissTitleEditing()
      this.dismissSegmentEditing()
    })
  }
}
