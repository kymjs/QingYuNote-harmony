import { usePcStyleLayoutWithSize } from '../../common/utils/DesktopLayout'
import { navigateToTodoEditor } from '../../common/utils/TodoEditorNavigation'
import { LocaleService } from '../../services/LocaleService'
import { NoteRepository } from '../../services/NoteRepository'
import { showCalendarAddScheduleDialog } from '../../dialogs/CalendarAddScheduleDialog'
import { CalendarProjector } from './calendar/CalendarProjector'
import type { CalendarItemKind } from './calendar/CalendarModels'
import { Logger } from '../../common/utils/Logger'
import {
  TodoItemRow,
  TodoListKind,
  TodoStatus,
  TodoTabLogic
} from './todo/TodoTabModels'

const PAGE_PAD = 16
const ROW_HEIGHT = 64
const ACCENT = '#0DAA4A'
const GREEN_BG = '#1A0DAA4A'
const GREEN_FG = '#0DAA4A'
const GRAY_BG = '#146B7280'
const GRAY_FG = '#6B7280'
const BLUE_BG = '#143B82F6'
const BLUE_FG = '#3B82F6'

// 列表左侧图标颜色。
// 已完成/灰色 = 待办事项完成态、日程结束态共用；与文字 disabled_text (#9CA3AF) 对齐。
const ICON_GRAY = '#9CA3AF'
// 待办事项：进行中按优先级染色；未设置优先级（=0）默认走低优先级绿色。
const ICON_TODO_LOW = '#0DAA4A'
const ICON_TODO_MEDIUM = '#3B82F6'
const ICON_TODO_HIGH = '#EAB308'
const ICON_TODO_URGENT = '#DC2626'
// 待办日程：仅二态，已完成灰、否则黄。
const ICON_SCHEDULE_DONE = '#9CA3AF'
const ICON_SCHEDULE_PENDING = '#EAB308'
const ICON_SIZE = 22

class PillStyle {
  bg: string = ''
  fg: string = ''
  label: string = ''
}

@Component
export struct DashboardTodoTab {
  @Prop @Watch('onVisibleChanged') visible: boolean = false
  /** 从编辑页返回时由 MainShell 递增，强制静默刷新（与 DashboardNotesTab 一致）。 */
  @Prop @Watch('onShellRefreshNonce') shellRefreshNonce: number = 0
  @StorageLink('appLocaleRevision') localeRevision: number = 0
  @StorageLink('appNotesRevision') @Watch('onNotesRevisionChanged')
  notesRevision: number = 0
  /**
   * 兜底刷新信号：MainShell.onPageShow 也会同步写入 AppStorage，
   * 避免 `@Watch on @Prop` 在某些 ArkUI 版本下不触发的 corner case。
   * 只要值变化就强制 reload。
   */
  @StorageLink('appShellRefreshNonce') @Watch('onAppShellRefresh')
  appShellRefreshNonce: number = 0
  @State allRows: TodoItemRow[] = []
  @State loading: boolean = true
  @State refreshing: boolean = false
  @State search: string = ''
  @State filter: TodoListKind = 'all'
  @State page: number = 0
  @State pageSize: number = 20
  @State selected: string[] = []
  // 多选模式：长按列表项进入，进入后隐藏图标、展示勾选框与底部批量操作栏。
  @State selectionMode: boolean = false
  @State pcLayout: boolean = false
  @State pageWidth: number = 360
  @State pageHeight: number = 780
  @State uiNonce: number = 0
  private initialLoaded: boolean = false
  // 并发 reload 抢占哨兵：每次 reload() 自增，
  // 只有 generation === reloadGeneration 的那次 reload 才允许写回 UI。
  // 这样下拉刷新期间即便 onNotesRevisionChanged / onVisibleChanged / bootstrap
  // 又触发了一次 reload，两份并发的 listNotes() 不会互相把 loading/UI 状态
  // 翻来覆去，「加载中」由最后启动的那次 reload 决定何时结束。
  private reloadGeneration: number = 0

  aboutToAppear(): void {
    Logger.info('DashHomeLoad', `[TodoTab] aboutToAppear visible=${this.visible} loading=${this.loading}`)
    void this.bootstrap()
  }

  onVisibleChanged(): void {
    Logger.info('DashHomeLoad',
      `[TodoTab] onVisibleChanged visible=${this.visible} loading=${this.loading} allRows=${this.allRows.length}`)
    if (this.visible) {
      void this.reload()
    }
  }

