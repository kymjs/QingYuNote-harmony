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
  /** 窄屏：去掉边框阴影卡片。 */
  @Prop flatChrome: boolean = false
  @Prop previewBlocks: MarkdownBlock[] = []
  @Prop filesDirCache: string = ''
  @Prop imageRefreshKey: number = 0
  onBackgroundTap: () => void = () => {
  }
  onLinkToast: (href: string) => void = (_href: string) => {
  }
  onCheckboxToggle: (lineIndex: number, checked: boolean) => void =
    (_lineIndex: number, _checked: boolean) => {
    }
  onImageTap: (src: string) => void = (_src: string) => {
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
          imageRefreshKey: this.imageRefreshKey,
          onLinkToast: this.onLinkToast,
          onCheckboxToggle: this.onCheckboxToggle,
          onImageTap: this.onImageTap
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .alignItems(HorizontalAlign.Start)
      .padding(this.flatChrome ? { top: 8, bottom: 16 } : 18)
      .margin({ bottom: this.flatChrome ? 0 : 16 })
      .backgroundColor(this.flatChrome ? Color.Transparent : $r('app.color.preview_background'))
      .borderRadius(this.flatChrome ? 0 : $r('app.float.card_radius'))
      .border(this.flatChrome ? { width: 0, color: Color.Transparent } :
        { width: 1, color: $r('app.color.card_border') })
      .shadow(this.flatChrome ? {
        radius: 0,
        color: Color.Transparent,
        offsetX: 0,
        offsetY: 0
      } : {
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
    .nestedScroll({
      scrollForward: NestedScrollMode.PARENT_FIRST,
      scrollBackward: NestedScrollMode.SELF_FIRST
    })
  }
}
