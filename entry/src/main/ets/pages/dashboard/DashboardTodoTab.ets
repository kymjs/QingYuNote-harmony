import type { Note } from '../../common/model/Note'
import { usePcStyleLayoutWithSize } from '../../common/utils/DesktopLayout'
import { navigateToTodoEditor } from '../../common/utils/TodoEditorNavigation'
import { LocaleService } from '../../services/LocaleService'
import { NoteRepository } from '../../services/NoteRepository'
import { showCalendarAddScheduleDialog } from '../../dialogs/CalendarAddScheduleDialog'
import { CalendarProjector } from './calendar/CalendarProjector'
import type { CalendarItemKind } from './calendar/CalendarModels'
import {
  TodoItemRow,
  TodoListKind,
  TodoStatus,
  TodoTabLogic
} from './todo/TodoTabModels'

const PAGE_PAD = 16
const TOP_BAR_GAP = 12
const ROW_HEIGHT = 64
const ACCENT = '#0DAA4A'
const GREEN_BG = '#1A0DAA4A'
const GREEN_FG = '#0DAA4A'
const GRAY_BG = '#146B7280'
const GRAY_FG = '#6B7280'
const BLUE_BG = '#143B82F6'
const BLUE_FG = '#3B82F6'
const SCHEDULE_DOT = '#8B5CF6'

@Component
export struct DashboardTodoTab {
  @Prop @Watch('onVisibleChanged') visible: boolean = false
  @StorageLink('appLocaleRevision') localeRevision: number = 0
  @StorageLink('appNotesRevision') @Watch('onNotesRevisionChanged')
  notesRevision: number = 0
  @State allRows: TodoItemRow[] = []
  @State loading: boolean = true
  @State search: string = ''
  @State filter: TodoListKind = 'all'
  @State page: number = 0
  @State pageSize: number = 20
  @State selected: string[] = []
  @State pcLayout: boolean = false
  @State pageWidth: number = 360
  @State pageHeight: number = 780
  @State uiNonce: number = 0
  private initialLoaded: boolean = false

  aboutToAppear(): void {
    void this.bootstrap()
  }

  onVisibleChanged(): void {
    if (this.visible) {
      void this.reload()
    }
  }

  onNotesRevisionChanged(): void {
    if (this.visible) {
      void this.reload()
    }
  }

  private async bootstrap(): Promise<void> {
    void this.reload()
    this.initialLoaded = true
  }

