import { AudioRecordingService } from '../services/AudioRecordingService'
import { APP_LOCALE_REVISION_KEY, LocaleService } from '../services/LocaleService'

enum VoiceRecordingPhase {
  Idle = 0,
  Recording = 1,
  Stopped = 2
}

export interface VoiceRecordingSheetParams {
  noteId: string
  noteTitle: string
  onComplete: (outputPath: string) => void
  onCancel: () => void
  onClose: () => void
  onPermissionDenied?: () => void
}

@Component
export struct VoiceRecordingSheet {
  @StorageProp(APP_LOCALE_REVISION_KEY) localeRevision: number = 0
  @Prop params: VoiceRecordingSheetParams = {
    noteId: '',
    noteTitle: '',
    onComplete: (_: string): void => {},
    onCancel: (): void => {},
    onClose: (): void => {}
  }

  @State private phase: VoiceRecordingPhase = VoiceRecordingPhase.Idle
  @State private amplitudes: number[] = []
  @State private elapsedMs: number = 0
  @State private busy: boolean = false

  private outputPath: string = ''
  private elapsedTimer: number = -1
  private recordingService: AudioRecordingService = AudioRecordingService.getInstance()

  aboutToDisappear(): void {
    this.clearElapsedTimer()
    this.recordingService.setAmplitudeCallback(undefined)
  }

  private clearElapsedTimer(): void {
    if (this.elapsedTimer >= 0) {
      clearInterval(this.elapsedTimer)
      this.elapsedTimer = -1
    }
  }

  private formatElapsed(ms: number): string {
    const totalCs = Math.floor(ms / 10)
    const cs = (totalCs % 100).toString().padStart(2, '0')
    const totalSec = Math.floor(ms / 1000)
    const sec = (totalSec % 60).toString().padStart(2, '0')
    const min = Math.floor(totalSec / 60).toString().padStart(2, '0')
    return `${min}:${sec}.${cs}`
  }

  private displayTitle(): string {
    const trimmed = this.params.noteTitle.trim()
    if (trimmed.length > 0) {
      return trimmed
    }
    return LocaleService.loc('新录音', 'New recording', '新規録音')
  }

  private async startRecording(): Promise<void> {
    if (this.busy) {
      return
    }
    this.busy = true
    try {
      this.outputPath = this.recordingService.resolveOutputPath(this.params.noteId)
      this.recordingService.setAmplitudeCallback((level: number): void => {
        const next = [...this.amplitudes, level]
        if (next.length > 120) {
          next.shift()
        }
        this.amplitudes = next
      })
      await this.recordingService.startRecording(this.outputPath)
      this.elapsedMs = 0
      this.clearElapsedTimer()
      this.elapsedTimer = setInterval((): void => {
        this.elapsedMs += 50
      }, 50)
      this.phase = VoiceRecordingPhase.Recording
    } catch (_) {
      this.recordingService.setAmplitudeCallback(undefined)
      if (this.params.onPermissionDenied) {
        this.params.onPermissionDenied()
      }
      this.params.onClose()
    } finally {
      this.busy = false
    }
  }

  private async stopRecording(): Promise<void> {
    if (this.busy || this.phase !== VoiceRecordingPhase.Recording) {
      return
    }
    this.busy = true
    this.clearElapsedTimer()
    await this.recordingService.stopRecording()
    this.recordingService.setAmplitudeCallback(undefined)
    this.phase = VoiceRecordingPhase.Stopped
    this.busy = false
  }

  private async handleCancel(): Promise<void> {
    if (this.busy) {
      return
    }
    await this.recordingService.cancelRecording(this.outputPath)
    this.params.onClose()
    this.params.onCancel()
  }

  private handleComplete(): void {
    if (this.busy || this.outputPath.length === 0) {
      return
    }
    const path = this.outputPath
    this.params.onClose()
    this.params.onComplete(path)
  }

