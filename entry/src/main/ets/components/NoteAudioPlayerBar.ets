import { AudioConstants } from '../common/constants/AudioConstants'
import { AudioPlaybackService } from '../services/AudioPlaybackService'
import { FileService } from '../services/FileService'
import { Logger } from '../common/utils/Logger'
import { SyncService } from '../services/SyncService'
import { AppContextHolder } from '../services/AppContextHolder'

const TAG = 'NoteAudioPlayerBar'

@Component
export struct NoteAudioPlayerBar {
  @Prop @Watch('onAudioIdChanged') audioId: string = ''
  @Prop noteId: string = ''

  @State private positionMs: number = 0
  @State private durationMs: number = 0
  @State private playing: boolean = false
  @State private speed: number = 1.0
  @State private loading: boolean = true
  @State private loadFailed: boolean = false
  @State private collapsed: boolean = false

  private static readonly SPEEDS: number[] = [0.8, 1.0, 1.5, 2.0]
  private static readonly SEEK_STEP_MS: number = 10000
  private static readonly CONTROL_GAP: number = 9
  private playbackService: AudioPlaybackService = AudioPlaybackService.getInstance()
  private loadedAudioId: string = ''
  private initGeneration: number = 0

  aboutToAppear(): void {
    void this.initPlayer()
  }

  aboutToDisappear(): void {
    this.playbackService.setCallbacks(undefined, undefined)
    void this.playbackService.pause()
  }

  onAudioIdChanged(): void {
    void this.initPlayer()
  }

  private localPath(): string {
    const ctx = AppContextHolder.tryGetContext()
    const base = ctx?.filesDir ?? ''
    return `${base}/${AudioConstants.audioDirectory}/${this.audioId}`
  }

  private async initPlayer(): Promise<void> {
    const generation = ++this.initGeneration
    const trimmed = this.audioId.trim()
    if (trimmed.length === 0 || this.noteId.trim().length === 0) {
      this.loading = false
      this.loadFailed = true
      return
    }
    if (this.loadedAudioId === trimmed && !this.loading && !this.loadFailed) {
      return
    }
    this.loading = true
    this.loadFailed = false
    this.playbackService.setCallbacks(
      (position: number, duration: number): void => {
        this.positionMs = position
        this.durationMs = duration
      },
      (isPlaying: boolean, _completed: boolean): void => {
        this.playing = isPlaying
      }
    )
    let path = this.localPath()
    if (!FileService.fileExists(path)) {
      await SyncService.getInstance().syncNote(this.noteId)
      path = this.localPath()
    }
    if (generation !== this.initGeneration) {
      return
    }
    if (!FileService.fileExists(path)) {
      Logger.warn(TAG, `audio file missing: path=${path}, audioId=${trimmed}, noteId=${this.noteId}`)
      this.loading = false
      this.loadFailed = true
      return
    }
    try {
      await this.playbackService.load(path)
      if (generation !== this.initGeneration) {
        return
      }
      await this.playbackService.setSpeed(this.speed)
      this.durationMs = this.playbackService.getDurationMs()
      this.loadedAudioId = trimmed
      this.loading = false
      this.loadFailed = false
    } catch (error) {
      Logger.warn(TAG, `initPlayer failed: path=${path}, error=${JSON.stringify(error)}`)
      if (generation !== this.initGeneration) {
        return
      }
      this.loading = false
      this.loadFailed = true
    }
  }

  private formatTime(ms: number): string {
    const totalSec = Math.max(0, Math.floor(ms / 1000))
    const h = Math.floor(totalSec / 3600).toString().padStart(2, '0')
    const m = Math.floor((totalSec % 3600) / 60).toString().padStart(2, '0')
    const s = (totalSec % 60).toString().padStart(2, '0')
    return `${h}:${m}:${s}`
  }

  private speedLabel(): string {
    return `${this.speed.toFixed(1)}x`
  }

  private togglePlay(): void {
    const targetPlaying = !this.playing
    this.playing = targetPlaying
    void this.playbackService.setPlaying(targetPlaying).catch((): void => {
      this.playing = !targetPlaying
    })
  }

  private cycleSpeed(): void {
    const index = NoteAudioPlayerBar.SPEEDS.indexOf(this.speed)
    const next = NoteAudioPlayerBar.SPEEDS[(index + 1) % NoteAudioPlayerBar.SPEEDS.length]
    this.speed = next
    void this.playbackService.setSpeed(next)
  }

  private sliderValue(): number {
    if (this.durationMs <= 0) {
      return 0
    }
    return Math.min(this.positionMs, this.durationMs)
  }

