import type { Note } from '../../../common/model/Note'
import { NotesTabLogic } from '../DashboardNotesModels'
import {
  CalendarChipFilter,
  CalendarDayCounts,
  CalendarItemKind,
  CalendarOccurrence
} from './CalendarModels'

export class CalendarProjector {
  static readonly DURATION_MS: number = 60 * 60 * 1000

  static dayKey(y: number, m: number, d: number): string {
    const mm = m < 10 ? `0${m}` : `${m}`
    const dd = d < 10 ? `0${d}` : `${d}`
    return `${y}-${mm}-${dd}`
  }

  static dayKeyFromMs(ms: number): string {
    const dt = new Date(ms)
    return CalendarProjector.dayKey(dt.getFullYear(), dt.getMonth() + 1, dt.getDate())
  }

  static classify(note: Note): CalendarItemKind {
    // 日程：is_todo=1（新版日历视图创建）；保留原 0/1 语义不变。
    if ((note.isTodo ?? 0) === 1) {
      return 'schedule'
    }
    // 待办事项：is_todo=2（新版首页快捷创建）。
    if ((note.isTodo ?? 0) === 2) {
      return 'todo'
    }
    // 兼容旧版：tag 命中 `Todo` 时视为待办。
    for (let i = 0; i < note.tags.length; i++) {
      if (`${note.tags[i]}`.trim() === 'Todo') {
        return 'todo'
      }
    }
    return 'note'
  }

  static shouldInclude(note: Note): boolean {
    if (note.deleted || note.deletedTime !== 0) {
      return false
    }
    if (note.isConflict !== 0) {
      return false
    }
    return true
  }

  static projectNotes(notes: Note[]): CalendarOccurrence[] {
    const out: CalendarOccurrence[] = []
    for (let i = 0; i < notes.length; i++) {
      const list = CalendarProjector.projectNote(notes[i])
      for (let j = 0; j < list.length; j++) {
        out.push(list[j])
      }
    }
    return out
  }

  static projectNote(note: Note): CalendarOccurrence[] {
    if (!CalendarProjector.shouldInclude(note)) {
      return []
    }
    const kind = CalendarProjector.classify(note)
    const title = note.title.trim().length > 0 ? note.title.trim() : '无标题'
    let summary = note.summary.trim()
    if (summary.length === 0) {
      summary = note.content.trim().replace(/\s+/g, ' ')
    }
    const thumb = note.imageRefs.length > 0 ? note.imageRefs[0] : ''
    const isTodo = note.isTodo ?? 0

    // 日程（is_todo=1）：直接用 startTime / endTime 作为锚点。
    if (isTodo === 1 && note.startTime > 0 && note.endTime > note.startTime) {
      const dt = new Date(note.startTime)
      return [
        CalendarProjector.makeOcc(
          note, kind, title, summary, thumb,
          note.startTime, note.endTime,
          dt.getFullYear(), dt.getMonth() + 1, dt.getDate(),
          false)
      ]
    }

    // 待办事项（is_todo=2）：todoDue 作为结束时间，向前 1h 作为开始时间；
    // 这样日程表上的待办色块固定为 1 小时。
    if (isTodo === 2 && note.todoDue > 0) {
      const todoDurationMs = 60 * 60 * 1000
      const end = note.todoDue
      const start = end - todoDurationMs
      const dt = new Date(end)
      return [
        CalendarProjector.makeOcc(
          note, kind, title, summary, thumb,
          start, end,
          dt.getFullYear(), dt.getMonth() + 1, dt.getDate(),
          false)
      ]
    }

    // 普通笔记：仍以 createdAt / updatedAt 作为锚点（同日则单点，跨日则两点）。
    const createdKey = CalendarProjector.dayKeyFromMs(note.createdAt)
    const updatedKey = CalendarProjector.dayKeyFromMs(note.updatedAt)
    if (createdKey === updatedKey) {
      return [
        CalendarProjector.makeOcc(
          note, kind, title, summary, thumb,
          note.createdAt, undefined, undefined, undefined, undefined,
          false)
      ]
    }
    return [
      CalendarProjector.makeOcc(
        note, kind, title, summary, thumb,
        note.createdAt, undefined, undefined, undefined, undefined,
        false),
      CalendarProjector.makeOcc(
        note, kind, title, summary, thumb,
        note.updatedAt, undefined, undefined, undefined, undefined,
        true)
    ]
  }

  private static makeOcc(
    note: Note,
    kind: CalendarItemKind,
    title: string,
    summary: string,
    thumb: string,
    anchorMs: number,
    endMs: number | undefined,
    dayY: number | undefined,
    dayM: number | undefined,
    dayD: number | undefined,
    isUpdate: boolean
  ): CalendarOccurrence {
    const dt = new Date(anchorMs)
    const o = new CalendarOccurrence()
    o.noteId = note.id
    o.note = note
    o.kind = kind
    o.anchorMs = anchorMs
    o.endMs = endMs !== undefined ? endMs : (anchorMs + CalendarProjector.DURATION_MS)
    o.dayY = dayY !== undefined ? dayY : dt.getFullYear()
    o.dayM = dayM !== undefined ? dayM : dt.getMonth() + 1
    o.dayD = dayD !== undefined ? dayD : dt.getDate()
    o.title = title
    o.summary = summary
    o.tags = [...note.tags]
    o.isUpdateOccurrence = isUpdate
    o.noteCreatedAt = note.createdAt
    o.thumbRelPath = thumb
    return o
  }

