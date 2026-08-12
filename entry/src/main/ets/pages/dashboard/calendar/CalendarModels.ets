import type { Note } from '../../../common/model/Note'

export type CalendarItemKind = 'note' | 'todo' | 'schedule'
export type CalendarViewMode = 'month' | 'week'
export type CalendarChipFilter = 'all' | 'note' | 'todo' | 'graph'
export type CalendarYearMonthPickerMode = 'month' | 'year'

export class CalendarOccurrence {
  noteId: string = ''
  note: Note = {} as Note
  kind: CalendarItemKind = 'note'
  anchorMs: number = 0
  endMs: number = 0
  dayY: number = 0
  dayM: number = 0
  dayD: number = 0
  title: string = ''
  summary: string = ''
  tags: string[] = []
  isUpdateOccurrence: boolean = false
  noteCreatedAt: number = 0
  thumbRelPath: string = ''
}

export class CalendarDayCounts {
  // 保留 all（全部）+ 取消 schedule 单独计数（与 todo 合并）；
  // 新增 graph（思维导图 + 知识图谱 合并）。
  all: number = 0
  note: number = 0
  todo: number = 0
  graph: number = 0
}

export class CalendarWeekBlockLayout {
  occurrence: CalendarOccurrence = new CalendarOccurrence()
  dayIndex: number = 0
  topRatio: number = 0
  heightRatio: number = 0
  leftRatio: number = 0
  widthRatio: number = 0
  layer: number = 0
}

export class CalendarWeekVisibleRange {
  startHour: number = 9
  endHour: number = 19

  spanHours(): number {
    const span = this.endHour - this.startHour
    if (span < 1) {
      return 1
    }
    if (span > 48) {
      return 48
    }
    return span
  }
}
