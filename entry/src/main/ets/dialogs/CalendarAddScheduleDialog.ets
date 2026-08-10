import { ComponentContent, UIContext } from '@kit.ArkUI'
import { NoteRepository } from '../services/NoteRepository'
import { Logger } from '../common/utils/Logger'
import { LocaleService } from '../common/utils/LocaleService'

export interface CalendarAddScheduleDialogOptions {
  startMs: number
  endMs: number
}

export interface CalendarAddScheduleDialogParams {
  startMs: number
  endMs: number
  title: string
  description: string
  saving: boolean
  fallbackTitle: string
  fallbackDescription: string
  dateLabel: (ts: number) => string
  timeLabel: (ts: number) => string
  /** 编辑开始 / 结束时间。 */
  onPickStart: () => void
  onPickEnd: () => void
  /** 关闭弹窗，参数表示是否已落库成功。 */
  onDismiss: (saved: boolean) => void
  /** 设置标题 / 描述文本。 */
  onTitleChange: (v: string) => void
  onDescriptionChange: (v: string) => void
  /** 点击保存：参数为最终标题 / 描述 / 开始时间 / 结束时间。 */
  onSave: (title: string, description: string, startMs: number, endMs: number) => void
}

@Component
export struct CalendarAddScheduleDialog {
  @State params: CalendarAddScheduleDialogParams = {
    startMs: 0,
    endMs: 0,
    title: '',
    description: '',
    saving: false,
    fallbackTitle: '',
    fallbackDescription: '',
    dateLabel: (_n: number): string => '',
    timeLabel: (_n: number): string => '',
    onPickStart: (): void => {},
    onPickEnd: (): void => {},
    onDismiss: (_b: boolean): void => {},
    onTitleChange: (_v: string): void => {},
    onDescriptionChange: (_v: string): void => {},
    onSave: (_t: string, _d: string, _s: number, _e: number): void => {}
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
        this.pillButton(this.params.dateLabel(this.params.startMs), this.params.onPickStart)
        this.pillButton(this.params.timeLabel(this.params.startMs), this.params.onPickStart)
        Text('—')
          .fontSize(15)
          .fontColor($r('app.color.secondary_text'))
        this.pillButton(this.params.timeLabel(this.params.endMs), this.params.onPickEnd)
        this.pillButton(this.params.dateLabel(this.params.endMs), this.params.onPickEnd)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      TextArea({ placeholder: this.params.fallbackDescription, text: this.params.description })
        .fontSize(14)
        .fontColor($r('app.color.primary_text'))
        .placeholderColor($r('app.color.placeholder_color'))
        .backgroundColor(Color.Transparent)
        .width('100%')
        .height(120)
        .onChange((value: string) => {
          this.params.onDescriptionChange(value)
        })

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
            this.params.onSave(
              this.params.title,
              this.params.description,
              this.params.startMs,
              this.params.endMs
            )
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

  @Builder
  pillButton(label: string, onTap: () => void) {
    Row() {
      Text(label)
        .fontSize(15)
        .fontColor($r('app.color.primary_text'))
    }
    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
    .borderRadius(8)
    .backgroundColor($r('app.color.surface_muted'))
    .onClick(onTap)
  }
}

@Builder
export function buildCalendarAddScheduleDialogContent(params: CalendarAddScheduleDialogParams): void {
  CalendarAddScheduleDialog({ params: params })
}

/**
 * 点击日历周视图空白格子时弹出。收集主题 / 描述 / 起止时间，
 * 「保存」在本地创建一条 `is_todo=1` 且 tag `Schedule` 的笔记，
 * 并把开始 / 结束时间戳写入笔记隐藏字段 (`start_time` / `end_time`)。
 *
 * 落地规则见项目 CLAUDE.md「日历日程 / 待办事项 隐藏字段规则」。
 */
export function showCalendarAddScheduleDialog(
  uiContext: UIContext,
  options: CalendarAddScheduleDialogOptions
): Promise<boolean> {
  return new Promise((resolve) => {
    let holder: ComponentContent<CalendarAddScheduleDialogParams> | undefined = undefined
    let state: {
      title: string
      description: string
      startMs: number
      endMs: number
      saving: boolean
    } = {
      title: '',
      description: '',
      startMs: options.startMs,
      endMs: options.endMs,
      saving: false
    }

    const rebuild = (): void => {
      if (holder === undefined) {
        return
      }
      holder.update(buildCalendarAddScheduleDialogParams())
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

    const openPicker = (which: 'start' | 'end'): void => {
      const baseMs = which === 'start' ? state.startMs : state.endMs
      const base = new Date(baseMs)
      const initialYear = base.getFullYear()
      const initialMonth = base.getMonth()
      const initialDay = base.getDate()
      const initialHour = base.getHours()
      const initialMinute = base.getMinutes()
      // ArkUI DatePickerDialog：先选日期，再串接 TimePickerDialog 选时间。
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
                  const span = state.endMs - state.startMs
                  state.startMs = next
                  if (span > 0) {
                    state.endMs = next + span
                  } else {
                    state.endMs = next + 30 * 60 * 1000
                  }
                } else {
                  state.endMs = next
                  if (state.endMs <= state.startMs) {
                    state.endMs = state.startMs + 30 * 60 * 1000
                  }
                }
                rebuild()
              },
              onCancel: (): void => {}
            })
          },
          onCancel: (): void => {}
        })
      } catch (error) {
        Logger.warn('LinkExtractDebug',
          `CalendarAddSchedule DatePicker failed: ${JSON.stringify(error)}`)
      }
    }

    const buildCalendarAddScheduleDialogParams = (): CalendarAddScheduleDialogParams => {
      return {
        startMs: state.startMs,
        endMs: state.endMs,
        title: state.title,
        description: state.description,
        saving: state.saving,
        fallbackTitle: LocaleService.loc('添加主题', 'Add title', '件名を追加'),
        fallbackDescription: LocaleService.loc('添加描述', 'Add description', '説明を追加'),
        dateLabel: formatDate,
        timeLabel: formatTime,
        onPickStart: (): void => { openPicker('start') },
        onPickEnd: (): void => { openPicker('end') },
        onDismiss: (_saved: boolean): void => { closeDialog(false) },
        onTitleChange: (v: string): void => {
          state.title = v
        },
        onDescriptionChange: (v: string): void => {
          state.description = v
        },
        onSave: (rawTitle: string, rawDesc: string, startMs: number, endMs: number): void => {
          if (state.saving) {
            return
          }
          const finalTitle = rawTitle.trim().length > 0
            ? rawTitle.trim()
            : LocaleService.loc('空主题', 'Untitled', '無題')
          const finalDesc = rawDesc.trim().length > 0
            ? rawDesc.trim()
            : LocaleService.loc('暂无描述', 'No description', '説明なし')
          if (endMs <= startMs) {
            state.endMs = startMs + 30 * 60 * 1000
          }
          state.saving = true
          rebuild()
          void NoteRepository.getInstance().createNote({
            title: finalTitle,
            content: finalDesc,
            tags: ['Schedule'],
            isTodo: 1,
            startTime: state.startMs,
            endTime: state.endMs
          }).then(() => {
            closeDialog(true)
          }).catch((error: object) => {
            Logger.warn('LinkExtractDebug',
              `CalendarAddScheduleDialog save failed: ${JSON.stringify(error)}`)
            state.saving = false
            rebuild()
          })
        }
      }
    }

    holder = new ComponentContent(uiContext,
      wrapBuilder(buildCalendarAddScheduleDialogContent),
      buildCalendarAddScheduleDialogParams())
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
      console.error(`showCalendarAddScheduleDialog failed: ${JSON.stringify(error)}`)
      resolve(false)
    }
  })
}