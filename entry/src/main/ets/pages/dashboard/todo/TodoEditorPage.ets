import router from '@ohos.router'
import { UIContext } from '@kit.ArkUI'
import { Logger } from '../../../common/utils/Logger'
import { MarkdownUtils } from '../../../common/utils/MarkdownUtils'
import { usePcStyleLayoutWithSize } from '../../../common/utils/DesktopLayout'
import { NoteRepository } from '../../../services/NoteRepository'
import { APP_LOCALE_REVISION_KEY, LocaleService } from '../../../services/LocaleService'

interface TodoEditorPageParams {
  noteId?: string
}

interface SubTask {
  title: string
  done: boolean
}

const SUBTASK_OPEN: string = '[ ]'
const SUBTASK_DONE: string = '[-]'

/**
 * 新版首页「待办事项」快捷入口 + 日历周视图 todo 块的「编辑」页。
 *
 * 移动端单列布局，PC / iPad 横屏两列布局（左：标题 / 描述 / 子任务；右：状态 / 优先级 / 日期 / 提醒）。
 * 落地规则与项目 CLAUDE.md「待办事项 / 日程 隐藏字段规则」一致：
 *   * `is_todo=2` + tag `Todo` + `start_time` / `end_time` + `todo_priority` / `todo_status` / `todo_reminder_minutes`
 *   * 子任务用 Markdown checkbox（`[ ]` / `[-]`）写入正文
 *   * 新建时如果标题为空 → 兜底「空主题」；描述为空 → 兜底「暂无描述」
 */
@Entry
@Component
struct TodoEditorPage {
  @StorageProp(APP_LOCALE_REVISION_KEY) localeRevision: number = 0
  @State pageWidth: number = 360
  @State pageHeight: number = 780
  @State title: string = ''
  @State description: string = ''
  @State priority: number = 2
  @State status: number = 0
  @State startMs: number = 0
  @State endMs: number = 0
  @State reminderMinutes: number = 0
  @State subTasks: SubTask[] = []
  @State loading: boolean = true
  @State saving: boolean = false
  @State noteId: string = ''
  @State startDateLabel: string = ''
  @State startTimeLabel: string = ''
  @State endDateLabel: string = ''
  @State endTimeLabel: string = ''
  @State reminderLabel: string = ''

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