  private async reload(): Promise<void> {
    try {
      await NoteRepository.getInstance().init()
      const notes = await NoteRepository.getInstance().listNotes()
      this.allRows = TodoTabLogic.buildTodoRows(notes)
      // 切换数据后丢弃已选
      const valid = new Set<string>()
      for (let i = 0; i < this.allRows.length; i++) {
        valid.add(this.allRows[i].noteId)
      }
      this.selected = this.selected.filter((id: string): boolean => valid.has(id))
      const filtered = this.currentFiltered()
      if (this.page > 0 && this.page * this.pageSize >= filtered.length) {
        this.page = 0
      }
      this.loading = false
      this.uiNonce += 1
    } catch (_) {
      this.allRows = []
      this.loading = false
      this.uiNonce += 1
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

  // 行为
  private async onAddSchedule(): Promise<void> {
    const now = Date.now()
    const saved = await showCalendarAddScheduleDialog(this.getUIContext(), {
      startMs: now,
      endMs: now + 30 * 60 * 1000
    })
    if (saved) {
      await this.reload()
    }
  }

  private async onAddTodo(): Promise<void> {
    // 与首页「快捷创建 → 待办事项」保持一致：统一走 TodoEditorPage 全页表单
    // （旧 CalendarAddTodoDialog 弹窗已删除）。
    await navigateToTodoEditor(this.getUIContext(), {})
    await this.reload()
  }

  private async onTapRow(row: TodoItemRow): Promise<void> {
    const note = row.sourceNote
    if (row.isTodo) {
      await navigateToTodoEditor(this.getUIContext(), { noteId: note.id })
    } else {
      const s = note.startTime > 0 ? note.startTime : Date.now()
      const e = note.endTime > 0 ? note.endTime : s + 30 * 60 * 1000
      await showCalendarAddScheduleDialog(this.getUIContext(), {
        startMs: s,
        endMs: e
      })
    }
    await this.reload()
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

  private pillStyle(status: TodoStatus): { bg: string, fg: string, label: string } {
    if (status === 'completed') {
      return {
        bg: BLUE_BG,
        fg: BLUE_FG,
        label: LocaleService.loc('已完成', 'Completed', '完了')
      }
    }
    if (status === 'inProgress') {
      return {
        bg: GREEN_BG,
        fg: GREEN_FG,
        label: LocaleService.loc('进行中', 'In progress', '進行中')
      }
    }
    return {
      bg: GRAY_BG,
      fg: GRAY_FG,
      label: LocaleService.loc('未开始', 'Not started', '未開始')
    }
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

  private filterIndex(idx: string): number {
    if (idx === 'todo') {
      return 1
    }
    if (idx === 'schedule') {
      return 2
    }
    return 0
  }

  private filterAt(idx: number): TodoListKind {
    if (idx === 1) {
      return 'todo'
    }
    if (idx === 2) {
      return 'schedule'
    }
    return 'all'
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

  private kindDotColor(kind: CalendarItemKind): string {
    if (kind === 'schedule') {
      return SCHEDULE_DOT
    }
    return ACCENT
  }

  private kindLabel(kind: CalendarItemKind): string {
    if (kind === 'schedule') {
      return LocaleService.loc('日程', 'Event', '予定')
    }
    return LocaleService.loc('待办', 'Todo', 'ToDo')
  }

  build() {
    Stack() {
      Column() {
        this.buildTopBar()
        const filtered = this.currentFiltered()
        const paged = this.currentPaged()
        if (this.pcLayout) {
          this.buildPcTable(paged)
        } else {
          this.buildMobileList(paged)
        }
        if (this.selected.length > 0) {
          this.buildSelectionBar()
        } else {
          this.buildPaginationBar(filtered.length)
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: this.pcLayout ? PAGE_PAD : 0, right: this.pcLayout ? PAGE_PAD : 0 })
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
    .width('100%')
    .height('100%')
  }

  @Builder
  buildTopBar() {
    if (this.pcLayout) {
      Row() {
        Text(LocaleService.loc('待办事项/日程', 'Todos & Schedules', 'ToDoと予定'))
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
        Blank().layoutWeight(1)
        this.searchInput()
        Text(LocaleService.loc('筛选', 'Filter', 'フィルター'))
          .fontSize(13)
          .fontColor($r('app.color.secondary_text'))
          .margin({ left: 8, right: 4 })
        this.filterDropdown()
        this.addScheduleButton()
        this.addTodoButton()
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ top: 12, bottom: 8 })
    } else {
      Column() {
        Row() {
          Text(LocaleService.loc('待办事项/日程', 'Todos & Schedules', 'ToDoと予定'))
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
            .layoutWeight(1)
          this.addScheduleButton()
          this.addTodoButton()
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ left: PAGE_PAD, right: PAGE_PAD, top: 12, bottom: 6 })

        Row() {
          this.searchInput()
          Text(LocaleService.loc('筛选', 'Filter', 'フィルター'))
            .fontSize(12)
            .fontColor($r('app.color.secondary_text'))
            .margin({ left: 8, right: 4 })
          this.filterDropdown()
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ left: PAGE_PAD, right: PAGE_PAD, bottom: 8 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
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
  addScheduleButton() {
    Button(LocaleService.loc('新建日程', 'New schedule', '新しい予定'))
      .fontSize(13)
      .fontColor(ACCENT)
      .backgroundColor(Color.Transparent)
      .borderRadius(8)
      .border({ width: 1, color: ACCENT })
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .margin({ left: 8 })
      .onClick(() => {
        void this.onAddSchedule()
      })
  }

  @Builder
  addTodoButton() {
    Button(LocaleService.loc('新建待办', 'New todo', '新しいToDo'))
      .fontSize(13)
      .fontColor(Color.White)
      .backgroundColor(ACCENT)
      .borderRadius(8)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .margin({ left: 6 })
      .onClick(() => {
        void this.onAddTodo()
      })
  }

  @Builder
  buildMobileList(paged: TodoItemRow[]) {
    if (this.loading) {
      Column() {
        LoadingProgress().width(32).height(32).color($r('app.color.accent'))
        Text(LocaleService.loc('加载中', 'Loading', '読み込み中'))
          .fontSize(13)
          .fontColor($r('app.color.secondary_text'))
          .margin({ top: 8 })
        Blank().layoutWeight(1)
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else if (paged.length === 0) {
      Column() {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(40)
          .fontColor([$r('app.color.secondary_text')])
          .margin({ bottom: 8 })
        Text(LocaleService.loc('暂无待办', 'No todos yet', 'ToDoなし'))
          .fontSize(15)
          .fontColor($r('app.color.secondary_text'))
        Blank().layoutWeight(1)
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else {
      List() {
        ForEach(paged, (row: TodoItemRow) => {
          ListItem() {
            this.mobileCard(row)
          }
        }, (row: TodoItemRow): string => `mt_${row.noteId}_${this.uiNonce}`)
      }
      .layoutWeight(1)
      .divider({ strokeWidth: 1, color: $r('app.color.surface_muted') })
      .padding({ left: PAGE_PAD, right: PAGE_PAD })
    }
  }

  @Builder
  buildPcTable(paged: TodoItemRow[]) {
    Column() {
      this.pcTableHeader()
      if (this.loading) {
        Column() {
          LoadingProgress().width(32).height(32).color($r('app.color.accent'))
          Text(LocaleService.loc('加载中', 'Loading', '読み込み中'))
            .fontSize(13)
            .fontColor($r('app.color.secondary_text'))
            .margin({ top: 8 })
          Blank().layoutWeight(1)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .width('100%')
      } else if (paged.length === 0) {
        Column() {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(40)
            .fontColor([$r('app.color.secondary_text')])
            .margin({ bottom: 8 })
          Text(LocaleService.loc('暂无待办', 'No todos yet', 'ToDoなし'))
            .fontSize(15)
            .fontColor($r('app.color.secondary_text'))
          Blank().layoutWeight(1)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .width('100%')
      } else {
        List() {
          ForEach(paged, (row: TodoItemRow) => {
            ListItem() {
              this.pcTableRow(row)
            }
          }, (row: TodoItemRow): string => `pt_${row.noteId}_${this.uiNonce}`)
        }
        .layoutWeight(1)
        .divider({ strokeWidth: 1, color: $r('app.color.surface_muted') })
        .padding({ left: 8, right: 8 })
      }
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
      Checkbox({ name: row.noteId, group: 'todoSel' })
        .select(this.selected.indexOf(row.noteId) >= 0)
        .selectedColor(ACCENT)
        .width(20)
        .height(20)
        .onChange((value: boolean) => {
          if (value) {
            if (this.selected.indexOf(row.noteId) < 0) {
              this.selected.push(row.noteId)
              this.uiNonce += 1
            }
          } else {
            const idx = this.selected.indexOf(row.noteId)
            if (idx >= 0) {
              this.selected.splice(idx, 1)
              this.uiNonce += 1
            }
          }
        })

      Circle({ width: 8, height: 8 })
        .fill(this.kindDotColor(row.kind))
        .margin({ left: 6, right: 6 })

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
  }

  @Builder
  pcTableRow(row: TodoItemRow) {
    Row() {
      Checkbox({ name: row.noteId, group: 'todoSel' })
        .select(this.selected.indexOf(row.noteId) >= 0)
        .selectedColor(ACCENT)
        .width(20)
        .height(20)
        .margin({ left: 10 })
        .onChange((value: boolean) => {
          if (value) {
            if (this.selected.indexOf(row.noteId) < 0) {
              this.selected.push(row.noteId)
              this.uiNonce += 1
            }
          } else {
            const idx = this.selected.indexOf(row.noteId)
            if (idx >= 0) {
              this.selected.splice(idx, 1)
              this.uiNonce += 1
            }
          }
        })

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
          this.selected = []
          this.uiNonce += 1
        })
    }
    .width('100%')
    .padding(this.pcLayout
      ? { left: PAGE_PAD, right: PAGE_PAD, top: 8, bottom: 8 }
      : { left: PAGE_PAD, right: PAGE_PAD, top: 8, bottom: 12 })
    .border({ width: { top: 1 }, color: $r('app.color.surface_muted') })
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  buildPaginationBar(total: number) {
    const totalPages = this.totalPages(total)
    Row() {
      Text(LocaleService.loc(
        `共 ${total} 条 · 第 ${this.page + 1} / ${Math.max(1, totalPages)} 页`,
        `Total: ${total} · Page ${this.page + 1} / ${Math.max(1, totalPages)}`,
        `合計 ${total} 件 · ${this.page + 1} / ${Math.max(1, totalPages)} ページ`
      ))
        .fontSize(12)
        .fontColor($r('app.color.secondary_text'))
      Blank().layoutWeight(1)
      Button(LocaleService.loc('上一页', 'Prev', '前へ'))
        .fontSize(12)
        .fontColor($r('app.color.primary_text'))
        .backgroundColor($r('app.color.surface_muted'))
        .borderRadius(6)
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .margin({ right: 6 })
        .enabled(this.page > 0)
        .onClick(() => {
          if (this.page > 0) {
            this.page -= 1
            this.uiNonce += 1
          }
        })
      Button(LocaleService.loc('下一页', 'Next', '次へ'))
        .fontSize(12)
        .fontColor($r('app.color.primary_text'))
        .backgroundColor($r('app.color.surface_muted'))
        .borderRadius(6)
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .margin({ right: 6 })
        .enabled(this.page + 1 < totalPages)
        .onClick(() => {
          if (this.page + 1 < totalPages) {
            this.page += 1
            this.uiNonce += 1
          }
        })
      Row() {
        Text(LocaleService.loc(`${this.pageSize} 条/页`, `${this.pageSize} / page`, `${this.pageSize}件/ページ`))
          .fontSize(12)
          .fontColor($r('app.color.primary_text'))
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(11)
          .fontColor([$r('app.color.secondary_text')])
          .margin({ left: 4 })
      }
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .borderRadius(6)
      .backgroundColor($r('app.color.surface_muted'))
      .bindMenu([
        { value: LocaleService.loc('10 条/页', '10 / page', '10件/ページ'), action: (): void => {
          this.pageSize = 10
          this.page = 0
          this.uiNonce += 1
        } },
        { value: LocaleService.loc('20 条/页', '20 / page', '20件/ページ'), action: (): void => {
          this.pageSize = 20
          this.page = 0
          this.uiNonce += 1
        } },
        { value: LocaleService.loc('50 条/页', '50 / page', '50件/ページ'), action: (): void => {
          this.pageSize = 50
          this.page = 0
          this.uiNonce += 1
        } },
        { value: LocaleService.loc('100 条/页', '100 / page', '100件/ページ'), action: (): void => {
          this.pageSize = 100
          this.page = 0
          this.uiNonce += 1
        } }
      ])
    }
    .width('100%')
    .padding(this.pcLayout
      ? { left: PAGE_PAD, right: PAGE_PAD, top: 6, bottom: 8 }
      : { left: PAGE_PAD, right: PAGE_PAD, top: 8, bottom: 12 })
  }
}