  onNotesRevisionChanged(): void {
    Logger.info('DashHomeLoad',
      `[TodoTab] onNotesRevisionChanged notesRevision=${this.notesRevision} visible=${this.visible} loading=${this.loading}`)
    if (this.visible) {
      void this.reload()
    }
  }

  onShellRefreshNonce(): void {
    if (this.initialLoaded && this.shellRefreshNonce > 0) {
      void this.reload()
    }
  }

  onAppShellRefresh(): void {
    if (this.initialLoaded && this.appShellRefreshNonce > 0) {
      void this.reload()
    }
  }

  private async bootstrap(): Promise<void> {
    Logger.info('DashHomeLoad', '[TodoTab] bootstrap start')
    void this.reload()
    this.initialLoaded = true
  }

  private async pullToRefresh(): Promise<void> {
    Logger.info('DashHomeLoad',
      `[TodoTab] pullToRefresh enter refreshing=${this.refreshing} loading=${this.loading}`)
    // 注意：不能在这里再用 `if (this.refreshing) return` 早退。
    // Refresh({ refreshing: $$this.refreshing }) 是双向绑定，用户下拉时 Refresh 组件会
    // 在 onRefreshing 回调触发**之前**就把 this.refreshing 翻成 true。
    // 如果在这里早退，await reload() / this.refreshing = false 都不会执行，
    // 下拉 spinner 就一直挂着、永不消失（之前日志里「refreshing=true loading=false」
    // 但没有 reload ENTER 也没有 finally 就是这个原因）。
    this.refreshing = true
    try {
      // 主动抛弃列表缓存，确保从磁盘重读，不被旧 cachedActiveNotes 顶住。
      NoteRepository.getInstance().discardCachedNoteLists()
      await this.reload()
    } finally {
      Logger.info('DashHomeLoad',
        `[TodoTab] pullToRefresh finally refreshing=false loading=${this.loading}`)
      this.refreshing = false
    }
  }

  private async reload(): Promise<void> {
    // 抢占最新 generation。后续若 generation 已被自增，说明有更新的 reload 接管，
    // 本次 reload 拿到的数据作废，避免晚启动的 reload 完成后又被早启动的旧结果覆盖。
    const generation = ++this.reloadGeneration
    Logger.info('DashHomeLoad',
      `[TodoTab] reload ENTER gen=${generation} loading(before)=${this.loading} allRows=${this.allRows.length}`)
    // 关键：每次进入 reload 都先无条件清掉 loading，避免：
    // 1) 初首次加载过程中 loading=true，下拉刷新直接 discardCachedNoteLists + 再次 reload，
    //    reload 链路过长时 finally 未及时执行导致「加载中」一直转；
    // 2) 并发 reload 中早启动那次被 generation 守卫拦下不写数据，但 finally 触发顺序
    //    不一定按 generation 倒序，UI 状态被翻来覆去。
    // 把「进入即清」+「退出 finally 再清」两层叠加，确保任意一次 reload 完成都会让
    // loading 翻成 false，不会出现「加载中」永不消失。
    this.loading = false
    this.uiNonce += 1
    try {
      await NoteRepository.getInstance().init()
      Logger.info('DashHomeLoad', `[TodoTab] reload gen=${generation} after init`)
      const notes = await NoteRepository.getInstance().listNotes()
      Logger.info('DashHomeLoad',
        `[TodoTab] reload gen=${generation} after listNotes count=${notes.length} sameGen=${generation === this.reloadGeneration}`)
      if (generation === this.reloadGeneration) {
        // 只有当本次 reload 仍是最新一次时，才把数据写回 UI；否则保持更晚的 reload 的结果。
        this.allRows = TodoTabLogic.buildTodoRows(notes)
        // 切换数据后丢弃已选；选中数清零时同步退出多选模式。
        const valid = new Set<string>()
        for (let i = 0; i < this.allRows.length; i++) {
          valid.add(this.allRows[i].noteId)
        }
        this.selected = this.selected.filter((id: string): boolean => valid.has(id))
        if (this.selected.length === 0) {
          this.selectionMode = false
        }
        const filtered = this.currentFiltered()
        if (this.page > 0 && this.page * this.pageSize >= filtered.length) {
          this.page = 0
        }
      }
    } catch (e) {
      Logger.error('DashHomeLoad',
        `[TodoTab] reload gen=${generation} catch ${JSON.stringify(e)}`)
      // 错误时保留已有 allRows（可能是上一次成功加载的有效数据）。
    } finally {
      // 双保险：finally 再清一次，覆盖 reload 进入即清之后的并发覆盖。
      this.loading = false
      this.uiNonce += 1
      Logger.info('DashHomeLoad',
        `[TodoTab] reload gen=${generation} FINALLY loading(after)=${this.loading} allRows=${this.allRows.length}`)
    }
  }

