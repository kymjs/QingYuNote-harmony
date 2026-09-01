import { common } from '@kit.AbilityKit'
import { fileUri } from '@kit.CoreFileKit'
import display from '@ohos.display'

import type { Note } from '../../common/model/Note'
import { isExtractStatusPending } from '../../common/model/Note'
import { NOTE_TYPE_FLOWCHART } from '../../common/model/FlowchartGraph'
import { navigateToFlowchart } from '../../common/utils/FlowchartNavigation'
import { navigateToNoteEdit } from '../../common/utils/NoteEditNavigation'
import { navigateToTodoEditor } from '../../common/utils/TodoEditorNavigation'
import { formatDashboardDateLine } from '../../common/utils/GreetingAndLunar'
import { AppContextHolder } from '../../services/AppContextHolder'
import { LocaleService } from '../../services/LocaleService'
import { NoteRepository } from '../../services/NoteRepository'
import { PreferencesService } from '../../services/PreferencesService'
import {
  CalendarChipFilter,
  CalendarItemKind,
  CalendarOccurrence,
  CalendarViewMode,
  CalendarWeekBlockLayout,
  CalendarWeekVisibleRange,
  CalendarYearMonthPickerMode
} from './calendar/CalendarModels'
import { CalendarProjector } from './calendar/CalendarProjector'
import { CalendarWeekLayout } from './calendar/CalendarWeekLayout'
import { NotesTabLogic } from './DashboardNotesModels'
import { showCalendarAddScheduleDialog } from '../../dialogs/CalendarAddScheduleDialog'
import { FlowchartService } from '../../services/FlowchartService'
import { FlowchartMindMap } from '../../common/utils/FlowchartMindMap'
import { FlowchartMermaidCodec } from '../../common/utils/FlowchartMermaidCodec'

const PAGE_PAD = 8
const WEEK_PAD = 4
const LIST_BOTTOM_PAD = 16
const HOUR_ROW_HEIGHT = 36.4 // 52 * 0.7
// 点击空白格子的最小时间粒度（30 分钟对齐），与 PC 端保持一致。
const SLOT_MINUTES = 30
const SHEET_MIN = 0.16
const SHEET_MID = 0.42
const SHEET_MAX = 0.94
// 图例小圆点使用浅/夜间模式自适应色
const ORANGE: ResourceColor = $r('app.color.calendar_kind_todo_fg')
const PURPLE: ResourceColor = $r('app.color.calendar_kind_schedule_fg')
const YELLOW: ResourceColor = $r('app.color.calendar_kind_yellow_fg')
const ACCENT: ResourceColor = $r('app.color.calendar_kind_note_fg')

@Component
export struct DashboardCalendarTab {
  @Prop @Watch('onVisibleChanged') visible: boolean = false
  @StorageLink('appLocaleRevision') localeRevision: number = 0
  @State viewMode: CalendarViewMode = 'month'
  @State selectedY: number = new Date().getFullYear()
  @State selectedM: number = new Date().getMonth() + 1
  @State selectedD: number = new Date().getDate()
  @State visibleYear: number = new Date().getFullYear()
  @State visibleMonth: number = new Date().getMonth() + 1
  @State chip: CalendarChipFilter = 'all'
  @State loading: boolean = true
  @State dayItems: CalendarOccurrence[] = []
  @State countAll: number = 0
  @State countNote: number = 0
  @State countTodo: number = 0
  @State countGraph: number = 0
  @State monthCells: CalendarMonthCell[] = []
  @State weekHeaders: CalendarWeekHeader[] = []
  @State weekBlocks: CalendarWeekBlockLayout[] = []
  @State weekStartHour: number = 9
  @State weekEndHour: number = 19
  @State weekHourLabels: string[] = []
  @State pickerVisible: boolean = false
  @State pickerMode: CalendarYearMonthPickerMode = 'month'
  @State pickerYear: number = new Date().getFullYear()
  @State pickerMonth: number = new Date().getMonth() + 1
  @State yearPageCenter: number = new Date().getFullYear()
  @State dateLine: string = ''
  @State uiNonce: number = 0
  @State sheetRatio: number = SHEET_MID
  @State pageHeight: number = 700
  /** 已预扫的「思维导图」笔记 id 集合（`.qy` 边车
   * `metadata.layoutMode == 'mindMapLinear'`），用于让日历列表 leading icon
   * 区分思维导图（蓝）与知识图谱（绿），与首页 / 笔记 tab 共用同一套图标。 */
  @State mindMapNoteIds: string[] = []
  private sheetDragStartRatio: number = SHEET_MID
  private byDay: Map<string, CalendarOccurrence[]> = new Map()
  private filesDir: string = ''
  private initialLoaded: boolean = false
  private monthSwiperController: SwiperController = new SwiperController()
  private weekSwiperController: SwiperController = new SwiperController()
  @State monthPageIndex: number = 1
  @State weekPageIndex: number = 1
  /** 月滑动窗口：上月 / 当月 / 下月 */
  @State monthWindow: CalendarMonthWindow[] = []
  /** 周滑动窗口：上周 / 当周 / 下周 */
  @State weekWindow: CalendarWeekWindow[] = []
  /** 周视图时间块放大：同一时间段笔记 */
  @State expandedItems: CalendarOccurrence[] = []
  @State expandedVisible: boolean = false
  /** 年月弹窗锚点：相对日期栏下方 Stack 的本地坐标 */
  @State periodBarBottomY: number = 48
  @State pickerAnchorWidth: number = 360
  private readonly pickerCardWidth: number = 292

  aboutToAppear(): void {
    void this.bootstrap()
  }

  onVisibleChanged(): void {
    if (this.visible) {
      void this.reload()
    } else {
      this.pickerVisible = false
    }
  }

  private async bootstrap(): Promise<void> {
    try {
      const ctx = AppContextHolder.getContext() as common.Context
      await PreferencesService.getInstance().init(ctx)
      this.filesDir = ctx.filesDir
      const mode = await PreferencesService.getInstance().getCalendarViewMode()
      this.viewMode = mode === 'week' ? 'week' : 'month'
    } catch (_) {
    }
    await this.reload()
    this.initialLoaded = true
  }

  private async reload(): Promise<void> {
    try {
      await NoteRepository.getInstance().init()
      const notes = await NoteRepository.getInstance().listNotes()
      const projected = CalendarProjector.projectNotes(notes)
      // 预扫所有 flowchart 笔记，识别「思维导图」子集。
      this.mindMapNoteIds = Array.from(await this.detectMindMapNoteIds(notes))
      this.byDay = CalendarProjector.indexByDay(projected)
      this.refreshDerived()
      this.loading = false
    } catch (_) {
      this.byDay = new Map()
      this.refreshDerived()
      this.loading = false
    }
  }

  /**
   * 扫描所有 flowchart 笔记，收集处于「思维导图」模式（`.qy` 边车
   * `metadata.layoutMode == 'mindMapLinear'`）的 note id 集合。
   * 解析失败时按流程图处理（即不进入集合），保证日历列表不会卡死。
   */
  private async detectMindMapNoteIds(notes: Note[]): Promise<Set<string>> {
    const result = new Set<string>()
    for (const n of notes) {
      if (n.type_ !== NOTE_TYPE_FLOWCHART) {
        continue
      }
      if (FlowchartMermaidCodec.isMindMapContent(n.content ?? '')) {
        result.add(n.id)
        continue
      }
      try {
        const graph = await FlowchartService.getInstance().load(n.id)
        if (FlowchartMindMap.isMindMapMode(graph)) {
          result.add(n.id)
        }
      } catch (e) {
        // 解析失败时保持知识图谱语义，不影响其它笔记。
      }
    }
    return result
  }

