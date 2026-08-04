import type { Note } from '../../../common/model/Note'
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
    if ((note.isTodo ?? 0) === 1) {
      return 'schedule'
    }
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
    const createdKey = CalendarProjector.dayKeyFromMs(note.createdAt)
    const updatedKey = CalendarProjector.dayKeyFromMs(note.updatedAt)
    if (createdKey === updatedKey) {
      return [CalendarProjector.makeOcc(note, kind, title, summary, thumb, note.createdAt, false)]
    }
    return [
      CalendarProjector.makeOcc(note, kind, title, summary, thumb, note.createdAt, false),
      CalendarProjector.makeOcc(note, kind, title, summary, thumb, note.updatedAt, true)
    ]
  }

  private static makeOcc(
    note: Note,
    kind: CalendarItemKind,
    title: string,
    summary: string,
    thumb: string,
    anchorMs: number,
    isUpdate: boolean
  ): CalendarOccurrence {
    const dt = new Date(anchorMs)
    const o = new CalendarOccurrence()
    o.noteId = note.id
    o.note = note
    o.kind = kind
    o.anchorMs = anchorMs
    o.endMs = anchorMs + CalendarProjector.DURATION_MS
    o.dayY = dt.getFullYear()
    o.dayM = dt.getMonth() + 1
    o.dayD = dt.getDate()
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

  static filterChip(items: CalendarOccurrence[], filter: CalendarChipFilter): CalendarOccurrence[] {
    if (filter === 'all') {
      return items
    }
    const out: CalendarOccurrence[] = []
    for (let i = 0; i < items.length; i++) {
      if (items[i].kind === filter) {
        out.push(items[i])
      }
    }
    return out
  }

  static countsFor(items: CalendarOccurrence[]): CalendarDayCounts {
    const c = new CalendarDayCounts()
    c.all = items.length
    for (let i = 0; i < items.length; i++) {
      const k = items[i].kind
      if (k === 'note') {
        c.note += 1
      } else if (k === 'todo') {
        c.todo += 1
      } else {
        c.schedule += 1
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
