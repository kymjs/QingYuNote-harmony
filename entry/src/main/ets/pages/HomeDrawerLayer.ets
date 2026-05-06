import { DrawerModel } from '../common/model/DrawerModel'

const DRAWER_WIDTH = 248
/** 收起时多向左移若干 vp，避免子像素/舍入导致面板右缘残留在可视区内。 */
const DRAWER_OFFSCREEN_PAD = 20
const DRAWER_SPAN = DRAWER_WIDTH + DRAWER_OFFSCREEN_PAD
/** 松手吸附动画时长（抽屉已由手指实时拖动，此处仅收尾过渡）。 */
const DRAWER_SNAP_MS = 220

@Component
export struct HomeDrawerLayer {
  /** 与 Index 侧 `@Provide('drawerModel')` 配对，勿在调用处写 `$drawerModel`。 */
  @Consume('drawerModel') drawerModel: DrawerModel

  /** 侧栏标签列表（与首页标签合并结果一致）。 */
  @Prop tags: string[] = []
  /** 当前选中的筛选标签 token。 */
  @Prop selectedTag: string = ''
  /** 表示「全部笔记」的 token，由调用方定义。 */
  @Prop allNotesTag: string = '__ALL_NOTES__'

  /** 菜单按钮触发切换抽屉：每次递增即可。 */
  @Prop @Watch('handleToggleNonceChanged') drawerToggleNonce: number = 0
  /** 选择标签或跳转前关闭抽屉：每次递增即可。 */
  @Prop @Watch('handleCloseNonceChanged') drawerCloseNonce: number = 0

  /** 选中某一筛选标签。 */
  onTagSelected: (tag: string) => void = (_tag: string) => {
  }
  onOpenTagManage: () => void = () => {
  }
  onOpenRecycleBin: () => void = () => {
  }
  onOpenAbout: () => void = () => {
  }

  private handleToggleNonceChanged(): void {
    if (this.drawerToggleNonce === 0) {
      return
    }
    this.toggleDrawer()
  }

  private handleCloseNonceChanged(): void {
    this.closeDrawer()
  }

  private closeDrawer(): void {
    if (this.drawerModel.progress <= 0) {
      return
    }
    this.animateDrawerSnapTo(0)
  }

  private toggleDrawer(): void {
    this.animateDrawerSnapTo(this.drawerModel.progress < 0.5 ? 1 : 0)
  }

  private animateDrawerSnapTo(targetOpen: number): void {
    const target = targetOpen >= 0.5 ? 1 : 0
    if (Math.abs(this.drawerModel.progress - target) < 0.001) {
      return
    }
    this.getUIContext().animateTo({
      duration: DRAWER_SNAP_MS,
      curve: Curve.EaseOut
    }, () => {
      this.drawerModel.progress = target
    })
  }

  @Builder
  private buildDrawerFilterItem(label: string, tag: string) {
    Row() {
      Text(label)
        .fontSize($r('app.float.body_font_size'))
        .fontWeight(this.selectedTag === tag ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.selectedTag === tag ? $r('app.color.accent') : $r('app.color.primary_text'))
    }
    .width('100%')
    .padding({ left: 18, right: 14, top: 12.8, bottom: 12.8 })
    .backgroundColor(this.selectedTag === tag ? $r('app.color.surface_muted') : Color.Transparent)
    .borderRadius(12)
    .onClick(() => {
      this.onTagSelected(tag)
    })
  }

  @Builder
  private buildDrawerSidebar() {
    Column({ space: 6 }) {
      Text('筛选标签')
        .fontSize(13)
        .fontColor($r('app.color.tertiary_text'))
        .margin({ top: 8, bottom: 8, left: 6 })

      this.buildDrawerFilterItem('全部笔记', this.allNotesTag)

      ForEach(this.tags, (tag: string) => {
        this.buildDrawerFilterItem(tag, tag)
      }, (tag: string) => `tag_${tag}`)

      Blank()
        .layoutWeight(1)
        .width('100%')
        .onClick(() => {
        })

      Divider()
        .strokeWidth(1)
        .color($r('app.color.divider'))
        .margin({ top: 8, bottom: 4 })

      Row() {
        Text($r('app.string.tag_manage'))
          .fontSize($r('app.float.body_font_size'))
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
        Text('›')
          .fontSize(22)
          .fontColor($r('app.color.tertiary_text'))
      }
      .width('100%')
      .padding({ left: 18, right: 14, top: 8, bottom: 8 })
      .onClick(() => {
        this.onOpenTagManage()
      })

      Divider()
        .strokeWidth(1)
        .color($r('app.color.divider'))

      Row() {
        Text($r('app.string.recycle_bin_title'))
          .fontSize($r('app.float.body_font_size'))
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
        Text('›')
          .fontSize(22)
          .fontColor($r('app.color.tertiary_text'))
      }
      .width('100%')
      .padding({ left: 18, right: 14, top: 8, bottom: 8 })
      .onClick(() => {
        this.onOpenRecycleBin()
      })

      Divider()
        .strokeWidth(1)
        .color($r('app.color.divider'))

      Row() {
        Text($r('app.string.about_title'))
          .fontSize($r('app.float.body_font_size'))
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
        Text('›')
          .fontSize(22)
          .fontColor($r('app.color.tertiary_text'))
      }
      .width('100%')
      .padding({ left: 18, right: 14, top: 8, bottom: 8 })
      .onClick(() => {
        this.onOpenAbout()
      })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 14, right: 14, top: 20, bottom: 18 })
    .backgroundColor($r('app.color.card_background'))
  }

  build() {
    Stack() {
      if (this.drawerModel.progress > 0.001) {
        Row() {}
          .width('100%')
          .height('100%')
          .backgroundColor('#66000000')
          .opacity(Math.min(0.55, this.drawerModel.progress * 0.55))
          .align(Alignment.TopStart)
          .onClick(() => {
            this.closeDrawer()
          })
      }

      Column() {
        this.buildDrawerSidebar()
      }
      .width(DRAWER_WIDTH)
      .height('100%')
      .align(Alignment.TopStart)
      .translate({ x: DRAWER_SPAN * (this.drawerModel.progress - 1) })
      .shadow({
        radius: 18,
        color: $r('app.color.shadow_color'),
        offsetX: 2,
        offsetY: 0
      })
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.TopStart)
    // 抽屉关闭时须穿透命中，否则主列表无法滚动、工具栏无法点击；打开时用 Default 拦截空白区域，避免点击穿透到笔记列表。
    .hitTestBehavior(this.drawerModel.progress > 0.001 ? HitTestMode.Default : HitTestMode.Transparent)
  }
}
