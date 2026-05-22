import type { Note } from '../model/Note'
import { Logger } from './Logger'
import { NoteSortUtils } from './NoteSortUtils'

export type HomeSidebarFilterMode = 'tag' | 'folder'

export interface FolderSidebarRow {
  noteId: string
  title: string
  depth: number
  hasChildFolders: boolean
  isExpanded: boolean
}

export interface FolderManageRow {
  noteId: string
  title: string
  depth: number
  isFolder: boolean
  isRoot?: boolean
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

  /** NOTE_STATE `parent_id`：父笔记不存在、指向自身或虚拟根时置空。 */
  static sanitizeParentId(
    parentId: string,
    existingNoteIds: Set<string>,
    selfNoteId?: string
  ): string {
    const trimmed = `${parentId ?? ''}`.trim()
    if (trimmed.length === 0 || trimmed === NoteFolderTree.VIRTUAL_ROOT_FOLDER_ID) {
      return ''
    }
    const self = `${selfNoteId ?? ''}`.trim()
    if (self.length > 0 && trimmed === self) {
      return ''
    }
    return existingNoteIds.has(trimmed) ? trimmed : ''
  }

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

    const childrenByParent = NoteFolderTree.folderChildrenByParent(notes, folderIds)

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
      const parent = note !== undefined ? `${note.parentId ?? ''}`.trim() : ''
      const bucket = parent.length > 0 && folderIds.has(parent) ? parent : ''
      const list = childrenByParent.get(bucket) ?? []
      list.push(id)
      childrenByParent.set(bucket, list)
    })
    childrenByParent.forEach((ids: string[]) => {
      ids.sort((a: string, b: string) => {
        const titleA = byId.get(a) !== undefined ?
          NoteFolderTree.folderTitle(byId.get(a)) : '无标题'
        const titleB = byId.get(b) !== undefined ?
          NoteFolderTree.folderTitle(byId.get(b)) : '无标题'
        return titleA.localeCompare(titleB, 'zh-Hans-CN')
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

  static manageFolderNodeIds(notes: Note[]): Set<string> {
    const folderIds = NoteFolderTree.folderNoteIds(notes)
    const manageIds: Set<string> = new Set(folderIds)
    for (const note of notes) {
      if (note.deleted || (note.deletedTime ?? 0) !== 0) {
        continue
      }
      if (folderIds.has(note.id)) {
        continue
      }
      if (`${note.content ?? ''}`.trim().length > 0) {
        continue
      }
      const parent = `${note.parentId ?? ''}`.trim()
      if (parent.length === 0) {
        manageIds.add(note.id)
        continue
      }
      if (folderIds.has(parent) || manageIds.has(parent)) {
        manageIds.add(note.id)
      }
    }
    return manageIds
  }

  static debugLogManagePageTree(activeNotes: Note[], allNotes?: Note[]): void {
    const tag = 'FolderManage'
    const folderIds = NoteFolderTree.folderNoteIds(activeNotes)
    const rootChildren = NoteFolderTree.notesUnderParent(activeNotes, '')
    const rootFiles: Note[] = []
    const rootFolders: Note[] = []
    for (const note of rootChildren) {
      if (folderIds.has(note.id)) {
        rootFolders.push(note)
      } else {
        rootFiles.push(note)
      }
    }
    const activeIds: Set<string> = new Set()
    for (const note of activeNotes) {
      activeIds.add(note.id)
    }

    Logger.info(tag,
      `========== 文件管理树诊断 ========== listNotes=${activeNotes.length} folderIds=${folderIds.size}`)

    if (allNotes !== undefined) {
      let inactive = 0
      let rootInAll = 0
      for (const note of allNotes) {
        if (note.deleted || (note.deletedTime ?? 0) !== 0) {
          inactive++
        }
        if (`${note.parentId ?? ''}`.trim().length === 0) {
          rootInAll++
        }
      }
      let rootActiveCount = 0
      for (const note of activeNotes) {
        if (`${note.parentId ?? ''}`.trim().length === 0) {
          rootActiveCount++
        }
      }
      Logger.info(tag,
        `listAllNotes=${allNotes.length} inactive=${inactive} rootEmpty(all)=${rootInAll} rootEmpty(active)=${rootActiveCount}`)
    }

    Logger.info(tag,
      `notesUnderParent(根)=${rootChildren.length} files=${rootFiles.length} folders=${rootFolders.length}`)
    for (const note of rootFiles) {
      Logger.info(tag,
        `  [文件] id=${note.id} title=${NoteFolderTree.folderTitle(note)} parentId=${note.parentId ?? ''}`)
    }
    for (const note of rootFolders) {
      let childCount = 0
      for (const child of activeNotes) {
        if (`${child.parentId ?? ''}`.trim() === note.id) {
          childCount++
        }
      }
      Logger.info(tag,
        `  [文件夹] id=${note.id} title=${NoteFolderTree.folderTitle(note)} parentId=${note.parentId ?? ''} children=${childCount}`)
    }

    const virtualParent: Note[] = []
    for (const note of activeNotes) {
      if (`${note.parentId ?? ''}`.trim() === NoteFolderTree.VIRTUAL_ROOT_FOLDER_ID) {
        virtualParent.push(note)
      }
    }
    if (virtualParent.length > 0) {
      Logger.info(tag,
        `WARN parent_id=${NoteFolderTree.VIRTUAL_ROOT_FOLDER_ID} count=${virtualParent.length} (不会出现在根目录)`)
      for (const note of virtualParent) {
        Logger.info(tag, `  id=${note.id} title=${NoteFolderTree.folderTitle(note)}`)
      }
    }

    const orphanParent: Note[] = []
    for (const note of activeNotes) {
      const parent = `${note.parentId ?? ''}`.trim()
      if (parent.length === 0 ||
        parent === NoteFolderTree.VIRTUAL_ROOT_FOLDER_ID ||
        activeIds.has(parent)) {
        continue
      }
      orphanParent.push(note)
    }
    if (orphanParent.length > 0) {
      Logger.info(tag, `WARN orphan parent_id count=${orphanParent.length}`)
      for (const note of orphanParent) {
        Logger.info(tag,
          `  id=${note.id} title=${NoteFolderTree.folderTitle(note)} parentId=${note.parentId ?? ''}`)
      }
    }

    const rows = NoteFolderTree.visibleManageRows(activeNotes, allNotes)
    let depth1 = 0
    let depth1Files = 0
    let depth1Folders = 0
    for (const row of rows) {
      if (row.depth !== 1) {
        continue
      }
      depth1++
      if (row.isFolder) {
        depth1Folders++
      } else {
        depth1Files++
      }
      Logger.info(tag,
        `  UI depth=1 ${row.isFolder ? '文件夹' : '文件'} id=${row.noteId} title=${row.title}`)
    }
    Logger.info(tag,
      `最终 UI rows=${rows.length} depth1=${depth1} files=${depth1Files} folders=${depth1Folders}`)
    Logger.info(tag, '========================================')
  }

  /** 文件管理页同级：文件夹在前、文件在后；各组内按最后修改时间降序。 */
  private static manageFilesUnderParent(
    notes: Note[],
    parentId: string,
    folderIds: Set<string>
  ): Note[] {
    const files: Note[] = []
    for (const note of NoteFolderTree.notesUnderParent(notes, parentId)) {
      if (!folderIds.has(note.id)) {
        files.push(note)
      }
    }
    return NoteSortUtils.sortByLastEditedDesc(files)
  }

  private static sortedManageFolderChildIds(
    childrenByParent: Map<string, string[]>,
    parentKey: string,
    byId: Map<string, Note>
  ): string[] {
    const ids = childrenByParent.get(parentKey) ?? []
    const folderNotes: Note[] = []
    for (const id of ids) {
      const note = byId.get(id)
      if (note !== undefined) {
        folderNotes.push(note)
      }
    }
    const sortedIds = NoteSortUtils.sortByLastEditedDesc(folderNotes).map((n: Note) => n.id)
    const missing = ids.filter((id: string) => !byId.has(id))
    return [...sortedIds, ...missing]
  }

  /**
   * 文件管理页：全量展开。titleLookupNotes 用于已删除/仅作 parent 引用的文件夹标题。
   */
  static visibleManageRows(notes: Note[], titleLookupNotes?: Note[]): FolderManageRow[] {
    const byId: Map<string, Note> = new Map()
    const lookup = titleLookupNotes ?? notes
    for (const note of lookup) {
      byId.set(note.id, note)
    }
    const folderIds = NoteFolderTree.folderNoteIds(notes)
    const childrenByParent = NoteFolderTree.folderChildrenByParent(notes, folderIds)
    const rows: FolderManageRow[] = [{
      noteId: NoteFolderTree.VIRTUAL_ROOT_FOLDER_ID,
      title: '根目录',
      depth: 0,
      isFolder: true,
      isRoot: true
    }]

    const walkParent = (parentKey: string, depth: number): void => {
      const folderChildIds = NoteFolderTree.sortedManageFolderChildIds(
        childrenByParent,
        parentKey,
        byId
      )
      for (const folderId of folderChildIds) {
        const folderNote = byId.get(folderId)
        rows.push({
          noteId: folderId,
          title: folderNote !== undefined ?
            NoteFolderTree.folderTitle(folderNote) : '无标题',
          depth,
          isFolder: true
        })
        walkParent(folderId, depth + 1)
      }
      for (const note of NoteFolderTree.manageFilesUnderParent(notes, parentKey, folderIds)) {
        rows.push({
          noteId: note.id,
          title: NoteFolderTree.folderTitle(note),
          depth,
          isFolder: false
        })
      }
    }

    walkParent('', 1)
    return rows
  }

  static parentIdForDropOnRow(row: FolderManageRow): string {
    return row.isRoot === true ? '' : row.noteId
  }

  static isDescendantOf(ancestorId: string, nodeId: string, notes: Note[]): boolean {
    if (ancestorId.length === 0 || nodeId.length === 0 || ancestorId === nodeId) {
      return false
    }
    const byId: Map<string, Note> = new Map()
    for (const note of notes) {
      byId.set(note.id, note)
    }
    let current = `${byId.get(nodeId)?.parentId ?? ''}`.trim()
    const visited: Set<string> = new Set()
    while (current.length > 0 && !visited.has(current)) {
      if (current === ancestorId) {
        return true
      }
      visited.add(current)
      const parent = byId.get(current)
      current = parent !== undefined ? `${parent.parentId ?? ''}`.trim() : ''
    }
    return false
  }

  static descendantNoteIds(rootId: string, notes: Note[]): Set<string> {
    const result: Set<string> = new Set()
    const walk = (parentId: string): void => {
      for (const note of notes) {
        if (note.deleted || (note.deletedTime ?? 0) !== 0) {
          continue
        }
        if (`${note.parentId ?? ''}`.trim() !== parentId) {
          continue
        }
        result.add(note.id)
        walk(note.id)
      }
    }
    walk(rootId)
    return result
  }

  static parentIdForManageRow(row: FolderManageRow, notes: Note[]): string {
    if (row.isRoot === true) {
      return ''
    }
    const byId: Map<string, Note> = new Map()
    for (const note of notes) {
      byId.set(note.id, note)
    }
    const note = byId.get(row.noteId)
    if (note === undefined) {
      return ''
    }
    const parent = `${note.parentId ?? ''}`.trim()
    const manageIds = NoteFolderTree.manageFolderNodeIds(notes)
    if (parent.length === 0 || !manageIds.has(parent)) {
      return ''
    }
    return parent
  }

  static rawParentIdForManageRow(row: FolderManageRow, notes: Note[]): string {
    if (row.isRoot === true) {
      return ''
    }
    const byId: Map<string, Note> = new Map()
    for (const note of notes) {
      byId.set(note.id, note)
    }
    const note = byId.get(row.noteId)
    if (note === undefined) {
      return ''
    }
    return `${note.parentId ?? ''}`.trim()
  }

  static parentIdForInsertBefore(rows: FolderManageRow[], insertBeforeIndex: number, notes: Note[]): string {
    if (rows.length === 0) {
      return ''
    }
    const index = Math.max(0, Math.min(insertBeforeIndex, rows.length))
    if (index >= rows.length) {
      const last = rows[rows.length - 1]
      if (last.isRoot === true) {
        return ''
      }
      return NoteFolderTree.rawParentIdForManageRow(last, notes)
    }
    const target = rows[index]
    if (target.isRoot === true) {
      return ''
    }
    if (index > 0) {
      const prev = rows[index - 1]
      if (prev.isRoot !== true) {
        if (prev.depth > target.depth) {
          return NoteFolderTree.rawParentIdForManageRow(target, notes)
        }
        if (prev.depth === target.depth) {
          return NoteFolderTree.rawParentIdForManageRow(prev, notes)
        }
        return NoteFolderTree.rawParentIdForManageRow(target, notes)
      }
    }
    return NoteFolderTree.rawParentIdForManageRow(target, notes)
  }

  static depthForInsertBefore(rows: FolderManageRow[], insertBeforeIndex: number): number {
    if (rows.length === 0) {
      return 1
    }
    const index = Math.max(0, Math.min(insertBeforeIndex, rows.length))
    if (index >= rows.length) {
      const last = rows[rows.length - 1]
      return last.isRoot === true ? 1 : last.depth
    }
    const target = rows[index]
    return target.isRoot === true ? 1 : target.depth
  }
}
