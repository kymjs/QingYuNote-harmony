import type { Note } from '../model/Note'
import { AudioConstants } from '../constants/AudioConstants'
import { NOTE_TYPE_FLOWCHART } from '../model/FlowchartGraph'

/** 笔记 Tab 排序规则（与 Preferences `notes_tab_sort` 一致）。 */
export type NotesTabSortRule = 'modified' | 'created' | 'type'

export class NoteSortUtils {
  static sortByLastEditedDesc(notes: Note[]): Note[] {
    return [...notes].sort((left: Note, right: Note) => NoteSortUtils.compareByLastEditedDesc(left, right))
  }

  static sortByCreatedDesc(notes: Note[]): Note[] {
    return [...notes].sort((left: Note, right: Note) => NoteSortUtils.compareByCreatedDesc(left, right))
  }

  static sortByTypeAsc(notes: Note[], mindMapNoteIds: Set<string> = new Set<string>()): Note[] {
    return [...notes].sort((left: Note, right: Note) => {
      return NoteSortUtils.compareByTypeAsc(left, right, mindMapNoteIds)
    })
  }

  static sortNotes(
    notes: Note[],
    rule: NotesTabSortRule,
    mindMapNoteIds: Set<string> = new Set<string>()
  ): Note[] {
    switch (rule) {
      case 'created':
        return NoteSortUtils.sortByCreatedDesc(notes)
      case 'type':
        return NoteSortUtils.sortByTypeAsc(notes, mindMapNoteIds)
      default:
        return NoteSortUtils.sortByLastEditedDesc(notes)
    }
  }

  static compareByLastEditedDesc(left: Note, right: Note): number {
    const updatedComparison = NoteSortUtils.compareNumberDesc(left.updatedAt, right.updatedAt)
    if (updatedComparison !== 0) {
      return updatedComparison
    }
    const timeComparison = NoteSortUtils.compareNumberDesc(left.localModified, right.localModified)
    if (timeComparison !== 0) {
      return timeComparison
    }
    const createdComparison = NoteSortUtils.compareNumberDesc(left.createdAt, right.createdAt)
    if (createdComparison !== 0) {
      return createdComparison
    }
    return right.id.localeCompare(left.id)
  }

  static compareByCreatedDesc(left: Note, right: Note): number {
    const createdComparison = NoteSortUtils.compareNumberDesc(left.createdAt, right.createdAt)
    if (createdComparison !== 0) {
      return createdComparison
    }
    return NoteSortUtils.compareByLastEditedDesc(left, right)
  }

  /** 普通 → mp3 → wav → Todo → 思维导图 → 流程图；同级再按修改时间。 */
  static compareByTypeAsc(left: Note, right: Note, mindMapNoteIds: Set<string> = new Set<string>()): number {
    const rankComparison =
      NoteSortUtils.typeRank(left, mindMapNoteIds) - NoteSortUtils.typeRank(right, mindMapNoteIds)
    if (rankComparison !== 0) {
      return rankComparison
    }
    return NoteSortUtils.compareByLastEditedDesc(left, right)
  }

  static typeRank(note: Note, mindMapNoteIds: Set<string> = new Set<string>()): number {
    if (note.type_ === NOTE_TYPE_FLOWCHART) {
      return mindMapNoteIds.has(note.id) ? 4 : 5
    }
    for (const tag of note.tags) {
      if (`${tag ?? ''}`.trim() === 'Todo') {
        return 3
      }
    }
    const audio = `${note.audioId ?? ''}`.trim().toLowerCase()
    if (audio.endsWith(AudioConstants.videoAudioFileExtension)) {
      return 1
    }
    if (audio.endsWith(AudioConstants.audioFileExtension)) {
      return 2
    }
    return 0
  }

  private static compareNumberDesc(left: number, right: number): number {
    return NoteSortUtils.normalizeTimestamp(right) - NoteSortUtils.normalizeTimestamp(left)
  }

  private static normalizeTimestamp(value: number): number {
    return value > 0 ? value : 0
  }
}
