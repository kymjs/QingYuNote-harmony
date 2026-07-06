import { NOTE_EDIT_SHARE_SCROLL_ID } from '../common/utils/NoteEditShareHelper'

/** 离屏分享导出挂载层（从 NoteEdit.ets 拆出）。 */
@Component
export struct NoteEditShareExportMount {
  @Prop active: boolean = false
  @Prop scrollBg: string = '#FF1A1A1C'
  @Prop mountKey: string = ''
  shareScroller: Scroller = new Scroller()
  onCardHeightChange: (height: number) => void = () => {
  }
  @BuilderParam exportCard: () => void = this.defaultExportCard

  @Builder
  defaultExportCard() {
  }

  build() {
    Stack() {
      if (this.active) {
        Scroll(this.shareScroller) {
          this.exportCard()
        }
        .id(NOTE_EDIT_SHARE_SCROLL_ID)
        .key(`share_scroll_${this.mountKey}`)
        .scrollable(ScrollDirection.Vertical)
        .scrollBar(BarState.Off)
        .width('100%')
        .height('100%')
        .constraintSize({ minHeight: 800 })
        .backgroundColor(this.scrollBg)
        .onAreaChange((_, value) => {
          this.onCardHeightChange(Number.parseFloat(`${value.height}`) || 0)
        })
        .position({ x: 0, y: 0 })
        .opacity(0.01)
        .hitTestBehavior(HitTestMode.None)
        .zIndex(10003)
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }
}
