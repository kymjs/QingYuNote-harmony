import router from '@ohos.router'
import { Logger } from '../../../common/utils/Logger'
import { MarkdownUtils } from '../../../common/utils/MarkdownUtils'
import { usePcStyleLayoutWithSize } from '../../../common/utils/DesktopLayout'
import { NoteRepository } from '../../../services/NoteRepository'
import { APP_LOCALE_REVISION_KEY, LocaleService } from '../../../services/LocaleService'

interface TodoEditorPageParams {
  noteId?: string
}

interface ReminderMenuItem {
  value: string
  action: () => void
}

class SubTask {
  title: string = ''
  done: boolean = false

  constructor(title: string = '', done: boolean = false) {
    this.title = title
    this.done = done
  }
}

interface ParsedTodoContent {
  description: string
  subTasks: SubTask[]
}

const SUBTASK_OPEN: string = '[ ]'
const SUBTASK_DONE: string = '[-]'
const AUTO_SAVE_DEBOUNCE_MS: number = 600

/**
 * 新版首页「待办事项」快捷入口 + 日历周视图 todo 块的「编辑」页。
 *
 * 移动端单列布局，PC / iPad 横屏两列布局（左：标题 / 描述 / 子任务；右：状态 / 优先级 / 日期 / 提醒）。
 * 落地规则与项目 CLAUDE.md「待办事项 / 日程 隐藏字段规则」一致：
 *   * `is_todo=2` + tag `Todo` + `start_time` / `end_time` + `todo_priority` / `todo_status` / `todo_reminder_minutes`
 *   * 子任务用 Markdown checkbox（`[ ]` / `[-]`）写入正文
 *   * 新建时如果标题为空 → 兜底「空主题」；描述为空 → 兜底「暂无描述」
 *
 * 自动保存：所有字段变化（含子任务增删 / 完成态切换 / 时间选择 / 状态切换 / 优先级切换）都会触发防抖落库。
 * 无需用户在右上角点保存；退出页面会在 `aboutToDisappear` 中执行最后一次同步保存。
 *
 * 视觉分组：页面拆成 4 张卡片：
 *   1) 标题 + 描述  2) 状态 + 优先级  3) 日期与时间 + 提醒  4) 子任务清单
 * 卡片背景与页面背景同色（白底在浅色模式、暗色卡片在深色模式），靠 1px 边框区分。
 */
@Entry
@Component
struct TodoEditorPage {
  @StorageProp(APP_LOCALE_REVISION_KEY) localeRevision: number = 0
  @State pageWidth: number = 360
  @State pageHeight: number = 780
  @State pcLayout: boolean = false
  @State title: string = ''
  @State description: string = ''
  @State priority: number = 2
  @State status: number = 0
  @State startMs: number = 0
  @State endMs: number = 0
  @State reminderMinutes: number = 0
  @State subTasks: SubTask[] = []
  @State loading: boolean = true
  @State noteId: string = ''
  @State startDateLabel: string = ''
  @State startTimeLabel: string = ''
  @State endDateLabel: string = ''
  @State endTimeLabel: string = ''
  @State reminderLabel: string = ''

  private autoSaveTimer: number = -1
  private dirty: boolean = false
  private leaving: boolean = false
  /** 复用已在飞行的保存任务，让 goBack / aboutToDisappear / 防抖到期共享同一份落库，
   *  避免关闭页面时与 aboutToDisappear 二次触发并发写同一份笔记造成 race。 */
  private flushPromise: Promise<void> | null = null

  aboutToAppear(): void {
    const params = router.getParams() as TodoEditorPageParams
    const incomingNoteId = (params?.noteId ?? '').trim()
    this.noteId = incomingNoteId
    if (incomingNoteId.length > 0) {
      void this.loadExistingNote(incomingNoteId)
    } else {
      this.loading = false
    }
    this.refreshReminderLabel()
    this.refreshDateLabels()
  }

