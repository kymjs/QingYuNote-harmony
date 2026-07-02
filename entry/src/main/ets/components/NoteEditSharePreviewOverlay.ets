import { NoteSharePreviewSheet, type NoteSharePreviewSheetParams } from '../share/NoteSharePreviewSheet'
import { ShareCardTheme, ShareCardTone } from '../share/ShareTheme'

/** 分享预览全屏浮层（从 NoteEdit.ets 拆出）。 */
@Component
export struct NoteEditSharePreviewOverlay {
  @Prop preparing: boolean = false
  @Prop visible: boolean = false
  @Prop regenerating: boolean = false
  @Prop previewPath: string = ''
  @Prop previewImageHeightVp: number = 0
  @Prop pageWidth: number = 360
  @Prop optionsSheetVisible: boolean = false
  @Prop shareTheme: ShareCardTheme = ShareCardTheme.CLASSIC
  @Prop shareTone: ShareCardTone = ShareCardTone.DARK
  @Prop shareShowAppIcon: boolean = false
  @Prop sheetRevision: number = 0
  @Prop sheetParams: NoteSharePreviewSheetParams = {
    onThemeChange: (_t: ShareCardTheme): void => {},
    onToneChange: (_t: ShareCardTone): void => {},
    onFooterImageToggle: (): void => {},
    onSave: (): void => {},
    onShare: (): void => {},
    onCancel: (): void => {}
  }
  onPreviewImageComplete: (width: number, height: number) => void = () => {
  }

  @Builder
  private buildOptionsSheet() {
    NoteSharePreviewSheet({
      theme: this.shareTheme,
      tone: this.shareTone,
      showAppIcon: this.shareShowAppIcon,
      sheetRevision: this.sheetRevision,
      params: this.sheetParams
    })
      .key(`share_preview_sheet_${this.shareShowAppIcon}`)
  }

  build() {
    Stack() {
      if (this.preparing && !this.visible) {
        Stack({ alignContent: Alignment.TopStart }) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('rgba(0,0,0,0.92)')
          Column() {
            LoadingProgress()
              .width(40)
              .height(40)
              .color(Color.White)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        }
        .width('100%')
        .height('100%')
        .zIndex(10004)
      } else if (this.visible) {
        Column() {
          Stack({ alignContent: Alignment.TopStart }) {
            Column()
              .width('100%')
              .height('100%')
              .backgroundColor(this.regenerating ? 'rgba(0,0,0,0.92)' : 'rgba(0,0,0,0.55)')
            if (this.regenerating) {
              Column() {
                LoadingProgress()
                  .width(40)
                  .height(40)
                  .color(Color.White)
              }
              .width('100%')
              .height('100%')
              .justifyContent(FlexAlign.Center)
            } else if (this.previewPath.length > 0) {
              Scroll() {
                Image(`file://${this.previewPath}`)
                  .width('100%')
                  .height(this.previewImageHeightVp > 0 ? this.previewImageHeightVp : '100%')
                  .objectFit(ImageFit.Contain)
                  .onComplete((event) => {
                    if (this.previewImageHeightVp > 0) {
                      return
                    }
                    const w = Number(event?.width ?? 0)
                    const h = Number(event?.height ?? 0)
                    if (w > 0 && h > 0) {
                      this.onPreviewImageComplete(w, h)
                    }
                  })
              }
              .scrollable(ScrollDirection.Vertical)
              .scrollBar(BarState.Off)
              .width('100%')
              .height('100%')
              .padding({ top: 48, bottom: 8 })
            }
          }
          .layoutWeight(1)
          .width('100%')
          .height('100%')

          if (this.optionsSheetVisible) {
            this.buildOptionsSheet()
          }
        }
        .width('100%')
        .height('100%')
        .zIndex(10004)
      }
    }
    .width('100%')
    .height('100%')
  }
}