  private onRecordButtonTap(): void {
    if (this.busy) {
      return
    }
    if (this.phase === VoiceRecordingPhase.Idle) {
      void this.startRecording()
    } else if (this.phase === VoiceRecordingPhase.Recording) {
      void this.stopRecording()
    }
  }

  @Builder
  private buildWaveform(): void {
    Row({ space: 2 }) {
      ForEach(this.buildWaveformSlots(), (level: number, index: number) => {
        Column()
          .width(3)
          .height(this.waveformBarHeight(level, index))
          .backgroundColor(this.waveformBarColor(level))
          .borderRadius(2)
      }, (level: number, index: number) => `${index}_${level.toFixed(4)}`)
    }
    .width('100%')
    .height(56)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
  }

  private buildWaveformSlots(): number[] {
    const slots: number[] = []
    const count = 60
    const start = Math.max(0, this.amplitudes.length - count)
    for (let index = start; index < this.amplitudes.length; index += 1) {
      slots.push(this.amplitudes[index])
    }
    while (slots.length < count) {
      slots.unshift(0)
    }
    return slots
  }

  private waveformBarHeight(level: number, index: number): number {
    const animating = this.phase === VoiceRecordingPhase.Recording
    const base = animating ? Math.max(6, level * 48) : 8
    if (!animating && level <= 0) {
      const wave = 6 + (index % 5) * 2
      return wave
    }
    return base
  }

  private waveformBarColor(level: number): ResourceColor {
    if (this.phase === VoiceRecordingPhase.Recording || level > 0) {
      return '#FFE53935'
    }
    return $r('app.color.divider')
  }

  @Builder
  private buildRecordButton(): void {
    Row() {
      Column()
        .width(this.phase === VoiceRecordingPhase.Recording ? 28 : 56)
        .height(this.phase === VoiceRecordingPhase.Recording ? 28 : 56)
        .backgroundColor('#FFE53935')
        .borderRadius(this.phase === VoiceRecordingPhase.Recording ? 4 : 28)
    }
    .width(72)
    .height(72)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .border({
      width: 3,
      color: $r('app.color.divider')
    })
    .borderRadius(36)
    .onClick((): void => {
      this.onRecordButtonTap()
    })
  }

  build() {
    Column({ space: 0 }) {
      Column()
        .width(36)
        .height(4)
        .backgroundColor($r('app.color.divider'))
        .borderRadius(2)
        .margin({ top: 12 })

      Text(this.displayTitle())
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary_text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ top: 20 })

      Text(this.formatElapsed(this.elapsedMs))
        .fontSize(28)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary_text'))
        .margin({ top: 8 })

      Column() {
        this.buildWaveform()
      }
      .width('100%')
      .margin({ top: 24 })

      if (this.phase === VoiceRecordingPhase.Stopped) {
        Row() {
          Button(LocaleService.loc('取消', 'Cancel', 'キャンセル'))
            .type(ButtonType.Normal)
            .backgroundColor(Color.Transparent)
            .fontColor($r('app.color.primary_text'))
            .enabled(!this.busy)
            .onClick((): void => {
              void this.handleCancel()
            })
          Blank()
          Button(LocaleService.loc('完成', 'Done', '完了'))
            .type(ButtonType.Normal)
            .backgroundColor(Color.Transparent)
            .fontColor('#FFE53935')
            .fontWeight(FontWeight.Medium)
            .enabled(!this.busy)
            .onClick((): void => {
              this.handleComplete()
            })
        }
        .width('100%')
        .margin({ top: 28 })
      } else {
        Column() {
          this.buildRecordButton()
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .margin({ top: 28 })
      }
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 0, bottom: 20 })
    .backgroundBlurStyle(BlurStyle.Thin)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius({ topLeft: 24, topRight: 24 })
  }
}

@Builder
export function buildVoiceRecordingSheetContent(params: VoiceRecordingSheetParams): void {
  VoiceRecordingSheet({ params: params })
}