  private mindMapSet(): Set<string> {
    return new Set<string>(this.mindMapNoteIds)
  }

  private refreshDerived(): void {
    const items = CalendarProjector.forDay(this.byDay, this.selectedY, this.selectedM, this.selectedD)
    const counts = CalendarProjector.countsFor(items, this.mindMapSet())
    this.countAll = counts.all
    this.countNote = counts.note
    this.countTodo = counts.todo
    this.countGraph = counts.graph
    this.dayItems = CalendarProjector.filterChip(items, this.chip, this.mindMapSet())
    this.dateLine = formatDashboardDateLine(new Date(this.selectedY, this.selectedM - 1, this.selectedD))
    this.rebuildMonthCells()
    this.rebuildWeek()
    this.rebuildSwipeWindows()
    this.uiNonce += 1
  }

  private rebuildSwipeWindows(): void {
    const months: CalendarMonthWindow[] = []
    for (let i = -1; i <= 1; i++) {
      const d = new Date(this.visibleYear, this.visibleMonth - 1 + i, 1)
      const w = new CalendarMonthWindow()
      w.y = d.getFullYear()
      w.m = d.getMonth() + 1
      months.push(w)
    }
    this.monthWindow = months
    this.monthPageIndex = 1

    const weeks: CalendarWeekWindow[] = []
    const cur = CalendarProjector.startOfWeekSunday(this.selectedY, this.selectedM, this.selectedD)
    for (let i = -1; i <= 1; i++) {
      const d = new Date(cur)
      d.setDate(cur.getDate() + i * 7)
      const w = new CalendarWeekWindow()
      w.y = d.getFullYear()
      w.m = d.getMonth() + 1
      w.d = d.getDate()
      weeks.push(w)
    }
    this.weekWindow = weeks
    this.weekPageIndex = 1
  }

  private rebuildMonthCells(): void {
    this.monthCells = this.cellsForMonth(this.visibleYear, this.visibleMonth)
  }

  private cellsForMonth(year: number, month: number): CalendarMonthCell[] {
    const first = new Date(year, month - 1, 1)
    const start = new Date(first)
    start.setDate(first.getDate() - first.getDay())
    const cells: CalendarMonthCell[] = []
    for (let i = 0; i < 42; i++) {
      const d = new Date(start)
      d.setDate(start.getDate() + i)
      const y = d.getFullYear()
      const m = d.getMonth() + 1
      const day = d.getDate()
      const dayItems = CalendarProjector.forDay(this.byDay, y, m, day)
      const cell = new CalendarMonthCell()
      cell.y = y
      cell.m = m
      cell.d = day
      cell.inMonth = m === month
      cell.selected = y === this.selectedY && m === this.selectedM && day === this.selectedD
      cell.dotKind = CalendarProjector.dayDotKind(dayItems)
      // 实际渲染时使用的红点颜色（按优先级：待办 > 思维导图 / 知识图谱 > 普通笔记）。
      cell.dotColor = dayItems.length > 0 ? this.calendarItemColor(dayItems) : null
      cells.push(cell)
    }
    return cells
  }

  private rebuildWeek(): void {
    const weekStart = CalendarProjector.startOfWeekSunday(this.selectedY, this.selectedM, this.selectedD)
    const headers: CalendarWeekHeader[] = []
    const weekItems: CalendarOccurrence[] = []
    for (let i = 0; i < 7; i++) {
      const d = new Date(weekStart)
      d.setDate(weekStart.getDate() + i)
      const y = d.getFullYear()
      const m = d.getMonth() + 1
      const day = d.getDate()
      const h = new CalendarWeekHeader()
      h.y = y
      h.m = m
      h.d = day
      h.label = `${m}/${day}`
      h.weekday = ['日', '一', '二', '三', '四', '五', '六'][d.getDay()]
      h.selected = y === this.selectedY && m === this.selectedM && day === this.selectedD
      headers.push(h)
      const list = CalendarProjector.forDay(this.byDay, y, m, day)
      for (let j = 0; j < list.length; j++) {
        weekItems.push(list[j])
      }
    }
    this.weekHeaders = headers
    const range = CalendarWeekLayout.visibleRange(weekItems)
    // 半页收起后上方空间变大：扩展展示更多小时
    if (this.sheetRatio <= 0.28) {
      if (range.startHour > 6) {
        range.startHour = 6
      }
      if (range.endHour < 22) {
        range.endHour = 22
      }
    }
    this.weekStartHour = range.startHour
    this.weekEndHour = range.endHour
    const labels: string[] = []
    for (let h = range.startHour; h < range.endHour; h++) {
      const hh = Math.floor(h)
      labels.push(`${hh < 10 ? '0' : ''}${hh}:00`)
    }
    this.weekHourLabels = labels
    this.weekBlocks = CalendarWeekLayout.layoutWeek(weekStart, weekItems, range)
  }

  private async setViewMode(mode: CalendarViewMode): Promise<void> {
    this.viewMode = mode
    this.pickerVisible = false
    this.closeWeekExpand()
    await PreferencesService.getInstance().setCalendarViewMode(mode)
    this.refreshDerived()
  }

  private goToday(): void {
    const t = new Date()
    this.selectedY = t.getFullYear()
    this.selectedM = t.getMonth() + 1
    this.selectedD = t.getDate()
    this.visibleYear = this.selectedY
    this.visibleMonth = this.selectedM
    this.pickerVisible = false
    this.closeWeekExpand()
    this.refreshDerived()
  }

  private shiftMonth(delta: number): void {
    if (delta > 0) {
      this.monthSwiperController.showNext()
    } else {
      this.monthSwiperController.showPrevious()
    }
  }

  private shiftWeek(delta: number): void {
    if (delta > 0) {
      this.weekSwiperController.showNext()
    } else {
      this.weekSwiperController.showPrevious()
    }
  }

  private selectDay(y: number, m: number, d: number): void {
    this.selectedY = y
    this.selectedM = m
    this.selectedD = d
    this.visibleYear = y
    this.visibleMonth = m
    this.refreshDerived()
  }

  private onMonthSwiperChange(index: number): void {
    if (index === 1) {
      return
    }
    const delta = index - 1
    const d = new Date(this.visibleYear, this.visibleMonth - 1 + delta, 1)
    this.visibleYear = d.getFullYear()
    this.visibleMonth = d.getMonth() + 1
    const today = new Date()
    const land = CalendarProjector.monthLandingDay(this.visibleYear, this.visibleMonth, today)
    this.selectedY = land.getFullYear()
    this.selectedM = land.getMonth() + 1
    this.selectedD = land.getDate()
    this.refreshDerived()
    this.monthSwiperController.changeIndex(1, false)
  }

  private onWeekSwiperChange(index: number): void {
    if (index === 1) {
      return
    }
    this.closeWeekExpand()
    const delta = index - 1
    const cur = CalendarProjector.startOfWeekSunday(this.selectedY, this.selectedM, this.selectedD)
    const next = new Date(cur)
    next.setDate(cur.getDate() + delta * 7)
    const today = new Date()
    const todayStart = CalendarProjector.startOfWeekSunday(
      today.getFullYear(), today.getMonth() + 1, today.getDate())
    if (todayStart.getTime() === next.getTime()) {
      this.selectedY = today.getFullYear()
      this.selectedM = today.getMonth() + 1
      this.selectedD = today.getDate()
    } else {
      this.selectedY = next.getFullYear()
      this.selectedM = next.getMonth() + 1
      this.selectedD = next.getDate()
    }
    this.visibleYear = this.selectedY
    this.visibleMonth = this.selectedM
    this.refreshDerived()
    this.weekSwiperController.changeIndex(1, false)
  }

