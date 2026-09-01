import type { Note } from '../../common/model/Note'
import { isExtractStatusPending } from '../../common/model/Note'
import { AudioConstants } from '../../common/constants/AudioConstants'
import { NOTE_TYPE_FLOWCHART } from '../../common/model/FlowchartGraph'
import { NoteFolderTree } from '../../common/utils/NoteFolderTree'
import { NoteSortUtils, type NotesTabSortRule } from '../../common/utils/NoteSortUtils'
import { NoteStateCodec } from '../../common/utils/NoteStateCodec'
import { LocaleService } from '../../services/LocaleService'

export type NotesTabDisplayMode = 'none' | 'folder' | 'tag'
export type NotesTabFilterChip = 'all' | 'favorite' | 'tags' | 'folders'
export type NotesTabManageEntry = 'folder' | 'tag'

export class NotesTabGroup {
  id: string = ''
  title: string = ''
  notes: Note[] = []

  constructor(id: string = '', title: string = '', notes: Note[] = []) {
    this.id = id
    this.title = title
    this.notes = notes
  }

  get count(): number {
    return this.notes.length
  }
}

export class NotesTabLogic {
  static readonly UNCategorizedGroupId: string = 'folder:__uncategorized__'
  static readonly NO_TAG_GROUP_ID: string = 'tag:__none__'

  static parseDisplayMode(raw: string): NotesTabDisplayMode {
    if (raw === 'folder') {
      return 'folder'
    }
    if (raw === 'tag') {
      return 'tag'
    }
    return 'none'
  }

  static serializeDisplayMode(mode: NotesTabDisplayMode): string {
    return mode
  }

  static parseSort(raw: string): NotesTabSortRule {
    if (raw === 'created') {
      return 'created'
    }
    if (raw === 'type') {
      return 'type'
    }
    return 'modified'
  }

  static serializeSort(rule: NotesTabSortRule): string {
    return rule
  }

  static parseManageEntry(raw: string): NotesTabManageEntry {
    return raw === 'tag' ? 'tag' : 'folder'
  }

  static matchesSearch(note: Note, query: string): boolean {
    const q = query.trim().toLowerCase()
    if (q.length === 0) {
      return true
    }
    return `${note.title ?? ''}`.toLowerCase().includes(q) ||
      `${note.content ?? ''}`.toLowerCase().includes(q) ||
      `${note.summary ?? ''}`.toLowerCase().includes(q)
  }

  static applyFilter(
    allNotes: Note[],
    searchQuery: string,
    filterChip: NotesTabFilterChip,
    selectedTags: Set<string>,
    selectedFolderIds: Set<string>
  ): Note[] {
    let pool: Note[] = allNotes.slice()
    const searching = searchQuery.trim().length > 0
    if (searching) {
      pool = pool.filter((n: Note) => NotesTabLogic.matchesSearch(n, searchQuery))
    } else {
      switch (filterChip) {
        case 'favorite':
          pool = pool.filter((n: Note) => (n.isFavorite ?? 0) !== 0)
          break
        case 'tags':
          pool = pool.filter((n: Note) => {
            for (const tag of n.tags) {
              if (selectedTags.has(`${tag ?? ''}`.trim())) {
                return true
              }
            }
            return false
          })
          break
        case 'folders':
          pool = pool.filter((n: Note) => {
            const root = NoteFolderTree.firstLevelFolderIdOf(n, allNotes)
            return root !== null && selectedFolderIds.has(root)
          })
          break
        default:
          break
      }
    }
    return pool
  }

  static buildGroups(
    filteredNotes: Note[],
    allNotes: Note[],
    mode: NotesTabDisplayMode,
    sortRule: NotesTabSortRule,
    mindMapNoteIds: Set<string>
  ): NotesTabGroup[] {
    const sorted = NoteSortUtils.sortNotes(filteredNotes, sortRule, mindMapNoteIds)
    if (mode === 'none') {
      return [new NotesTabGroup('none:all', '', sorted)]
    }
    if (mode === 'folder') {
      return NotesTabLogic.buildFolderGroups(sorted, allNotes)
    }
    return NotesTabLogic.buildTagGroups(sorted)
  }

