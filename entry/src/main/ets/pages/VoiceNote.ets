import router from '@ohos.router'
import { fileIo as fs } from '@kit.CoreFileKit'
import { AudioConstants } from '../common/constants/AudioConstants'
import { AudioRecordingService } from '../services/AudioRecordingService'
import { NoteRepository } from '../services/NoteRepository'
import { IdUtils } from '../common/utils/IdUtils'
import { PageLifecycle } from '../common/utils/PageLifecycle'
import { PageCloseGuard } from '../common/utils/PageCloseGuard'
import { showConfirmAlertDialog } from '../dialogs/ConfirmAlertDialog'
import { Logger } from '../common/utils/Logger'
import { APP_LOCALE_REVISION_KEY, LocaleService } from '../services/LocaleService'
import { VoiceNoteVisual } from '../components/VoiceNoteVisual'

enum VoiceNotePhase {
  Idle = 0,
  Recording = 1,
  Stopped = 2
}

@Entry
@Component
struct VoiceNote {
  @StorageProp(APP_LOCALE_REVISION_KEY) localeRevision: number = 0
  @State private phase: VoiceNotePhase = VoiceNotePhase.Idle
  @State private amplitudes: number[] = []
  @State private elapsedMs: number = 0
  @State private busy: boolean = false
  @State private rippleProgress: number = 0
  @State private visualTick: number = 0

  /** Temp recording session id (not a note id) until user taps 完成. */
  private sessionId: string = ''
  private outputPath: string = ''
  private elapsedTimer: number = -1
  private rippleTimer: number = -1
  private closingHandled: boolean = false
  private lifecycle = new PageLifecycle()
  private closeGuard = new PageCloseGuard()
  private recordingService: AudioRecordingService = AudioRecordingService.getInstance()

  aboutToAppear(): void {
    this.lifecycle.appear()
    this.closeGuard.reset()
  }

  aboutToDisappear(): void {
    this.clearElapsedTimer()
    this.clearRippleTimer()
    this.recordingService.setAmplitudeCallback(undefined)
    if (!this.closingHandled && this.phase === VoiceNotePhase.Recording) {
      void this.recordingService.cancelRecording(this.outputPath)
    }
    this.lifecycle.disappear()
  }

  onBackPress(): boolean {
    void this.handleBack()
    return true
  }

  private clearElapsedTimer(): void {
    if (this.elapsedTimer >= 0) {
      clearInterval(this.elapsedTimer)
      this.elapsedTimer = -1
    }
  }

  private clearRippleTimer(): void {
    if (this.rippleTimer >= 0) {
      clearInterval(this.rippleTimer)
      this.rippleTimer = -1
    }
  }

  private bumpVisual(): void {
    this.visualTick = this.visualTick + 1
  }

  private formatElapsed(ms: number): string {
    const totalSec = Math.floor(ms / 1000)
    const sec = (totalSec % 60).toString().padStart(2, '0')
    const min = Math.floor((totalSec % 3600) / 60).toString().padStart(2, '0')
    const hours = Math.floor(totalSec / 3600).toString().padStart(2, '0')
    return `${hours}:${min}:${sec}`
  }

  private statusText(): string {
    if (this.phase === VoiceNotePhase.Recording) {
      return LocaleService.loc('正在录音中…', 'Recording...', '録音中…')
    }
    if (this.phase === VoiceNotePhase.Stopped) {
      return LocaleService.loc('已停止录音', 'Recording stopped', '録音を停止しました')
    }
    return LocaleService.loc('请开始录音', 'Please start recording', '録音を開始してください')
  }