  private openPicker(): void {
    this.pickerYear = this.viewMode === 'week' ? this.selectedY : this.visibleYear
    this.pickerMonth = this.viewMode === 'week' ? this.selectedM : this.visibleMonth
    this.yearPageCenter = this.pickerYear
    this.pickerMode = 'month'
    this.pickerVisible = true
  }

  private onPickMonth(month: number): void {
    const year = this.pickerYear
    const today = new Date()
    const land = this.viewMode === 'week' ?
      CalendarProjector.weekLandingDay(year, month, today) :
      CalendarProjector.monthLandingDay(year, month, today)
    this.visibleYear = year
    this.visibleMonth = month
    this.selectedY = land.getFullYear()
    this.selectedM = land.getMonth() + 1
    this.selectedD = land.getDate()
    this.pickerVisible = false
    this.refreshDerived()
  }

  private kindColor(kind: CalendarItemKind): ResourceColor {
    // 日历视图专用：待办日程 + 待办事项都统一为黄色，知识图谱 / 思维导图走紫色（见 kindFgForCell）。
    if (kind === 'schedule') {
      return YELLOW
    }
    if (kind === 'todo') {
      return YELLOW
    }

    return ACCENT
  }

  /**
   * 日历视图（周视图块、月视图红点）专用配色，覆盖 `kindColor(kind)`。
   * 优先级：待办日程 / 待办事项（黄） > 知识图谱 / 思维导图（紫） > 普通笔记（绿）。
   * 月视图某天可能同时存在多类笔记，按上述优先级选一种颜色作为该天的红点。
   */
  private calendarItemColor(items: CalendarOccurrence[]): ResourceColor {
    for (let i = 0; i < items.length; i++) {
      if (items[i].kind === 'todo' || items[i].kind === 'schedule') {
        return YELLOW
      }
    }
    for (let i = 0; i < items.length; i++) {
      const lk = NotesTabLogic.leadingKindFor(items[i].note, this.mindMapSet())
      if (lk === 'flowchart' || lk === 'knowledgeGraph') {
        return PURPLE
      }
    }
    return ACCENT
  }

  /**
   * 周视图块（背景 + 边框 + 文字）的配色，按 occurrence 计算。
   * - 待办日程 / 待办事项 → 黄（边框 + 文字 = calendar_kind_yellow_fg；底色 = calendar_week_block_yellow）
   * - 知识图谱 / 思维导图 → 紫（边框 + 文字 = calendar_kind_schedule_fg；底色 = calendar_week_block_schedule）
   * - 普通笔记 → 绿（边框 + 文字 = calendar_kind_note_fg；底色 = calendar_week_block_note）
   */
  private calendarBlockFg(o: CalendarOccurrence): ResourceColor {
    if (o.kind === 'todo' || o.kind === 'schedule') {
      return YELLOW
    }
    const lk = NotesTabLogic.leadingKindFor(o.note, this.mindMapSet())
    if (lk === 'flowchart' || lk === 'knowledgeGraph') {
      return PURPLE
    }
    return ACCENT
  }

  private calendarBlockBg(o: CalendarOccurrence): ResourceColor {
    if (o.kind === 'todo' || o.kind === 'schedule') {
      return $r('app.color.calendar_week_block_yellow')
    }
    const lk = NotesTabLogic.leadingKindFor(o.note, this.mindMapSet())
    if (lk === 'flowchart' || lk === 'knowledgeGraph') {
      return $r('app.color.calendar_week_block_schedule')
    }
    return $r('app.color.calendar_week_block_note')
  }

  /**
   * 日历列表图标的「主色」：与 `dayLeadingIcon` 中的 fillColor / fontColor 保持一致。
   * 列表项的图标、时间、标题都用这个色，保证视觉同源。
   *  - 待办（kind=todo）→ 橙
   *  - 日程（kind=schedule）→ 紫
   *  - 思维导图 / 知识图谱（leadingKind=flowchart/knowledgeGraph）→ 蓝
   *  - 其它（普通笔记 / mp3 / 提取中）→ kindColor 对应的色
   */
  private dayLeadingColor(o: CalendarOccurrence): ResourceColor {
    if (o.kind === 'todo') {
      return $r('app.color.calendar_kind_todo_fg')
    }
    if (o.kind === 'schedule') {
      // 待办日程与待办事项共用 todo 橙，与首页 / 笔记 tab 三端同源。
      return $r('app.color.calendar_kind_todo_fg')
    }
    const leadingKind = NotesTabLogic.leadingKindFor(o.note, this.mindMapSet())
    if (leadingKind === 'flowchart' || leadingKind === 'knowledgeGraph') {
      // 思维导图 / 知识图谱在日历 tab 全部走紫色（与图例 / 月视图红点 / 周视图块同源）。
      return PURPLE
    }
    // mp3 音频笔记：与笔记统计卡「图谱」旧版图标同源，但 mp3 笔记类型走主题 accent 绿色，
    // 保证日历列表项的标题/时间与图标一致。
    if (leadingKind === 'mp3') {
      return $r('app.color.calendar_kind_note_fg')
    }
    return this.kindColor(o.kind)
  }

  private hhmm(ms: number): string {
    const d = new Date(ms)
    const h = d.getHours()
    const m = d.getMinutes()
    return `${h < 10 ? '0' : ''}${h}:${m < 10 ? '0' : ''}${m}`
  }

  private clampSheetRatio(next: number): number {
    if (next < SHEET_MIN) {
      return SHEET_MIN
    }
    if (next > SHEET_MAX) {
      return SHEET_MAX
    }
    return next
  }

  private snapSheetRatio(): void {
    if (this.sheetRatio > 0.68) {
      this.sheetRatio = SHEET_MAX
    } else if (this.sheetRatio <= 0.28) {
      this.sheetRatio = SHEET_MIN
    } else {
      this.sheetRatio = SHEET_MID
    }
    if (this.viewMode === 'week') {
      this.rebuildWeek()
      this.uiNonce += 1
    }
  }

  private onSheetPanUpdate(e: GestureEvent): void {
    if (this.pageHeight <= 0) {
      return
    }
    if (this.expandedVisible) {
      this.closeWeekExpand()
    }
    this.sheetRatio = this.clampSheetRatio(
      this.sheetDragStartRatio - e.offsetY / this.pageHeight)
  }

  private thumbUri(rel: string): string {
    if (!rel || rel.length === 0 || this.filesDir.length === 0) {
      return ''
    }
    const parts = rel.split('/')
    const fileName = parts.length > 0 ? parts[parts.length - 1] : rel
    const full = `${this.filesDir}/qingyu-note-image/${fileName}`
    try {
      return fileUri.getUriFromPath(full)
    } catch (_) {
      return ''
    }
  }