  // 派生：过滤 + 搜索 + 排序
  private currentFiltered(): TodoItemRow[] {
    const byKind = TodoTabLogic.applyKindFilter(this.allRows, this.filter)
    const searched = this.search.trim().length === 0
      ? byKind
      : byKind.filter((r: TodoItemRow): boolean => TodoTabLogic.matchesSearch(r, this.search))
    return TodoTabLogic.sortByStartDesc(searched)
  }

  private currentPaged(): TodoItemRow[] {
    const filtered = this.currentFiltered()
    return TodoTabLogic.paginate(filtered, this.page, this.pageSize)
  }

  private totalPages(total: number): number {
    if (total <= 0 || this.pageSize <= 0) {
      return 0
    }
    return Math.ceil(total / this.pageSize)
  }

  private allSelectedAreTodo(): boolean {
    if (this.selected.length === 0) {
      return false
    }
    for (let i = 0; i < this.allRows.length; i++) {
      if (this.selected.indexOf(this.allRows[i].noteId) >= 0 && !this.allRows[i].isTodo) {
        return false
      }
    }
    return true
  }

  /** 待办日程（kind=schedule）左侧图标颜色：已完成灰、否则黄。 */
  private scheduleIconColor(row: TodoItemRow): string {
    if (row.status === 'completed') {
      return ICON_SCHEDULE_DONE
    }
    return ICON_SCHEDULE_PENDING
  }

  // 行为
  private async onTapRow(row: TodoItemRow): Promise<void> {
    // 多选模式：单击切换选中，不再打开编辑器；最后一项被取消勾选时自动退出多选。
    if (this.selectionMode) {
      const idx = this.selected.indexOf(row.noteId)
      if (idx >= 0) {
        this.selected.splice(idx, 1)
      } else {
        this.selected.push(row.noteId)
      }
      this.uiNonce += 1
      if (this.selected.length === 0) {
        this.selectionMode = false
      }
      return
    }
    const note = row.sourceNote
    if (row.isTodo) {
      await navigateToTodoEditor(this.getUIContext(), { noteId: note.id })
    } else {
      // 已有日程：弹「编辑」弹窗，调 saveDraft 原地更新，而不是再 createNote 一条新的。
      // 否则用户改完保存会多出一条同主题的空壳日程，老的还在。
      const s = note.startTime > 0 ? note.startTime : Date.now()
      const e = note.endTime > 0 ? note.endTime : s + 30 * 60 * 1000
      await showCalendarAddScheduleDialog(this.getUIContext(), {
        startMs: s,
        endMs: e
      })
    }
    await this.reload()
  }

  /** 长按列表项：进入多选模式，并把长按项加入选中集合。 */
  private onLongPressRow(row: TodoItemRow): void {
    if (this.selected.indexOf(row.noteId) < 0) {
      this.selected.push(row.noteId)
    }
    this.selectionMode = true
    this.uiNonce += 1
  }

  /** 退出多选模式并清空选中集合。 */
  private exitSelectionMode(): void {
    this.selectionMode = false
    this.selected = []
    this.uiNonce += 1
  }

  private async onBatchDelete(): Promise<void> {
    if (this.selected.length === 0) {
      return
    }
    const now = Date.now()
    const ids = [...this.selected]
    for (let i = 0; i < ids.length; i++) {
      try {
        await NoteRepository.getInstance().deleteNote(ids[i], now)
      } catch (_) {
        // ignore single delete failure
      }
    }
    this.selected = []
    await this.reload()
  }

  private async onBatchMarkComplete(): Promise<void> {
    if (this.selected.length === 0) {
      return
    }
    const ids = [...this.selected]
    for (let i = 0; i < ids.length; i++) {
      const row = this.allRows.find((r: TodoItemRow): boolean => r.noteId === ids[i])
      if (row === undefined) {
        continue
      }
      const note = row.sourceNote
      if ((note.isTodo ?? 0) !== 2) {
        continue
      }
      try {
        await NoteRepository.getInstance().saveDraft(note.id, {
          todoStatus: 1
        })
      } catch (_) {
        // ignore
      }
    }
    this.selected = []
    await this.reload()
  }

  private toggleSelect(noteId: string): void {
    const idx = this.selected.indexOf(noteId)
    if (idx >= 0) {
      this.selected.splice(idx, 1)
    } else {
      this.selected.push(noteId)
    }
    this.uiNonce += 1
  }