  private sliderMax(): number {
    return this.durationMs > 0 ? this.durationMs : 1
  }

  @Builder
  private outlineIconButton(icon: Resource, onClick: () => void) {
    Button({ type: ButtonType.Normal }) {
      SymbolGlyph(icon)
        .fontSize(18)
        .fontColor([$r('app.color.primary_text')])
    }
    .width(56)
    .height(32)
    .padding(0)
    .backgroundColor(Color.Transparent)
    .fontColor($r('app.color.primary_text'))
    .border({ width: 1, color: $r('app.color.divider') })
    .borderRadius(8)
    .onClick((): void => {
      onClick()
    })
  }

  @Builder
  private collapsedChip() {
    this.outlineIconButton($r('sys.symbol.chevron_up'), (): void => {
      this.collapsed = false
    })
  }

  @Builder
  private playbackControlsRow() {
    Row() {
      this.outlineIconButton($r('sys.symbol.chevron_down'), (): void => {
        this.collapsed = true
      })

      Blank()
        .layoutWeight(1)

      Row({ space: NoteAudioPlayerBar.CONTROL_GAP }) {
        Row() {
          SymbolGlyph($r('sys.symbol.gobackward_10'))
            .fontSize(26)
            .fontColor([$r('app.color.primary_text')])
        }
        .width(40)
        .height(40)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .onClick((): void => {
          void this.playbackService.seekRelative(-NoteAudioPlayerBar.SEEK_STEP_MS)
        })

        Row() {
          SymbolGlyph(this.playing ? $r('sys.symbol.pause') : $r('sys.symbol.play'))
            .fontSize(32)
            .fontColor([$r('app.color.primary_text')])
        }
        .width(44)
        .height(44)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .onClick((): void => {
          this.togglePlay()
        })

        Row() {
          SymbolGlyph($r('sys.symbol.goforward_10'))
            .fontSize(26)
            .fontColor([$r('app.color.primary_text')])
        }
        .width(40)
        .height(40)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .onClick((): void => {
          void this.playbackService.seekRelative(NoteAudioPlayerBar.SEEK_STEP_MS)
        })
      }

      Blank()
        .layoutWeight(1)

      Button(this.speedLabel())
        .type(ButtonType.Normal)
        .fontSize(13)
        .width(56)
        .height(32)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .fontColor($r('app.color.primary_text'))
        .border({ width: 1, color: $r('app.color.divider') })
        .borderRadius(8)
        .onClick((): void => {
          this.cycleSpeed()
        })
    }
    .width('100%')
    .height(44)
    .alignItems(VerticalAlign.Center)
  }

  build() {
    if (this.collapsed) {
      Row() {
        this.collapsedChip()
      }
      .width('100%')
      .padding({ top: 8, bottom: 12 })
      .justifyContent(FlexAlign.Start)
    } else {
      Column({ space: 8 }) {
        if (this.loading) {
          LoadingProgress()
            .width(24)
            .height(24)
        } else if (this.loadFailed) {
          Row({ space: 12 }) {
            Text('音频加载失败')
              .fontSize(14)
              .fontColor($r('app.color.secondary_text'))
              .layoutWeight(1)
            Button('重试')
              .type(ButtonType.Normal)
              .fontSize(13)
              .width(64)
              .height(32)
              .backgroundColor(Color.Transparent)
              .fontColor($r('app.color.primary_text'))
              .border({ width: 1, color: $r('app.color.divider') })
              .borderRadius(8)
              .onClick((): void => {
                this.loadedAudioId = ''
                void this.initPlayer()
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        } else {
          Row() {
            Text(this.formatTime(this.positionMs))
              .fontSize(12)
              .fontColor($r('app.color.secondary_text'))
            Slider({
              value: this.sliderValue(),
              min: 0,
              max: this.sliderMax(),
              style: SliderStyle.OutSet
            })
              .layoutWeight(1)
              .onChange((value: number): void => {
                void this.playbackService.seekTo(Math.round(value))
              })
            Text(this.formatTime(this.durationMs))
              .fontSize(12)
              .fontColor($r('app.color.secondary_text'))
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          this.playbackControlsRow()
        }
      }
      .width('100%')
      .margin({ top: 8, bottom: 12 })
      .padding({ left: 16, right: 16, top: 14, bottom: 14 })
      .backgroundColor($r('app.color.card_background'))
      .borderRadius($r('app.float.card_radius'))
      .border({ width: 1, color: $r('app.color.card_border') })
      .shadow({
        radius: 20,
        color: $r('app.color.shadow_color'),
        offsetX: 0,
        offsetY: 4
      })
    }
  }
}