  aboutToDisappear(): void {
    this.leaving = true
    if (this.autoSaveTimer !== -1) {
      clearTimeout(this.autoSaveTimer)
      this.autoSaveTimer = -1
    }
    if (this.dirty) {
      // 兜底：处理「用户未点击返回按钮，而是直接通过系统手势 / 物理返回键 / 路由栈被外部 pop」等
      // 不会经过 goBack() 的退出路径。fire-and-forget，由框架异步等待 Promise。
      // 通常 goBack() 已经 await 过 flushSave，这里大多为 no-op。
      void this.flushSave().catch((e: Error): void => {
        Logger.warn('LinkExtractDebug',
          `TodoEditorPage aboutToDisappear flushSave failed: ${JSON.stringify(e)}`)
      })
    }
  }

  private async loadExistingNote(noteId: string): Promise<void> {
    try {
      await NoteRepository.getInstance().init()
      const note = await NoteRepository.getInstance().getNote(noteId)
      if (note === null) {
        this.loading = false
        return
      }
      const parsed = this.parseContent(note.content)
      this.title = note.title
      this.description = parsed.description
      this.subTasks = parsed.subTasks
      this.priority = note.todoPriority ?? 0
      this.status = note.todoStatus ?? 0
      this.startMs = note.startTime ?? 0
      this.endMs = note.endTime ?? 0
      this.reminderMinutes = note.todoReminderMinutes ?? 0
      this.refreshReminderLabel()
      this.refreshDateLabels()
    } catch (e) {
      Logger.warn('LinkExtractDebug', `TodoEditorPage loadExistingNote failed: ${JSON.stringify(e)}`)
    } finally {
      this.loading = false
    }
  }

  private parseContent(raw: string): ParsedTodoContent {
    const lines = (raw ?? '').split('\n')
    const subTasks: SubTask[] = []
    const descLines: string[] = []
    for (const line of lines) {
      const trimmed = line.trim()
      if (MarkdownUtils.isCheckboxLine(trimmed)) {
        const text = MarkdownUtils.checkboxLineText(trimmed)
        const done = MarkdownUtils.isCheckedCheckboxLine(trimmed)
        subTasks.push(new SubTask(text, done))
      } else {
        descLines.push(line)
      }
    }
    // 去掉首尾空行
    while (descLines.length > 0 && descLines[0].trim().length === 0) {
      descLines.shift()
    }
    while (descLines.length > 0 && descLines[descLines.length - 1].trim().length === 0) {
      descLines.pop()
    }
    return { description: descLines.join('\n'), subTasks: subTasks }
  }

  private buildContent(): string {
    const parts: string[] = []
    if (this.description.trim().length > 0) {
      parts.push(this.description.trim())
    }
    if (this.subTasks.length > 0) {
      const subLines: string[] = []
      for (const t of this.subTasks) {
        const title = t.title.trim()
        if (title.length === 0) {
          continue
        }
        subLines.push(`${t.done ? SUBTASK_DONE : SUBTASK_OPEN} ${title}`)
      }
      if (subLines.length > 0) {
        if (parts.length > 0) {
          parts.push('')
        }
        parts.push(subLines.join('\n'))
      }
    }
    return parts.join('\n')
  }

  private refreshDateLabels(): void {
    if (this.startMs > 0) {
      this.startDateLabel = this.formatDate(this.startMs)
      this.startTimeLabel = this.formatTime(this.startMs)
    } else {
      this.startDateLabel = LocaleService.loc('点击选择', 'Tap to pick', 'タップ')
      this.startTimeLabel = LocaleService.loc('点击选择', 'Tap to pick', 'タップ')
    }
    if (this.endMs > 0) {
      this.endDateLabel = this.formatDate(this.endMs)
      this.endTimeLabel = this.formatTime(this.endMs)
    } else {
      this.endDateLabel = LocaleService.loc('点击选择', 'Tap to pick', 'タップ')
      this.endTimeLabel = LocaleService.loc('点击选择', 'Tap to pick', 'タップ')
    }
  }

  private refreshReminderLabel(): void {
    this.reminderLabel = TodoEditorPage.reminderLabel(this.reminderMinutes)
  }

