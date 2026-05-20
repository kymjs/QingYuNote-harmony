import type { MarkdownBlock } from '../common/utils/MarkdownUtils'
import { NoteEditMarkdownBlocksView } from './NoteEditMarkdownBlocksView'

@Builder
function noteEditPreviewDefaultTagBar(): void {
}

@Component
export struct NoteEditPreviewPane {
  @Prop title: string = ''
  @Prop splitMode: boolean = false
  /** 为 false 时标题由页面顶栏展示（窄屏全屏预览）。 */
  @Prop includeTitle: boolean = true
  @Prop showSplitTagRow: boolean = false
  @Prop previewBlocks: MarkdownBlock[] = []
  @Prop filesDirCache: string = ''
  onBackgroundTap: () => void = () => {
  }
  onLinkToast: (href: string) => void = (_href: string) => {
  }
  @BuilderParam tagBarSlot: () => void = noteEditPreviewDefaultTagBar

  build() {
    Scroll() {
      Column({ space: 14 }) {
        if (!this.splitMode && this.includeTitle) {
          Text(this.title.trim().length > 0 ? this.title : '无标题')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
            .copyOption(CopyOptions.LocalDevice)
            .width('100%')
        } else {
          if (this.showSplitTagRow) {
            Row() {
              Blank()
                .layoutWeight(1)
              this.tagBarSlot()
            }
            .width('100%')
          }
        }
        NoteEditMarkdownBlocksView({
          blocks: this.previewBlocks,
          filesDirCache: this.filesDirCache,
          onLinkToast: this.onLinkToast
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .alignItems(HorizontalAlign.Start)
      .padding(18)
      .margin({ bottom: 16 })
      .backgroundColor($r('app.color.preview_background'))
      .borderRadius($r('app.float.card_radius'))
      .border({ width: 1, color: $r('app.color.card_border') })
      .shadow({
        radius: 16,
        color: $r('app.color.shadow_color'),
        offsetX: 0,
        offsetY: 3
      })
    }
    .scrollBar(BarState.Off)
    .layoutWeight(1)
    .width('100%')
    .height('100%')
    .align(Alignment.TopStart)
    .onClick(() => {
      this.onBackgroundTap()
    })
  }
}