  private async openNote(note: Note): Promise<void> {
    if (note.type_ === NOTE_TYPE_FLOWCHART) {
      await navigateToFlowchart(this.getUIContext(), { noteId: note.id })
      await this.reload()
      return
    }
    if (isExtractStatusPending(note.extractStatus) ||
      note.extractStatus === 'failed' ||
      note.voiceTranscribeStatus === 'running' ||
      note.voiceTranscribeStatus === 'failed') {
      const kind = note.sourceUrl.trim().length === 0 &&
        note.extractStatus !== 'failed' &&
        !isExtractStatusPending(note.extractStatus)
        ? 'voiceTranscribe'
        : 'linkExtract'
      try {
        await this.getUIContext().getRouter().pushUrl({
          url: 'pages/LinkExtractProgress',
          params: { noteId: note.id, kind: kind, url: note.sourceUrl.trim() }
        })
      } catch (_) {
      }
      await this.reload()
      return
    }
    if (`${note.audioId ?? ''}`.trim().length > 0) {
      try {
        await this.getUIContext().getRouter().pushUrl({
          url: 'pages/VoiceNoteDetail',
          params: { noteId: note.id }
        })
      } catch (_) {
      }
      await this.reload()
      return
    }
    // 待办事项（is_todo=2）→ 跳到新的待办编辑页，提供结构化字段编辑。
    if ((note.isTodo ?? 0) === 2) {
      await navigateToTodoEditor(this.getUIContext(), { noteId: note.id })
      await this.reload()
      return
    }
    await navigateToNoteEdit(this.getUIContext(), {
      noteId: note.id,
      openWithPreview: `${note.content ?? ''}`.trim().length > 0
    })
    await this.reload()
  }

  private periodTitle(): string {
    if (this.viewMode === 'month') {
      return `${this.visibleYear}${LocaleService.loc('年', ' ', '年')}${this.visibleMonth}${LocaleService.loc('月', '', '月')}`
    }
    const ws = CalendarProjector.startOfWeekSunday(this.selectedY, this.selectedM, this.selectedD)
    const we = new Date(ws)
    we.setDate(ws.getDate() + 6)
    return `${ws.getFullYear()}${LocaleService.loc('年', '-', '年')}${ws.getMonth() + 1}${LocaleService.loc('月', '', '月')}${ws.getDate()}${LocaleService.loc('日', '', '日')} - ${we.getMonth() + 1}${LocaleService.loc('月', '', '月')}${we.getDate()}${LocaleService.loc('日', '', '日')}`
  }

  private yearPage(): number[] {
    const out: number[] = []
    for (let i = -4; i <= 4; i++) {
      out.push(this.yearPageCenter + i)
    }
    return out
  }

  private chipCount(value: CalendarChipFilter): number {
    // 列表筛选项：全部 / 笔记 / 待办（= 待办事项 + 待办日程）/ 图谱（= 思维导图 + 知识图谱）。
    if (value === 'all') {
      return this.countAll
    }
    if (value === 'note') {
      return this.countNote
    }
    if (value === 'todo') {
      return this.countTodo
    }
    if (value === 'graph') {
      return this.countGraph
    }
    return 0
  }

