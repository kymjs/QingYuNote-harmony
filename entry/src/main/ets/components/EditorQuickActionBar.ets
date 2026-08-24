import { MermaidTemplates } from '../common/utils/MermaidTemplates'
import { EditorUiStrings } from '../common/utils/EditorUiStrings'
import { promptAction } from '@kit.ArkUI'

interface MermaidDialogButton {
  text: string
  color: string
}

export type EditorQuickActionType =
  | 'link'
  | 'image'
  | 'checkbox'
  | 'quote'
  | 'hr'
  | 'orderedList'
  | 'bulletList'
  | 'bold'
  | 'strike'
  | 'italic'
  | 'mermaid'

@Component
export struct EditorQuickActionBar {
  /** 与编辑页 [pageWidth] 同步，避免首帧宽度为 0 时按满 padding 布局导致图标被挤出。 */
  @Prop barWidthVp: number = 360
  /** 在 onClick 之前触发（TouchDown），此时 TextArea 往往仍保有正确选区。 */
  onBeforeAction: () => void = () => {
  }
  onAction: (action: EditorQuickActionType) => void = (_: EditorQuickActionType) => {
  }
  /** 短按 flowchart / 长按选类型后回调 kind。 */
  onMermaidKindSelected: (kind: string) => void = (_kind: string) => {
  }

  private static readonly BAR_HEIGHT: number = 40
  private static readonly SLOT_SIZE: number = 40
  private static readonly BAR_PADDING_H: number = 0
  private static readonly ICON_COUNT: number = 11
  private static readonly ICON_VISUAL_SIZE: number = EditorQuickActionBar.SLOT_SIZE * 0.7
  /** 加粗/斜体/删除线图标视觉缩小 15%，点击区域仍用 ICON_VISUAL_SIZE 计算。 */
  private static readonly ICON_VISUAL_SIZE_COMPACT: number =
    EditorQuickActionBar.ICON_VISUAL_SIZE * 0.85
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

  private needsHorizontalScroll(hPad: number): boolean {
    const usable = this.barWidthVp - EditorQuickActionBar.BAR_PADDING_H * 2
    return EditorQuickActionBar.ICON_COUNT * this.cellWidth(hPad) > usable
  }

  private cellWidth(hPad: number): number {
    return EditorQuickActionBar.ICON_VISUAL_SIZE + hPad * 2
  }

  private showMermaidKindMenu(): void {
    const buttons: MermaidDialogButton[] = []
    for (let i = 0; i < MermaidTemplates.KINDS.length; i++) {
      const kind: string = MermaidTemplates.KINDS[i]
      const label: string = MermaidTemplates.labelFor(kind)
      const btn: MermaidDialogButton = {
        text: EditorUiStrings.loc(label, label, label),
        color: '#007AFF'
      }
      buttons.push(btn)
    }
    const dialogOpts: promptAction.ShowDialogOptions = {
      title: EditorUiStrings.loc('插入 Mermaid', 'Insert Mermaid', 'Mermaidを挿入'),
      message: EditorUiStrings.loc('选择图表类型', 'Choose diagram type', '図の種類を選択'),
      buttons: buttons
    }
    try {
      promptAction.showDialog(dialogOpts, (error, data) => {
        if (error || data === undefined) {
          return
        }
        const index = data.index as number
        if (index >= 0 && index < MermaidTemplates.KINDS.length) {
          this.onMermaidKindSelected(MermaidTemplates.KINDS[index])
        }
      })
    } catch (_) {
      this.onMermaidKindSelected(MermaidTemplates.DEFAULT_KIND)
    }
  }

