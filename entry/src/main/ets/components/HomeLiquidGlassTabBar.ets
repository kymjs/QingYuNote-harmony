import { SymbolGlyphModifier } from '@kit.ArkUI'
import { HomeTabBarMaterial } from '../common/utils/HomeTabBarMaterial'
import { APP_LOCALE_REVISION_KEY, LocaleService } from '../services/LocaleService'
import {
  HdsTabs,
  HdsTabsController,
  type SystemMaterialParams
} from '@kit.UIDesignKit'

/** 首页底部三按钮动作坞：链接 / 语音 / 笔记（HdsTabs 悬浮 + 沉浸光感，低版本毛玻璃降级）。
 * 语义为瞬时动作，不是导航 Tab（选中/未选同色）。
 * 现挂载在新版首页 MainShell 的「首页」Tab 内，悬浮于底部 5 Tab 导航栏上方
 * TAB_BAR_BOTTOM_MARGIN_VP 处。 */

const TAB_BAR_HEIGHT_VP = 45

/** 与 HdsTabs barFloatingStyle.barOpacity 对齐。 */
const TAB_BAR_OPACITY = 0.9

/** 距容器底边 50vp；挂在首页 Tab 内时容器底边即底部导航栏顶边。 */
const TAB_BAR_BOTTOM_MARGIN_VP = 50

/** 与 Flutter HomeLiquidGlassTabBar 一致：屏宽 68%。 */
const TAB_BAR_WIDTH_FACTOR = 0.68

const TAB_BAR_HORIZONTAL_PADDING_VP = 4

/** 列表等内容需躲开整块坞时的垂直占位（含安全区）。 */
export function homeTabBarOccupiedHeight(bottomInsetVp: number = 0): number {
  return TAB_BAR_HEIGHT_VP + TAB_BAR_BOTTOM_MARGIN_VP + bottomInsetVp
}

@Component
export struct HomeLiquidGlassTabBar {
  @StorageProp(APP_LOCALE_REVISION_KEY) localeRevision: number = 0
  onLink: () => void = (): void => {}
  onVoice: () => void = (): void => {}
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
      this.onLink()
    } else if (index === 1) {
      this.onVoice()
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
    this.buildTabItem(LocaleService.loc('链接', 'Link', 'リンク'), $r('sys.symbol.link'), this.onLink)
    this.buildTabItem(LocaleService.loc('语音', 'Voice'), $r('sys.symbol.mic'), this.onVoice)
    this.buildTabItem(LocaleService.loc('笔记', 'Notes'), $r('sys.symbol.square_and_pencil'), this.onNote)
  }

  @Builder
  private buildImmersiveHdsTabs() {
    HdsTabs({ controller: this.tabsController, index: 0 }) {
      TabContent() {
        this.buildPassthroughTabPane()
      }
      .tabBar(this.buildTabBarStyle($r('sys.symbol.link'), LocaleService.loc('链接', 'Link', 'リンク')))

      TabContent() {
        this.buildPassthroughTabPane()
      }
      .tabBar(this.buildTabBarStyle($r('sys.symbol.mic'), LocaleService.loc('语音', 'Voice')))

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
