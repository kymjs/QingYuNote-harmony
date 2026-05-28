import { SyncConstants } from '../constants/SyncConstants'

/** 去重并保留 JSON 数组中的先后顺序（越靠前视为越老）。 */
export function dedupePermanentlyDeletedNoteIdsPreserveOrder(ids: string[]): string[] {
  const out: string[] = []
  for (let i = 0; i < ids.length; i += 1) {
    const id = ids[i]
    if (id.length === 0) {
      continue
    }
    if (!out.includes(id)) {
      out.push(id)
    }
  }
  return out
}

/** 超过阈值时移除最老的一批 id（与 Flutter `prunePermanentlyDeletedNoteIds` 一致）。 */
export function prunePermanentlyDeletedNoteIds(ids: string[]): string[] {
  const ordered = dedupePermanentlyDeletedNoteIdsPreserveOrder(ids)
  if (ordered.length <= SyncConstants.permanentlyDeletedNoteIdsPruneThreshold) {
    return ordered
  }
  return ordered.slice(SyncConstants.permanentlyDeletedNoteIdsPruneCount)
}

export function appendPermanentlyDeletedNoteIdOrdered(list: string[], noteId: string): void {
  if (noteId.length === 0) {
    return
  }
  const idx = list.indexOf(noteId)
  if (idx >= 0) {
    list.splice(idx, 1)
  }
  list.push(noteId)
}
