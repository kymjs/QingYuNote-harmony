import type { Note } from '../model/Note'

export type HomeSidebarFilterMode = 'tag' | 'folder'

export interface FolderSidebarRow {
  noteId: string
  title: string
  depth: number
  hasChildFolders: boolean
  isExpanded: boolean
}

export interface MovePickerEntry {
  id: string
  title: string
  depth: number
  isFolder: boolean
  canExpand: boolean
  isExpanded: boolean
  /** 点击文件夹时写入的 parent_id；文件为 undefined。 */
  moveTargetParentId?: string
}

export class NoteFolderTree {
  /** 移动弹窗中的虚拟根目录（parent_id 为空表示位于根目录）。 */
  static readonly VIRTUAL_ROOT_FOLDER_ID: string = '__virtual_root__'

  private static folderTitle(note: Note | undefined): string {
    if (note === undefined) {
      return '无标题'
    }
    const title = `${note.title ?? ''}`.trim()
    return title.length > 0 ? title : '无标题'
  }

  static folderNoteIds(notes: Note[]): Set<string> {
    const childCount: Map<string, number> = new Map()
    for (const note of notes) {
      const parent = `${note.parentId ?? ''}`.trim()
      if (parent.length === 0) {
        continue
      }
      childCount.set(parent, (childCount.get(parent) ?? 0) + 1)
    }
    const out: Set<string> = new Set()
    childCount.forEach((count: number, id: string) => {
      if (count > 0) {
        out.add(id)
      }
    })
    return out
  }

  static visibleSidebarRows(notes: Note[], expandedFolderIds: Set<string>): FolderSidebarRow[] {
    const byId: Map<string, Note> = new Map()
    for (const note of notes) {
      byId.set(note.id, note)
    }
    const folderIds = NoteFolderTree.folderNoteIds(notes)
    if (folderIds.size === 0) {
      return []
    }

    const childrenByParent: Map<string, string[]> = new Map()
    folderIds.forEach((id: string) => {
      const note = byId.get(id)
      if (note === undefined) {
        return
      }
      const parent = `${note.parentId ?? ''}`.trim()
      const bucket = parent.length > 0 && folderIds.has(parent) ? parent : ''
      const list = childrenByParent.get(bucket) ?? []
      list.push(id)
      childrenByParent.set(bucket, list)
    })

    childrenByParent.forEach((ids: string[]) => {
      ids.sort((a: string, b: string) => {
        return NoteFolderTree.folderTitle(byId.get(a)).localeCompare(
          NoteFolderTree.folderTitle(byId.get(b)),
          'zh-Hans-CN'
        )
      })
    })

    const rows: FolderSidebarRow[] = []

    const walk = (parentKey: string, depth: number): void => {
      const ids = childrenByParent.get(parentKey)
      if (ids === undefined) {
        return
      }
      for (const id of ids) {
        const childFolderIds = childrenByParent.get(id) ?? []
        const expanded = expandedFolderIds.has(id)
        rows.push({
          noteId: id,
          title: NoteFolderTree.folderTitle(byId.get(id)),
          depth,
          hasChildFolders: childFolderIds.length > 0,
          isExpanded: expanded
        })
        if (expanded) {
          walk(id, depth + 1)
        }
      }
    }

    walk('', 0)
    return rows
  }

  static notesUnderParent(notes: Note[], parentId: string): Note[] {
    const key = `${parentId ?? ''}`.trim()
    const filtered: Note[] = []
    for (const note of notes) {
      if (note.deleted) {
        continue
      }
      const p = `${note.parentId ?? ''}`.trim()
      if (key.length === 0 ? p.length === 0 : p === key) {
        filtered.push(note)
      }
    }
    filtered.sort((a: Note, b: Note) => {
      return NoteFolderTree.folderTitle(a).localeCompare(
        NoteFolderTree.folderTitle(b),
        'zh-Hans-CN'
      )
    })
    return filtered
  }

