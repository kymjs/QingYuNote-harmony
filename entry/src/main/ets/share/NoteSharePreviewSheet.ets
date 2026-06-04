import { LengthMetrics } from '@kit.ArkUI'
import { Logger } from '../common/utils/Logger'
import { ShareCardTheme, ShareCardTone, ShareThemeColors } from './ShareTheme'

const SHARE_PREVIEW_SHEET_LOG_TAG: string = 'NoteSharePreviewSheet'

export interface NoteSharePreviewSheetParams {
  onThemeChange: (theme: ShareCardTheme) => void
  onToneChange: (tone: ShareCardTone) => void
  onSave: () => void
  onShare: () => void
  onCancel: () => void
}

@Component
export struct NoteSharePreviewSheet {
  @Prop @Watch('onThemePropChanged') theme: ShareCardTheme = ShareCardTheme.CLASSIC
  @Prop @Watch('onTonePropChanged') tone: ShareCardTone = ShareCardTone.DARK
  @Prop sheetRevision: number = 0
  @Prop params: NoteSharePreviewSheetParams = {
    onThemeChange: (_t: ShareCardTheme): void => {},
    onToneChange: (_t: ShareCardTone): void => {},
    onSave: (): void => {},
    onShare: (): void => {},
    onCancel: (): void => {}
  }

  @State private selectedTheme: ShareCardTheme = ShareCardTheme.CLASSIC
  @State private selectedTone: ShareCardTone = ShareCardTone.DARK

  private readonly themes: ShareCardTheme[] =
    [ShareCardTheme.CLASSIC, ShareCardTheme.QINGYU, ShareCardTheme.CALENDAR, ShareCardTheme.JINSHU]

  private readonly tones: ShareCardTone[] = [ShareCardTone.DARK, ShareCardTone.LIGHT]

  aboutToAppear(): void {
    this.selectedTheme = this.theme
    this.selectedTone = this.tone
    this.logSelection('aboutToAppear')
  }

  aboutToReuse(params: Record<string, Object>): void {
    this.selectedTheme = this.theme
    this.selectedTone = this.tone
    Logger.info(SHARE_PREVIEW_SHEET_LOG_TAG,
      `aboutToReuse revision=${this.sheetRevision} theme=${this.theme} tone=${this.tone} keys=${Object.keys(params).join(',')}`)
  }

  onThemePropChanged(_propName: string): void {
    this.selectedTheme = this.theme
  }

  onTonePropChanged(_propName: string): void {
    this.selectedTone = this.tone
  }

  private logSelection(stage: string): void {
    Logger.info(SHARE_PREVIEW_SHEET_LOG_TAG,
      `${stage} revision=${this.sheetRevision} theme=${this.selectedTheme} tone=${this.selectedTone}`)
  }

  private logButtonTap(button: string, label: string): void {
    Logger.info(SHARE_PREVIEW_SHEET_LOG_TAG,
      `button=${button} label=${label} sheetTheme=${this.selectedTheme} sheetTone=${this.selectedTone} revision=${this.sheetRevision}`)
  }

  @Builder
  private buildChip(label: string, selected: boolean, onTap: () => void) {
    Text(label)
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .fontColor(selected ? $r('app.color.on_accent') : $r('app.color.primary_text'))
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .backgroundColor(selected ? $r('app.color.accent') : $r('app.color.surface_muted'))
      .borderRadius(20)
      .onClick(onTap)
  }

