import type { Note } from '../model/Note'

export class TagSortUtils {
  /** 按标签所含笔记数量降序；数量相同则按标签名字典序。 */
  static sortByNoteCountDesc(tags: string[], notes: Note[]): string[] {
    if (tags.length === 0) {
      return []
    }
    const counts: Map<string, number> = new Map()
    for (const note of notes) {
      for (const tag of note.tags) {
        counts.set(tag, (counts.get(tag) ?? 0) + 1)
      }
    }
    return [...tags].sort((left: string, right: string) => {
      const countDiff = (counts.get(right) ?? 0) - (counts.get(left) ?? 0)
      if (countDiff !== 0) {
        return countDiff
      }
      return left.localeCompare(right, 'zh-Hans-CN')
    })
  }
}