  static indexByDay(all: CalendarOccurrence[]): Map<string, CalendarOccurrence[]> {
    const map = new Map<string, CalendarOccurrence[]>()
    for (let i = 0; i < all.length; i++) {
      const o = all[i]
      const key = CalendarProjector.dayKey(o.dayY, o.dayM, o.dayD)
      let list = map.get(key)
      if (!list) {
        list = []
        map.set(key, list)
      }
      list.push(o)
    }
    map.forEach((list: CalendarOccurrence[], _key: string) => {
      list.sort((a: CalendarOccurrence, b: CalendarOccurrence) => {
        if (a.anchorMs !== b.anchorMs) {
          return a.anchorMs - b.anchorMs
        }
        return a.noteId.localeCompare(b.noteId)
      })
    })
    return map
  }

  static forDay(index: Map<string, CalendarOccurrence[]>, y: number, m: number, d: number): CalendarOccurrence[] {
    const list = index.get(CalendarProjector.dayKey(y, m, d))
    return list ? [...list] : []
  }

  static filterChip(items: CalendarOccurrence[], filter: CalendarChipFilter,
    mindMapSet: Set<string>): CalendarOccurrence[] {
    // 「全部」直接放行。
    if (filter === 'all') {
      return items
    }
    const out: CalendarOccurrence[] = []
    for (let i = 0; i < items.length; i++) {
      const o = items[i]
      // 待办 = 待办事项 + 待办日程（合并）
      if (filter === 'todo') {
        if (o.kind === 'todo' || o.kind === 'schedule') {
          out.push(o)
        }
        continue
      }
      // 图谱 = 思维导图 + 知识图谱（按 leadingKind 过滤）
      if (filter === 'graph') {
        if (o.kind === 'note' && CalendarProjector.isGraphNote(o.note, mindMapSet)) {
          out.push(o)
        }
        continue
      }
      // 笔记 = 普通 note（非图谱）
      if (filter === 'note') {
        if (o.kind === 'note' && !CalendarProjector.isGraphNote(o.note, mindMapSet)) {
          out.push(o)
        }
        continue
      }
    }
    return out
  }

  /**
   * 是否为「图谱」笔记：思维导图 + 知识图谱。
   * 直接复用 `NotesTabLogic.leadingKindFor` 的判定结果（思维导图 = `flowchart`，
   * 知识图谱 = `knowledgeGraph`），保证图谱筛选与首页 / 笔记 tab 的列表着色同源同语义。
   * 知识图谱的真正判定是 `note.type_ === NOTE_TYPE_FLOWCHART` 且不在 `mindMapNoteIds`
   * 集合里 —— 不能简单靠 tag 命中，否则知识图谱会被漏掉。
   */
  private static isGraphNote(note: Note, mindMapSet: Set<string>): boolean {
    const lk = NotesTabLogic.leadingKindFor(note, mindMapSet)
    return lk === 'flowchart' || lk === 'knowledgeGraph'
  }

  static countsFor(items: CalendarOccurrence[], mindMapSet: Set<string>): CalendarDayCounts {
    const c = new CalendarDayCounts()
    c.all = items.length
    for (let i = 0; i < items.length; i++) {
      const o = items[i]
      // 待办 = 待办事项 + 待办日程
      if (o.kind === 'todo' || o.kind === 'schedule') {
        c.todo += 1
        continue
      }
      // kind === 'note'：进一步拆分图谱 vs 普通笔记
      if (CalendarProjector.isGraphNote(o.note, mindMapSet)) {
        c.graph += 1
      } else {
        c.note += 1
      }
    }
    return c
  }

  static dayDotKind(items: CalendarOccurrence[]): CalendarItemKind | null {
    if (items.length === 0) {
      return null
    }
    for (let i = 0; i < items.length; i++) {
      if (items[i].kind === 'schedule') {
        return 'schedule'
      }
    }
    for (let i = 0; i < items.length; i++) {
      if (items[i].kind === 'todo') {
        return 'todo'
      }
    }
    return 'note'
  }

  static startOfWeekSunday(y: number, m: number, d: number): Date {
    const dt = new Date(y, m - 1, d)
    const dow = dt.getDay() // 0=Sun
    dt.setDate(dt.getDate() - dow)
    dt.setHours(0, 0, 0, 0)
    return dt
  }

  static weekLandingDay(year: number, month: number, today: Date): Date {
    if (today.getFullYear() === year && today.getMonth() + 1 === month) {
      return new Date(today.getFullYear(), today.getMonth(), today.getDate())
    }
    return new Date(year, month - 1, 1)
  }

  static monthLandingDay(year: number, month: number, today: Date): Date {
    return CalendarProjector.weekLandingDay(year, month, today)
  }
}