  private static reminderLabel(minutes: number): string {
    if (minutes <= 0) {
      return LocaleService.loc('不提醒', 'No reminder', 'リマインダーなし')
    }
    if (minutes === 15) {
      return LocaleService.loc('提前 15 分钟', '15 min before', '15分前')
    }
    if (minutes === 30) {
      return LocaleService.loc('提前 30 分钟', '30 min before', '30分前')
    }
    if (minutes === 60) {
      return LocaleService.loc('提前 1 小时', '1 hour before', '1時間前')
    }
    if (minutes === 120) {
      return LocaleService.loc('提前 2 小时', '2 hours before', '2時間前')
    }
    if (minutes === 1440) {
      return LocaleService.loc('提前 1 天', '1 day before', '1日前')
    }
    return LocaleService.loc('不提醒', 'No reminder', 'リマインダーなし')
  }

  private formatDate(ms: number): string {
    const d = new Date(ms)
    const y = d.getFullYear()
    const m = d.getMonth() + 1
    const day = d.getDate()
    return LocaleService.loc(
      `${y}年${m}月${day}日`,
      `${y}-${m < 10 ? '0' : ''}${m}-${day < 10 ? '0' : ''}${day}`,
      `${y}年${m}月${day}日`
    )
  }

  private formatTime(ms: number): string {
    const d = new Date(ms)
    const hh = d.getHours() < 10 ? `0${d.getHours()}` : `${d.getHours()}`
    const mm = d.getMinutes() < 10 ? `0${d.getMinutes()}` : `${d.getMinutes()}`
    return `${hh}:${mm}`
  }

  private openStartPicker(): void {
    this.openDateTimePicker('start', this.startMs)
  }

  private openEndPicker(): void {
    this.openDateTimePicker('end', this.endMs)
  }

  private openDateTimePicker(which: 'start' | 'end', baseMs: number): void {
    const base = baseMs > 0 ? new Date(baseMs) : new Date()
    const initialYear = base.getFullYear()
    const initialMonth = base.getMonth()
    const initialDay = base.getDate()
    const initialHour = base.getHours()
    const initialMinute = base.getMinutes()
    try {
      DatePickerDialog.show({
        start: new Date(initialYear, initialMonth, initialDay),
        selected: new Date(initialYear, initialMonth, initialDay),
        // 高亮选中文字、确认按钮颜色统一用主题绿色（accent），覆盖默认蓝色。
      selectedTextStyle: { color: $r('app.color.accent'), font: { weight: FontWeight.Medium } },
      acceptButtonStyle: { fontColor: $r('app.color.accent'), fontSize: 16 },
      cancelButtonStyle: { fontColor: $r('app.color.secondary_text'), fontSize: 16 },
        onAccept: (value: DatePickerResult) => {
          const y = value.year ?? initialYear
          const m0 = value.month ?? initialMonth
          const d = value.day ?? initialDay
          TimePickerDialog.show({
            selected: new Date(y, m0, d, initialHour, initialMinute, 0, 0),
            selectedTextStyle: { color: $r('app.color.accent'), font: { weight: FontWeight.Medium } },
            acceptButtonStyle: { fontColor: $r('app.color.accent'), fontSize: 16 },
            cancelButtonStyle: { fontColor: $r('app.color.secondary_text'), fontSize: 16 },
            onAccept: (tValue: TimePickerResult) => {
              const hh = tValue.hour ?? initialHour
              const mm = tValue.minute ?? initialMinute
              const next = new Date(y, m0, d, hh, mm, 0, 0).getTime()
              if (which === 'start') {
                this.startMs = next
                if (this.endMs <= this.startMs) {
                  this.endMs = this.startMs + 30 * 60 * 1000
                }
              } else {
                this.endMs = next
                if (this.endMs <= this.startMs) {
                  this.startMs = this.endMs - 30 * 60 * 1000
                  if (this.startMs <= 0) {
                    this.startMs = next
                    this.endMs = next + 30 * 60 * 1000
                  }
                }
              }
              this.refreshDateLabels()
              this.scheduleAutoSave()
            },
            onCancel: (): void => {}
          })
        },
        onCancel: (): void => {}
      })
    } catch (e) {
      Logger.warn('LinkExtractDebug', `TodoEditorPage DatePicker failed: ${JSON.stringify(e)}`)
    }
  }

