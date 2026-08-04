import {
  CalendarOccurrence,
  CalendarWeekBlockLayout,
  CalendarWeekVisibleRange
} from './CalendarModels'
import { CalendarProjector } from './CalendarProjector'

export class CalendarWeekLayout {
  static readonly DEFAULT_START: number = 9
  static readonly DEFAULT_END: number = 19
  static readonly LAYER_INSET: number = 0.14

  static visibleRange(weekItems: CalendarOccurrence[]): CalendarWeekVisibleRange {
    const range = new CalendarWeekVisibleRange()
    range.startHour = CalendarWeekLayout.DEFAULT_START
    range.endHour = CalendarWeekLayout.DEFAULT_END
    for (let i = 0; i < weekItems.length; i++) {
      const o = weekItems[i]
      const a = new Date(o.anchorMs)
      const e = new Date(o.endMs)
      const sh = a.getHours() + a.getMinutes() / 60 + a.getSeconds() / 3600
      let eh = e.getHours() + e.getMinutes() / 60 + e.getSeconds() / 3600
      if (eh <= sh) {
        eh = sh + 1
      }
      if (sh < range.startHour) {
        range.startHour = Math.floor(sh)
      }
      if (eh > range.endHour) {
        range.endHour = Math.ceil(eh)
      }
    }
    if (range.endHour <= range.startHour) {
      range.endHour = range.startHour + 1
    }
    return range
  }

  static layoutWeek(
    weekStart: Date,
    weekItems: CalendarOccurrence[],
    range: CalendarWeekVisibleRange
  ): CalendarWeekBlockLayout[] {
    const byDay: Map<number, CalendarOccurrence[]> = new Map()
    const startY = weekStart.getFullYear()
    const startM = weekStart.getMonth() + 1
    const startD = weekStart.getDate()
    for (let i = 0; i < weekItems.length; i++) {
      const o = weekItems[i]
      const dayDate = new Date(o.dayY, o.dayM - 1, o.dayD)
      const startDate = new Date(startY, startM - 1, startD)
      const idx = Math.round((dayDate.getTime() - startDate.getTime()) / (24 * 3600 * 1000))
      if (idx < 0 || idx > 6) {
        continue
      }
      let list = byDay.get(idx)
      if (!list) {
        list = []
        byDay.set(idx, list)
      }
      list.push(o)
    }

    const out: CalendarWeekBlockLayout[] = []
    const span = range.spanHours()
    for (let dayIndex = 0; dayIndex < 7; dayIndex++) {
      const items = byDay.get(dayIndex) ?? []
      if (items.length === 0) {
        continue
      }
      const layers = CalendarWeekLayout.assignLayers(items)
      for (let i = 0; i < items.length; i++) {
        const o = items[i]
        const layer = layers.get(o) ?? 0
        const leftRatio = layer * CalendarWeekLayout.LAYER_INSET
        let widthRatio = 1 - leftRatio
        if (widthRatio < 0.35) {
          widthRatio = 0.35
        }
        const alignedLeft = 1 - widthRatio
        const a = new Date(o.anchorMs)
        const e = new Date(o.endMs)
        const sh = a.getHours() + a.getMinutes() / 60 + a.getSeconds() / 3600
        let eh = e.getHours() + e.getMinutes() / 60 + e.getSeconds() / 3600
        if (eh <= sh) {
          eh = sh + 1
        }
        let topRatio = (sh - range.startHour) / span
        let bottomRatio = (eh - range.startHour) / span
        if (topRatio < 0) {
          topRatio = 0
        }
        if (topRatio > 1) {
          topRatio = 1
        }
        if (bottomRatio < 0) {
          bottomRatio = 0
        }
        if (bottomRatio > 1) {
          bottomRatio = 1
        }
        let heightRatio = bottomRatio - topRatio
        if (heightRatio < 0.02) {
          heightRatio = 0.02
        }
        const block = new CalendarWeekBlockLayout()
        block.occurrence = o
        block.dayIndex = dayIndex
        block.topRatio = topRatio
        block.heightRatio = heightRatio
        block.leftRatio = alignedLeft
        block.widthRatio = widthRatio
        block.layer = layer
        out.push(block)
      }
    }
    out.sort((a: CalendarWeekBlockLayout, b: CalendarWeekBlockLayout) => {
      if (a.layer !== b.layer) {
        return a.layer - b.layer
      }
      return a.occurrence.noteCreatedAt - b.occurrence.noteCreatedAt
    })
    return out
  }

  static overlaps(a: CalendarOccurrence, b: CalendarOccurrence): boolean {
    return a.anchorMs < b.endMs && b.anchorMs < a.endMs
  }

  /** 与 tapped 同一时间段重叠连通分量（通常 1 条，叠层时多条）。 */
  static overlapGroup(
    tapped: CalendarOccurrence,
    dayItems: CalendarOccurrence[]
  ): CalendarOccurrence[] {
    const group: CalendarOccurrence[] = [tapped]
    const remaining: CalendarOccurrence[] = []
    for (let i = 0; i < dayItems.length; i++) {
      const e = dayItems[i]
      if (!(e.noteId === tapped.noteId && e.anchorMs === tapped.anchorMs)) {
        remaining.push(e)
      }
    }
    let grew = true
    while (grew) {
      grew = false
      for (let i = remaining.length - 1; i >= 0; i--) {
        const cand = remaining[i]
        let hit = false
        for (let j = 0; j < group.length; j++) {
          if (CalendarWeekLayout.overlaps(group[j], cand)) {
            hit = true
            break
          }
        }
        if (hit) {
          group.push(cand)
          remaining.splice(i, 1)
          grew = true
        }
      }
    }
    group.sort((a: CalendarOccurrence, b: CalendarOccurrence) => a.anchorMs - b.anchorMs)
    return group
  }

  private static assignLayers(items: CalendarOccurrence[]): Map<CalendarOccurrence, number> {
    const layers = new Map<CalendarOccurrence, number>()
    const groups = CalendarWeekLayout.connectedGroups(items)
    for (let g = 0; g < groups.length; g++) {
      const group = groups[g]
      group.sort((a: CalendarOccurrence, b: CalendarOccurrence) => {
        if (a.noteCreatedAt !== b.noteCreatedAt) {
          return a.noteCreatedAt - b.noteCreatedAt
        }
        return a.noteId.localeCompare(b.noteId)
      })
      for (let i = 0; i < group.length; i++) {
        layers.set(group[i], i)
      }
    }
    return layers
  }

  private static connectedGroups(items: CalendarOccurrence[]): CalendarOccurrence[][] {
    const remaining = [...items]
    const groups: CalendarOccurrence[][] = []
    while (remaining.length > 0) {
      const group: CalendarOccurrence[] = [remaining.shift() as CalendarOccurrence]
      let grew = true
      while (grew) {
        grew = false
        for (let i = remaining.length - 1; i >= 0; i--) {
          const cand = remaining[i]
          let hit = false
          for (let j = 0; j < group.length; j++) {
            if (CalendarWeekLayout.overlaps(group[j], cand)) {
              hit = true
              break
            }
          }
          if (hit) {
            group.push(cand)
            remaining.splice(i, 1)
            grew = true
          }
        }
      }
      groups.push(group)
    }
    return groups
  }
}