  private static folderChildrenByParent(
    notes: Note[],
    folderIds: Set<string>
  ): Map<string, string[]> {
    const byId: Map<string, Note> = new Map()
    for (const note of notes) {
      byId.set(note.id, note)
    }
    const childrenByParent: Map<string, string[]> = new Map()
    folderIds.forEach((id: string) => {
      const note = byId.get(id)
      if (note === undefined) {
        return
      }
      const parent = `${note.parentId ?? ''}`.trim()
      const bucket = parent.length > 0 && folderIds.has(parent) ? parent : ''
      const list = childrenByParent.get(bucket) ?? []
      list.push(id)
      childrenByParent.set(bucket, list)
    })
    childrenByParent.forEach((ids: string[]) => {
      ids.sort((a: string, b: string) => {
        return NoteFolderTree.folderTitle(byId.get(a)).localeCompare(
          NoteFolderTree.folderTitle(byId.get(b)),
          'zh-Hans-CN'
        )
      })
    })
    return childrenByParent
  }

  private static parentHasPickerChildren(
    notes: Note[],
    parentId: string,
    folderIds: Set<string>,
    childrenByParent: Map<string, string[]>,
    excludeNoteId: string
  ): boolean {
    for (const note of NoteFolderTree.notesUnderParent(notes, parentId)) {
      if (note.id !== excludeNoteId && !folderIds.has(note.id)) {
        return true
      }
    }
    const key = `${parentId ?? ''}`.trim()
    const list = childrenByParent.get(key.length > 0 ? key : '') ?? []
    return list.length > 0
  }

  static visibleMovePickerEntries(
    notes: Note[],
    expandedFolderIds: Set<string>,
    excludeNoteId: string = ''
  ): MovePickerEntry[] {
    const byId: Map<string, Note> = new Map()
    for (const note of notes) {
      byId.set(note.id, note)
    }
    const folderIds = NoteFolderTree.folderNoteIds(notes)
    const childrenByParent = NoteFolderTree.folderChildrenByParent(notes, folderIds)
    const entries: MovePickerEntry[] = []

    const addFiles = (parent: string, depth: number): void => {
      for (const note of NoteFolderTree.notesUnderParent(notes, parent)) {
        if (note.id === excludeNoteId || folderIds.has(note.id)) {
          continue
        }
        entries.push({
          id: note.id,
          title: NoteFolderTree.folderTitle(note),
          depth: depth,
          isFolder: false,
          canExpand: false,
          isExpanded: false,
          moveTargetParentId: note.id
        })
      }
    }

    const walkFolders = (parentKey: string, depth: number): void => {
      const ids = childrenByParent.get(parentKey) ?? []
      for (const id of ids) {
        const expanded = expandedFolderIds.has(id)
        const hasSubfolders = (childrenByParent.get(id) ?? []).length > 0
        const files = NoteFolderTree.notesUnderParent(notes, id)
        let hasFiles = false
        for (const n of files) {
          if (n.id !== excludeNoteId && !folderIds.has(n.id)) {
            hasFiles = true
            break
          }
        }
        entries.push({
          id: id,
          title: NoteFolderTree.folderTitle(byId.get(id)),
          depth: depth,
          isFolder: true,
          canExpand: hasSubfolders || hasFiles,
          isExpanded: expanded,
          moveTargetParentId: id
        })
        if (expanded) {
          addFiles(id, depth + 1)
          walkFolders(id, depth + 1)
        }
      }
    }

    const rootExpanded = expandedFolderIds.has(NoteFolderTree.VIRTUAL_ROOT_FOLDER_ID)
    const rootHasChildren = NoteFolderTree.parentHasPickerChildren(
      notes, '', folderIds, childrenByParent, excludeNoteId
    )
    entries.push({
      id: NoteFolderTree.VIRTUAL_ROOT_FOLDER_ID,
      title: '根目录',
      depth: 0,
      isFolder: true,
      canExpand: rootHasChildren,
      isExpanded: rootExpanded,
      moveTargetParentId: ''
    })
    if (rootExpanded) {
      addFiles('', 1)
      walkFolders('', 1)
    }
    return entries
  }