  /**
   * 构建提醒时间菜单项（与 `DashboardNotesTab` 排序按钮的 `bindMenu` 风格一致：
   * 没有标题/副标题，只有 `value + action`）。
   */
  private reminderMenuItems(): ReminderMenuItem[] {
    const options: number[] = [0, 15, 30, 60, 120, 1440]
    return options.map((minutes: number): ReminderMenuItem => {
      return {
        value: TodoEditorPage.reminderLabel(minutes),
        action: (): void => {
          this.reminderMinutes = minutes
          this.refreshReminderLabel()
          this.scheduleAutoSave()
        }
      }
    })
  }

  /**
   * 触发防抖自动保存。多次连续变更会合并成一次落库，避免每次按键都写一次数据库。
   */
  private scheduleAutoSave(): void {
    if (this.loading) {
      return
    }
    this.dirty = true
    if (this.autoSaveTimer !== -1) {
      clearTimeout(this.autoSaveTimer)
    }
    this.autoSaveTimer = setTimeout((): void => {
      this.autoSaveTimer = -1
      void this.flushSave()
    }, AUTO_SAVE_DEBOUNCE_MS)
  }

  /**
   * 立即执行一次保存；退出页面与防抖到期都会走这里。
   *
   * 共享 in-flight Promise：goBack / 防抖到期 / aboutToDisappear 多次触发时，
   * 复用同一次落库，避免并发写同一份笔记导致的 race（重复 writeNoteFile、
   * bumpVersion 被双触发等）。
   */
  private flushSave(): Promise<void> {
    if (this.flushPromise) {
      return this.flushPromise
    }
    const run = async (): Promise<void> => {
      if (this.loading) {
        return
      }
      const isNew = this.noteId.length === 0
      try {
        await NoteRepository.getInstance().init()
        const finalTitle = this.title.trim().length > 0
          ? this.title.trim()
          : LocaleService.loc('空主题', 'Untitled', '無題')
        const content = this.buildContent()
        let resolvedNoteId: string = this.noteId
        if (isNew) {
          const created = await NoteRepository.getInstance().createNote({
            title: finalTitle,
            content: content,
            tags: ['Todo'],
            isTodo: 2,
            startTime: this.startMs > 0 ? this.startMs : 0,
            endTime: this.endMs > 0 ? this.endMs : 0,
            todoPriority: this.priority,
            todoStatus: this.status,
            todoReminderMinutes: this.reminderMinutes
          })
          resolvedNoteId = created.id ?? ''
          this.noteId = resolvedNoteId
        } else {
          await NoteRepository.getInstance().saveDraft(this.noteId, {
            title: finalTitle,
            content: content,
            tags: ['Todo'],
            isTodo: 2,
            startTime: this.startMs > 0 ? this.startMs : 0,
            endTime: this.endMs > 0 ? this.endMs : 0,
            todoPriority: this.priority,
            todoStatus: this.status,
            todoReminderMinutes: this.reminderMinutes
          })
        }
        this.dirty = false
        // 兜底：直接在 AppStorage 写入一次刷新信号，确保待办 Tab @StorageLink watcher
        // 触发（避免依赖 `appNotesRevision` 在某些时序下被吞的情况）。
        const cur = (AppStorage.get('appShellRefreshNonce') as number | undefined) ?? 0
        AppStorage.setOrCreate('appShellRefreshNonce', cur + 1)
      } catch (e) {
        Logger.warn('LinkExtractDebug', `TodoEditorPage flushSave failed: ${JSON.stringify(e)}`)
        if (!this.leaving) {
          try {
            this.getUIContext().getPromptAction().showToast({
              message: LocaleService.loc('保存失败', 'Save failed', '保存に失敗しました'),
              duration: 2000
            })
          } catch (_) {
          }
        }
      }
    }
    this.flushPromise = run().finally((): void => {
      this.flushPromise = null
    })
    return this.flushPromise
  }

