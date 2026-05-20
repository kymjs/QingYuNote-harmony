import { describe, it, expect } from '@ohos/hypium'
import type { Note } from '../main/ets/common/model/Note'
import { NoteSortUtils } from '../main/ets/common/utils/NoteSortUtils'

function createNote(overrides: Partial<Note>): Note {
  return {
    id: overrides.id ?? 'note-default',
    title: overrides.title ?? '',
    content: overrides.content ?? '',
    tags: overrides.tags ?? [],
    summary: overrides.summary ?? '',
    localModified: overrides.localModified ?? 0,
    remoteModified: overrides.remoteModified ?? 0,
    deleted: overrides.deleted ?? false,
    deletedAt: overrides.deletedAt ?? 0,
    lastOperationAt: overrides.lastOperationAt ?? 0,
    syncStatus: overrides.syncStatus ?? 'pending',
    filePath: overrides.filePath ?? '',
    createdAt: overrides.createdAt ?? 0,
    updatedAt: overrides.updatedAt ?? 0,
    parentId: overrides.parentId ?? '',
    isConflict: overrides.isConflict ?? 0,
    latitude: overrides.latitude ?? 0,
    longitude: overrides.longitude ?? 0,
    altitude: overrides.altitude ?? 0,
    author: overrides.author ?? '',
    sourceUrl: overrides.sourceUrl ?? '',
    isTodo: overrides.isTodo ?? 0,
    todoDue: overrides.todoDue ?? 0,
    todoCompleted: overrides.todoCompleted ?? 0,
    source: overrides.source ?? 'harmony',
    order: overrides.order ?? 0,
    userData: overrides.userData ?? '',
    rsa: overrides.rsa ?? 0,
    deletedTime: overrides.deletedTime ?? 0,
    type_: overrides.type_ ?? 1
  }
}

export default function noteSortUtilsTest() {
  describe('NoteSortUtils', () => {
    it('should sort notes by localModified in descending order', 0, () => {
      const notes = [
        createNote({ id: 'note-1', localModified: 100 }),
        createNote({ id: 'note-2', localModified: 300 }),
        createNote({ id: 'note-3', localModified: 200 })
      ]

      const sorted = NoteSortUtils.sortByLastEditedDesc(notes)

      expect(sorted[0].id).assertEqual('note-2')
      expect(sorted[1].id).assertEqual('note-3')
      expect(sorted[2].id).assertEqual('note-1')
    })

    it('should keep ordering stable when localModified is the same', 0, () => {
      const notes = [
        createNote({ id: 'note-1', localModified: 100, updatedAt: 300, createdAt: 100 }),
        createNote({ id: 'note-2', localModified: 100, updatedAt: 300, createdAt: 200 }),
        createNote({ id: 'note-3', localModified: 100, updatedAt: 400, createdAt: 50 })
      ]

      const sorted = NoteSortUtils.sortByLastEditedDesc(notes)

      expect(sorted[0].id).assertEqual('note-3')
      expect(sorted[1].id).assertEqual('note-2')
      expect(sorted[2].id).assertEqual('note-1')
    })

    it('should ignore updatedAt-only changes when localModified is lower', 0, () => {
      const notes = [
        createNote({ id: 'edited-note', localModified: 200, updatedAt: 200 }),
        createNote({ id: 'synced-note', localModified: 100, updatedAt: 999 })
      ]

      const sorted = NoteSortUtils.sortByLastEditedDesc(notes)

      expect(sorted[0].id).assertEqual('edited-note')
      expect(sorted[1].id).assertEqual('synced-note')
    })

    it('should not mutate the input array', 0, () => {
      const notes = [
        createNote({ id: 'note-1', localModified: 100 }),
        createNote({ id: 'note-2', localModified: 300 })
      ]

      const sorted = NoteSortUtils.sortByLastEditedDesc(notes)

      expect(notes[0].id).assertEqual('note-1')
      expect(notes[1].id).assertEqual('note-2')
      expect(sorted[0].id).assertEqual('note-2')
    })
  })
}
