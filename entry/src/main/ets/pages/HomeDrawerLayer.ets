import { DrawerModel } from '../common/model/DrawerModel'
import type { FolderSidebarRow, HomeSidebarFilterMode } from '../common/utils/NoteFolderTree'

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
  @Prop filterMode: HomeSidebarFilterMode = 'tag'
  @Prop folderModeEnabled: boolean = false
  @Prop folderRows: FolderSidebarRow[] = []

  /** 菜单按钮触发切换抽屉：每次递增即可。 */
  @Prop @Watch('handleToggleNonceChanged') drawerToggleNonce: number = 0
  /** 选择标签或跳转前关闭抽屉：每次递增即可。 */
  @Prop @Watch('handleCloseNonceChanged') drawerCloseNonce: number = 0

  /** 选中某一筛选标签。 */
  onTagSelected: (tag: string) => void = (_tag: string) => {
  }
  onFolderSelected: (folderId: string) => void = (_folderId: string) => {
  }
  onFilterModeChanged: (mode: HomeSidebarFilterMode) => void = (_mode: HomeSidebarFilterMode) => {
  }
  onOpenTagManage: () => void = () => {
  }
  onOpenFolderManage: () => void = () => {
  }
  onOpenRecycleBin: () => void = () => {
  }
  onOpenSettings: () => void = () => {
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
  private buildModeSegment(label: string, mode: HomeSidebarFilterMode) {
    Text(label)
      .fontSize(13)
      .fontWeight(this.filterMode === mode ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.filterMode === mode ? $r('app.color.accent') : $r('app.color.secondary_text'))
      .layoutWeight(1)
      .textAlign(TextAlign.Center)
      .padding({ top: 8, bottom: 8 })
      .backgroundColor(this.filterMode === mode ? $r('app.color.surface_muted') : Color.Transparent)
      .borderRadius(10)
      .onClick(() => {
        if (this.filterMode !== mode) {
          this.onFilterModeChanged(mode)
        }
      })
  }

  @Builder
  private buildFilterModeSwitcher() {
    Row({ space: 4 }) {
      this.buildModeSegment('标签模式', 'tag')
      this.buildModeSegment('文件夹模式', 'folder')
    }
    .width('100%')
    .padding(4)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(12)
    .border({ width: 1, color: $r('app.color.card_border') })
  }

  @Builder
  private buildDrawerFilterItem(label: string, tag: string, showFolderIcon: boolean = false) {
    Row({ space: showFolderIcon ? 10 : 0 }) {
      if (showFolderIcon) {
        Image(this.selectedTag === tag ? $r('app.media.ic_folder_open') : $r('app.media.ic_folder_closed'))
          .width(20)
          .height(20)
          .objectFit(ImageFit.Contain)
      }
      Text(label)
        .fontSize($r('app.float.body_font_size'))
        .fontWeight(this.selectedTag === tag ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.selectedTag === tag ? $r('app.color.accent') : $r('app.color.primary_text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .padding({
      left: showFolderIcon ? 12 : 18,
      right: 14,
      top: 12.8,
      bottom: 12.8
    })
    .backgroundColor(this.selectedTag === tag ? $r('app.color.surface_muted') : Color.Transparent)
    .borderRadius(12)
    .onClick(() => {
      this.onTagSelected(tag)
    })
  }

  @Builder
  private buildDrawerFolderItem(row: FolderSidebarRow) {
    Row({ space: 10 }) {
      Image(row.isExpanded ? $r('app.media.ic_folder_open') : $r('app.media.ic_folder_closed'))
        .width(20)
        .height(20)
        .objectFit(ImageFit.Contain)
      Text(row.title)
        .fontSize($r('app.float.body_font_size'))
        .fontWeight(this.selectedTag === row.noteId ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.selectedTag === row.noteId ? $r('app.color.accent') : $r('app.color.primary_text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .padding({
      left: 12 + row.depth * 14,
      right: 14,
      top: 12.8,
      bottom: 12.8
    })
    .backgroundColor(this.selectedTag === row.noteId ? $r('app.color.surface_muted') : Color.Transparent)
    .borderRadius(12)
    .onClick(() => {
      this.onFolderSelected(row.noteId)
    })
  }

  @Builder
  private buildDrawerSidebar() {
    Column({ space: 6 }) {
      if (this.folderModeEnabled) {
        this.buildFilterModeSwitcher()
      } else {
        Text('筛选标签')
          .fontSize(13)
          .fontColor($r('app.color.tertiary_text'))
          .margin({ top: 8, bottom: 8, left: 6 })
      }

      if (this.folderModeEnabled && this.filterMode === 'folder') {
        this.buildDrawerFilterItem('根目录', this.allNotesTag, true)
      } else {
        this.buildDrawerFilterItem('全部笔记', this.allNotesTag)
      }

      if (!this.folderModeEnabled) {
        ForEach(this.tags, (tag: string) => {
          this.buildDrawerFilterItem(tag, tag)
        }, (tag: string) => `tag_${tag}`)
      } else if (this.filterMode === 'folder') {
        ForEach(this.folderRows, (row: FolderSidebarRow) => {
          this.buildDrawerFolderItem(row)
        }, (row: FolderSidebarRow) => `folder_${row.noteId}_${row.depth}_${row.isExpanded}`)
      }

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
        Text(
          this.folderModeEnabled && this.filterMode === 'folder'
            ? $r('app.string.folder_manage')
            : $r('app.string.tag_manage')
        )
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
        if (this.folderModeEnabled && this.filterMode === 'folder') {
          this.onOpenFolderManage()
        } else {
          this.onOpenTagManage()
        }
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
        Text($r('app.string.settings'))
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
        this.onOpenSettings()
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