  private hhmm(ms: number): string {
    if (ms <= 0) {
      return '—'
    }
    const d = new Date(ms)
    const h = d.getHours()
    const m = d.getMinutes()
    return `${h < 10 ? '0' : ''}${h}:${m < 10 ? '0' : ''}${m}`
  }

  private pillStyle(status: TodoStatus): PillStyle {
    const s: PillStyle = new PillStyle()
    if (status === 'completed') {
      s.bg = BLUE_BG
      s.fg = BLUE_FG
      s.label = LocaleService.loc('已完成', 'Completed', '完了')
      return s
    }
    if (status === 'inProgress') {
      s.bg = GREEN_BG
      s.fg = GREEN_FG
      s.label = LocaleService.loc('进行中', 'In progress', '進行中')
      return s
    }
    s.bg = GRAY_BG
    s.fg = GRAY_FG
    s.label = LocaleService.loc('未开始', 'Not started', '未開始')
    return s
  }

  private filterLabel(k: TodoListKind): string {
    if (k === 'todo') {
      return LocaleService.loc('待办事项', 'Todo items', 'ToDo')
    }
    if (k === 'schedule') {
      return LocaleService.loc('日程清单', 'Schedules', '予定一覧')
    }
    return LocaleService.loc('全部待办', 'All todos', 'すべてのToDo')
  }

  private chipBg(status: TodoStatus): string {
    if (status === 'completed') {
      return BLUE_BG
    }
    if (status === 'inProgress') {
      return GREEN_BG
    }
    return GRAY_BG
  }

  private chipFg(status: TodoStatus): string {
    if (status === 'completed') {
      return BLUE_FG
    }
    if (status === 'inProgress') {
      return GREEN_FG
    }
    return GRAY_FG
  }

  private kindLabel(kind: CalendarItemKind): string {
    if (kind === 'schedule') {
      return LocaleService.loc('日程', 'Event', '予定')
    }
    return LocaleService.loc('待办', 'Todo', 'ToDo')
  }

  /**
   * 计算当前页数据。注意 pcLayout 在一次 build 内恒定，所以下面只调用一次。
   * 不可见时不计算，避免触发 currentPaged 的额外开销。
   */
  private pagedForBuild(): TodoItemRow[] {
    return this.currentPaged()
  }