  @Builder
  chipBtn(label: string, value: CalendarChipFilter) {
    // 必须读 this.count*，不能把 count 当 @Builder 入参，否则数量变更不刷新
    Text(`${label} ${this.chipCount(value)}`)
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.chip === value ? Color.White : $r('app.color.secondary_text'))
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor(this.chip === value ? $r('app.color.accent') : Color.Transparent)
      .border({
        width: 1,
        color: this.chip === value ? $r('app.color.accent') : $r('app.color.surface_muted'),
        radius: 16
      })
      .margin({ right: 8 })
      .onClick(() => {
        this.chip = value
        this.refreshDerived()
      })
  }

  build() {
    Stack() {
      Column() {
        Row() {
          Row() {
            Text(LocaleService.loc('月视图', 'Month', '月表示'))
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.viewMode === 'month' ? $r('app.color.accent') : $r('app.color.primary_text'))
              .textAlign(TextAlign.Center)
              .padding({ left: 14, right: 14, top: 7, bottom: 7 })
              .backgroundColor(this.viewMode === 'month' ? $r('app.color.card_background') : Color.Transparent)
              .borderRadius(8)
              .onClick(() => {
                void this.setViewMode('month')
              })
            Text(LocaleService.loc('周视图', 'Week', '週表示'))
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.viewMode === 'week' ? $r('app.color.accent') : $r('app.color.primary_text'))
              .textAlign(TextAlign.Center)
              .padding({ left: 14, right: 14, top: 7, bottom: 7 })
              .backgroundColor(this.viewMode === 'week' ? $r('app.color.card_background') : Color.Transparent)
              .borderRadius(8)
              .onClick(() => {
                void this.setViewMode('week')
              })
          }
          .padding(3)
          .backgroundColor(Color.Transparent)
          .border({ width: 1, color: $r('app.color.accent'), radius: 11 })
          .justifyContent(FlexAlign.Center)
          .height(40)

          Blank().layoutWeight(1)

          Text(LocaleService.loc('今天', 'Today', '今日'))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.accent'))
            .textAlign(TextAlign.Center)
            .padding({ left: 14, right: 14 })
            .height(40)
            .border({ width: 1, color: $r('app.color.accent'), radius: 11 })
            .onClick(() => this.goToday())
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ left: PAGE_PAD, right: PAGE_PAD, top: 8, bottom: 4 })

        Stack() {
          Column() {
        Row() {
          Row() {
            SymbolGlyph($r('sys.symbol.chevron_left'))
              .fontSize(22)
              .fontColor([$r('app.color.primary_text')])
          }
          .width(48)
          .height(44)
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            if (this.viewMode === 'month') {
              this.shiftMonth(-1)
            } else {
              this.shiftWeek(-1)
            }
          })

          Row() {
            Text(this.periodTitle())
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.primary_text'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(14)
              .fontColor([$r('app.color.secondary_text')])
              .margin({ left: 2 })
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .padding({ top: 10, bottom: 10 })
          .onClick(() => this.openPicker())

          Row() {
            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontSize(22)
              .fontColor([$r('app.color.primary_text')])
          }
          .width(48)
          .height(44)
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            if (this.viewMode === 'month') {
              this.shiftMonth(1)
            } else {
              this.shiftWeek(1)
            }
          })
        }
        .width('100%')
        .padding({ left: Math.max(0, PAGE_PAD - 4), right: Math.max(0, PAGE_PAD - 4), top: 12 })
        .onAreaChange((_o: Area, a: Area) => {
          // position 相对父 Column（与弹窗 Stack 同坐标系）
          const top = Number(a.position.y)
          const h = Number(a.height)
          if (h > 0) {
            this.periodBarBottomY = top + h
          }
        })

        if (this.viewMode === 'month') {
          Swiper(this.monthSwiperController) {
            ForEach(this.monthWindow, (w: CalendarMonthWindow) => {
              this.monthGridFor(w.y, w.m)
            }, (w: CalendarMonthWindow) => `mw_${w.y}_${w.m}_${this.uiNonce}`)
          }
          .index(this.monthPageIndex)
          .loop(false)
          .indicator(false)
          .cachedCount(1)
          .onChange((i: number) => this.onMonthSwiperChange(i))
          .layoutWeight(1)
        } else {
          this.weekHeaderBar()
          Swiper(this.weekSwiperController) {
            ForEach(this.weekWindow, (w: CalendarWeekWindow) => {
              this.weekTimelineFor(w.y, w.m, w.d)
            }, (w: CalendarWeekWindow) => `ww_${w.y}_${w.m}_${w.d}_${this.uiNonce}`)
          }
          .index(this.weekPageIndex)
          .loop(false)
          .indicator(false)
          .cachedCount(1)
          .onChange((i: number) => this.onWeekSwiperChange(i))
          .layoutWeight(1)
        }

        this.legendBar()
          }
          .width('100%')
          .height('100%')

          if (this.pickerVisible) {
            // 透明点击层关闭（无灰色蒙版）
            Column()
              .width('100%')
              .height('100%')
              .backgroundColor(Color.Transparent)
              .onClick(() => {
                this.pickerVisible = false
              })

            // 用顶部 Blank 占位控制垂直位置（比 .position 更可靠）
            // 相对日期栏底边上移 4vp
            Column() {
              Blank()
                .width('100%')
                .height(Math.max(0, this.periodBarBottomY - 4))
                .hitTestBehavior(HitTestMode.None)

              Row() {
                Blank()
                  .layoutWeight(1)
                  .hitTestBehavior(HitTestMode.None)
                Column() {
                  Row() {
                    Blank().layoutWeight(1)
                    Polygon({ width: 18, height: 9 })
                      .points([[0, 9], [9, 0], [18, 9]])
                      .fill($r('app.color.card_background'))
                    Blank().layoutWeight(1)
                  }
                  .width(this.pickerCardWidth)
                  .height(9)

                  Column() {
                    Text(LocaleService.loc('选择年月', 'Select month', '年月を選択'))
                      .fontSize(15)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.primary_text'))
                      .width('100%')
                      .textAlign(TextAlign.Start)
                      .margin({ bottom: 8 })

                    Row() {
                      SymbolGlyph($r('sys.symbol.chevron_left'))
                        .fontSize(20)
                        .fontColor([$r('app.color.primary_text')])
                        .onClick(() => {
                          if (this.pickerMode === 'month') {
                            this.pickerYear -= 1
                          } else {
                            this.yearPageCenter -= 9
                          }
                        })
                      Row() {
                        Text(`${this.pickerYear}${LocaleService.loc('年', '', '年')}`)
                          .fontSize(14)
                          .fontWeight(FontWeight.Medium)
                          .fontColor($r('app.color.primary_text'))
                        if (this.pickerMode === 'month') {
                          SymbolGlyph($r('sys.symbol.chevron_down'))
                            .fontSize(14)
                            .fontColor([$r('app.color.secondary_text')])
                            .margin({ left: 2 })
                        }
                      }
                      .layoutWeight(1)
                      .justifyContent(FlexAlign.Center)
                      .alignItems(VerticalAlign.Center)
                      .onClick(() => {
                        if (this.pickerMode === 'month') {
                          this.pickerMode = 'year'
                          this.yearPageCenter = this.pickerYear
                        }
                      })
                      SymbolGlyph($r('sys.symbol.chevron_right'))
                        .fontSize(20)
                        .fontColor([$r('app.color.primary_text')])
                        .onClick(() => {
                          if (this.pickerMode === 'month') {
                            this.pickerYear += 1
                          } else {
                            this.yearPageCenter += 9
                          }
                        })
                    }
                    .width('100%')
                    .margin({ bottom: 5 })

                    if (this.pickerMode === 'month') {
                      Grid() {
                        ForEach([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12], (m: number) => {
                          GridItem() {
                            Text(`${m}${LocaleService.loc('月', '', '月')}`)
                              .fontSize(14)
                              .fontWeight(FontWeight.Medium)
                              .fontColor(m === this.pickerMonth ? $r('app.color.accent') : $r('app.color.primary_text'))
                              .textAlign(TextAlign.Center)
                              .width('100%')
                              .height(34)
                              .backgroundColor(m === this.pickerMonth ? '#260DAA4A' : Color.Transparent)
                              .borderRadius(8)
                              .onClick(() => this.onPickMonth(m))
                          }
                        }, (m: number) => `m_${m}`)
                      }
                      .columnsTemplate('1fr 1fr 1fr 1fr')
                      .rowsGap(4)
                      .columnsGap(4)
                      .height(120)
                    } else {
                      Grid() {
                        ForEach(this.yearPage(), (y: number) => {
                          GridItem() {
                            Text(`${y}`)
                              .fontSize(14)
                              .fontWeight(FontWeight.Medium)
                              .fontColor(y === this.pickerYear ? $r('app.color.accent') : $r('app.color.primary_text'))
                              .textAlign(TextAlign.Center)
                              .width('100%')
                              .height(34)
                              .backgroundColor(y === this.pickerYear ? '#260DAA4A' : Color.Transparent)
                              .borderRadius(8)
                              .onClick(() => {
                                this.pickerYear = y
                                this.pickerMode = 'month'
                              })
                          }
                        }, (y: number) => `y_${y}`)
                      }
                      .columnsTemplate('1fr 1fr 1fr')
                      .rowsGap(4)
                      .columnsGap(4)
                      .height(110)
                    }

                    Text(LocaleService.loc('回到今天', 'Back to today', '今日に戻る'))
                      .fontSize(14)
                      .fontColor($r('app.color.accent'))
                      .textAlign(TextAlign.Center)
                      .width('100%')
                      .padding(12)
                      .backgroundColor($r('app.color.surface_muted'))
                      .borderRadius(10)
                      .margin({ top: 10 })
                      .onClick(() => this.goToday())
                  }
                  .width(this.pickerCardWidth)
                  .padding({ left: 14, right: 14, top: 12, bottom: 12 })
                  .backgroundColor($r('app.color.card_background'))
                  .borderRadius(14)
                  .shadow({ radius: 16, color: '#33000000', offsetY: 4 })
                  .alignItems(HorizontalAlign.Start)
                  .onClick(() => {
                  })
                }
                .width(this.pickerCardWidth)
                .onClick(() => {
                })

                Blank()
                  .layoutWeight(1)
                  .hitTestBehavior(HitTestMode.None)
              }
              .width('100%')
            }
            .width('100%')
            .hitTestBehavior(HitTestMode.Transparent)
          }
        }
        .layoutWeight(1)
        .width('100%')
        .onAreaChange((_o: Area, a: Area) => {
          const w = Number(a.width)
          if (w > 0) {
            this.pickerAnchorWidth = w
          }
        })
      }
      .width('100%')
      .height('100%')
      .padding({ bottom: this.pageHeight * this.sheetRatio + 2 })
      .onAreaChange((_o, a) => {
        const h = Number(a.height)
        if (h > 0) {
          this.pageHeight = h
        }
      })

      // 底部可上拉列表
      Column() {
        Column() {
          Row()
            .width(36)
            .height(4)
            .backgroundColor($r('app.color.surface_muted'))
            .borderRadius(2)
            .margin({ top: 8, bottom: 4 })

          Text(this.dateLine)
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
            .width('100%')
            .padding({ left: 16, right: 16, top: 6, bottom: 8 })

          Scroll() {
            Row() {
              this.chipBtn(LocaleService.loc('全部', 'All', 'すべて'), 'all')
              this.chipBtn(LocaleService.loc('笔记', 'Notes', 'ノート'), 'note')
              this.chipBtn(LocaleService.loc('待办', 'To-do', 'ToDo'), 'todo')
              this.chipBtn(LocaleService.loc('图谱', 'Graphs', 'グラフ'), 'graph')
            }
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .padding({ left: 12, right: 12 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .gesture(
          PanGesture({ direction: PanDirection.Vertical })
            .onActionStart(() => {
              this.sheetDragStartRatio = this.sheetRatio
            })
            .onActionUpdate((e: GestureEvent) => {
              this.onSheetPanUpdate(e)
            })
            .onActionEnd(() => {
              this.snapSheetRatio()
            })
        )

        if (this.loading) {
          Column() {
            LoadingProgress().width(32).height(32).color($r('app.color.accent')).margin({ top: 40 })
            Blank().layoutWeight(1)
          }
          .width('100%')
          .layoutWeight(1)
          .gesture(
            PanGesture({ direction: PanDirection.Vertical })
              .onActionStart(() => {
                this.sheetDragStartRatio = this.sheetRatio
              })
              .onActionUpdate((e: GestureEvent) => {
                this.onSheetPanUpdate(e)
              })
              .onActionEnd(() => {
                this.snapSheetRatio()
              })
          )
        } else if (this.dayItems.length === 0) {
          Column() {
            Text(LocaleService.loc('暂无内容', 'No content', '内容がありません'))
              .fontColor($r('app.color.secondary_text'))
              .margin({ top: 40 })
            Blank().layoutWeight(1)
          }
          .width('100%')
          .layoutWeight(1)
          .gesture(
            PanGesture({ direction: PanDirection.Vertical })
              .onActionStart(() => {
                this.sheetDragStartRatio = this.sheetRatio
              })
              .onActionUpdate((e: GestureEvent) => {
                this.onSheetPanUpdate(e)
              })
              .onActionEnd(() => {
                this.snapSheetRatio()
              })
          )
        } else {
          List() {
            ForEach(this.dayItems, (o: CalendarOccurrence) => {
              ListItem() {
                this.dayRow(o)
              }
            }, (o: CalendarOccurrence) => `${o.noteId}_${o.anchorMs}_${o.isUpdateOccurrence}_${this.uiNonce}`)
          }
          .layoutWeight(1)
          .divider({ strokeWidth: 1, color: $r('app.color.surface_muted') })
          .padding({ left: 12, right: 12, bottom: LIST_BOTTOM_PAD })
          .gesture(
            PanGesture({ direction: PanDirection.Vertical })
              .onActionStart(() => {
                this.sheetDragStartRatio = this.sheetRatio
              })
              .onActionUpdate((e: GestureEvent) => {
                // 列表在中档且向下拖时交给列表滚动
                if (e.offsetY >= 0 && this.sheetRatio <= SHEET_MID + 0.001) {
                  return
                }
                this.onSheetPanUpdate(e)
              })
              .onActionEnd(() => {
                this.snapSheetRatio()
              })
          )
        }
      }
      .width('100%')
      .height(`${this.sheetRatio * 100}%`)
      .backgroundColor($r('app.color.card_background'))
      .borderRadius({ topLeft: 18, topRight: 18 })
      .shadow({ radius: 12, color: '#22000000', offsetY: -2 })
      .position({ x: 0, y: `${(1 - this.sheetRatio) * 100}%` })

      // 盖住标题与日历；半页仍可拖（遮罩高度止于半页顶边）
      if (this.expandedVisible) {
        Column() {
          this.weekDayExpandOverlay()
        }
        .width('100%')
        .height(`${(1 - this.sheetRatio) * 100}%`)
        .position({ x: 0, y: 0 })
      }

    }
    .width('100%')
    .height('100%')
    // 与「我的」tab 保持一致：app_background 浅灰底，而非 card_background 纯白。
    .backgroundColor($r('app.color.app_background'))
  }

  @Builder
  monthGridFor(year: number, month: number) {
    Column() {
      Row() {
        ForEach(['日', '一', '二', '三', '四', '五', '六'], (l: string) => {
          Text(l)
            .fontSize(12)
            .fontColor($r('app.color.secondary_text'))
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
        }, (l: string) => `${l}_${year}_${month}`)
      }
      .width('100%')
      .margin({ bottom: 4 })

      Grid() {
        ForEach(this.cellsForMonth(year, month), (c: CalendarMonthCell) => {
          GridItem() {
            Column() {
              Text(`${c.d}`)
                .fontSize(14)
                .fontWeight(c.selected ? FontWeight.Bold : FontWeight.Medium)
                .fontColor(c.selected ? Color.White :
                  (c.inMonth ? $r('app.color.primary_text') : $r('app.color.secondary_text')))
                .width(30)
                .height(30)
                .textAlign(TextAlign.Center)
                .backgroundColor(c.selected ? $r('app.color.accent') : Color.Transparent)
                .borderRadius(15)
              if (c.dotKind && c.dotColor) {
                Circle()
                  .width(5)
                  .height(5)
                  .fill(c.dotColor)
                  .margin({ top: 2 })
              } else {
                Blank().height(7)
              }
            }
            .width('100%')
            .height(48)
            .justifyContent(FlexAlign.Center)
            .padding({ top: 2, bottom: 2 })
            .onClick(() => this.selectDay(c.y, c.m, c.d))
          }
        }, (c: CalendarMonthCell) => `${year}_${month}_${c.y}-${c.m}-${c.d}-s${c.selected ? 1 : 0}-n${this.uiNonce}`)
      }
      .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr')
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding({ left: PAGE_PAD, right: PAGE_PAD })
    .justifyContent(FlexAlign.Start)
  }

  @Builder
  weekHeaderBar() {
    Row() {
      Blank().width(44)
      ForEach(this.weekHeaders, (h: CalendarWeekHeader) => {
        Column() {
          Text(h.label)
            .fontSize(11)
            .fontColor($r('app.color.secondary_text'))
          Text(h.weekday)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(h.selected ? Color.White : $r('app.color.primary_text'))
            .width(28)
            .height(28)
            .textAlign(TextAlign.Center)
            .backgroundColor(h.selected ? $r('app.color.accent') : Color.Transparent)
            .borderRadius(14)
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .padding({ top: 4, bottom: 4 })
        .onClick(() => this.selectDay(h.y, h.m, h.d))
      }, (h: CalendarWeekHeader) =>
        `wh_${h.y}-${h.m}-${h.d}-s${h.selected ? 1 : 0}-n${this.uiNonce}`)
    }
    .width('100%')
    .padding({ left: WEEK_PAD, right: WEEK_PAD })
    .margin({ bottom: 6 })
  }

  @Builder
  weekTimelineFor(startY: number, startM: number, startD: number) {
    Column() {
      Scroll() {
        this.weekBodyFor(startY, startM, startD)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .padding({ left: WEEK_PAD, right: WEEK_PAD })
  }

  @Builder
  weekBodyFor(startY: number, startM: number, startD: number) {
    Row() {
      Column() {
        ForEach(this.labelsForWeekPage(startY, startM, startD), (lab: string) => {
          Text(lab)
            .fontSize(10)
            .fontColor($r('app.color.secondary_text'))
            .height(HOUR_ROW_HEIGHT)
        }, (lab: string) => `hl_${startY}_${startM}_${startD}_${lab}_${this.uiNonce}`)
      }
      .width(44)

      Stack() {
        // 空白格子点击层：命中事件块几何范围时不做任何处理，
        // 让块本身的 onClick（openWeekExpand）正常处理；其余位置触发新建日程。
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Transparent)
          .onClick((event: ClickEvent) => {
            this.onWeekGridTap(startY, startM, startD, event)
          })

        Column() {
          ForEach(this.labelsForWeekPage(startY, startM, startD), (lab: string) => {
            Divider().color($r('app.color.surface_muted')).height(HOUR_ROW_HEIGHT)
          }, (lab: string) => `line_${startY}_${lab}_${this.uiNonce}`)
        }
        .width('100%')

        ForEach(this.blocksForWeek(startY, startM, startD), (b: CalendarWeekBlockLayout) => {
          Column() {
            Text(b.occurrence.title)
              .fontSize(9)
              .fontWeight(FontWeight.Medium)
              // 标题颜色走 calendarBlockFg，与底色 / 时间 / 左边框 同源；
              // 知识图谱 / 思维导图笔记标题才会正确显示紫色，而不是退化成绿色。
              .fontColor(this.calendarBlockFg(b.occurrence))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
            Text(`${this.hhmm(b.occurrence.anchorMs)}-${this.hhmm(b.occurrence.endMs)}`)
              .fontSize(8)
              .fontColor(this.calendarBlockFg(b.occurrence))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .margin({ top: 1 })
          }
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 3, right: 2, top: 2, bottom: 2 })
          .backgroundColor(this.calendarBlockBg(b.occurrence))
          .clip(true)
          .border({ width: { left: 2 }, color: this.calendarBlockFg(b.occurrence), radius: 4 })
          .width(`${(100 / 7) * b.widthRatio}%`)
          .height(`${b.heightRatio * 100}%`)
          .position({
            x: `${(100 / 7) * (b.dayIndex + b.leftRatio)}%`,
            y: `${b.topRatio * 100}%`
          })
          .onClick(() => {
            this.openWeekExpand(b.occurrence)
          })
        }, (b: CalendarWeekBlockLayout) =>
          `${startY}_${b.occurrence.noteId}_${b.dayIndex}_${b.layer}_${b.occurrence.anchorMs}_${this.uiNonce}`)
      }
      .layoutWeight(1)
      .height(this.labelsForWeekPage(startY, startM, startD).length * HOUR_ROW_HEIGHT)
    }
    .width('100%')
    .height(this.labelsForWeekPage(startY, startM, startD).length * HOUR_ROW_HEIGHT)
  }

  private labelsForWeekPage(startY: number, startM: number, startD: number): string[] {
    const weekStart = new Date(startY, startM - 1, startD)
    const weekItems: CalendarOccurrence[] = []
    for (let i = 0; i < 7; i++) {
      const d = new Date(weekStart)
      d.setDate(weekStart.getDate() + i)
      const list = CalendarProjector.forDay(this.byDay, d.getFullYear(), d.getMonth() + 1, d.getDate())
      for (let j = 0; j < list.length; j++) {
        weekItems.push(list[j])
      }
    }
    return this.hourLabelsForRange(this.displayRangeForItems(weekItems))
  }

  @Builder
  weekDayExpandOverlay() {
    Column() {
      Column() {
        ForEach(this.expandedItems, (o: CalendarOccurrence) => {
          Column() {
            this.dayRow(o)
          }
          .width('100%')
        }, (o: CalendarOccurrence) =>
          `exp_${o.noteId}_${o.anchorMs}_${o.isUpdateOccurrence}_${this.uiNonce}`)
      }
      .width('88%')
      .constraintSize({ maxHeight: '70%' })
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .backgroundColor($r('app.color.card_background'))
      .borderRadius(14)
      .shadow({ radius: 18, color: '#33000000', offsetY: 4 })
      .onClick(() => {
        // 吞掉点击，避免关闭
      })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(Color.Transparent)
    .onClick(() => {
      this.closeWeekExpand()
    })
  }

  private openWeekExpand(tapped: CalendarOccurrence): void {
    const dayItems = CalendarProjector.forDay(
      this.byDay, tapped.dayY, tapped.dayM, tapped.dayD)
    this.expandedItems = CalendarWeekLayout.overlapGroup(tapped, dayItems)
    this.expandedVisible = true
  }

  private closeWeekExpand(): void {
    this.expandedVisible = false
    this.expandedItems = []
  }

  /**
   * 周视图空白格子点击：把点击本地坐标换算成「第几列 + SLOT_MINUTES 对齐的时刻」，
   * 若命中事件块几何范围则忽略（让块自身的 onClick 处理），否则弹出新建日程弹窗。
   * 落地规则见项目 CLAUDE.md「日历日程 / 待办事项 隐藏字段规则」。
   */
  private async onWeekGridTap(
    startY: number,
    startM: number,
    startD: number,
    event: ClickEvent
  ): Promise<void> {
    const px = event.x
    const py = event.y
    if (px < 0 || py < 0) {
      return
    }
    const blocks = this.blocksForWeek(startY, startM, startD)
    const range = this.displayRangeForItems(
      blocks.length > 0 ? blocks.map((b): CalendarOccurrence => b.occurrence) : []
    )
    const stackHeight = this.labelsForWeekPage(startY, startM, startD).length * HOUR_ROW_HEIGHT
    if (stackHeight <= 0) {
      return
    }
    const colWidthRatio = 1 / 7
    // 命中块几何范围时不做任何处理（块自身的 onClick 会处理 openWeekExpand）。
    for (let i = 0; i < blocks.length; i++) {
      const b = blocks[i]
      const leftPct = (100 / 7) * (b.dayIndex + b.leftRatio)
      const topPct = b.topRatio * 100
      const widthPct = (100 / 7) * b.widthRatio
      const heightPct = b.heightRatio * 100
      const left = (leftPct / 100) * this.weekStackWidth
      const top = (topPct / 100) * stackHeight
      const right = left + (widthPct / 100) * this.weekStackWidth
      const bottom = top + (heightPct / 100) * stackHeight
      if (px >= left && px <= right && py >= top && py <= bottom) {
        return
      }
    }
    const dayIndex = Math.max(0, Math.min(6, Math.floor(px / (this.weekStackWidth * colWidthRatio))))
    const hourOffset = Math.max(0,
      Math.min(range.spanHours() - SLOT_MINUTES / 60.0, py / HOUR_ROW_HEIGHT))
    const totalMinutes = Math.floor(
      ((range.startHour * 60 + hourOffset * 60) / SLOT_MINUTES)
    ) * SLOT_MINUTES
    const weekStart = new Date(startY, startM - 1, startD)
    const day = new Date(weekStart)
    day.setDate(weekStart.getDate() + dayIndex)
    day.setHours(0, 0, 0, 0)
    const startMs = day.getTime() + totalMinutes * 60 * 1000
    const endMs = startMs + SLOT_MINUTES * 60 * 1000
    if (this.expandedVisible) {
      this.closeWeekExpand()
    }
    const saved = await showCalendarAddScheduleDialog(this.getUIContext(), {
      startMs,
      endMs
    })
    if (saved) {
      // 落库后强制刷新：与 Flutter PC 端保持一致，避免依赖异步通知。
      await this.reload()
    }
  }

  /**
   * 周视图 Stack 的估算宽度（vp）。
   *
   * 周视图根布局：Scroll(WEEK_PAD 横向 padding) → Row(44px 时辰标签 + Stack)。
   * 这里用「设备宽度 - 标签栏 - 外层 PAGE_PAD*2 - WEEK_PAD*2」近似得到 Stack
   * 的实际可用宽度；与 `event.x` 的本地坐标系保持一致。
   */
  private get weekStackWidth(): number {
    let totalW = 0
    try {
      const dd = display.getDefaultDisplaySync()
      totalW = dd.width
    } catch (_) {
      totalW = 0
    }
    if (totalW <= 0) {
      return 0
    }
    return Math.max(0, totalW - 44 - PAGE_PAD * 2 - WEEK_PAD * 2)
  }

  private blocksForWeek(startY: number, startM: number, startD: number): CalendarWeekBlockLayout[] {
    const weekStart = new Date(startY, startM - 1, startD)
    const weekItems: CalendarOccurrence[] = []
    for (let i = 0; i < 7; i++) {
      const d = new Date(weekStart)
      d.setDate(weekStart.getDate() + i)
      const list = CalendarProjector.forDay(this.byDay, d.getFullYear(), d.getMonth() + 1, d.getDate())
      for (let j = 0; j < list.length; j++) {
        weekItems.push(list[j])
      }
    }
    // 必须与当前小时轴标签同一 range，否则会出现 8:25 画在 6:00 行
    return CalendarWeekLayout.layoutWeek(
      weekStart,
      weekItems,
      this.displayRangeForItems(weekItems)
    )
  }

  private displayRangeForItems(weekItems: CalendarOccurrence[]): CalendarWeekVisibleRange {
    const range = CalendarWeekLayout.visibleRange(weekItems)
    if (this.sheetRatio <= 0.28) {
      if (range.startHour > 6) {
        range.startHour = 6
      }
      if (range.endHour < 22) {
        range.endHour = 22
      }
    }
    return range
  }

  private hourLabelsForRange(range: CalendarWeekVisibleRange): string[] {
    const labels: string[] = []
    for (let h = range.startHour; h < range.endHour; h++) {
      const hh = Math.floor(h)
      labels.push(`${hh < 10 ? '0' : ''}${hh}:00`)
    }
    return labels
  }

  @Builder
  monthGrid() {
    this.monthGridFor(this.visibleYear, this.visibleMonth)
  }

  @Builder
  legendBar() {
    Row() {
      Row() {
        Circle().width(7).height(7).fill(ACCENT)
        Text(LocaleService.loc('有笔记', 'Notes', 'ノートあり'))
          .fontSize(12)
          .fontColor($r('app.color.secondary_text'))
          .margin({ left: 6 })
      }
      Row() {
        // 待办日程 + 待办事项共用黄色（YELLOW）
        Circle().width(7).height(7).fill(YELLOW)
        Text(LocaleService.loc('有日程', 'Events', '予定あり'))
          .fontSize(12)
          .fontColor($r('app.color.secondary_text'))
          .margin({ left: 6 })
      }
      Row() {
        // 思维导图 + 知识图谱共用紫色（PURPLE）
        Circle().width(7).height(7).fill(PURPLE)
        Text(LocaleService.loc('有图谱', 'Graphs', 'グラフあり'))
          .fontSize(12)
          .fontColor($r('app.color.secondary_text'))
          .margin({ left: 6 })
      }
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceEvenly)
    .padding(8)
    .margin({ left: PAGE_PAD, right: PAGE_PAD, top: 8, bottom: 0 })
    .backgroundColor($r('app.color.surface_muted'))
    .borderRadius(10)
  }

  @Builder
  dayRow(o: CalendarOccurrence) {
    Row() {
      Text(this.hhmm(o.anchorMs))
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.dayLeadingColor(o))
        .width(44)
      Column() {
        this.dayLeadingIcon(o)
      }
      .width(34)
      .height(34)
      .borderRadius(8)
      // 列表项取消图标盒子底色，时间与标题颜色统一跟随图标主色（dayLeadingColor）。
      .margin({ right: 10 })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      Column() {
        Text(o.title)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.dayLeadingColor(o))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (o.summary.trim().length > 0) {
          Text(o.summary)
            .fontSize(12)
            .fontColor($r('app.color.secondary_text'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 2 })
        }
        if (o.tags.length > 0) {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(o.tags, (t: string) => {
              Text(`#${t}`)
                .fontSize(11)
                .fontColor($r('app.color.secondary_text'))
                .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                .backgroundColor($r('app.color.surface_muted'))
                .borderRadius(10)
                .margin({ right: 6, top: 4 })
            }, (t: string) => t)
          }
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.thumbUri(o.thumbRelPath).length > 0) {
        Image(this.thumbUri(o.thumbRelPath))
          .width(52)
          .height(40)
          .objectFit(ImageFit.Cover)
          .borderRadius(8)
          .margin({ left: 8 })
      }
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
    .onClick(() => {
      void this.openNote(o.note)
    })
  }

  @Builder
  dayLeadingIcon(o: CalendarOccurrence) {
    if (o.kind === 'todo') {
      // 待办事项：与首页 / 笔记 tab 共用橙色；与首页快捷创建卡「待办事项」入口同图（ic_quick_todo.svg）。
      Image($r('app.media.ic_quick_todo'))
        .width(18)
        .height(18)
        .objectFit(ImageFit.Contain)
        .fillColor($r('app.color.calendar_kind_todo_fg'))
    } else if (o.kind === 'schedule') {
      // 待办日程：与首页 / 笔记 tab 共用 todo 橙（与待办事项完全一致）。
      SymbolGlyph($r('sys.symbol.calendar'))
        .fontSize(18)
        .fontColor([$r('app.color.calendar_kind_todo_fg')])
    } else if (NotesTabLogic.leadingKindFor(o.note, this.mindMapSet()) === 'mp3') {
      // mp3 音频笔记：图标复用笔记统计卡「图谱」旧版（sys.symbol.shareplay），按主题 accent 绿色上色。
      SymbolGlyph($r('sys.symbol.shareplay'))
        .fontSize(18)
        .fontColor([$r('app.color.calendar_kind_note_fg')])
    } else if (NotesTabLogic.leadingKindFor(o.note, this.mindMapSet()) === 'flowchart') {
      // 思维导图：日历 tab 走紫色（与图例 / 标题 / 时间 同源）。
      Image($r('app.media.ic_quick_mindmap'))
        .width(18)
        .height(18)
        .objectFit(ImageFit.Contain)
        .fillColor(PURPLE)
    } else if (NotesTabLogic.leadingKindFor(o.note, this.mindMapSet()) === 'knowledgeGraph') {
      // 知识图谱：日历 tab 走紫色（与图例 / 标题 / 时间 同源）。
      Image($r('app.media.ic_note_knowledge_graph'))
        .width(18)
        .height(18)
        .objectFit(ImageFit.Contain)
        .fillColor(PURPLE)
    } else if (NotesTabLogic.leadingKindFor(o.note, this.mindMapSet()) === 'extract') {
      SymbolGlyph($r('sys.symbol.link'))
        .fontSize(18)
        .fontColor([this.kindColor(o.kind)])
    } else {
      SymbolGlyph($r('sys.symbol.doc_text'))
        .fontSize(18)
        .fontColor([this.kindColor(o.kind)])
    }
  }
}

class CalendarMonthCell {
  y: number = 0
  m: number = 0
  d: number = 0
  inMonth: boolean = true
  selected: boolean = false
  dotKind: CalendarItemKind | null = null
  // 月视图红点的实际颜色（考虑 leadingKind：知识图谱 / 思维导图走紫色）；
  // 为 null 时表示当天没有任何笔记，不渲染红点。
  dotColor: ResourceColor | null = null
}

class CalendarWeekHeader {
  y: number = 0
  m: number = 0
  d: number = 0
  label: string = ''
  weekday: string = ''
  selected: boolean = false
}

class CalendarMonthWindow {
  y: number = 0
  m: number = 0
}

class CalendarWeekWindow {
  y: number = 0
  m: number = 0
  d: number = 0
}