  private static buildFolderGroups(sorted: Note[], allNotes: Note[]): NotesTabGroup[] {
    const firstLevels = NoteFolderTree.firstLevelFolderIds(allNotes)
    const buckets: Map<string, Note[]> = new Map()
    for (const id of firstLevels) {
      buckets.set(id, [])
    }
    const uncategorized: Note[] = []
    const firstLevelSet = new Set<string>(firstLevels)
    for (const note of sorted) {
      const root = NoteFolderTree.firstLevelFolderIdOf(note, allNotes)
      if (root !== null) {
        const list = buckets.get(root) ?? []
        list.push(note)
        buckets.set(root, list)
      } else if (!firstLevelSet.has(note.id)) {
        uncategorized.push(note)
      }
    }
    const groups: NotesTabGroup[] = []
    for (const id of firstLevels) {
      const notes = buckets.get(id) ?? []
      if (notes.length === 0) {
        continue
      }
      groups.push(new NotesTabGroup(
        `folder:${id}`,
        NoteFolderTree.folderTitleOf(id, allNotes),
        notes
      ))
    }
    if (uncategorized.length > 0) {
      groups.push(new NotesTabGroup(
        NotesTabLogic.UNCategorizedGroupId,
        LocaleService.loc('未分类', 'Uncategorized', '未分類'),
        uncategorized
      ))
    }
    return groups
  }

  private static buildTagGroups(sorted: Note[]): NotesTabGroup[] {
    const tagOrder: string[] = []
    const buckets: Map<string, Note[]> = new Map()
    const noTag: Note[] = []
    for (const note of sorted) {
      const tags: string[] = []
      for (const raw of note.tags) {
        const t = `${raw ?? ''}`.trim()
        if (t.length > 0) {
          tags.push(t)
        }
      }
      if (tags.length === 0) {
        noTag.push(note)
        continue
      }
      for (const tag of tags) {
        if (!buckets.has(tag)) {
          tagOrder.push(tag)
          buckets.set(tag, [])
        }
        const list = buckets.get(tag) ?? []
        list.push(note)
        buckets.set(tag, list)
      }
    }
    tagOrder.sort((a: string, b: string) => a.localeCompare(b, 'zh-Hans-CN'))
    const groups: NotesTabGroup[] = []
    for (const tag of tagOrder) {
      const notes = buckets.get(tag) ?? []
      if (notes.length === 0) {
        continue
      }
      groups.push(new NotesTabGroup(`tag:${tag}`, tag, notes))
    }
    if (noTag.length > 0) {
      groups.push(new NotesTabGroup(
        NotesTabLogic.NO_TAG_GROUP_ID,
        LocaleService.loc('无标签', 'No tags', 'タグなし'),
        noTag
      ))
    }
    return groups
  }

  static leadingKindFor(note: Note, mindMapNoteIds: Set<string> = new Set()): string {
    // 待办 / 日程沿用日历 tab 列表中的样式；放最前避免被流程图分支吞掉。
    if (note.isTodo === 2) {
      return 'todo'
    }
    if (note.isTodo === 1) {
      return 'schedule'
    }
    if (note.type_ === NOTE_TYPE_FLOWCHART) {
      // 流程图需要根据 `.qy` 边车里的 `layoutMode` 区分思维导图 / 知识图谱；
      // 集合由 DashboardNotesTab.detectMindMaps 预扫后传入，命中即为思维导图。
      if (mindMapNoteIds.has(note.id)) {
        return 'flowchart'
      }
      return 'knowledgeGraph'
    }
    const audio = `${note.audioId ?? ''}`.trim().toLowerCase()
    if (audio.endsWith(AudioConstants.videoAudioFileExtension)) {
      return 'mp3'
    }
    if (isExtractStatusPending(note.extractStatus)) {
      return 'extract'
    }
    return 'document'
  }

  static relativeTimeLabel(ms: number): string {
    if (ms <= 0) {
      return ''
    }
    const dt = new Date(ms)
    const hm =
      `${dt.getHours().toString().padStart(2, '0')}:${dt.getMinutes().toString().padStart(2, '0')}`
    const now = new Date()
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
    const that = new Date(dt.getFullYear(), dt.getMonth(), dt.getDate()).getTime()
    const diff = Math.floor((today - that) / 86400000)
    if (diff === 0) {
      return `${LocaleService.loc('今天', 'Today', '今日')} ${hm}`
    }
    if (diff === 1) {
      return `${LocaleService.loc('昨天', 'Yesterday', '昨日')} ${hm}`
    }
    return `${dt.getMonth() + 1}/${dt.getDate()} ${hm}`
  }

