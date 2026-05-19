export type EditorQuickActionType =
  | 'link'
  | 'quote'
  | 'hr'
  | 'orderedList'
  | 'bulletList'
  | 'bold'
  | 'strike'
  | 'italic'

@Component
export struct EditorQuickActionBar {
  /** 与编辑页 [pageWidth] 同步，避免首帧宽度为 0 时按满 padding 布局导致第 8 个图标被挤出。 */
  @Prop barWidthVp: number = 360
  /** 在 onClick 之前触发（TouchDown），此时 TextArea 往往仍保有正确选区。 */
  onBeforeAction: () => void = () => {
  }
  onAction: (action: EditorQuickActionType) => void = (_: EditorQuickActionType) => {
  }

  private static readonly BAR_HEIGHT: number = 40
  private static readonly SLOT_SIZE: number = 40
  private static readonly BAR_PADDING_H: number = 8
  private static readonly ICON_COUNT: number = 8
  private static readonly ICON_VISUAL_SIZE: number = EditorQuickActionBar.SLOT_SIZE * 0.7
  private static readonly ICON_PADDING: number = EditorQuickActionBar.SLOT_SIZE * 0.3
  private static readonly ICON_CELL_WIDTH: number =
    EditorQuickActionBar.ICON_VISUAL_SIZE + EditorQuickActionBar.ICON_PADDING * 2

  private resolveHorizontalPadding(): number {
    const usable = this.barWidthVp - EditorQuickActionBar.BAR_PADDING_H * 2
    if (usable <= 0) {
      return 0
    }
    const fullWidth = EditorQuickActionBar.ICON_COUNT * EditorQuickActionBar.ICON_CELL_WIDTH
    if (fullWidth <= usable) {
      return EditorQuickActionBar.ICON_PADDING
    }
    const perSlot = usable / EditorQuickActionBar.ICON_COUNT
    const pad = (perSlot - EditorQuickActionBar.ICON_VISUAL_SIZE) / 2
    return Math.max(0, Math.min(EditorQuickActionBar.ICON_PADDING, pad))
  }

  private cellWidth(hPad: number): number {
    return EditorQuickActionBar.ICON_VISUAL_SIZE + hPad * 2
  }

  @Builder
  private buildIcon(action: EditorQuickActionType, media: Resource, hPad: number) {
    Row() {
      Image(media)
        .width(EditorQuickActionBar.ICON_VISUAL_SIZE)
        .height(EditorQuickActionBar.ICON_VISUAL_SIZE)
        .objectFit(ImageFit.Contain)
    }
    .width(this.cellWidth(hPad))
    .height(EditorQuickActionBar.SLOT_SIZE)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(Color.Transparent)
    .focusable(false)
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.onBeforeAction()
      }
    })
    .onClick(() => {
      this.onAction(action)
    })
  }

  @Builder
  private buildBar(hPad: number) {
    Row() {
      this.buildIcon('link', $r('app.media.ic_editor_link'), hPad)
      this.buildIcon('quote', $r('app.media.ic_editor_quote'), hPad)
      this.buildIcon('hr', $r('app.media.ic_editor_hr'), hPad)
      this.buildIcon('orderedList', $r('app.media.ic_editor_ol'), hPad)
      this.buildIcon('bulletList', $r('app.media.ic_editor_ul'), hPad)
      this.buildIcon('bold', $r('app.media.ic_editor_bold'), hPad)
      this.buildIcon('strike', $r('app.media.ic_editor_strike'), hPad)
      this.buildIcon('italic', $r('app.media.ic_editor_italic'), hPad)
    }
    .width('100%')
    .height(EditorQuickActionBar.BAR_HEIGHT)
    .padding({ left: EditorQuickActionBar.BAR_PADDING_H, right: EditorQuickActionBar.BAR_PADDING_H })
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('app.color.surface_muted'))
    .focusable(false)
  }

  build() {
    this.buildBar(this.resolveHorizontalPadding())
  }
}
