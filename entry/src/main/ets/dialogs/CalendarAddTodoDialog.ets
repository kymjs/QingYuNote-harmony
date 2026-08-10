import { ComponentContent, UIContext } from '@kit.ArkUI'
import type { Note } from '../common/model/Note'
import { NoteRepository } from '../services/NoteRepository'
import { Logger } from '../common/utils/Logger'
import { LocaleService } from '../common/utils/LocaleService'

export interface CalendarAddTodoDialogOptions {
  /** 默认截止时间戳（毫秒）。为空时取 now + 1h。 */
  initialDueMs?: number
  /** 编辑现有待办时传 noteId。 */
  editingNoteId?: string
}

interface CalendarAddTodoDialogParams {
  title: string
  saving: boolean
  dateLabel: string
  timeLabel: string
  fallbackTitle: string
  onTitleChange: (v: string) => void
  onPickDue: () => void
  onDismiss: (saved: boolean) => void
  onSave: (title: string) => void
}

@Component
export struct CalendarAddTodoDialog {
  @State params: CalendarAddTodoDialogParams = {
    title: '',
    saving: false,
    dateLabel: '',
    timeLabel: '',
    fallbackTitle: '',
    onTitleChange: (_v: string): void => {},
    onPickDue: (): void => {},
    onDismiss: (_b: boolean): void => {},
    onSave: (_t: string): void => {}
  }

  build() {
    Column({ space: 16 }) {
      TextInput({ placeholder: this.params.fallbackTitle, text: this.params.title })
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .placeholderColor($r('app.color.placeholder_color'))
        .placeholderFont({ size: 22 })
        .backgroundColor(Color.Transparent)
        .width('100%')
        .onChange((value: string) => {
          this.params.onTitleChange(value)
        })

      Row({ space: 8 }) {
        Row() {
          Text(this.params.dateLabel)
            .fontSize(15)
            .fontColor($r('app.color.primary_text'))
        }
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .borderRadius(8)
        .backgroundColor($r('app.color.surface_muted'))
        .onClick(() => {
          this.params.onPickDue()
        })

        Row() {
          Text(this.params.timeLabel)
            .fontSize(15)
            .fontColor($r('app.color.primary_text'))
        }
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .borderRadius(8)
        .backgroundColor($r('app.color.surface_muted'))
        .onClick(() => {
          this.params.onPickDue()
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: 12 }) {
        Button(LocaleService.loc('取消', 'Cancel', 'キャンセル'))
          .layoutWeight(1)
          .fontSize($r('app.float.body_font_size'))
          .fontColor($r('app.color.primary_text'))
          .backgroundColor(Color.Transparent)
          .borderRadius($r('app.float.pill_radius'))
          .padding({ top: 12, bottom: 12 })
          .onClick(() => {
            this.params.onDismiss(false)
          })
        Button(LocaleService.loc('保存', 'Save', '保存'))
          .layoutWeight(1)
          .fontSize($r('app.float.body_font_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.accent'))
          .borderRadius($r('app.float.pill_radius'))
          .padding({ top: 12, bottom: 12 })
          .enabled(!this.params.saving)
          .onClick(() => {
            this.params.onSave(this.params.title)
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
    }
    .width('85%')
    .constraintSize({ maxWidth: 560 })
    .padding(20)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(16)
    .shadow({
      radius: 20,
      color: $r('app.color.shadow_color'),
      offsetX: 0,
      offsetY: 4
    })
  }
}

@Builder
export function buildCalendarAddTodoDialogContent(params: CalendarAddTodoDialogParams): void {
  CalendarAddTodoDialog({ params: params })
}

/**
 * 「新建待办」轻量弹窗。收集标题 + 截止日期/时间，
 * 截止前 1 小时作为 startTime（与 CalendarProjector 渲染 1h 色块一致）。
 * 「保存」在本地创建一条 `is_todo=2` 且 tag `Todo` 的笔记，
 * 并把 startTime / endTime（同步到 todoDue）写入笔记隐藏字段。
 *
 * 落地规则见项目 CLAUDE.md「日历日程 / 待办事项 隐藏字段规则」。
 */
export function showCalendarAddTodoDialog(
  uiContext: UIContext,
  options: CalendarAddTodoDialogOptions = {}
): Promise<boolean> {
  return new Promise((resolve) => {
    let holder: ComponentContent<CalendarAddTodoDialogParams> | undefined = undefined
    let state: {
      title: string
      dueMs: number
      saving: boolean
      editingNoteId: string
      existingContent: string
    } = {
      title: '',
      dueMs: options.initialDueMs ?? (Date.now() + 60 * 60 * 1000),
      saving: false,
      editingNoteId: (options.editingNoteId ?? '').trim(),
      existingContent: ''
    }

    const rebuild = (): void => {
      if (holder === undefined) {
        return
      }
      holder.update(buildParams())
    }

    const closeDialog = (saved: boolean): void => {
      if (holder === undefined) {
        return
      }
      try {
        uiContext.getPromptAction().closeCustomDialog(holder)
      } catch (_) {
        // ignore
      }
      resolve(saved)
    }

    const formatDate = (ms: number): string => {
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
    const formatTime = (ms: number): string => {
      const d = new Date(ms)
      const hh = d.getHours() < 10 ? `0${d.getHours()}` : `${d.getHours()}`
      const mm = d.getMinutes() < 10 ? `0${d.getMinutes()}` : `${d.getMinutes()}`
      return `${hh}:${mm}`
    }

    const openPicker = (): void => {
      const base = new Date(state.dueMs)
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
                const candidate = new Date(y, m0, d, hh, mm, 0, 0).getTime()
                // 兜底：截止至少比当前晚 1 分钟。
                const floor = Date.now() + 60 * 1000
                state.dueMs = candidate < floor ? floor : candidate
                rebuild()
              },
              onCancel: (): void => {}
            })
          },
          onCancel: (): void => {}
        })
      } catch (error) {
        Logger.warn('LinkExtractDebug',
          `CalendarAddTodoDialog DatePicker failed: ${JSON.stringify(error)}`)
      }
    }

