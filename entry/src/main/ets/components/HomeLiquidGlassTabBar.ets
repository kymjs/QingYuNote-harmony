import { Logger } from '../common/utils/Logger'

const HOME_TAB_BAR_LOG_TAG = 'HomeTabBar'

/** 首页底部三按钮 TabBar：更多 / 图谱 / 笔记（液态玻璃风格）。 */

const TAB_BAR_HEIGHT_VP = 45

const TAB_BAR_WIDTH_PERCENT = '55%'

@Component
export struct HomeLiquidGlassTabBar {
  onMore: () => void = (): void => {}
  onGraph: () => void = (): void => {}
  onNote: () => void = (): void => {}

  @Builder
  private buildTabItem(label: string, icon: Resource, emphasized: boolean, onTap: () => void): void {
    Row({ space: 4 }) {
      SymbolGlyph(icon)
        .fontSize(20)
        .fontColor( [$r('app.color.accent')])
      Text(label)
        .fontSize(11)
        .fontWeight(FontWeight.Medium )
        .fontColor($r('app.color.primary_text'))
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .onClick(onTap)
  }

  build() {
    Row() {
      this.buildTabItem('更多', $r('sys.symbol.square_grid_2x2'), false, this.onMore)
      this.buildTabItem('图谱', $r('sys.symbol.shareplay'), false, this.onGraph)
      this.buildTabItem('笔记', $r('sys.symbol.square_and_pencil'), true, this.onNote)
    }
    .width(TAB_BAR_WIDTH_PERCENT)
    .height(TAB_BAR_HEIGHT_VP)
    .padding({ left: 10, right: 10 })
    .backgroundBlurStyle(BlurStyle.Thin)
    .backgroundColor('#6BFFFFFF')
    .borderRadius(TAB_BAR_HEIGHT_VP / 2)
    .border({ width: 1, color: '#0F000000' })
    .shadow({
      radius: 20,
      color: $r('app.color.shadow_color'),
      offsetX: 0,
      offsetY: 6
    })
    .onAppear(() => {
      Logger.info(
        HOME_TAB_BAR_LOG_TAG,
        `bar appear size=${TAB_BAR_WIDTH_PERCENT}x${TAB_BAR_HEIGHT_VP}vp bottomPad=50`
      )
    })
    .onAreaChange((_old: Area, area: Area) => {
      Logger.info(
        HOME_TAB_BAR_LOG_TAG,
        `bar area w=${area.width} h=${area.height} ` +
          `global=(${area.globalPosition.x},${area.globalPosition.y})`
      )
    })
  }
}
