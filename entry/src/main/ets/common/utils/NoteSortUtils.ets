import type { Note } from '../model/Note'

export class NoteSortUtils {
  static sortByLastEditedDesc(notes: Note[]): Note[] {
    return [...notes].sort((left: Note, right: Note) => NoteSortUtils.compareByLastEditedDesc(left, right))
  }

  private static compareByLastEditedDesc(left: Note, right: Note): number {
    const timeComparison = NoteSortUtils.compareNumberDesc(left.localModified, right.localModified)
    if (timeComparison !== 0) {
      return timeComparison
    }

    const updatedAtComparison = NoteSortUtils.compareNumberDesc(left.updatedAt, right.updatedAt)
    if (updatedAtComparison !== 0) {
      return updatedAtComparison
    }

    const createdAtComparison = NoteSortUtils.compareNumberDesc(left.createdAt, right.createdAt)
    if (createdAtComparison !== 0) {
      return createdAtComparison
    }

    return right.id.localeCompare(left.id)
  }

  private static compareNumberDesc(left: number, right: number): number {
    return NoteSortUtils.normalizeTimestamp(right) - NoteSortUtils.normalizeTimestamp(left)
  }

  private static normalizeTimestamp(value: number): number {
    return value > 0 ? value : 0
  }
}
