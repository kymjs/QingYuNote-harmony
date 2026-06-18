import { SymbolGlyphModifier } from '@kit.ArkUI'
import { HomeTabBarMaterial } from '../common/utils/HomeTabBarMaterial'
import { APP_LOCALE_REVISION_KEY, LocaleService } from '../services/LocaleService'
import {
  HdsTabs,
  HdsTabsController,
  type SystemMaterialParams
} from '@kit.UIDesignKit'

/** 首页底部三按钮 TabBar：更多 / 待办 / 笔记（HdsTabs 悬浮 + 沉浸光感，低版本毛玻璃降级）。 */

const TAB_BAR_HEIGHT_VP = 45

/** 与 HdsTabs barFloatingStyle.barOpacity 对齐。 */
const TAB_BAR_OPACITY = 0.9

/** 与 Index 原底部 padding 对齐，由外层 Column padding 承载。 */
const TAB_BAR_BOTTOM_MARGIN_VP = 50

/** 与 Flutter HomeLiquidGlassTabBar 一致：屏宽 68%。 */
const TAB_BAR_WIDTH_FACTOR = 0.68

const TAB_BAR_HORIZONTAL_PADDING_VP = 4

@Component
export struct HomeLiquidGlassTabBar {
  @StorageProp(APP_LOCALE_REVISION_KEY) localeRevision: number = 0
  onMore: () => void = (): void => {}
  onTodo: () => void = (): void => {}
  onNote: () => void = (): void => {}

  private tabsController: HdsTabsController = new HdsTabsController()
  private systemMaterial: SystemMaterialParams | undefined = undefined
  @State private tabBarWidthVp: number = 198

  aboutToAppear(): void {
    this.systemMaterial = HomeTabBarMaterial.resolveAdaptiveMaterial()
  }

  private buildTabSymbol(icon: Resource): TabBarSymbol {
    const accentColor = $r('app.color.accent')
    const glyph = new SymbolGlyphModifier(icon)
      .fontSize(20)
      .fontColor([accentColor])
    const tabSymbol: TabBarSymbol = {
      normal: glyph,
      selected: glyph
    }
    return tabSymbol
  }

  private widthFactor(): number {
    return TAB_BAR_WIDTH_FACTOR
  }

  private horizontalPaddingVp(): number {
    return TAB_BAR_HORIZONTAL_PADDING_VP
  }

  private buildTabBarStyle(icon: Resource, label: string): BottomTabBarStyle {
    const pad = this.horizontalPaddingVp()
    return new BottomTabBarStyle(this.buildTabSymbol(icon), label)
      .layoutMode(LayoutMode.HORIZONTAL)
      .padding({ left: pad, right: pad, top: 0, bottom: 0 })
      .labelStyle({
        font: { size: 11, weight: FontWeight.Medium },
        unselectedColor: $r('app.color.primary_text'),
        selectedColor: $r('app.color.primary_text')
      })
  }

  private updateHostWidth(width: Length): void {
    const widthVp = typeof width === 'number' ? width : Number.parseFloat(`${width}`)
    if (!Number.isFinite(widthVp) || widthVp <= 0) {
      return
    }
    this.tabBarWidthVp = Math.round(widthVp * this.widthFactor())
  }

  private dispatchTabAction(index: number): void {
    if (index === 0) {
      this.onMore()
    } else if (index === 1) {
      this.onTodo()
    } else if (index === 2) {
      this.onNote()
    }
  }

  @Builder
  private buildPassthroughTabPane() {
    Column()
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private buildTabItem(label: string, icon: Resource, onTap: () => void): void {
    Row({ space: 4 }) {
      SymbolGlyph(icon)
        .fontSize(20)
        .fontColor([$r('app.color.accent')])
      Text(label)
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary_text'))
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .onClick(onTap)
  }

  @Builder
  private buildTabItems() {
    this.buildTabItem(LocaleService.loc('更多', 'More'), $r('sys.symbol.square_grid_2x2'), this.onMore)
    this.buildTabItem(LocaleService.loc('待办', 'Todo'), $r('sys.symbol.list_bullet'), this.onTodo)
    this.buildTabItem(LocaleService.loc('笔记', 'Notes'), $r('sys.symbol.square_and_pencil'), this.onNote)
  }

  @Builder
  private buildImmersiveHdsTabs() {
    HdsTabs({ controller: this.tabsController, index: 0 }) {
      TabContent() {
        this.buildPassthroughTabPane()
      }
      .tabBar(this.buildTabBarStyle($r('sys.symbol.square_grid_2x2'), LocaleService.loc('更多', 'More')))

      TabContent() {
        this.buildPassthroughTabPane()
      }
      .tabBar(this.buildTabBarStyle($r('sys.symbol.list_bullet'), LocaleService.loc('待办', 'Todo')))

      TabContent() {
        this.buildPassthroughTabPane()
      }
      .tabBar(this.buildTabBarStyle($r('sys.symbol.square_and_pencil'), LocaleService.loc('笔记', 'Notes')))
    }
    .width(this.tabBarWidthVp)
    .height(TAB_BAR_HEIGHT_VP)
    .hitTestBehavior(HitTestMode.Default)
    .barOverlap(true)
    .barPosition(BarPosition.End)
    .vertical(false)
    .scrollable(false)
    .animationDuration(0)
    .barMode(BarMode.Fixed)
    .barHeight(TAB_BAR_HEIGHT_VP)
    .barFloatingStyle({
      barWidth: {
        smallWidth: this.tabBarWidthVp,
        mediumWidth: this.tabBarWidthVp,
        largeWidth: this.tabBarWidthVp
      },
      barBottomMargin: 0,
      barOpacity: TAB_BAR_OPACITY,
      systemMaterialEffect: this.systemMaterial
    })
    .onTabBarClick((index: number) => {
      this.dispatchTabAction(index)
    })
    .onContentWillChange((_current: number, _coming: number) => {
      return false
    })
  }

  @Builder
  private buildImmersiveHost() {
    Column() {
      this.buildImmersiveHdsTabs()
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.End)
    .alignItems(HorizontalAlign.Center)
    .padding({ bottom: TAB_BAR_BOTTOM_MARGIN_VP })
    .hitTestBehavior(HitTestMode.None)
    .onAreaChange((_old: Area, area: Area) => {
      this.updateHostWidth(area.width as Length)
    })
  }

  @Builder
  private buildFallbackGlassBar() {
    Row() {
      this.buildTabItems()
    }
    .width(this.tabBarWidthVp)
    .height(TAB_BAR_HEIGHT_VP)
    .padding({ left: this.horizontalPaddingVp(), right: this.horizontalPaddingVp() })
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .backgroundColor($r('app.color.tab_bar_immersive_tint'))
    .opacity(TAB_BAR_OPACITY)
    .borderRadius(TAB_BAR_HEIGHT_VP / 2)
    .border({ width: 1, color: $r('app.color.tab_bar_immersive_border') })
    .shadow({
      radius: 20,
      color: $r('app.color.shadow_color'),
      offsetX: 0,
      offsetY: 6
    })
  }

  build() {
    if (this.systemMaterial !== undefined) {
      this.buildImmersiveHost()
    } else {
      Column() {
        this.buildFallbackGlassBar()
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.End)
      .alignItems(HorizontalAlign.Center)
      .padding({ bottom: TAB_BAR_BOTTOM_MARGIN_VP })
      .hitTestBehavior(HitTestMode.None)
      .onAreaChange((_old: Area, area: Area) => {
        this.updateHostWidth(area.width as Length)
      })
    }
  }
}