  @Builder
  private buildSymbolIcon(
    action: EditorQuickActionType,
    symbol: Resource,
    hPad: number,
    iconColor?: ResourceColor
  ) {
    Row() {
      SymbolGlyph(symbol)
        .fontSize(20)
        .fontColor([iconColor ?? $r('app.color.primary_text')])
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
      if (action === 'mermaid') {
        this.onMermaidKindSelected(MermaidTemplates.DEFAULT_KIND)
        return
      }
      this.onAction(action)
    })
    .gesture(
      LongPressGesture({ repeat: false })
        .onAction(() => {
          if (action === 'mermaid') {
            this.showMermaidKindMenu()
          }
        })
    )
  }

  @Builder
  private buildIcon(
    action: EditorQuickActionType,
    media: Resource,
    hPad: number,
    imageFill?: ResourceColor,
    visualSize: number = EditorQuickActionBar.ICON_VISUAL_SIZE
  ) {
    Row() {
      Image(media)
        .width(visualSize)
        .height(visualSize)
        .objectFit(ImageFit.Contain)
        .fillColor(imageFill ?? Color.Transparent)
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
      if (action === 'mermaid') {
        this.onMermaidKindSelected(MermaidTemplates.DEFAULT_KIND)
        return
      }
      this.onAction(action)
    })
  }

  @Builder
  private buildActionRow(hPad: number, justify: FlexAlign) {
    Row() {
      this.buildSymbolIcon('link', $r('sys.symbol.link'), hPad)
      this.buildSymbolIcon('image', $r('sys.symbol.picture'), hPad, $r('app.color.primary_text'))
      this.buildSymbolIcon('checkbox', $r('sys.symbol.smallcircle_filled_circle'), hPad)
      this.buildSymbolIcon('quote', $r('sys.symbol.quote'), hPad)
      this.buildSymbolIcon('hr', $r('sys.symbol.minus'), hPad)
      this.buildSymbolIcon('orderedList', $r('sys.symbol.list_number'), hPad)
      this.buildSymbolIcon('bulletList', $r('sys.symbol.list_bullet'), hPad)
      this.buildSymbolIcon('bold', $r('sys.symbol.bold'), hPad)
      this.buildSymbolIcon('strike', $r('sys.symbol.strikethrough'), hPad)
      this.buildSymbolIcon('italic', $r('sys.symbol.italic'), hPad)
      this.buildSymbolIcon('mermaid', $r('sys.symbol.square_grid_2x2'), hPad)
    }
    .height(EditorQuickActionBar.BAR_HEIGHT)
    .justifyContent(justify)
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('app.color.surface_muted'))
    .focusable(false)
  }

  @Builder
  private buildScrollableBar(hPad: number) {
    Scroll() {
      Row() {
        this.buildSymbolIcon('link', $r('sys.symbol.link'), hPad)
        this.buildSymbolIcon('image', $r('sys.symbol.picture'), hPad, $r('app.color.primary_text'))
        this.buildSymbolIcon('checkbox', $r('sys.symbol.smallcircle_filled_circle'), hPad)
        this.buildSymbolIcon('quote', $r('sys.symbol.quote'), hPad)
        this.buildSymbolIcon('hr', $r('sys.symbol.minus'), hPad)
        this.buildSymbolIcon('orderedList', $r('sys.symbol.list_number'), hPad)
        this.buildSymbolIcon('bulletList', $r('sys.symbol.list_bullet'), hPad)
        this.buildSymbolIcon('bold', $r('sys.symbol.bold'), hPad)
        this.buildSymbolIcon('strike', $r('sys.symbol.strikethrough'), hPad)
        this.buildSymbolIcon('italic', $r('sys.symbol.italic'), hPad)
        this.buildSymbolIcon('mermaid', $r('sys.symbol.square_grid_2x2'), hPad)
      }
      .height(EditorQuickActionBar.BAR_HEIGHT)
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r('app.color.surface_muted'))
      .focusable(false)
    }
    .width('100%')
    .height(EditorQuickActionBar.BAR_HEIGHT)
    .padding({ left: EditorQuickActionBar.BAR_PADDING_H, right: EditorQuickActionBar.BAR_PADDING_H })
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.None)
    .align(Alignment.Start)
    .focusable(false)
  }

  @Builder
  private buildBar(hPad: number) {
    if (this.needsHorizontalScroll(hPad)) {
      this.buildScrollableBar(hPad)
    } else {
      Row() {
        this.buildActionRow(hPad, FlexAlign.SpaceBetween)
      }
      .width('100%')
      .padding({ left: EditorQuickActionBar.BAR_PADDING_H, right: EditorQuickActionBar.BAR_PADDING_H })
    }
  }

  build() {
    this.buildBar(this.resolveHorizontalPadding())
  }
}