  /**
   * 退出页面：取消防抖定时器，立刻 `router.back()`，让保存与路由返回并行。
   *
   * 历史：`await flushSave()` 之后再 router.back() —— 编辑后立刻返回会被
   * `saveDraft → fsync + 读回校验` 这段 I/O 卡住 100~300ms。
   *
   * 现在：保存以 fire-and-forget 方式起在后台，flushPromise 会被 `aboutToDisappear`
   * 复用同一份，保证不会出现并发落库；同时取消残留的防抖定时器，避免离开页面后
   * setTimeout 回调里再次进入组件状态。
   */
  private goBack(): void {
    this.leaving = true
    if (this.autoSaveTimer !== -1) {
      clearTimeout(this.autoSaveTimer)
      this.autoSaveTimer = -1
    }
    if (this.dirty) {
      // fire-and-forget：保存仍在跑，flushPromise 共享给 aboutToDisappear 复用，
      // 不会重复落盘。flushSave 内部继续推进 bumpVersion / AppStorage 信号，
      // MainShell.onPageShow 触发的 listNotes reload 会拿到最新数据。
      this.flushSave().catch((e: Error): void => {
        Logger.warn('LinkExtractDebug',
          `TodoEditorPage goBack flushSave failed: ${JSON.stringify(e)}`)
      })
    }
    try {
      router.back()
    } catch (_) {
    }
  }

  private addSubTask(): void {
    const next: SubTask[] = [...this.subTasks]
    next.push(new SubTask('', false))
    this.subTasks = next
    this.scheduleAutoSave()
  }

  private removeSubTask(index: number): void {
    if (index < 0 || index >= this.subTasks.length) {
      return
    }
    const next: SubTask[] = [...this.subTasks]
    next.splice(index, 1)
    this.subTasks = next
    this.scheduleAutoSave()
  }

  private updateSubTaskTitle(index: number, value: string): void {
    if (index < 0 || index >= this.subTasks.length) {
      return
    }
    const next: SubTask[] = [...this.subTasks]
    next[index] = new SubTask(value, next[index].done)
    this.subTasks = next
    this.scheduleAutoSave()
  }

  private toggleSubTaskDone(index: number): void {
    if (index < 0 || index >= this.subTasks.length) {
      return
    }
    const next: SubTask[] = [...this.subTasks]
    next[index] = new SubTask(next[index].title, !next[index].done)
    this.subTasks = next
    this.scheduleAutoSave()
  }