  static applyToggleExpand(folderId: string, notes: Note[], expandedFolderIds: Set<string>): void {
    const byId: Map<string, Note> = new Map()
    for (const note of notes) {
      byId.set(note.id, note)
    }
    const folderIds = NoteFolderTree.folderNoteIds(notes)
    if (!folderIds.has(folderId)) {
      return
    }

    if (expandedFolderIds.has(folderId)) {
      NoteFolderTree.collapseWithDescendants(folderId, notes, expandedFolderIds)
      return
    }

    const note = byId.get(folderId)
    if (note === undefined) {
      return
    }
    const parentRaw = `${note.parentId ?? ''}`.trim()
    const parentKey = parentRaw.length > 0 && folderIds.has(parentRaw) ? parentRaw : ''

    const siblings: string[] = []
    for (const n of notes) {
      if (!folderIds.has(n.id)) {
        continue
      }
      const p = `${n.parentId ?? ''}`.trim()
      const key = p.length > 0 && folderIds.has(p) ? p : ''
      if (key === parentKey) {
        siblings.push(n.id)
      }
    }

    for (const sibling of siblings) {
      if (sibling !== folderId) {
        NoteFolderTree.collapseWithDescendants(sibling, notes, expandedFolderIds)
      }
    }

    expandedFolderIds.add(folderId)
    NoteFolderTree.expandAncestors(folderId, notes, expandedFolderIds)
  }

  private static expandAncestors(
    folderId: string,
    notes: Note[],
    expandedFolderIds: Set<string>
  ): void {
    const byId: Map<string, Note> = new Map()
    for (const note of notes) {
      byId.set(note.id, note)
    }
    const folderIds = NoteFolderTree.folderNoteIds(notes)
    let current = byId.get(folderId)
    while (current !== undefined) {
      const parent = `${current.parentId ?? ''}`.trim()
      if (parent.length === 0 || !folderIds.has(parent)) {
        break
      }
      expandedFolderIds.add(parent)
      current = byId.get(parent)
    }
  }

  private static collapseWithDescendants(
    folderId: string,
    notes: Note[],
    expandedFolderIds: Set<string>
  ): void {
    expandedFolderIds.delete(folderId)
    const byId: Map<string, Note> = new Map()
    for (const note of notes) {
      byId.set(note.id, note)
    }
    const folderIds = NoteFolderTree.folderNoteIds(notes)
    folderIds.forEach((id: string) => {
      const note = byId.get(id)
      if (note === undefined) {
        return
      }
      if (`${note.parentId ?? ''}`.trim() === folderId) {
        NoteFolderTree.collapseWithDescendants(id, notes, expandedFolderIds)
      }
    })
  }

  static isUnderFolder(note: Note, folderId: string, notes: Note[]): boolean {
    const byId: Map<string, Note> = new Map()
    for (const n of notes) {
      byId.set(n.id, n)
    }
    let current = `${note.parentId ?? ''}`.trim()
    const visited: Set<string> = new Set()
    while (current.length > 0 && !visited.has(current)) {
      if (current === folderId) {
        return true
      }
      visited.add(current)
      const parent = byId.get(current)
      current = parent !== undefined ? `${parent.parentId ?? ''}`.trim() : ''
    }
    return false
  }

  /** 从根到直接父文件夹的名称链（不含当前笔记）。 */
  static parentPathSegments(parentId: string, notes: Note[]): string[] {
    const trimmed = `${parentId ?? ''}`.trim()
    if (trimmed.length === 0) {
      return []
    }
    const byId: Map<string, Note> = new Map()
    for (const note of notes) {
      byId.set(note.id, note)
    }
    const segments: string[] = []
    let current = trimmed
    const visited: Set<string> = new Set()
    while (current.length > 0 && !visited.has(current)) {
      visited.add(current)
      const note = byId.get(current)
      if (note === undefined) {
        break
      }
      segments.push(NoteFolderTree.folderTitle(note))
      current = `${note.parentId ?? ''}`.trim()
    }
    return segments.reverse()
  }

  static wouldCreateParentCycle(noteId: string, newParentId: string, notes: Note[]): boolean {
    const target = `${newParentId ?? ''}`.trim()
    if (target.length === 0) {
      return false
    }
    if (target === noteId) {
      return true
    }
    const byId: Map<string, Note> = new Map()
    for (const note of notes) {
      byId.set(note.id, note)
    }
    let current = target
    const visited: Set<string> = new Set()
    while (current.length > 0 && !visited.has(current)) {
      if (current === noteId) {
        return true
      }
      visited.add(current)
      const parent = byId.get(current)
      current = parent !== undefined ? `${parent.parentId ?? ''}`.trim() : ''
    }
    return false
  }
}