  @Builder
  private buildAction(icon: Resource, label: string, onTap: () => void) {
    Column({ space: 4 }) {
      Row() {
        SymbolGlyph(icon)
          .fontSize(22)
          .fontColor([$r('app.color.secondary_text')])
      }
      .width(48)
      .height(48)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r('app.color.surface_muted'))
      .borderRadius(24)
      Text(label)
        .fontSize(12)
        .fontColor($r('app.color.secondary_text'))
    }
    .onClick(onTap)
  }

  build() {
    Column({ space: 14 }) {
      Row() {
        Blank()
          .layoutWeight(1)
        Row() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(16)
            .fontColor([$r('app.color.secondary_text')])
        }
        .width(32)
        .height(32)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .backgroundColor($r('app.color.surface_muted'))
        .borderRadius(16)
        .onClick((): void => {
          this.logButtonTap('cancel', '取消')
          this.params.onCancel()
        })
      }
      .width('100%')
      .margin({ top: 4 })

      Column()
        .width(36)
        .height(4)
        .backgroundColor($r('app.color.divider'))
        .borderRadius(2)
        .alignSelf(ItemAlign.Center)

      Row({ space: 10 }) {
        Text('主题')
          .fontSize(13)
          .fontColor($r('app.color.secondary_text'))
          .width(40)
        Flex({
          wrap: FlexWrap.Wrap,
          space: { main: LengthMetrics.vp(10), cross: LengthMetrics.vp(8) }
        }) {
          ForEach(this.themes, (t: ShareCardTheme) => {
            this.buildChip(
              ShareThemeColors.label(t),
              this.selectedTheme === t,
              (): void => {
                if (this.selectedTheme === t) {
                  return
                }
                this.selectedTheme = t
                this.logButtonTap('theme', ShareThemeColors.label(t))
                this.params.onThemeChange(t)
              }
            )
          }, (t: ShareCardTheme) => `${this.sheetRevision}_${t}`)
        }
        .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: 10 }) {
        Text('色调')
          .fontSize(13)
          .fontColor($r('app.color.secondary_text'))
          .width(40)
        Flex({
          wrap: FlexWrap.Wrap,
          space: { main: LengthMetrics.vp(10), cross: LengthMetrics.vp(8) }
        }) {
          ForEach(this.tones, (t: ShareCardTone) => {
            this.buildChip(
              ShareThemeColors.toneLabel(t),
              this.selectedTone === t,
              (): void => {
                if (this.selectedTone === t) {
                  return
                }
                this.selectedTone = t
                this.logButtonTap('tone', ShareThemeColors.toneLabel(t))
                this.params.onToneChange(t)
              }
            )
          }, (t: ShareCardTone) => `${this.sheetRevision}_${t}`)
        }
        .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: 10 }) {
        Text('操作')
          .fontSize(13)
          .fontColor($r('app.color.secondary_text'))
          .width(40)
        Row({ space: 24 }) {
          this.buildAction($r('sys.symbol.arrow_down_to_line'), '保存到相册', (): void => {
            this.logButtonTap('action', '保存到相册')
            this.params.onSave()
          })
          this.buildAction($r('sys.symbol.share'), '分享到其他应用', (): void => {
            this.logButtonTap('action', '分享到其他')
            this.params.onShare()
          })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 12, bottom: 24 })
    .backgroundBlurStyle(BlurStyle.Thin)
    .backgroundColor($r('app.color.sheet_background'))
    .borderRadius({ topLeft: 24, topRight: 24 })
  }
}

export interface NoteSharePreviewOverlayParams {
  previewPath: string
  regenerating: boolean
}

@Component
export struct NoteSharePreviewOverlay {
  @Prop params: NoteSharePreviewOverlayParams = {
    previewPath: '',
    regenerating: false
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.55)')
      if (this.params.regenerating) {
        Stack({ alignContent: Alignment.Center }) {
          LoadingProgress()
            .width(40)
            .height(40)
            .color(Color.White)
        }
        .width('100%')
        .height('100%')
      } else if (this.params.previewPath.length > 0) {
        Scroll() {
          Image(`file://${this.params.previewPath}`)
            .width('100%')
            .objectFit(ImageFit.Contain)
        }
        .scrollable(ScrollDirection.Vertical)
        .scrollBar(BarState.Off)
        .width('100%')
        .height('100%')
        .padding({ top: 48, bottom: 200 })
      }
    }
    .width('100%')
    .height('100%')
  }
}
