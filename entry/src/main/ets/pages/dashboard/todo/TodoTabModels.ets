import type { Note } from '../../../common/model/Note'
import type { CalendarItemKind } from '../calendar/CalendarModels'
import { CalendarProjector } from '../calendar/CalendarProjector'

export type TodoStatus = 'inProgress' | 'notStarted' | 'completed'
export type TodoListKind = 'all' | 'todo' | 'schedule'

export class TodoItemRow {
  noteId: string = ''
  kind: CalendarItemKind = 'note'
  title: string = ''
  status: TodoStatus = 'notStarted'
  startMs: number = 0
  endMs: number = 0
  remark: string = ''
  sourceNote: Note = {} as Note

  get isTodo(): boolean {
    return this.kind === 'todo'
  }
}

export class TodoTabLogic {
  /**
   * 与 Flutter `computeTodoStatus` 规则严格对齐：
   * 1. is_todo=2 且 todoStatus=1 → completed
   * 2. is_todo=1 且 endTime >0 且 endTime < now → completed（日程已结束）
   * 3. startTime > 0 且 startTime > now → notStarted
   * 4. startTime > 0 且 endTime > 0 且 startTime <= now <= endTime → inProgress
   * 5. 其它 → notStarted
   */
  static computeTodoStatus(n: Note, now: number = Date.now()): TodoStatus {
    const isTodo = n.isTodo ?? 0
    if (isTodo === 2 && (n.todoStatus ?? 0) === 1) {
      return 'completed'
    }
    if (isTodo === 1 && n.endTime > 0 && n.endTime < now) {
      return 'completed'
    }
    const start = n.startTime ?? 0
    const end = n.endTime ?? 0
    if (start > 0 && start > now) {
      return 'notStarted'
    }
    if (start > 0 && end > 0 && start <= now && now <= end) {
      return 'inProgress'
    }
    return 'notStarted'
  }

  /**
   * 过滤 isTodo ∈ {1, 2} 的有效笔记，转换为 TodoItemRow。
   * startMs/endMs 与 CalendarProjector 语义一致：
   *   - schedule: startTime / endTime
   *   - todo:    endTime 作为截止，startMs = endMs - 1h（1 小时色块）
   */
  static buildTodoRows(notes: Note[], now: number = Date.now()): TodoItemRow[] {
    const out: TodoItemRow[] = []
    for (let i = 0; i < notes.length; i++) {
      const n = notes[i]
      if (!CalendarProjector.shouldInclude(n)) {
        continue
      }
      const kind = CalendarProjector.classify(n)
      if (kind !== 'todo' && kind !== 'schedule') {
        continue
      }
      const isTodo = n.isTodo ?? 0
      const title = (n.title ?? '').trim().length > 0 ? (n.title ?? '').trim() : '空主题'
      let remark = (n.summary ?? '').trim()
      if (remark.length === 0) {
        remark = (n.content ?? '').trim().replace(/\s+/g, ' ')
      }
      let startMs = 0
      let endMs = 0
      if (isTodo === 1) {
        startMs = n.startTime ?? 0
        endMs = n.endTime ?? 0
      } else if (isTodo === 2) {
        endMs = n.endTime ?? 0
        if (endMs > 0) {
          startMs = Math.max(0, endMs - 60 * 60 * 1000)
        }
      }
      const row = new TodoItemRow()
      row.noteId = n.id
      row.kind = kind
      row.title = title
      row.status = TodoTabLogic.computeTodoStatus(n, now)
      row.startMs = startMs
      row.endMs = endMs
      row.remark = remark
      row.sourceNote = n
      out.push(row)
    }
    return out
  }

  /** 大小写不敏感子串匹配 标题 + 备注。 */
  static matchesSearch(row: TodoItemRow, q: string): boolean {
    const query = q.trim().toLowerCase()
    if (query.length === 0) {
      return true
    }
    const t = row.title.toLowerCase()
    const r = row.remark.toLowerCase()
    return t.indexOf(query) >= 0 || r.indexOf(query) >= 0
  }

  /** 按 kind 过滤；all 返回原数组（拷贝）。 */
  static applyKindFilter(rows: TodoItemRow[], kind: TodoListKind): TodoItemRow[] {
    if (kind === 'all') {
      return [...rows]
    }
    const out: TodoItemRow[] = []
    for (let i = 0; i < rows.length; i++) {
      if (rows[i].kind === kind) {
        out.push(rows[i])
      }
    }
    return out
  }

  /** 按 startMs 倒序（无起始时间的排到末尾）。 */
  static sortByStartDesc(rows: TodoItemRow[]): TodoItemRow[] {
    const out = [...rows]
    out.sort((a: TodoItemRow, b: TodoItemRow): number => {
      const sa = a.startMs > 0 ? a.startMs : 0
      const sb = b.startMs > 0 ? b.startMs : 0
      if (sa === sb) {
        return 0
      }
      return sb - sa
    })
    return out
  }

  /** 分页。 */
  static paginate(rows: TodoItemRow[], page: number, pageSize: number): TodoItemRow[] {
    if (page < 0 || pageSize <= 0) {
      return []
    }
    const start = page * pageSize
    if (start >= rows.length) {
      return []
    }
    const end = Math.min(rows.length, start + pageSize)
    const out: TodoItemRow[] = []
    for (let i = start; i < end; i++) {
      out.push(rows[i])
    }
    return out
  }
}