  build() {
    // 关键：build() 必须读 this.visible，否则 ArkTS 在 visibility 翻转时不会重渲染。
    // MainShell 用 visibility: Visibility.None 隐藏非激活 tab；ArkTS 会缓存子树，
    // visible 从 false→true 时不重新调用 build()，所以 allRows 更新但 UI 不刷新。
    // 这里用 if (this.visible) 让 build() 显式依赖 visible，强制 ArkTS 重建。
    // 关键：build() 里还必须**直接读一次 this.allRows**，否则 ArkTS 的依赖追踪不会
    // 穿透 pagedForBuild → currentPaged → currentFiltered 这条方法调用链，
    // allRows 在 reload() 里被新数组覆盖时 build() 不会重跑（手动切 tab 修好就是这个原因：
    // 切 tab 销毁旧组件、新组件 build() 从头跑，allRows 自然生效）。
    // 这里用一个隐藏的 Text 读 this.allRows.length，强制 ArkTS 把 allRows 注册为 build() 依赖。
    Stack() {
      // 隐藏依赖标记：读 this.allRows 让 ArkTS 注册 build 依赖。visibility=Hidden 不占布局。
      Text(`${this.allRows.length}`)
        .visibility(Visibility.Hidden)
        .width(0)
        .height(0)
      if (this.visible) {
        Column() {
          this.buildTopBar()
          if (this.pcLayout) {
            this.buildPcTable(this.pagedForBuild())
          } else {
            this.buildMobileList(this.pagedForBuild())
          }
          if (this.selectionMode) {
            this.buildSelectionBar()
          }
          // 未选中时底部留白，不再渲染翻页条 / 共X条 / XX页 等冗余信息。
        }
        .width('100%')
        .height('100%')
        .padding({ left: this.pcLayout ? PAGE_PAD : 0, right: this.pcLayout ? PAGE_PAD : 0 })
      } else {
        // 不可见时只占位，不读 allRows / 触发 List 渲染。
        Column() {
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_old, area) => {
      const w = Number(area.width)
      const h = Number(area.height)
      if (w > 0) {
        this.pageWidth = w
      }
      if (h > 0) {
        this.pageHeight = h
      }
      const next = usePcStyleLayoutWithSize(this.pageWidth, this.pageHeight)
      if (next !== this.pcLayout) {
        this.pcLayout = next
        this.uiNonce += 1
      }
    })
  }

  @Builder
  buildTopBar() {
    if (this.pcLayout) {
      // PC：只保留搜索框 + 筛选下拉，顶部标题 / 新建日程 / 新建待办按钮已移除。
      // 「筛选」文案已删除，搜索框 layoutWeight=1 自动占据释放出的横向空间。
      Row() {
        this.searchInput()
        this.filterDropdown()
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: PAGE_PAD, right: PAGE_PAD, top: 12, bottom: 8 })
    } else {
      // 手机：原顶部 Title + 「新建日程 / 新建待办」按钮一行已删除，只保留搜索 + 筛选。
      // 「筛选」文案已删除，搜索框 layoutWeight=1 自动占据释放出的横向空间。
      Row() {
        this.searchInput()
        this.filterDropdown()
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: PAGE_PAD, right: PAGE_PAD, top: 12, bottom: 8 })
    }
  }

  @Builder
  searchInput() {
    // 与笔记 Tab 顶部搜索框保持一致：圆角矩形灰底（notes_search_fill）、
    // 字号 18 放大镜、字号 15 输入、无边框、有清除按钮。
    Row({ space: 0 }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(18)
        .fontColor([$r('app.color.secondary_text')])
        .padding({ left: 12, right: 6 })
      TextInput({
        placeholder: LocaleService.loc('搜索待办事项', 'Search todos', 'ToDoを検索'),
        text: this.search
      })
        .layoutWeight(1)
        .fontSize(15)
        .fontColor($r('app.color.primary_text'))
        .placeholderColor($r('app.color.secondary_text'))
        .backgroundColor(Color.Transparent)
        .border({ width: 0 })
        .padding({ left: 0, right: 4, top: 0, bottom: 0 })
        .onChange((value: string) => {
          this.search = value
          this.page = 0
          this.uiNonce += 1
        })
      if (this.search.length > 0) {
        Row() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(16)
            .fontColor([$r('app.color.secondary_text')])
        }
        .padding({ left: 6, right: 12, top: 10, bottom: 10 })
        .onClick((): void => {
          this.search = ''
          this.page = 0
          this.uiNonce += 1
        })
      }
    }
    .layoutWeight(1)
    .height(40)
    .padding({ left: 0, right: 0 })
    .alignItems(VerticalAlign.Center)
    .borderRadius(10)
    .backgroundColor($r('app.color.notes_search_fill'))
  }

  @Builder
  filterDropdown() {
    Row() {
      Text(this.filterLabel(this.filter))
        .fontSize(13)
        .fontColor($r('app.color.primary_text'))
      SymbolGlyph($r('sys.symbol.chevron_down'))
        .fontSize(12)
        .fontColor([$r('app.color.secondary_text')])
        .margin({ left: 4 })
    }
    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
    .borderRadius(8)
    .backgroundColor($r('app.color.surface_muted'))
    .bindMenu([
      { value: LocaleService.loc('全部待办', 'All todos', 'すべてのToDo'), action: (): void => {
        this.filter = 'all'
        this.page = 0
        this.uiNonce += 1
      } },
      { value: LocaleService.loc('待办事项', 'Todo items', 'ToDo'), action: (): void => {
        this.filter = 'todo'
        this.page = 0
        this.uiNonce += 1
      } },
      { value: LocaleService.loc('日程清单', 'Schedules', '予定一覧'), action: (): void => {
        this.filter = 'schedule'
        this.page = 0
        this.uiNonce += 1
      } }
    ])
  }

  @Builder
  buildMobileList(paged: TodoItemRow[]) {
    // 与笔记 Tab 同款：Refresh 直接包 List，空态/加载态作为 ListItem 嵌入 List，
    // 避免 Refresh 内嵌套 if/else 时的高度坍缩问题。
    Refresh({ refreshing: $$this.refreshing, offset: 64, friction: 100 }) {
      List() {
        if (this.loading) {
          ListItem() {
            Column() {
              LoadingProgress().width(32).height(32).color($r('app.color.accent'))
              Text(LocaleService.loc('加载中', 'Loading', '読み込み中'))
                .fontSize(13)
                .fontColor($r('app.color.secondary_text'))
                .margin({ top: 8 })
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
          }
        } else if (paged.length === 0) {
          // 空态：图标 + 提示文字居中，颜色与文字保持一致（次级文字灰）。
          ListItem() {
            Column() {
              Image($r('app.media.ic_quick_todo'))
                .width(72)
                .height(72)
                .objectFit(ImageFit.Contain)
                .fillColor($r('app.color.secondary_text'))
                .margin({ bottom: 14 })
              Text(LocaleService.loc('暂无待办', 'No todos yet', 'ToDoなし'))
                .fontSize(15)
                .fontColor($r('app.color.secondary_text'))
            }
            .alignItems(HorizontalAlign.Center)
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
          }
        } else {
          ForEach(paged, (row: TodoItemRow) => {
            ListItem() {
              this.mobileCard(row)
            }
          }, (row: TodoItemRow): string =>
            `mt_${row.noteId}_${row.sourceNote.todoPriority ?? 0}_${row.sourceNote.updatedAt}_${this.uiNonce}`)
        }
      }
      .width('100%')
      .height('100%')
      .divider({ strokeWidth: 1, color: $r('app.color.surface_muted') })
      .padding({ left: PAGE_PAD, right: PAGE_PAD })
      // 关闭 List 缓存：每次数据更新都强制重绘所有 item，绕开 ArkUI List
      // 内部对相同 noteId 的 item 复用导致的 fillColor 不刷新问题。
      .cachedCount(0)
    }
    .layoutWeight(1)
    .width('100%')
    .onRefreshing((): void => {
      void this.pullToRefresh()
    })
  }

  @Builder
  buildPcTable(paged: TodoItemRow[]) {
    Column() {
      this.pcTableHeader()
      // 与笔记 Tab / 移动端同款：Refresh 直接包 List，空态/加载态作为 ListItem 嵌入。
      Refresh({ refreshing: $$this.refreshing, offset: 64, friction: 100 }) {
        List() {
          if (this.loading) {
            ListItem() {
              Column() {
                LoadingProgress().width(32).height(32).color($r('app.color.accent'))
                Text(LocaleService.loc('加载中', 'Loading', '読み込み中'))
                  .fontSize(13)
                  .fontColor($r('app.color.secondary_text'))
                  .margin({ top: 8 })
              }
              .width('100%')
              .height('100%')
              .justifyContent(FlexAlign.Center)
            }
          } else if (paged.length === 0) {
            ListItem() {
              Column() {
                // 表格区空态：图标 + 文字双居中，图标颜色与文字保持一致（次级文字灰）。
                Column() {
                  Image($r('app.media.ic_quick_todo'))
                    .width(72)
                    .height(72)
                    .objectFit(ImageFit.Contain)
                    .fillColor($r('app.color.secondary_text'))
                    .margin({ bottom: 14 })
                  Text(LocaleService.loc('暂无待办', 'No todos yet', 'ToDoなし'))
                    .fontSize(15)
                    .fontColor($r('app.color.secondary_text'))
                }
                .alignItems(HorizontalAlign.Center)
              }
              .width('100%')
              .height('100%')
              .justifyContent(FlexAlign.Center)
            }
          } else {
            ForEach(paged, (row: TodoItemRow) => {
              ListItem() {
                this.pcTableRow(row)
              }
            }, (row: TodoItemRow): string =>
              `pt_${row.noteId}_${row.sourceNote.todoPriority ?? 0}_${row.sourceNote.updatedAt}_${this.uiNonce}`)
          }
        }
        .width('100%')
        .height('100%')
        .divider({ strokeWidth: 1, color: $r('app.color.surface_muted') })
        .padding({ left: 8, right: 8 })
        // 关闭 List 缓存：每次数据更新都强制重绘所有 item。
        .cachedCount(0)
      }
      .layoutWeight(1)
      .width('100%')
      .onRefreshing((): void => {
        void this.pullToRefresh()
      })
    }
    .layoutWeight(1)
    .width('100%')
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(12)
  }

  @Builder
  pcTableHeader() {
    Row() {
      Blank().width(40)
      Text(LocaleService.loc('标题', 'Title', 'タイトル'))
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.secondary_text'))
        .layoutWeight(4)
        .padding({ left: 8 })
      Text(LocaleService.loc('状态', 'Status', 'ステータス'))
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.secondary_text'))
        .width(110)
      Text(LocaleService.loc('开始时间', 'Start time', '開始時間'))
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.secondary_text'))
        .width(170)
      Text(LocaleService.loc('截止时间', 'Deadline', '締切'))
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.secondary_text'))
        .width(170)
      Text(LocaleService.loc('备注', 'Remarks', '備考'))
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.secondary_text'))
        .layoutWeight(3)
        .padding({ left: 8 })
    }
    .width('100%')
    .height(40)
    .alignItems(VerticalAlign.Center)
    .padding({ left: 8, right: 8 })
    .border({ width: { bottom: 1 }, color: $r('app.color.surface_muted') })
  }

  @Builder
  mobileCard(row: TodoItemRow) {
    Row() {
      // 左侧图标位：多选模式下显示自绘勾选指示器，否则显示待办/日程图标。
      // 图标到屏幕左边 = List padding (PAGE_PAD) = 16vp，所以图标右侧留同样 16vp 间距
      // 与正文分隔，使「图标 ↔ 列表项」间距 ==「图标 ↔ 屏幕左边」间距。
      // 注意：ArkTS 严格模式下 @Builder 调用返回 void，无法链式 .margin()，
      // 需要外层包一个 Row 让 margin 落在容器上。
      Row() {
        this.buildItemLeading(row)
      }
      .margin({ right: PAGE_PAD })

      Column() {
        Row() {
          Text(row.title)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Row() {
            Text(this.pillStyle(row.status).label)
              .fontSize(11)
              .fontColor(this.pillStyle(row.status).fg)
              .padding({ left: 8, right: 8, top: 2, bottom: 2 })
              .backgroundColor(this.pillStyle(row.status).bg)
              .borderRadius(10)
            Text(this.kindLabel(row.kind))
              .fontSize(10)
              .fontColor($r('app.color.secondary_text'))
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(8)
              .border({ width: 1, color: $r('app.color.surface_muted') })
              .margin({ left: 6 })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        if (row.startMs > 0 || row.endMs > 0) {
          Text(`${row.startMs > 0 ? this.hhmm(row.startMs) : '—'} ~ ${row.endMs > 0 ? this.hhmm(row.endMs) : '—'}`)
            .fontSize(12)
            .fontColor($r('app.color.secondary_text'))
            .margin({ top: 4 })
        }

        if (row.remark.length > 0) {
          Text(row.remark)
            .fontSize(12)
            .fontColor($r('app.color.secondary_text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 2 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .onClick(() => {
      void this.onTapRow(row)
    })
    // 长按进入多选模式：嵌在 Refresh → List 里，父级滑动手势可能抢占触摸序列，
    // 用 priorityGesture 确保长按能被识别（参考 Feedback.ets 中保存二维码的写法）。
    .priorityGesture(
      LongPressGesture({ repeat: false, duration: 500 })
        .onAction((): void => {
          this.onLongPressRow(row)
        })
    )
  }

  @Builder
  pcTableRow(row: TodoItemRow) {
    Row() {
      // 左侧图标位：与 mobileCard 共用，多选模式下展示自绘勾选指示器。
      // PC 端图标到屏幕左边 = Column padding (PAGE_PAD) + List padding (8) = 24vp，
      // 标题 Text 已自带 padding({ left: 8 }) = 8vp，所以再在图标右侧加 PAGE_PAD 间距，
      // 总间隙 8 + 16 = 24vp，正好等于「图标 ↔ 屏幕左边」间距。
      // 注意：ArkTS 严格模式下 @Builder 调用返回 void，无法链式 .margin()，
      // 需要外层包一个 Row 让 margin 落在容器上。
      Row() {
        this.buildItemLeading(row)
      }
      .margin({ right: PAGE_PAD })

      Text(row.title)
        .fontSize(13)
        .fontColor($r('app.color.primary_text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(4)
        .padding({ left: 8 })

      Row() {
        Text(this.pillStyle(row.status).label)
          .fontSize(11)
          .fontColor(this.pillStyle(row.status).fg)
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .backgroundColor(this.pillStyle(row.status).bg)
          .borderRadius(10)
      }
      .width(110)

      Text(row.startMs > 0 ? this.hhmm(row.startMs) : '—')
        .fontSize(13)
        .fontColor($r('app.color.primary_text'))
        .width(170)

      Text(row.endMs > 0 ? this.hhmm(row.endMs) : '—')
        .fontSize(13)
        .fontColor($r('app.color.primary_text'))
        .width(170)

      Text(row.remark)
        .fontSize(12)
        .fontColor($r('app.color.secondary_text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(3)
        .padding({ left: 8 })
    }
    .width('100%')
    .height(ROW_HEIGHT)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      void this.onTapRow(row)
    })
    // 长按进入多选模式（与 mobileCard 一致）。
    .priorityGesture(
      LongPressGesture({ repeat: false, duration: 500 })
        .onAction((): void => {
          this.onLongPressRow(row)
        })
    )
  }

  @Builder
  buildItemLeading(row: TodoItemRow) {
    // 多选模式：自绘勾选指示器，避开 ArkTS Checkbox 内部状态与 select() 绑定的潜在竞争；
    // 勾选/取消完全交给 onTapRow 单击逻辑统一处理，视觉态由 this.selected 推导。
    if (this.selectionMode) {
      if (this.selected.indexOf(row.noteId) >= 0) {
        Text('✓')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .width(20)
          .height(20)
          .textAlign(TextAlign.Center)
          .borderRadius(10)
          .backgroundColor(ACCENT)
      } else {
        Row()
          .width(20)
          .height(20)
          .border({ width: 1.5, color: '#9CA3AF' })
          .borderRadius(10)
      }
    } else if (row.kind === 'schedule') {
      // 待办日程：复用日历 tab 的 sys.symbol.calendar，颜色按状态（已完成灰/否则黄）。
      SymbolGlyph($r('sys.symbol.calendar'))
        .fontSize(ICON_SIZE)
        .fontColor([this.scheduleIconColor(row)])
    } else if (row.status === 'completed') {
      // 已完成待办：固定灰色。
      Image($r('app.media.ic_quick_todo'))
        .width(ICON_SIZE)
        .height(ICON_SIZE)
        .objectFit(ImageFit.Contain)
        .fillColor(ICON_GRAY)
    } else {
      // 按 priority 拆 5 个分支，每个分支独立 Image 组件实例 + fillColor 写死常量，
      // 保证 priority 切换时一定会走到新分支创建新 Image 实例。
      // ForEach key 已包含 todoPriority，priority 变化时 ListItem 销毁重建，
      // 新 Image 用新 fillColor 创建，build() 现在会读 this.allRows 触发重渲染。
      if (row.sourceNote.todoPriority === 1) {
        Image($r('app.media.ic_quick_todo'))
          .width(ICON_SIZE)
          .height(ICON_SIZE)
          .objectFit(ImageFit.Contain)
          .fillColor(ICON_TODO_LOW)
      } else if (row.sourceNote.todoPriority === 2) {
        Image($r('app.media.ic_quick_todo'))
          .width(ICON_SIZE)
          .height(ICON_SIZE)
          .objectFit(ImageFit.Contain)
          .fillColor(ICON_TODO_MEDIUM)
      } else if (row.sourceNote.todoPriority === 3) {
        Image($r('app.media.ic_quick_todo'))
          .width(ICON_SIZE)
          .height(ICON_SIZE)
          .objectFit(ImageFit.Contain)
          .fillColor(ICON_TODO_HIGH)
      } else if (row.sourceNote.todoPriority === 4) {
        Image($r('app.media.ic_quick_todo'))
          .width(ICON_SIZE)
          .height(ICON_SIZE)
          .objectFit(ImageFit.Contain)
          .fillColor(ICON_TODO_URGENT)
      } else {
        Image($r('app.media.ic_quick_todo'))
          .width(ICON_SIZE)
          .height(ICON_SIZE)
          .objectFit(ImageFit.Contain)
          .fillColor(ICON_TODO_LOW)
      }
    }
  }

  @Builder
  buildSelectionBar() {
    Row() {
      Text(LocaleService.loc(`已选 ${this.selected.length} 项`, `${this.selected.length} selected`, `${this.selected.length}件選択中`))
        .fontSize(13)
        .fontColor($r('app.color.secondary_text'))
      Blank().layoutWeight(1)
      Button(LocaleService.loc('标记完成', 'Mark complete', '完了にする'))
        .fontSize(13)
        .fontColor(this.allSelectedAreTodo() ? ACCENT : $r('app.color.disabled_text'))
        .backgroundColor(Color.Transparent)
        .padding({ left: 8, right: 8 })
        .enabled(this.allSelectedAreTodo())
        .onClick(() => {
          void this.onBatchMarkComplete()
        })
      Button(LocaleService.loc('删除', 'Delete', '削除'))
        .fontSize(13)
        .fontColor(Color.White)
        .backgroundColor('#E53935')
        .borderRadius(8)
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .margin({ left: 8 })
        .onClick(() => {
          void this.onBatchDelete()
        })
      Button(LocaleService.loc('取消', 'Cancel', 'キャンセル'))
        .fontSize(13)
        .fontColor($r('app.color.secondary_text'))
        .backgroundColor(Color.Transparent)
        .padding({ left: 8, right: 8 })
        .margin({ left: 8 })
        .onClick(() => {
          this.exitSelectionMode()
        })
    }
    .width('100%')
    .padding(this.pcLayout
      ? { left: PAGE_PAD, right: PAGE_PAD, top: 8, bottom: 8 }
      : { left: PAGE_PAD, right: PAGE_PAD, top: 8, bottom: 12 })
    .border({ width: { top: 1 }, color: $r('app.color.surface_muted') })
    .backgroundColor($r('app.color.card_background'))
  }
}