  static filterChipLabel(
    chip: NotesTabFilterChip,
    selectedTags: Set<string>,
    selectedFolderIds: Set<string>,
    allNotes: Note[]
  ): string {
    switch (chip) {
      case 'all':
        return LocaleService.loc('全部', 'All', 'すべて')
      case 'favorite':
        return LocaleService.loc('收藏', 'Favorites', 'お気に入り')
      case 'tags':
        if (selectedTags.size === 1) {
          const first = Array.from(selectedTags)[0]
          return `#${first}`
        }
        return LocaleService.loc('标签', 'Tags', 'タグ')
      case 'folders':
        if (selectedFolderIds.size === 1) {
          const first = Array.from(selectedFolderIds)[0]
          return NoteFolderTree.folderTitleOf(first, allNotes)
        }
        return LocaleService.loc('文件夹', 'Folders', 'フォルダ')
      default:
        return ''
    }
  }
}

export class NotesTabListRow {
  kind: 'groupHeader' | 'note' = 'note'
  rowKey: string = ''
  groupId: string = ''
  groupTitle: string = ''
  groupCount: number = 0
  groupExpanded: boolean = true
  note: Note | null = null
}

export class DashboardNotesListDataSource implements IDataSource {
  private listeners: DataChangeListener[] = []
  private rows: NotesTabListRow[] = []

  totalCount(): number {
    return this.rows.length
  }

  getData(index: number): Object {
    return this.rows[index]
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener)
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const pos = this.listeners.indexOf(listener)
    if (pos >= 0) {
      this.listeners.splice(pos, 1)
    }
  }

  replaceAll(rows: NotesTabListRow[]): void {
    this.rows = rows.slice()
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataReloaded()
    })
  }
}

export class NotesTabMultiSelectItem {
  id: string = ''
  label: string = ''
  count: number = 0

  constructor(id: string = '', label: string = '', count: number = 0) {
    this.id = id
    this.label = label
    this.count = count
  }
}

export function cloneNoteWithFavorite(note: Note, isFavorite: number): Note {
  return {
    id: note.id,
    title: note.title,
    content: note.content,
    tags: [...note.tags],
    summary: note.summary,
    localModified: note.localModified,
    remoteModified: note.remoteModified,
    deleted: note.deleted,
    deletedAt: note.deletedAt,
    lastOperationAt: note.lastOperationAt,
    syncStatus: note.syncStatus,
    filePath: note.filePath,
    createdAt: note.createdAt,
    updatedAt: note.updatedAt,
    parentId: note.parentId,
    isConflict: note.isConflict,
    latitude: note.latitude,
    longitude: note.longitude,
    altitude: note.altitude,
    author: note.author,
    sourceUrl: note.sourceUrl,
    isFavorite: isFavorite,
    isTodo: note.isTodo,
    todoDue: note.todoDue,
    todoCompleted: note.todoCompleted,
    todoPriority: note.todoPriority,
    todoStatus: note.todoStatus,
    todoReminderMinutes: note.todoReminderMinutes,
    startTime: note.startTime,
    endTime: note.endTime,
    source: note.source,
    order: note.order,
    userData: note.userData,
    rsa: note.rsa,
    imageRefs: [...note.imageRefs],
    audioId: note.audioId,
    deletedTime: note.deletedTime,
    type_: note.type_,
    extractStatus: note.extractStatus,
    extractJobId: note.extractJobId,
    extractError: note.extractError,
    extractedAt: note.extractedAt,
    extractProgress: note.extractProgress,
    voiceSummary: note.voiceSummary,
    voiceSegmentsJson: note.voiceSegmentsJson,
    voiceTranscribeStatus: note.voiceTranscribeStatus,
    flowchartExt: note.flowchartExt
  }
}

export function thumbnailPathForNote(note: Note, filesDir: string): string {
  const refs = (note.imageRefs !== undefined && note.imageRefs.length > 0) ?
    note.imageRefs :
    NoteStateCodec.extractImageRefs(note.content)
  if (refs.length === 0 || filesDir.length === 0) {
    return ''
  }
  const parts = refs[0].split('/')
  const fileName = parts[parts.length - 1]
  return `${filesDir}/qingyu-note-image/${fileName}`
}
