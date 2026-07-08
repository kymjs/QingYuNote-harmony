import { describe, it, expect } from '@ohos/hypium'
import type { Note } from '../../../main/ets/common/model/Note'
import { NoteFolderTree } from '../../../main/ets/common/utils/NoteFolderTree'

function note(id: string, parentId: string = '', title: string = ''): Note {
  return {
    id,
    title,
    content: '',
    tags: [],
    summary: '',
    localModified: 0,
    remoteModified: 0,
    deleted: false,
    deletedAt: 0,
    lastOperationAt: 0,
    syncStatus: 'synced',
    filePath: '',
    createdAt: 0,
    updatedAt: 0,
    parentId,
    isConflict: 0,
    latitude: 0,
    longitude: 0,
    altitude: 0,
    author: '',
    sourceUrl: '',
    isTodo: 0,
    todoDue: 0,
    todoCompleted: 0,
    source: '',
    applicationData: '',
    order: 0,
    userCreatedTime: 0,
    userUpdatedTime: 0,
    encryptionCipherText: '',
    encryptionApplied: 0,
    markupLanguage: 0,
    isShared: 0,
    shareId: '',
    conflictOriginalId: '',
    masterKeyId: '',
    userData: '',
    rsa: 0,
    deletedTime: 0,
    type: 0,
    imageRefs: [],
    audioId: ''
  } as Note
}

export default function noteFolderTreeTest() {
  describe('NoteFolderTree', () => {
    it('folderNoteIds_only_parents_with_children', 0, () => {
      const notes = [
        note('f1', '', 'Folder'),
        note('n1', 'f1', 'Child'),
        note('n2', '', 'Root note')
      ]
      const ids = NoteFolderTree.folderNoteIds(notes)
      expect(ids.has('f1')).assertTrue()
      expect(ids.has('n1')).assertFalse()
    })

    it('sanitizeParentId_rejects_unknown_parent', 0, () => {
      const existing = new Set<string>(['a'])
      expect(NoteFolderTree.sanitizeParentId('missing', existing)).assertEqual('')
      expect(NoteFolderTree.sanitizeParentId('a', existing, 'b')).assertEqual('a')
      expect(NoteFolderTree.sanitizeParentId('b', existing, 'b')).assertEqual('')
    })

    it('isUnderFolder_descendant_chain', 0, () => {
      const notes = [
        note('f1', '', 'Folder'),
        note('n1', 'f1', 'Child'),
        note('n2', 'n1', 'Grandchild')
      ]
      expect(NoteFolderTree.isUnderFolder(notes[2], 'f1', notes)).assertTrue()
      expect(NoteFolderTree.isUnderFolder(notes[0], 'f1', notes)).assertFalse()
    })
  })
}