  private parseContent(raw: string): { description: string, subTasks: SubTask[] } {
    const lines = (raw ?? '').split('\n')
    const subTasks: SubTask[] = []
    const descLines: string[] = []
    for (const line of lines) {
      const trimmed = line.trim()
      if (MarkdownUtils.isCheckboxLine(trimmed)) {
        const text = MarkdownUtils.checkboxLineText(trimmed)
        const done = MarkdownUtils.isCheckedCheckboxLine(trimmed)
        subTasks.push({ title: text, done: done })
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
    const uiContext: UIContext = this.getUIContext()
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
        onAccept: (value: DatePickerResult) => {
          const y = value.year ?? initialYear
          const m0 = value.month ?? initialMonth
          const d = value.day ?? initialDay
          TimePickerDialog.show({
            selected: { hour: initialHour, minute: initialMinute },
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

  private openReminderPicker(): void {
    const options: number[] = [0, 15, 30, 60, 120, 1440]
    const labels: string[] = options.map((m: number): string => TodoEditorPage.reminderLabel(m))
    try {
      this.getUIContext().showActionSheet({
        title: LocaleService.loc('提醒时间', 'Reminder', 'リマインダー'),
        sheets: labels,
        onSelected: (index: number): void => {
          if (index >= 0 && index < options.length) {
            this.reminderMinutes = options[index]
            this.refreshReminderLabel()
          }
        }
      })
    } catch (e) {
      Logger.warn('LinkExtractDebug', `TodoEditorPage reminder picker failed: ${JSON.stringify(e)}`)
    }
  }

  private async save(completeAfter: boolean): Promise<void> {
    if (this.saving) {
      return
    }
    this.saving = true
    const isNew = this.noteId.length === 0
    try {
      await NoteRepository.getInstance().init()
      const finalTitle = this.title.trim().length > 0
        ? this.title.trim()
        : LocaleService.loc('空主题', 'Untitled', '無題')
      const finalDesc = this.description.trim().length > 0
        ? this.description.trim()
        : LocaleService.loc('暂无描述', 'No description', '説明なし')
      const content = this.buildContent()
      const status = completeAfter ? 1 : this.status
      if (isNew) {
        await NoteRepository.getInstance().createNote({
          title: finalTitle,
          content: content,
          tags: ['Todo'],
          isTodo: 2,
          startTime: this.startMs > 0 ? this.startMs : 0,
          endTime: this.endMs > 0 ? this.endMs : 0,
          todoPriority: this.priority,
          todoStatus: status,
          todoReminderMinutes: this.reminderMinutes
        })
      } else {
        await NoteRepository.getInstance().saveDraft(this.noteId, {
          title: finalTitle,
          content: content,
          tags: ['Todo'],
          isTodo: 2,
          startTime: this.startMs > 0 ? this.startMs : 0,
          endTime: this.endMs > 0 ? this.endMs : 0,
          todoPriority: this.priority,
          todoStatus: status,
          todoReminderMinutes: this.reminderMinutes
        })
      }
      try {
        router.back()
      } catch (_) {
        // 在 iPad 浮窗等场景下可能没有路由栈，忽略
      }
    } catch (e) {
      Logger.warn('LinkExtractDebug', `TodoEditorPage save failed: ${JSON.stringify(e)}`)
      this.saving = false
      try {
        this.getUIContext().getPromptAction().showToast({
          message: LocaleService.loc('保存失败', 'Save failed', '保存に失敗しました'),
          duration: 2000
        })
      } catch (_) {
      }
    }
  }

  private goBack(): void {
    try {
      router.back()
    } catch (_) {
    }
  }

  private addSubTask(): void {
    const next: SubTask[] = [...this.subTasks]
    next.push({ title: '', done: false })
    this.subTasks = next
  }

  private removeSubTask(index: number): void {
    if (index < 0 || index >= this.subTasks.length) {
      return
    }
    const next: SubTask[] = [...this.subTasks]
    next.splice(index, 1)
    this.subTasks = next
  }

  private updateSubTaskTitle(index: number, value: string): void {
    if (index < 0 || index >= this.subTasks.length) {
      return
    }
    const next: SubTask[] = [...this.subTasks]
    next[index] = { title: value, done: next[index].done }
    this.subTasks = next
  }

  private toggleSubTaskDone(index: number): void {
    if (index < 0 || index >= this.subTasks.length) {
      return
    }
    const next: SubTask[] = [...this.subTasks]
    next[index] = { title: next[index].title, done: !next[index].done }
    this.subTasks = next
  }

  build() {
    if (this.loading) {
      Stack() {
        Column() {
          LoadingProgress()
            .width(36)
            .height(36)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.app_background'))
      .onAreaChange((_old, area) => {
        const w = Number(area.width)
        const h = Number(area.height)
        if (w > 0 && h > 0) {
          this.pageWidth = w
          this.pageHeight = h
        }
      })
      return
    }

    const isPc = usePcStyleLayoutWithSize(this.pageWidth, this.pageHeight)

    Stack() {
      Column() {
        this.buildToolbar(isPc)
        if (isPc) {
          Scroll() {
            Row({ space: 24 }) {
              this.buildLeftColumn()
                .layoutWeight(1)
              this.buildRightColumn()
                .width(360)
            }
            .width('100%')
            .padding({ left: 32, right: 32, top: 16, bottom: 32 })
            .alignItems(VerticalAlign.Top)
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
        } else {
          Scroll() {
            Column({ space: 16 }) {
              this.buildTitleField()
              this.buildDescriptionField()
              this.buildStatusField()
              this.buildPriorityField()
              this.buildDateTimeField()
              this.buildSubTaskField()
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 16, bottom: 32 })
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.app_background'))
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_old, area) => {
      const w = Number(area.width)
      const h = Number(area.height)
      if (w > 0 && h > 0) {
        this.pageWidth = w
        this.pageHeight = h
      }
    })
  }

  @Builder
  buildToolbar(isPc: boolean) {
    Row({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.chevron_backward'))
        .fontSize(20)
        .fontColor([$r('app.color.primary_text')])
        .onClick((): void => {
          this.goBack()
        })
      Text(LocaleService.loc('编辑待办', 'Edit Todo', 'タスクを編集'))
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary_text'))
        .layoutWeight(1)
      if (isPc) {
        Button(LocaleService.loc('取消', 'Cancel', 'キャンセル'))
          .fontSize(14)
          .fontColor($r('app.color.primary_text'))
          .backgroundColor(Color.Transparent)
          .borderRadius(16)
          .padding({ left: 14, right: 14, top: 6, bottom: 6 })
          .onClick((): void => {
            this.goBack()
          })
        Button(LocaleService.loc('保存', 'Save', '保存'))
          .fontSize(14)
          .fontColor($r('app.color.primary_text'))
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius(16)
          .padding({ left: 14, right: 14, top: 6, bottom: 6 })
          .enabled(!this.saving)
          .onClick((): void => {
            void this.save(false)
          })
        Button(LocaleService.loc('保存并完成', 'Save & complete', '保存して完了'))
          .fontSize(14)
          .fontColor(Color.White)
          .fontWeight(FontWeight.Medium)
          .backgroundColor($r('app.color.accent'))
          .borderRadius(16)
          .padding({ left: 14, right: 14, top: 6, bottom: 6 })
          .enabled(!this.saving)
          .onClick((): void => {
            void this.save(true)
          })
      } else {
        Button(LocaleService.loc('保存', 'Save', '保存'))
          .fontSize(14)
          .fontColor(Color.White)
          .fontWeight(FontWeight.Medium)
          .backgroundColor($r('app.color.accent'))
          .borderRadius(16)
          .padding({ left: 14, right: 14, top: 6, bottom: 6 })
          .enabled(!this.saving)
          .onClick((): void => {
            void this.save(false)
          })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  buildLeftColumn() {
    Column({ space: 16 }) {
      this.buildTitleField()
      this.buildDescriptionField()
      this.buildSubTaskField()
    }
  }

  @Builder
  buildRightColumn() {
    Column({ space: 16 }) {
      this.buildStatusField()
      this.buildPriorityField()
      this.buildDateTimeField()
    }
  }

  @Builder
  buildTitleField() {
    Column({ space: 8 }) {
      TextInput({ placeholder: LocaleService.loc('添加主题', 'Add title', '件名を追加'), text: this.title })
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .placeholderColor($r('app.color.placeholder_color'))
        .placeholderFont({ size: 24 })
        .backgroundColor(Color.Transparent)
        .width('100%')
        .onChange((value: string): void => {
          this.title = value
        })
    }
    .width('100%')
  }

  @Builder
  buildDescriptionField() {
    Column({ space: 8 }) {
      Row() {
        Text(LocaleService.loc('描述', 'Description', '説明'))
          .fontSize(13)
          .fontColor($r('app.color.secondary_text'))
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
        .backgroundColor($r('app.color.surface_muted'))
        .borderRadius(12)
        .padding(12)
        .width('100%')
        .height(120)
        .maxLength(1000)
        .onChange((value: string): void => {
          this.description = value
        })
    }
    .width('100%')
  }

  @Builder
  buildStatusField() {
    Column({ space: 8 }) {
      Text(LocaleService.loc('状态', 'Status', 'ステータス'))
        .fontSize(13)
        .fontColor($r('app.color.secondary_text'))
      Row({ space: 8 }) {
        this.statusPill(0, LocaleService.loc('进行中', 'In progress', '進行中'))
        this.statusPill(1, LocaleService.loc('已完成', 'Completed', '完了'))
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  statusPill(value: number, label: string) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor(this.status === value ? Color.White : $r('app.color.primary_text'))
    }
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .borderRadius(20)
    .backgroundColor(this.status === value ? $r('app.color.accent') : $r('app.color.surface_muted'))
    .onClick((): void => {
      this.status = value
    })
  }

  @Builder
  buildPriorityField() {
    Column({ space: 8 }) {
      Text(LocaleService.loc('优先级', 'Priority', '優先度'))
        .fontSize(13)
        .fontColor($r('app.color.secondary_text'))
      Row({ space: 8 }) {
        this.priorityPill(1, LocaleService.loc('低', 'Low', '低'))
        this.priorityPill(2, LocaleService.loc('中', 'Medium', '中'))
        this.priorityPill(3, LocaleService.loc('高', 'High', '高'))
        this.priorityPill(4, LocaleService.loc('紧急', 'Urgent', '緊急'))
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  priorityPill(value: number, label: string) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor(this.priority === value ? Color.White : $r('app.color.primary_text'))
    }
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .borderRadius(20)
    .backgroundColor(this.priority === value ? $r('app.color.accent') : $r('app.color.surface_muted'))
    .onClick((): void => {
      this.priority = value
    })
  }

  @Builder
  buildDateTimeField() {
    Column({ space: 8 }) {
      Text(LocaleService.loc('日期与时间', 'Date & time', '日時'))
        .fontSize(13)
        .fontColor($r('app.color.secondary_text'))
      Row({ space: 8 }) {
        Text(LocaleService.loc('开始时间', 'Start time', '開始時間'))
          .fontSize(13)
          .fontColor($r('app.color.secondary_text'))
          .width(64)
      }
      Row({ space: 8 }) {
        this.dateTimePill(this.startDateLabel, (): void => { this.openStartPicker() })
        this.dateTimePill(this.startTimeLabel, (): void => { this.openStartPicker() })
      }
      .width('100%')
      Row({ space: 8 }) {
        Text(LocaleService.loc('截止时间', 'Deadline', '締切'))
          .fontSize(13)
          .fontColor($r('app.color.secondary_text'))
          .width(64)
      }
      Row({ space: 8 }) {
        this.dateTimePill(this.endDateLabel, (): void => { this.openEndPicker() })
        this.dateTimePill(this.endTimeLabel, (): void => { this.openEndPicker() })
      }
      .width('100%')
      Row({ space: 8 }) {
        Text(LocaleService.loc('提醒时间', 'Reminder', 'リマインダー'))
          .fontSize(13)
          .fontColor($r('app.color.secondary_text'))
          .width(64)
      }
      this.dateTimePill(this.reminderLabel, (): void => { this.openReminderPicker() })
    }
    .width('100%')
  }

  @Builder
  dateTimePill(label: string, onTap: () => void) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor($r('app.color.primary_text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .borderRadius(16)
    .backgroundColor($r('app.color.surface_muted'))
    .onClick(onTap)
  }

  @Builder
  buildSubTaskField() {
    Column({ space: 8 }) {
      Row() {
        Text(LocaleService.loc('清单（子任务）', 'Subtasks', 'サブタスク'))
          .fontSize(13)
          .fontColor($r('app.color.secondary_text'))
        Blank()
        Button(LocaleService.loc('添加子任务', 'Add subtask', 'サブタスクを追加'))
          .fontSize(12)
          .fontColor($r('app.color.accent'))
          .backgroundColor(Color.Transparent)
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .onClick((): void => {
            this.addSubTask()
          })
      }
      .width('100%')
      if (this.subTasks.length === 0) {
        Text(LocaleService.loc('暂无子任务', 'No subtasks', 'サブタスクなし'))
          .fontSize(13)
          .fontColor($r('app.color.placeholder_color'))
          .padding({ top: 8, bottom: 8 })
      }
      ForEach(this.subTasks, (item: SubTask, index: number): void => {
        this.subTaskRow(item, index)
      }, (item: SubTask, index: number): string => `${index}_${item.title.length}`)
    }
    .width('100%')
  }

  @Builder
  subTaskRow(item: SubTask, index: number) {
    Row({ space: 8 }) {
      Checkbox({ name: `subtask_${index}`, group: 'subtasks' })
        .select(item.done)
        .selectedColor($r('app.color.accent'))
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
        .onChange((value: string): void => {
          this.updateSubTaskTitle(index, value)
        })
      SymbolGlyph($r('sys.symbol.trash'))
        .fontSize(18)
        .fontColor([$r('app.color.secondary_text')])
        .onClick((): void => {
          this.removeSubTask(index)
        })
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .borderRadius(8)
    .backgroundColor($r('app.color.surface_muted'))
  }
}