  build() {
    Stack() {
      if (this.loading) {
        Column() {
          LoadingProgress()
            .width(36)
            .height(36)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        Column() {
          this.buildToolbar()
          if (this.pcLayout) {
            Scroll() {
              Row({ space: 24 }) {
                Column({ space: 12 }) {
                  this.buildTitleDescriptionCard()
                  this.buildSubTaskCard()
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                Column({ space: 12 }) {
                  this.buildStatusPriorityCard()
                  this.buildDateTimeCard()
                }
                .width(380)
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .padding({ left: 32, right: 32, top: 16, bottom: 32 })
              .alignItems(VerticalAlign.Top)
            }
            .layoutWeight(1)
            .scrollBar(BarState.Off)
          } else {
            Scroll() {
              Column({ space: 12 }) {
                this.buildTitleDescriptionCard()
                this.buildStatusPriorityCard()
                this.buildDateTimeCard()
                this.buildSubTaskCard()
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 16, bottom: 32 })
              .alignItems(HorizontalAlign.Start)
            }
            .layoutWeight(1)
            .scrollBar(BarState.Off)
          }
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.card_background'))
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.card_background'))
    .onAreaChange((_old, area) => {
      const w = Number(area.width)
      const h = Number(area.height)
      if (w > 0 && h > 0) {
        this.pageWidth = w
        this.pageHeight = h
        this.pcLayout = usePcStyleLayoutWithSize(w, h)
      }
    })
  }

  /**
   * 标题栏：与 `pages/About.ets` 保持一致的胶囊返回按钮 + 居左粗体标题样式。
   * 移除了右上角的「保存 / 取消 / 保存并完成」按钮，依赖自动保存落库。
   */
  @Builder
  buildToolbar() {
    Row() {
      Row() {
        SymbolGlyph($r('sys.symbol.arrow_left'))
          .fontSize(18)
          .fontColor([$r('app.color.primary_text')])
      }
      .height('100%')
      .padding({
        left: $r('app.float.toolbar_icon_button_padding_h'),
        right: $r('app.float.toolbar_icon_button_padding_h')
      })
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r('app.color.surface_muted'))
      .borderRadius($r('app.float.pill_radius'))
      .onClick((): void => {
        this.goBack()
      })

      Row() {
        Text(LocaleService.loc('编辑待办', 'Edit Todo', 'タスクを編集'))
          .fontSize($r('app.float.title_font_size'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
          .textAlign(TextAlign.Start)
      }
      .layoutWeight(1)
      .height('100%')
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Start)
      .padding({ left: 12 })
    }
    .width('100%')
    .height($r('app.float.toolbar_height'))
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('app.color.card_background'))
  }

  /**
   * 卡片 1：标题 + 描述。
   * 整张卡用 1px 边框包裹；标题 TextInput 顶部、描述 TextArea 底部，两者之间用 Divider 分隔。
   */
  @Builder
  buildTitleDescriptionCard() {
    Column() {
      this.buildTitleField()
      Divider()
        .color($r('app.color.divider'))
        .strokeWidth(1)
        .width('100%')
      this.buildDescriptionField()
    }
    .width('100%')
    .padding(12)
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 1, color: $r('app.color.card_border') })
    .alignItems(HorizontalAlign.Start)
  }

  /**
   * 卡片 2：状态 + 优先级。
   */
  @Builder
  buildStatusPriorityCard() {
    Column({ space: 12 }) {
      Column({ space: 8 }) {
        Text(LocaleService.loc('状态', 'Status', 'ステータス'))
          .fontSize(13)
          .fontColor($r('app.color.secondary_text'))
          .width('100%')
          .textAlign(TextAlign.Start)
        Row({ space: 8 }) {
          // 每个状态按钮占约 1/2 宽度。
          this.statusPill(0, LocaleService.loc('进行中', 'In progress', '進行中'))
          this.statusPill(1, LocaleService.loc('已完成', 'Completed', '完了'))
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Divider()
        .color($r('app.color.divider'))
        .strokeWidth(1)
        .width('100%')

      Column({ space: 8 }) {
        Text(LocaleService.loc('优先级', 'Priority', '優先度'))
          .fontSize(13)
          .fontColor($r('app.color.secondary_text'))
          .width('100%')
          .textAlign(TextAlign.Start)
        Row({ space: 8 }) {
          // 顺序：低、中、高、急。
          this.priorityImagePill(1, 'ic_todo_priority_low', LocaleService.loc('低', 'Low', '低'))
          this.priorityImagePill(2, 'ic_todo_priority_medium', LocaleService.loc('中', 'Medium', '中'))
          this.priorityImagePill(3, 'ic_todo_priority_high', LocaleService.loc('高', 'High', '高'))
          this.priorityImagePill(4, 'ic_todo_priority_urgent', LocaleService.loc('紧急', 'Urgent', '緊急'))
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(12)
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 1, color: $r('app.color.card_border') })
    .alignItems(HorizontalAlign.Start)
  }

  /**
   * 卡片 3：日期与时间 + 提醒时间。
   * 每行采用「左侧标签 + 右侧 value + icon」布局，行间用 Divider 分隔。
   */
  @Builder
  buildDateTimeCard() {
    Column() {
      this.buildDateRow(
        LocaleService.loc('开始时间', 'Start time', '開始時間'),
        this.startDateLabel,
        this.startTimeLabel,
        (): void => { this.openStartPicker() }
      )
      Divider()
        .color($r('app.color.divider'))
        .strokeWidth(1)
        .width('100%')
      this.buildDateRow(
        LocaleService.loc('截止时间', 'Deadline', '締切'),
        this.endDateLabel,
        this.endTimeLabel,
        (): void => { this.openEndPicker() }
      )
      Divider()
        .color($r('app.color.divider'))
        .strokeWidth(1)
        .width('100%')
      this.buildReminderRow(
        LocaleService.loc('提醒时间', 'Reminder', 'リマインダー'),
        this.reminderLabel
      )
    }
    .width('100%')
    .padding(4)
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 1, color: $r('app.color.card_border') })
    .alignItems(HorizontalAlign.Start)
  }

  /**
   * 卡片 4：子任务清单。
   */
  @Builder
  buildSubTaskCard() {
    Column({ space: 8 }) {
      Row() {
        Text(LocaleService.loc('清单（子任务）', 'Subtasks', 'サブタスク'))
          .fontSize(13)
          .fontColor($r('app.color.secondary_text'))
          .textAlign(TextAlign.Start)
        Blank()
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(14)
            .fontColor([$r('app.color.accent')])
          Text(LocaleService.loc('添加子任务', 'Add subtask', 'サブタスクを追加'))
            .fontSize(13)
            .fontColor($r('app.color.accent'))
        }
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .onClick((): void => {
          this.addSubTask()
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.subTasks.length === 0) {
        Text(LocaleService.loc('暂无子任务', 'No subtasks', 'サブタスクなし'))
          .fontSize(13)
          .fontColor($r('app.color.placeholder_color'))
          .padding({ top: 8, bottom: 8 })
          .textAlign(TextAlign.Start)
      }
      ForEach(this.subTasks, (item: SubTask, index: number): void => {
        this.subTaskRow(item, index)
      }, (item: SubTask, index: number): string => `${index}_${item.title.length}`)
    }
    .width('100%')
    .padding(12)
    .borderRadius(12)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 1, color: $r('app.color.card_border') })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  buildTitleField() {
    TextInput({ placeholder: LocaleService.loc('添加主题', 'Add title', '件名を追加'), text: this.title })
      .fontSize(22)
      .fontWeight(FontWeight.Bold)
      .fontColor($r('app.color.primary_text'))
      .placeholderColor($r('app.color.placeholder_color'))
      .placeholderFont({ size: 22 })
      .backgroundColor(Color.Transparent)
      .width('100%')
      .textAlign(TextAlign.Start)
      .padding({ top: 4, bottom: 4 })
      .onChange((value: string): void => {
        this.title = value
        this.scheduleAutoSave()
      })
  }

  @Builder
  buildDescriptionField() {
    Column({ space: 8 }) {
      Row() {
        Text(LocaleService.loc('描述', 'Description', '説明'))
          .fontSize(13)
          .fontColor($r('app.color.secondary_text'))
          .textAlign(TextAlign.Start)
        Blank()
        Text(`${this.description.length}/1000`)
          .fontSize(12)
          .fontColor($r('app.color.secondary_text'))
      }
      .width('100%')
      TextArea({ placeholder: LocaleService.loc('添加描述', 'Add description', '説明を追加'), text: this.description })
        .fontSize(14)
        .fontColor($r('app.color.primary_text'))
        .placeholderColor($r('app.color.placeholder_color'))
        .backgroundColor(Color.Transparent)
        .borderRadius(8)
        .padding(8)
        .width('100%')
        .height(120)
        .maxLength(1000)
        .onChange((value: string): void => {
          this.description = value
          this.scheduleAutoSave()
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  statusPill(value: number, label: string) {
    Row() {
      SymbolGlyph(value === 0 ? $r('sys.symbol.play') : $r('sys.symbol.checkmark'))
        .fontSize(16)
        .fontColor([this.status === value ? $r('app.color.accent') : $r('app.color.secondary_text')])
      Text(label)
        .fontSize(14)
        .fontColor(this.status === value ? $r('app.color.accent') : $r('app.color.primary_text'))
        .margin({ left: 6 })
    }
    .layoutWeight(1)
    .height(44)
    .padding({ left: 14, right: 14 })
    .borderRadius(22)
    .backgroundColor($r('app.color.card_background'))
    .border({
      width: 1,
      color: this.status === value ? $r('app.color.accent') : $r('app.color.card_border')
    })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .onClick((): void => {
      this.status = value
      this.scheduleAutoSave()
    })
  }

  @Builder
  priorityImagePill(value: number, assetName: string, semanticLabel: string) {
    Row() {
      Image($r(`app.media.${assetName}`))
        .width(28)
        .height(28)
        .objectFit(ImageFit.Contain)
        .accessibilityText(semanticLabel)
    }
    .layoutWeight(1)
    .height(44)
    .padding({ left: 8, right: 8 })
    .borderRadius(22)
    .backgroundColor(this.priority === value ? Color.Transparent : $r('app.color.card_background'))
    .border({
      width: this.priority === value ? 2 : 1,
      color: this.priority === value ? $r('app.color.accent') : $r('app.color.card_border')
    })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .onClick((): void => {
      this.priority = value
      this.scheduleAutoSave()
    })
  }

  @Builder
  buildDateRow(label: string, dateLabel: string, timeLabel: string, onTap: () => void) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor($r('app.color.secondary_text'))
      Blank()
      Text(`${dateLabel}  ${timeLabel}`)
        .fontSize(14)
        .fontColor($r('app.color.primary_text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      SymbolGlyph($r('sys.symbol.calendar'))
        .fontSize(18)
        .fontColor([$r('app.color.secondary_text')])
        .margin({ left: 8 })
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 12, bottom: 12 })
    .alignItems(VerticalAlign.Center)
    .onClick(onTap)
  }

  @Builder
  buildReminderRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor($r('app.color.secondary_text'))
      Blank()
      // 把 bindMenu 挂在「value + chevron」这个子 Row 上，菜单锚点对齐下拉箭头，
      // 第一个选项「不提醒」会直接出现在 chevron 正上方，而不是整个外层 Row 的中点。
      Row({ space: 4 }) {
        Text(value)
          .fontSize(14)
          .fontColor($r('app.color.primary_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(16)
          .fontColor([$r('app.color.secondary_text')])
      }
      .alignItems(VerticalAlign.Center)
      .padding({ left: 8, right: 4, top: 4, bottom: 4 })
      .bindMenu(this.reminderMenuItems())
    }
    .width('100%')
    .padding({ left: 8, right: 4, top: 12, bottom: 12 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  subTaskRow(item: SubTask, index: number) {
    Row({ space: 8 }) {
      Checkbox({ name: `subtask_${index}`, group: 'subtasks' })
        .select(item.done)
        .selectedColor($r('app.color.accent'))
        .width(20)
        .height(20)
        .onChange((value: boolean): void => {
          if (item.done !== value) {
            this.toggleSubTaskDone(index)
          }
        })
      TextInput({ placeholder: LocaleService.loc('子任务', 'Subtask', 'サブタスク'), text: item.title })
        .fontSize(14)
        .fontColor($r('app.color.primary_text'))
        .placeholderColor($r('app.color.placeholder_color'))
        .backgroundColor(Color.Transparent)
        .layoutWeight(1)
        .padding({ left: 4, right: 4 })
        .onChange((value: string): void => {
          this.updateSubTaskTitle(index, value)
        })
      SymbolGlyph($r('sys.symbol.trash'))
        .fontSize(18)
        .fontColor([$r('app.color.tertiary_text')])
        .onClick((): void => {
          this.removeSubTask(index)
        })
    }
    .width('100%')
    .padding({ left: 4, right: 4, top: 6, bottom: 6 })
    .alignItems(VerticalAlign.Center)
  }
}