    const buildParams = (): CalendarAddTodoDialogParams => {
      return {
        title: state.title,
        saving: state.saving,
        dateLabel: formatDate(state.dueMs),
        timeLabel: formatTime(state.dueMs),
        fallbackTitle: LocaleService.loc('待办事项', 'Todo item', 'ToDo'),
        onTitleChange: (v: string): void => {
          state.title = v
        },
        onPickDue: (): void => {
          openPicker()
        },
        onDismiss: (_saved: boolean): void => {
          closeDialog(false)
        },
        onSave: (rawTitle: string): void => {
          if (state.saving) {
            return
          }
          const finalTitle = rawTitle.trim().length > 0
            ? rawTitle.trim()
            : LocaleService.loc('待办事项', 'Todo item', 'ToDo')
          const startMs = Math.max(0, state.dueMs - 60 * 60 * 1000)
          const endMs = state.dueMs
          state.saving = true
          rebuild()
          if (state.editingNoteId.length > 0) {
            // 编辑：仅覆盖标题 / 内容 / 隐藏字段（优先级 / 状态 / 提醒不传，沿用原值）。
            void NoteRepository.getInstance().saveDraft(state.editingNoteId, {
              title: finalTitle,
              content: state.existingContent,
              tags: ['Todo'],
              isTodo: 2,
              startTime: startMs,
              endTime: endMs,
              todoStatus: 0
            }).then(() => {
              closeDialog(true)
            }).catch((error: object) => {
              Logger.warn('LinkExtractDebug',
                `CalendarAddTodoDialog edit failed: ${JSON.stringify(error)}`)
              state.saving = false
              rebuild()
            })
          } else {
            void NoteRepository.getInstance().createNote({
              title: finalTitle,
              content: '',
              tags: ['Todo'],
              isTodo: 2,
              startTime: startMs,
              endTime: endMs,
              todoStatus: 0
            }).then(() => {
              closeDialog(true)
            }).catch((error: object) => {
              Logger.warn('LinkExtractDebug',
                `CalendarAddTodoDialog save failed: ${JSON.stringify(error)}`)
              state.saving = false
              rebuild()
            })
          }
        }
      }
    }

    // 编辑模式：预填标题 / 截止时间 / 原内容。
    if (state.editingNoteId.length > 0) {
      void NoteRepository.getInstance().getNote(state.editingNoteId).then((n: Note | null) => {
        if (n === null) {
          rebuild()
          return
        }
        state.title = n.title ?? ''
        state.existingContent = n.content ?? ''
        const due = (n.endTime ?? 0) > 0 ? n.endTime : (Date.now() + 60 * 60 * 1000)
        state.dueMs = due
        rebuild()
      }).catch((): void => {
        rebuild()
      })
    }

    holder = new ComponentContent(uiContext,
      wrapBuilder(buildCalendarAddTodoDialogContent),
      buildParams())
    try {
      uiContext.getPromptAction().openCustomDialog(holder, {
        alignment: DialogAlignment.Center,
        autoCancel: false,
        isModal: true,
        onWillDismiss: (_: DismissDialogAction) => {
          // 不允许蒙层 / 返回 / 侧滑关闭：只走按钮逻辑。
        }
      })
    } catch (error) {
      console.error(`showCalendarAddTodoDialog failed: ${JSON.stringify(error)}`)
      resolve(false)
    }
  })
}