  private centerSymbol(): Resource {
    if (this.phase === VoiceNotePhase.Recording) {
      return $r('sys.symbol.pause')
    }
    if (this.phase === VoiceNotePhase.Stopped) {
      return $r('sys.symbol.mic')
    }
    return $r('sys.symbol.record_circle')
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message,
        duration: 2000
      })
    } catch (error) {
      Logger.warn('VoiceNote', `showToast failed: ${JSON.stringify(error)}`)
    }
  }

  private popPage(): void {
    this.closeGuard.runBack(() => {
      this.getUIContext().getRouter().back()
    }, 'VoiceNote')
  }

  private moveRecordingToNotePath(tempPath: string, noteId: string): string {
    const finalPath = this.recordingService.resolveOutputPath(noteId)
    if (tempPath === finalPath) {
      return finalPath
    }
    try {
      if (fs.accessSync(finalPath)) {
        fs.unlinkSync(finalPath)
      }
    } catch (_) {
      // ignore
    }
    fs.renameSync(tempPath, finalPath)
    return finalPath
  }

  private async startRecording(): Promise<void> {
    if (this.busy) {
      return
    }
    this.busy = true
    try {
      this.sessionId = IdUtils.uuid()
      this.outputPath = this.recordingService.resolveOutputPath(this.sessionId)
      this.recordingService.setAmplitudeCallback((level: number): void => {
        const next = this.amplitudes.slice()
        next.push(level)
        if (next.length > 120) {
          next.shift()
        }
        this.amplitudes = next
        this.bumpVisual()
      })
      await this.recordingService.startRecording(this.outputPath)
      this.elapsedMs = 0
      this.clearElapsedTimer()
      this.elapsedTimer = setInterval((): void => {
        this.elapsedMs += 200
      }, 200)
      this.clearRippleTimer()
      this.rippleTimer = setInterval((): void => {
        this.rippleProgress = (this.rippleProgress + 0.025) % 1.0
        this.bumpVisual()
      }, 50)
      this.phase = VoiceNotePhase.Recording
      this.bumpVisual()
    } catch (_) {
      this.recordingService.setAmplitudeCallback(undefined)
      this.showToast(LocaleService.loc(
        '需要麦克风权限才能录音',
        'Microphone permission is required to record',
        '録音にはマイク権限が必要です'
      ))
      this.closingHandled = true
      await this.recordingService.cancelRecording(this.outputPath)
      this.sessionId = ''
      this.outputPath = ''
      this.popPage()
    } finally {
      this.busy = false
    }
  }

  private async stopRecording(): Promise<void> {
    if (this.busy || this.phase !== VoiceNotePhase.Recording) {
      return
    }
    this.busy = true
    this.clearElapsedTimer()
    this.clearRippleTimer()
    await this.recordingService.stopRecording()
    this.recordingService.setAmplitudeCallback(undefined)
    this.phase = VoiceNotePhase.Stopped
    this.bumpVisual()
    this.busy = false
  }

  private isRecordingFileReady(path: string): boolean {
    const trimmed = path.trim()
    if (trimmed.length === 0) {
      return false
    }
    try {
      if (!fs.accessSync(trimmed)) {
        return false
      }
      // WAV 头 44 字节；无有效 PCM 时视为无效录音。
      return fs.statSync(trimmed).size > 44
    } catch (_) {
      return false
    }
  }

  private async discardAndClose(): Promise<void> {
    if (this.busy) {
      return
    }
    this.closingHandled = true
    await this.recordingService.cancelRecording(this.outputPath)
    this.sessionId = ''
    this.outputPath = ''
    this.popPage()
  }

  private async handleComplete(): Promise<void> {
    if (this.busy || this.outputPath.length === 0 || this.phase !== VoiceNotePhase.Stopped) {
      return
    }
    if (!this.isRecordingFileReady(this.outputPath)) {
      this.showToast(LocaleService.loc(
        '录音文件未找到，请稍后重试',
        'Recording file not found; please try again',
        '録音ファイルが見つかりません。後でもう一度お試しください'
      ))
      return
    }
    this.busy = true
    this.closingHandled = true
    const tempPath = this.outputPath
    let createdNoteId = ''
    try {
      // Create the note only on complete so abandon never leaves an empty list item.
      const note = await NoteRepository.getInstance().createNote({
        title: LocaleService.loc('新录音', 'New recording', '新規録音'),
        content: '',
        tags: [],
        skipTitleAutoFill: true
      })
      createdNoteId = note.id
      const finalPath = this.moveRecordingToNotePath(tempPath, createdNoteId)
      this.outputPath = finalPath
      this.sessionId = ''
      // Bind audioId before opening editor so NoteEdit won't treat this as a
      // discardable voice placeholder and purge the note during autosave.
      await NoteRepository.getInstance().saveDraft(createdNoteId, {
        audioId: AudioConstants.audioFileNameForNote(createdNoteId)
      })
      await this.getUIContext().getRouter().replaceUrl({
        url: 'pages/VoiceNoteDetail',
        params: {
          noteId: createdNoteId,
          pendingVoicePath: finalPath
        }
      }, router.RouterMode.Single)
    } catch (e) {
      Logger.warn('VoiceNote', `complete navigate failed: ${JSON.stringify(e)}`)
      if (createdNoteId.length > 0) {
        try {
          await NoteRepository.getInstance().purgeLocalNoteCompletely(createdNoteId)
        } catch (_) {
          // ignore rollback errors
        }
      }
      this.showToast(LocaleService.loc(
        '保存录音失败，请稍后重试',
        'Failed to save recording; please try again',
        '録音の保存に失敗しました。後でもう一度お試しください'
      ))
      this.busy = false
      this.closingHandled = false
    }
  }

  private onCenterTap(): void {
    if (this.busy) {
      return
    }
    if (this.phase === VoiceNotePhase.Idle) {
      void this.startRecording()
    } else if (this.phase === VoiceNotePhase.Recording) {
      void this.stopRecording()
    }
  }

  private async confirmAbandon(): Promise<boolean> {
    return await showConfirmAlertDialog(this.getUIContext(), {
      title: LocaleService.loc('提示', 'Notice', '提示'),
      message: LocaleService.loc(
        '确定放弃本次录音？',
        'Discard this recording?',
        'この録音を破棄しますか？'
      ),
      cancelLabel: LocaleService.loc('取消', 'Cancel', 'キャンセル'),
      confirmLabel: LocaleService.loc('放弃', 'Discard', '放棄'),
      confirmColor: '#DC2626'
    })
  }

  private async handleBack(): Promise<void> {
    if (this.phase === VoiceNotePhase.Idle) {
      this.closingHandled = true
      this.popPage()
      return
    }
    const ok = await this.confirmAbandon()
    if (!ok || !this.lifecycle.isActive()) {
      return
    }
    await this.discardAndClose()
  }

  @Builder
  private buildDiscardAction(): void {
    Column({ space: 6 }) {
      SymbolGlyph($r('sys.symbol.xmark_circle'))
        .fontSize(28)
        .fontColor([$r('app.color.secondary_text')])
      Text(LocaleService.loc('放弃', 'Discard', '放棄'))
        .fontSize(13)
        .fontColor($r('app.color.secondary_text'))
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .alignItems(HorizontalAlign.Center)
    .onClick((): void => {
      if (!this.busy) {
        void this.discardAndClose()
      }
    })
  }

  @Builder
  private buildCompleteAction(): void {
    Column({ space: 6 }) {
      SymbolGlyph($r('sys.symbol.checkmark'))
        .fontSize(28)
        .fontColor([$r('app.color.secondary_text')])
      Text(LocaleService.loc('完成', 'Done', '完了'))
        .fontSize(13)
        .fontColor($r('app.color.secondary_text'))
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .alignItems(HorizontalAlign.Center)
    .onClick((): void => {
      if (!this.busy) {
        void this.handleComplete()
      }
    })
  }

  build() {
    Column() {
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
          void this.handleBack()
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
      }
      .width('100%')
      .height($r('app.float.toolbar_height'))
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)

      Column() {
        Blank().layoutWeight(2)

        VoiceNoteVisual({
          amplitudes: this.amplitudes,
          phase: this.phase === VoiceNotePhase.Recording ? 1 :
            (this.phase === VoiceNotePhase.Stopped ? 2 : 0),
          rippleProgress: this.rippleProgress,
          visualTick: this.visualTick,
          accentColor: '#0DAA4A',
          visualWidth: 260,
          visualHeight: 220
        })

        Text(this.formatElapsed(this.elapsedMs))
          .fontSize(36)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
          .margin({ top: 28 })

        Text(this.statusText())
          .fontSize(15)
          .fontColor($r('app.color.secondary_text'))
          .margin({ top: 10 })

        Blank().layoutWeight(3)

        Row() {
          if (this.phase === VoiceNotePhase.Stopped) {
            Column() {
              this.buildDiscardAction()
            }
            .layoutWeight(1)
          } else {
            Blank().layoutWeight(1)
          }

          // 圆形按钮：不用半透明 Circle 叠在 Stack 白底上，避免透出白方块。
          Column() {
            Button({ type: ButtonType.Circle }) {
              SymbolGlyph(this.centerSymbol())
                .fontSize(32)
                .fontColor([Color.White])
            }
            .width(68)
            .height(68)
            .backgroundColor($r('app.color.accent'))
            .shadow({
              radius: 16,
              color: '#590DAA4A',
              offsetX: 0,
              offsetY: 2
            })
            .onClick((): void => {
              this.onCenterTap()
            })
          }
          .width(84)
          .height(84)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor(Color.Transparent)

          if (this.phase === VoiceNotePhase.Stopped) {
            Column() {
              this.buildCompleteAction()
            }
            .layoutWeight(1)
          } else {
            Blank().layoutWeight(1)
          }
        }
        .width('100%')
        .padding({ bottom: 36 })
        .alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: 24, right: 24 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
