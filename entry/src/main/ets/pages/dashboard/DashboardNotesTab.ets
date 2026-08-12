import { common } from '@kit.AbilityKit'
import { fileUri } from '@kit.CoreFileKit'

import type { Note, SyncResult, SyncStatus } from '../../common/model/Note'
import { isExtractStatusPending } from '../../common/model/Note'
import { NOTE_TYPE_FLOWCHART } from '../../common/model/FlowchartGraph'
import { navigateToFlowchart } from '../../common/utils/FlowchartNavigation'
import { navigateToNoteEdit } from '../../common/utils/NoteEditNavigation'
import { NoteFolderTree } from '../../common/utils/NoteFolderTree'
import { TagSortUtils } from '../../common/utils/TagSortUtils'
import { FlowchartMindMap } from '../../common/utils/FlowchartMindMap'
import { AppContextHolder } from '../../services/AppContextHolder'
import { FlowchartService } from '../../services/FlowchartService'
import { LocaleService } from '../../services/LocaleService'
import { NoteRepository } from '../../services/NoteRepository'
import { PreferencesService } from '../../services/PreferencesService'
import { SyncService } from '../../services/SyncService'
import { WebDAVClient } from '../../services/WebDAVClient'
import { previewQingyuForHomeSubscription } from '../../services/QingyuCloudAutoProvision'
import { Logger } from '../../common/utils/Logger'
import {
  DashboardNotesListDataSource,
  NotesTabGroup,
  NotesTabLogic,
  NotesTabListRow,
  NotesTabMultiSelectItem,
  cloneNoteWithFavorite,
  thumbnailPathForNote,
  type NotesTabDisplayMode,
  type NotesTabFilterChip,
  type NotesTabManageEntry
} from './DashboardNotesModels'
import type { NotesTabSortRule } from '../../common/utils/NoteSortUtils'

const PAGE_PAD = 16
const BOTTOM_BAR_PAD = 72
const MODE_FONT = 11
const FILTER_PIN_FADE = 48
/** 分组收起时：箭头与文件夹图标间距（vp）。 */
const GROUP_COLLAPSE_ICON_GAP_VP = 2.5
const GROUP_EXPAND_ICON_GAP_VP = 1.5
/** 模式选中描边（半透明 accent，深浅色通用）。 */
const MODE_SELECTED_BORDER = '#8C0DAA4A'

@Component
export struct DashboardNotesTab {
  @Prop @Watch('onVisibleChanged') visible: boolean = false
  /** 从编辑/管理页返回时由 MainShell 递增，强制静默刷新。 */
  @Prop @Watch('onShellRefreshNonce') shellRefreshNonce: number = 0
  @StorageLink('appLocaleRevision') localeRevision: number = 0
  /** 仓库 bumpVersion 时写入，编辑保存后即时刷新列表。 */
  @StorageLink('appNotesRevision') @Watch('onNotesRevisionChanged')
  notesRevision: number = 0
  @State allNotes: Note[] = []
  @State mindMapNoteIds: string[] = []
  @State loading: boolean = true
  @State syncing: boolean = false
  @State refreshing: boolean = false
  @State cloudConfigured: boolean = true
  @State searchQuery: string = ''
  @State displayMode: NotesTabDisplayMode = 'none'
  @State sortRule: NotesTabSortRule = 'modified'
  @State lastManageEntry: NotesTabManageEntry = 'folder'
  @State selectedFilter: NotesTabFilterChip = 'all'
  @State selectedTags: string[] = []
  @State selectedFolderIds: string[] = []
  @State collapsedGroupIds: string[] = []
  @State listEmpty: boolean = true
  @State undoNoteId: string = ''
  @State undoBarVisible: boolean = false
  @State multiSelectVisible: boolean = false
  @State multiSelectTitle: string = ''
  @State multiSelectItems: NotesTabMultiSelectItem[] = []
  @State multiSelectDraft: string[] = []
  @State multiSelectKind: string = 'tags'
  /** 下拉相对本页 Stack 的偏移（随芯片滚动实时更新）。 */
  @State filterDropdownTop: number = 96
  @State filterDropdownLeft: number = PAGE_PAD
  @State filterPinProgress: number = 0
  /** 递增以强制模式栏 ListItem 重建（List 会缓存子项 UI）。 */
  @State modeBarNonce: number = 0
  /** 是否已完成首次加载；切 Tab 不再整页重载。 */
  private initialLoaded: boolean = false
  private filesDir: string = ''
  private reloadGeneration: number = 0
  private undoHideTimer: number = -1
  private listScroller: Scroller = new Scroller()
  private listDataSource: DashboardNotesListDataSource = new DashboardNotesListDataSource()
  private rootGlobalX: number = 0
  private rootGlobalY: number = 0
  private rootWidth: number = 0
  private tagsChipX: number = PAGE_PAD
  private tagsChipY: number = 0
  private tagsChipH: number = 36
  private foldersChipX: number = PAGE_PAD
  private foldersChipY: number = 0
  private foldersChipH: number = 36

  private parseAreaNum(value: Object | undefined | null, fallback: number = 0): number {
    const n = Number.parseFloat(`${value ?? ''}`)
    return Number.isFinite(n) ? n : fallback
  }

  private recordRootArea(area: Area): void {
    this.rootGlobalX = this.parseAreaNum(area.globalPosition?.x as Object, 0)
    this.rootGlobalY = this.parseAreaNum(area.globalPosition?.y as Object, 0)
    this.rootWidth = this.parseAreaNum(area.width as Object, 0)
  }

  private recordFilterChipArea(kind: 'tags' | 'folders', area: Area): void {
    const x = this.parseAreaNum(area.globalPosition?.x as Object, PAGE_PAD)
    const y = this.parseAreaNum(area.globalPosition?.y as Object, 0)
    const h = this.parseAreaNum(area.height as Object, 36)
    if (kind === 'tags') {
      this.tagsChipX = x
      this.tagsChipY = y
      this.tagsChipH = h
    } else {
      this.foldersChipX = x
      this.foldersChipY = y
      this.foldersChipH = h
    }
  }

  private filterDropdownMaxWidth(): number {
    return this.rootWidth > 0 ? Math.min(280, this.rootWidth - 24) : 280
  }

  /** 按标题/选项/管理文案估算菜单宽度（Scroll 会撑满父宽，必须显式 width）。 */
  private estimateTextWidthVp(text: string, fontSize: number): number {
    let w = 0
    for (let i = 0; i < text.length; i++) {
      const code = text.charCodeAt(i)
      if (code > 0x2E80) {
        w += fontSize
      } else {
        w += fontSize * 0.58
      }
    }
    return w
  }

  private filterDropdownWidth(): number {
    const padH = 28
    const checkSlot = 26
    let content = this.estimateTextWidthVp(this.multiSelectTitle, 14) + 22
    const manageLabel = this.multiSelectKind === 'tags' ?
      LocaleService.loc('管理标签', 'Manage tags', 'タグ管理') :
      LocaleService.loc('管理文件夹', 'Manage folders', 'フォルダ管理')
    content = Math.max(content, this.estimateTextWidthVp(manageLabel, 13) + 32)
    for (let i = 0; i < this.multiSelectItems.length; i++) {
      const item = this.multiSelectItems[i]
      const line = `${item.label}  ${item.count}`
      content = Math.max(content, this.estimateTextWidthVp(line, 14) + checkSlot)
    }
    const raw = content + padH
    return Math.min(this.filterDropdownMaxWidth(), Math.max(132, raw))
  }

  private placeFilterDropdown(kind: 'tags' | 'folders'): void {
    const x = kind === 'tags' ? this.tagsChipX : this.foldersChipX
    const y = kind === 'tags' ? this.tagsChipY : this.foldersChipY
    const h = kind === 'tags' ? this.tagsChipH : this.foldersChipH
    const menuW = this.filterDropdownWidth()
    let left = x - this.rootGlobalX
    const maxLeft = this.rootWidth > 0 ? this.rootWidth - menuW - 12 : left
    if (left > maxLeft) {
      left = Math.max(12, maxLeft)
    }
    if (left < 12) {
      left = 12
    }
    this.filterDropdownLeft = left
    this.filterDropdownTop = Math.max(0, y + h - this.rootGlobalY + 4)
  }

  /** 吸顶底：仅 0/1 两档，避免滚动中连续改 @State 导致整页重建卡顿。 */
  private filterPinBg(): ResourceColor {
    if (this.filterPinProgress < 0.5) {
      return Color.Transparent
    }
    return $r('app.color.notes_filter_pin')
  }

  private syncFilterPinFromScroller(): void {
    // onDidScroll 的 scrollOffset 是增量；吸顶必须用绝对 yOffset。
    let y = 0
    try {
      y = this.listScroller.currentOffset().yOffset
    } catch (_) {
      y = 0
    }
    // 越过搜索区后直接实心，回顶透明；不做逐帧渐变。
    const next = y >= FILTER_PIN_FADE ? 1 : 0
    if (next === this.filterPinProgress) {
      return
    }
    this.filterPinProgress = next
  }

  aboutToAppear(): void {
    // 保活后可能先以 visible=false 挂载；真正可见时再由 onVisibleChanged 触发首次加载。
    if (this.visible && !this.initialLoaded) {
      void this.reload()
    }
  }

  onVisibleChanged(): void {
    // 与 Flutter 一致：切回笔记 Tab 不整页重载；仅首次进入时加载。
    // 从其它页返回的刷新由 shellRefreshNonce / notesRevision 负责。
    if (this.visible && !this.initialLoaded) {
      void this.reload()
    }
  }

  onShellRefreshNonce(): void {
    if (this.initialLoaded && this.shellRefreshNonce > 0) {
      void this.reload()
    }
  }

  onNotesRevisionChanged(): void {
    if (this.initialLoaded && this.notesRevision > 0) {
      void this.reload()
    }
  }

  private async reload(): Promise<void> {
    const generation = ++this.reloadGeneration
    // 已有列表时静默刷新，避免再次出现「加载中」。
    if (this.allNotes.length === 0) {
      this.loading = true
    }
    try {
      const context = AppContextHolder.tryGetContext()
      if (context) {
        await PreferencesService.getInstance().init(context)
        await NoteRepository.getInstance().init(context)
        this.filesDir = (context as common.UIAbilityContext).filesDir ?? ''
      } else {
        await NoteRepository.getInstance().init()
      }
      const modeRaw = await PreferencesService.getInstance().getNotesTabDisplayMode()
      const sortRaw = await PreferencesService.getInstance().getNotesTabSort()
      const manageRaw = await PreferencesService.getInstance().getNotesTabLastManageEntry()
      const collapsed = await PreferencesService.getInstance().getNotesTabCollapsedGroupIds()
      const notes = await NoteRepository.getInstance().listNotes()
      const mindMaps = await this.detectMindMaps(notes)
      const cloudConfigured = await this.resolveCloudConfigured()
      if (generation !== this.reloadGeneration) {
        return
      }
      this.displayMode = NotesTabLogic.parseDisplayMode(modeRaw)
      this.sortRule = NotesTabLogic.parseSort(sortRaw)
      this.lastManageEntry = NotesTabLogic.parseManageEntry(manageRaw)
      this.collapsedGroupIds = collapsed.slice()
      this.allNotes = notes
      this.mindMapNoteIds = Array.from(mindMaps)
      this.cloudConfigured = cloudConfigured
      this.loading = false
      this.initialLoaded = true
      this.rebuildListRows()
    } catch (e) {
      Logger.error('DashboardNotesTab', `reload failed: ${JSON.stringify(e)}`)
      if (generation === this.reloadGeneration) {
        this.loading = false
      }
    }
  }

  private async detectMindMaps(notes: Note[]): Promise<Set<string>> {
    const ids: Set<string> = new Set()
    for (const note of notes) {
      if (note.type_ !== NOTE_TYPE_FLOWCHART) {
        continue
      }
      try {
        const graph = await FlowchartService.getInstance().load(note.id)
        if (FlowchartMindMap.isMindMapMode(graph)) {
          ids.add(note.id)
        }
      } catch (_) {
      }
    }
    return ids
  }

  private async resolveCloudConfigured(): Promise<boolean> {
    try {
      if (await PreferencesService.getInstance().hasEnabledCustomWebDAVConfig()) {
        return true
      }
      const status =
        await WebDAVClient.getInstance().fetchQingyuCloudSubscriptionStatus(previewQingyuForHomeSubscription)
      return status.kind === 'lifetime' || status.kind === 'active'
    } catch (_) {
      return false
    }
  }

  private mindMapSet(): Set<string> {
    return new Set<string>(this.mindMapNoteIds)
  }

  private selectedTagsSet(): Set<string> {
    return new Set<string>(this.selectedTags)
  }

  private selectedFolderIdsSet(): Set<string> {
    return new Set<string>(this.selectedFolderIds)
  }

  private collapsedSet(): Set<string> {
    return new Set<string>(this.collapsedGroupIds)
  }

  private filteredNotes(): Note[] {
    return NotesTabLogic.applyFilter(
      this.allNotes,
      this.searchQuery,
      this.selectedFilter,
      this.selectedTagsSet(),
      this.selectedFolderIdsSet()
    )
  }

  private buildGroups(): NotesTabGroup[] {
    return NotesTabLogic.buildGroups(
      this.filteredNotes(),
      this.allNotes,
      this.displayMode,
      this.sortRule,
      this.mindMapSet()
    )
  }

  private rebuildListRows(): void {
    const groups = this.buildGroups()
    this.listEmpty = groups.length === 0 ||
      (groups.length === 1 && groups[0].notes.length === 0)
    if (this.listEmpty) {
      this.listDataSource.replaceAll([])
      return
    }
    const collapsed = this.collapsedSet()
    const rows: NotesTabListRow[] = []
    for (const group of groups) {
      const showHeader = this.displayMode !== 'none' && group.title.length > 0
      const expanded = !collapsed.has(group.id)
      if (showHeader) {
        const header = new NotesTabListRow()
        header.kind = 'groupHeader'
        // rowKey 含展开态与模式，确保 LazyForEach 刷新左侧图标。
        header.rowKey = `h-${group.id}-${expanded ? '1' : '0'}-${this.displayMode}`
        header.groupId = group.id
        header.groupTitle = group.title
        header.groupCount = group.count
        header.groupExpanded = expanded
        rows.push(header)
      }
      if (!showHeader || expanded) {
        for (const note of group.notes) {
          const row = new NotesTabListRow()
          row.kind = 'note'
          row.rowKey = `n-${group.id}-${note.id}`
          row.groupId = group.id
          row.note = note
          rows.push(row)
        }
      }
    }
    this.listDataSource.replaceAll(rows)
  }

  private async pullToSync(): Promise<void> {
    if (!this.cloudConfigured) {
      try {
        await this.getUIContext().getRouter().pushUrl({ url: 'pages/CloudSyncSettings' })
      } catch (_) {
      }
      await this.reload()
      this.refreshing = false
      return
    }
    if (this.syncing) {
      return
    }
    this.syncing = true
    try {
      const results: SyncResult[] = await SyncService.getInstance().syncNow()
      const failed = results.filter((r: SyncResult) => !r.success)
      if (failed.length > 0) {
        this.showToast(LocaleService.loc(
          `同步完成，但有 ${failed.length} 条笔记同步失败`,
          `Sync finished with ${failed.length} note failures`,
          `同期完了。${failed.length}件のノート同期に失敗`
        ))
      }
    } catch (_) {
      this.showToast(LocaleService.loc('同步失败，请稍后重试', 'Sync failed, try again later', '同期に失敗しました'))
    } finally {
      this.syncing = false
      this.refreshing = false
      NoteRepository.getInstance().discardCachedNoteLists()
      await this.reload()
    }
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message, duration: 2500 })
    } catch (_) {
    }
  }

  private async setDisplayMode(mode: NotesTabDisplayMode): Promise<void> {
    this.displayMode = mode
    this.modeBarNonce = this.modeBarNonce + 1
    if (mode === 'folder') {
      this.lastManageEntry = 'folder'
    } else if (mode === 'tag') {
      this.lastManageEntry = 'tag'
    }
    this.rebuildListRows()
    await PreferencesService.getInstance().setNotesTabDisplayMode(NotesTabLogic.serializeDisplayMode(mode))
    if (mode === 'folder') {
      await PreferencesService.getInstance().setNotesTabLastManageEntry('folder')
    } else if (mode === 'tag') {
      await PreferencesService.getInstance().setNotesTabLastManageEntry('tag')
    }
  }

  private async setSort(rule: NotesTabSortRule): Promise<void> {
    this.sortRule = rule
    await PreferencesService.getInstance().setNotesTabSort(NotesTabLogic.serializeSort(rule))
    this.rebuildListRows()
  }

  private async toggleGroup(groupId: string): Promise<void> {
    const next = this.collapsedGroupIds.slice()
    const idx = next.indexOf(groupId)
    if (idx >= 0) {
      next.splice(idx, 1)
    } else {
      next.push(groupId)
    }
    this.collapsedGroupIds = next
    await PreferencesService.getInstance().setNotesTabCollapsedGroupIds(next)
    this.rebuildListRows()
  }

  private groupIconGapVp(expanded: boolean): number {
    return expanded ? GROUP_EXPAND_ICON_GAP_VP : GROUP_COLLAPSE_ICON_GAP_VP
  }

  private async openManage(): Promise<void> {
    let entry: NotesTabManageEntry = this.lastManageEntry
    if (this.displayMode === 'folder') {
      entry = 'folder'
    } else if (this.displayMode === 'tag') {
      entry = 'tag'
    }
    await this.openManageEntry(entry)
  }

  private async openManageEntry(entry: NotesTabManageEntry): Promise<void> {
    await PreferencesService.getInstance().setNotesTabLastManageEntry(entry)
    this.lastManageEntry = entry
    try {
      if (entry === 'tag') {
        await this.getUIContext().getRouter().pushUrl({ url: 'pages/TagManage' })
      } else {
        await this.getUIContext().getRouter().pushUrl({ url: 'pages/FolderManage' })
      }
    } catch (e) {
      Logger.error('DashboardNotesTab', `openManage failed: ${JSON.stringify(e)}`)
    }
    await this.reload()
  }

  private async pickTags(): Promise<void> {
    const tagCounts: Map<string, number> = new Map()
    for (const note of this.allNotes) {
      for (const tag of note.tags) {
        const t = `${tag ?? ''}`.trim()
        if (t.length === 0) {
          continue
        }
        tagCounts.set(t, (tagCounts.get(t) ?? 0) + 1)
      }
    }
    const stored = await PreferencesService.getInstance().getNoteTags()
    const merged: string[] = []
    tagCounts.forEach((_count: number, tag: string) => {
      merged.push(tag)
    })
    for (const t of stored) {
      merged.push(t)
    }
    const allTags = TagSortUtils.sortByNoteCountDesc(merged, this.allNotes)
    const items: NotesTabMultiSelectItem[] = []
    for (const t of allTags) {
      items.push(new NotesTabMultiSelectItem(t, `#${t}`, tagCounts.get(t) ?? 0))
    }
    this.multiSelectKind = 'tags'
    this.multiSelectTitle = LocaleService.loc('全部标签', 'All tags', 'すべてのタグ')
    this.multiSelectItems = items
    this.multiSelectDraft = this.selectedTags.slice()
    this.placeFilterDropdown('tags')
    this.multiSelectVisible = true
  }

  private async pickFolders(): Promise<void> {
    const firstLevels = NoteFolderTree.firstLevelFolderIds(this.allNotes)
    const items: NotesTabMultiSelectItem[] = []
    for (const id of firstLevels) {
      let count = 0
      for (const n of this.allNotes) {
        if (NoteFolderTree.firstLevelFolderIdOf(n, this.allNotes) === id) {
          count += 1
        }
      }
      if (count <= 0) {
        continue
      }
      items.push(new NotesTabMultiSelectItem(
        id,
        NoteFolderTree.folderTitleOf(id, this.allNotes),
        count
      ))
    }
    this.multiSelectKind = 'folders'
    this.multiSelectTitle = LocaleService.loc('全部文件夹', 'All folders', 'すべてのフォルダ')
    this.multiSelectItems = items
    this.multiSelectDraft = this.selectedFolderIds.slice()
    this.placeFilterDropdown('folders')
    this.multiSelectVisible = true
  }

  private applyMultiSelect(): void {
    const selected = this.multiSelectDraft.slice()
    if (selected.length === 0) {
      this.selectedFilter = 'all'
      this.selectedTags = []
      this.selectedFolderIds = []
    } else if (this.multiSelectKind === 'tags') {
      this.selectedFilter = 'tags'
      this.selectedTags = selected
      this.selectedFolderIds = []
    } else {
      this.selectedFilter = 'folders'
      this.selectedFolderIds = selected
      this.selectedTags = []
    }
    this.multiSelectVisible = false
    this.rebuildListRows()
  }

  private async toggleFavorite(note: Note): Promise<void> {
    const next = (note.isFavorite ?? 0) !== 0 ? 0 : 1
    const previous = note.isFavorite ?? 0
    this.allNotes = this.allNotes.map((n: Note) => {
      return n.id === note.id ? cloneNoteWithFavorite(n, next) : n
    })
    this.rebuildListRows()
    try {
      await NoteRepository.getInstance().saveDraft(note.id, { isFavorite: next })
    } catch (_) {
      this.allNotes = this.allNotes.map((n: Note) => {
        return n.id === note.id ? cloneNoteWithFavorite(n, previous) : n
      })
      this.rebuildListRows()
      this.showToast(LocaleService.loc('收藏更新失败', 'Failed to update favorite', 'お気に入り更新失敗'))
    }
  }

  private clearUndoHideTimer(): void {
    if (this.undoHideTimer >= 0) {
      clearTimeout(this.undoHideTimer)
      this.undoHideTimer = -1
    }
  }

  private showUndoBar(noteId: string): void {
    this.clearUndoHideTimer()
    this.undoNoteId = noteId
    this.undoBarVisible = true
    this.undoHideTimer = setTimeout((): void => {
      this.undoBarVisible = false
      this.undoNoteId = ''
      this.undoHideTimer = -1
    }, 5000)
  }

  private async handleDelete(noteId: string): Promise<void> {
    const previous = this.allNotes.slice()
    this.allNotes = this.allNotes.filter((n: Note) => n.id !== noteId)
    this.rebuildListRows()
    try {
      await NoteRepository.getInstance().deleteNote(noteId, Date.now())
      this.showUndoBar(noteId)
      await this.reload()
    } catch (_) {
      this.allNotes = previous
      this.rebuildListRows()
      this.showToast(LocaleService.loc('删除失败', 'Delete failed', '削除失敗'))
    }
  }

  private async undoDelete(): Promise<void> {
    const noteId = this.undoNoteId
    this.clearUndoHideTimer()
    this.undoBarVisible = false
    this.undoNoteId = ''
    if (noteId.length === 0) {
      return
    }
    try {
      await NoteRepository.getInstance().restoreRecycleBinNote(noteId)
    } catch (_) {
    }
    await this.reload()
  }

  private thumbUri(note: Note): string {
    const full = thumbnailPathForNote(note, this.filesDir)
    if (full.length === 0) {
      return ''
    }
    try {
      return fileUri.getUriFromPath(full)
    } catch (_) {
      return ''
    }
  }

  private async openNote(note: Note): Promise<void> {
    if (note.type_ === NOTE_TYPE_FLOWCHART) {
      await navigateToFlowchart(this.getUIContext(), { noteId: note.id })
      await this.reload()
      return
    }
    if (isExtractStatusPending(note.extractStatus) ||
      note.extractStatus === 'failed' ||
      note.voiceTranscribeStatus === 'running' ||
      note.voiceTranscribeStatus === 'failed') {
      const kind = note.sourceUrl.trim().length === 0 &&
        note.extractStatus !== 'failed' &&
        !isExtractStatusPending(note.extractStatus)
        ? 'voiceTranscribe'
        : 'linkExtract'
      try {
        await this.getUIContext().getRouter().pushUrl({
          url: 'pages/LinkExtractProgress',
          params: { noteId: note.id, kind: kind, url: note.sourceUrl.trim() }
        })
      } catch (_) {
      }
      await this.reload()
      return
    }
    if (`${note.audioId ?? ''}`.trim().length > 0) {
      try {
        await this.getUIContext().getRouter().pushUrl({
          url: 'pages/VoiceNoteDetail',
          params: { noteId: note.id }
        })
      } catch (_) {
      }
      await this.reload()
      return
    }
    await navigateToNoteEdit(this.getUIContext(), {
      noteId: note.id,
      openWithPreview: `${note.content ?? ''}`.trim().length > 0
    })
    await this.reload()
  }

  private manageLabel(): string {
    if (this.displayMode === 'folder') {
      return LocaleService.loc('文件管理', 'Folders', 'フォルダ管理')
    }
    if (this.displayMode === 'tag') {
      return LocaleService.loc('标签管理', 'Tags', 'タグ管理')
    }
    return this.lastManageEntry === 'tag' ?
      LocaleService.loc('标签管理', 'Tags', 'タグ管理') :
      LocaleService.loc('文件管理', 'Folders', 'フォルダ管理')
  }

  private activeFilterChip(): NotesTabFilterChip {
    return this.searchQuery.trim().length > 0 ? 'all' : this.selectedFilter
  }

  build() {
    Stack() {
      Column() {
        if (this.loading && this.allNotes.length === 0) {
          Column() {
            LoadingProgress()
              .width(36)
              .height(36)
              .color($r('app.color.accent'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Refresh({ refreshing: $$this.refreshing, offset: 64, friction: 100 }) {
            List({ scroller: this.listScroller }) {
              ListItem() {
                this.buildSearchBar()
              }
              .padding({ left: PAGE_PAD, right: PAGE_PAD })
              // 加大搜索框与筛选栏间距（仅鸿蒙）。
              .margin({ bottom: 10 })
              // 筛选栏吸顶；白底全宽渐变，内容保留左右内边距。
              ListItemGroup({ header: this.buildFilterBar() }) {
                ListItem() {
                  this.buildModeBar()
                }
                .padding({ left: PAGE_PAD, right: PAGE_PAD })
                // ListItem 默认复用会导致 displayMode 变了高亮不刷新。
                .key(`notes_mode_bar_${this.displayMode}_${this.modeBarNonce}`)
                if (this.listEmpty) {
                  ListItem() {
                    this.buildEmptyState()
                  }
                  .padding({ left: PAGE_PAD, right: PAGE_PAD })
                } else {
                  LazyForEach(this.listDataSource, (row: Object) => {
                    this.buildListRow(row as NotesTabListRow)
                  }, (row: Object) => (row as NotesTabListRow).rowKey)
                }
              }
            }
            .sticky(StickyStyle.Header)
            .width('100%')
            .height('100%')
            .backgroundColor(Color.Transparent)
            .contentEndOffset(BOTTOM_BAR_PAD)
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
            .onDidScroll((_scrollOffset: number, _scrollState: ScrollState): void => {
              // 仅在越过阈值时翻转 0/1，避免逐帧刷新 sticky header。
              this.syncFilterPinFromScroller()
            })
            .onScrollStop((): void => {
              this.syncFilterPinFromScroller()
            })
            .cachedCount(8)
          }
          .layoutWeight(1)
          .width('100%')
          .onRefreshing((): void => {
            void this.pullToSync()
          })
        }
        if (this.undoBarVisible) {
          this.buildUndoBar()
        }
      }
      .width('100%')
      .height('100%')

      if (this.multiSelectVisible) {
        this.buildFilterDropdownOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .onAreaChange((_oldArea: Area, area: Area): void => {
      this.recordRootArea(area)
    })
  }

  @Builder
  buildListRow(row: NotesTabListRow) {
    if (row.kind === 'groupHeader') {
      ListItem() {
        this.buildGroupHeader(row)
      }
      .width('100%')
      .padding({ left: PAGE_PAD, right: PAGE_PAD })
    } else {
      ListItem() {
        this.buildNoteTile(row)
      }
      .width('100%')
      .padding({ left: PAGE_PAD, right: PAGE_PAD })
      .swipeAction({
        end: {
          builder: (): void => {
            if (row.note !== null) {
              this.buildDeleteAction(row.note)
            }
          },
          actionAreaDistance: 88
        },
        edgeEffect: SwipeEdgeEffect.Spring
      })
    }
  }

  @Builder
  buildSearchBar() {
    Row({ space: 0 }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(18)
        .fontColor([$r('app.color.secondary_text')])
        .padding({ left: 12, right: 6 })
      TextInput({ text: this.searchQuery, placeholder: LocaleService.loc(
        '搜索笔记、流程图节点',
        'Search notes and flowchart nodes',
        'ノート・フローチャートを検索'
      ) })
        .layoutWeight(1)
        .fontSize(15)
        .fontColor($r('app.color.primary_text'))
        .placeholderColor($r('app.color.secondary_text'))
        .backgroundColor(Color.Transparent)
        .border({ width: 0 })
        .padding({ left: 0, right: 4, top: 0, bottom: 0 })
        .onChange((value: string): void => {
          this.searchQuery = value
          this.rebuildListRows()
        })
      if (this.searchQuery.trim().length > 0) {
        Row() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(16)
            .fontColor([$r('app.color.secondary_text')])
        }
        .padding({ left: 6, right: 12, top: 10, bottom: 10 })
        .onClick((): void => {
          this.searchQuery = ''
          this.rebuildListRows()
        })
      }
    }
    .width('100%')
    .height(40)
    .margin({ top: 8 })
    .alignItems(VerticalAlign.Center)
    .borderRadius(10)
    .backgroundColor($r('app.color.notes_search_fill'))
  }

  @Builder
  buildModeBar() {
    Row() {
      Scroll() {
        Row({ space: 0 }) {
          // 直接读 @State displayMode，避免 @Builder 传参缓存。
          // 无分组：背景框左缘对齐搜索框；文案在框内左右对称居中。
          Row({ space: 4 }) {
            Text(LocaleService.loc('无分组', 'No groups', 'グループなし'))
              .fontSize(MODE_FONT)
              .fontWeight(this.displayMode === 'none' ? FontWeight.Medium : FontWeight.Normal)
              .fontColor(this.displayMode === 'none' ? $r('app.color.accent') : $r('app.color.secondary_text'))
          }
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .justifyContent(FlexAlign.Center)
          .borderRadius(8)
          .backgroundColor(this.displayMode === 'none' ? $r('app.color.notes_chip_selected') : Color.Transparent)
          .border({
            width: 1,
            color: this.displayMode === 'none' ? MODE_SELECTED_BORDER : Color.Transparent
          })
          .onClick((): void => {
            void this.setDisplayMode('none')
          })

          this.modeDivider()

          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.folder'))
              .fontSize(MODE_FONT)
              .fontColor([this.displayMode === 'folder' ? $r('app.color.accent') : $r('app.color.secondary_text')])
            Text(LocaleService.loc('文件夹分组', 'Folder groups', 'フォルダグループ'))
              .fontSize(MODE_FONT)
              .fontWeight(this.displayMode === 'folder' ? FontWeight.Medium : FontWeight.Normal)
              .fontColor(this.displayMode === 'folder' ? $r('app.color.accent') : $r('app.color.secondary_text'))
          }
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(8)
          .backgroundColor(this.displayMode === 'folder' ? $r('app.color.notes_chip_selected') : Color.Transparent)
          .border({
            width: 1,
            color: this.displayMode === 'folder' ? MODE_SELECTED_BORDER : Color.Transparent
          })
          .onClick((): void => {
            void this.setDisplayMode('folder')
          })

          this.modeDivider()

          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.label'))
              .fontSize(MODE_FONT)
              .fontColor([this.displayMode === 'tag' ? $r('app.color.accent') : $r('app.color.secondary_text')])
            Text(LocaleService.loc('标签分组', 'Tag groups', 'タググループ'))
              .fontSize(MODE_FONT)
              .fontWeight(this.displayMode === 'tag' ? FontWeight.Medium : FontWeight.Normal)
              .fontColor(this.displayMode === 'tag' ? $r('app.color.accent') : $r('app.color.secondary_text'))
          }
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .borderRadius(8)
          .backgroundColor(this.displayMode === 'tag' ? $r('app.color.notes_chip_selected') : Color.Transparent)
          .border({
            width: 1,
            color: this.displayMode === 'tag' ? MODE_SELECTED_BORDER : Color.Transparent
          })
          .onClick((): void => {
            void this.setDisplayMode('tag')
          })
        }
        .justifyContent(FlexAlign.Start)
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .align(Alignment.Start)
      .layoutWeight(1)
      Row({ space: 4 }) {
        SymbolGlyph((this.displayMode === 'tag' ||
          (this.displayMode === 'none' && this.lastManageEntry === 'tag')) ?
          $r('sys.symbol.label') : $r('sys.symbol.folder'))
          .fontSize(MODE_FONT)
          .fontColor([$r('app.color.secondary_text')])
        Text(this.manageLabel())
          .fontSize(MODE_FONT)
          .fontColor($r('app.color.secondary_text'))
      }
      .padding({ left: 8, right: 0, top: 6, bottom: 6 })
      .flexShrink(0)
      .onClick((): void => {
        void this.openManage()
      })
    }
    .width('100%')
    .margin({ top: 4, bottom: 4 })
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  modeDivider() {
    Divider()
      .vertical(true)
      .height(18)
      .color('#38000000')
      .margin({ left: 6, right: 6 })
  }

  @Builder
  buildFilterBar() {
    // 左右 PAGE_PAD 与搜索框同宽；芯片靠左，「排序」贴右缘。
    // 勿用 Stack+height(100%) 作 ListItemGroup header，会把吸顶栏撑成全屏。
    Row() {
      Scroll() {
        Row({ space: 8 }) {
          this.buildFilterChipItem(
            NotesTabLogic.filterChipLabel('all', this.selectedTagsSet(), this.selectedFolderIdsSet(), this.allNotes),
            this.activeFilterChip() === 'all',
            (): void => {
              this.selectedFilter = 'all'
              this.selectedTags = []
              this.selectedFolderIds = []
              this.rebuildListRows()
            }
          )
          this.buildFilterChipItem(
            NotesTabLogic.filterChipLabel('favorite', this.selectedTagsSet(), this.selectedFolderIdsSet(), this.allNotes),
            this.activeFilterChip() === 'favorite',
            (): void => {
              this.selectedFilter = 'favorite'
              this.selectedTags = []
              this.selectedFolderIds = []
              this.rebuildListRows()
            }
          )
          this.buildFilterChipItem(
            NotesTabLogic.filterChipLabel('tags', this.selectedTagsSet(), this.selectedFolderIdsSet(), this.allNotes),
            this.activeFilterChip() === 'tags',
            (): void => { void this.pickTags() },
            true,
            'tags'
          )
          this.buildFilterChipItem(
            NotesTabLogic.filterChipLabel('folders', this.selectedTagsSet(), this.selectedFolderIdsSet(), this.allNotes),
            this.activeFilterChip() === 'folders',
            (): void => { void this.pickFolders() },
            true,
            'folders'
          )
        }
        .justifyContent(FlexAlign.Start)
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .align(Alignment.Start)
      .layoutWeight(1)
      Row({ space: 2 }) {
        SymbolGlyph($r('sys.symbol.line_3_horizontal'))
          .fontSize(16)
          .fontColor([$r('app.color.accent')])
        Text(LocaleService.loc('排序', 'Sort', '並べ替え'))
          .fontSize(14)
          .fontColor($r('app.color.accent'))
      }
      .padding({ left: 8, right: 0, top: 6, bottom: 6 })
      .flexShrink(0)
      .bindMenu([
        {
          value: LocaleService.loc('按创建时间排序', 'Sort by created', '作成日時'),
          action: (): void => { void this.setSort('created') }
        },
        {
          value: LocaleService.loc('按修改时间排序', 'Sort by modified', '更新日時'),
          action: (): void => { void this.setSort('modified') }
        },
        {
          value: LocaleService.loc('按类型排序', 'Sort by type', '種類'),
          action: (): void => { void this.setSort('type') }
        }
      ])
    }
    .width('100%')
    .padding({ left: PAGE_PAD, right: PAGE_PAD, top: 4, bottom: 8 })
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.filterPinBg())
  }

  @Builder
  buildFilterChipItem(
    label: string,
    selected: boolean,
    onTap: () => void,
    showArrow: boolean = false,
    trackKind: string = ''
  ) {
    Row({ space: 2 }) {
      Text(label)
        .fontSize(13)
        .fontWeight(selected ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(selected ? $r('app.color.accent') : $r('app.color.primary_text'))
      if (showArrow) {
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(14)
          .fontColor([selected ? $r('app.color.accent') : $r('app.color.secondary_text')])
      }
    }
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    .borderRadius(999)
    .backgroundColor(selected ? $r('app.color.notes_chip_selected') : $r('app.color.notes_chip_muted'))
    .onClick(onTap)
    .onAreaChange((_oldArea: Area, area: Area): void => {
      if (trackKind === 'tags') {
        this.recordFilterChipArea('tags', area)
      } else if (trackKind === 'folders') {
        this.recordFilterChipArea('folders', area)
      }
    })
  }

  @Builder
  buildEmptyState() {
    Column() {
      Text(this.searchQuery.trim().length > 0 ?
        LocaleService.loc('未找到匹配的笔记', 'No matching notes', '一致するノートなし') :
        LocaleService.loc('暂无笔记', 'No notes yet', 'ノートがありません'))
        .fontSize(14)
        .fontColor($r('app.color.secondary_text'))
    }
    .width('100%')
    .padding({ top: 48, bottom: 48 })
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildGroupHeader(row: NotesTabListRow) {
    Row({ space: 6 }) {
      // 箭头 | 固定宽占位 | 文件夹或标签。占位始终存在，用 width 切换 1.5/2.5。
      Row() {
        SymbolGlyph(row.groupExpanded ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right'))
          .fontSize(20)
          .fontColor([$r('app.color.secondary_text')])
          .width(20)
          .height(20)
        Column()
          .width(this.groupIconGapVp(row.groupExpanded))
          .height(20)
          .flexShrink(0)
          .backgroundColor(Color.Transparent)
        // 展开：保持实心；收起：空心（标签用 outline SVG，文件夹用 folder 线框）。
        if (this.displayMode === 'tag') {
          Image(row.groupExpanded ? $r('app.media.ic_tag_fill') : $r('app.media.ic_tag_outline'))
            .width(16)
            .height(16)
            .objectFit(ImageFit.Contain)
            .fillColor(row.groupExpanded ? $r('app.color.accent') : $r('app.color.secondary_text'))
        } else {
          SymbolGlyph(row.groupExpanded ? $r('sys.symbol.folder_fill') : $r('sys.symbol.folder'))
            .fontSize(16)
            .fontColor([row.groupExpanded ? $r('app.color.accent') : $r('app.color.secondary_text')])
            .width(16)
            .height(16)
        }
      }
      .alignItems(VerticalAlign.Center)
      .flexShrink(0)
      // 标题 + 数量左对齐紧挨；外层吃剩余宽度，子项不 stretch，避免数量被顶到最右。
      Row({ space: 4 }) {
        Text(row.groupTitle)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ minWidth: 0 })
          .flexGrow(0)
          .flexShrink(1)
        Text(`(${row.groupCount})`)
          .fontSize(13)
          .fontColor($r('app.color.secondary_text'))
          .flexGrow(0)
          .flexShrink(0)
      }
      .layoutWeight(1)
      .justifyContent(FlexAlign.Start)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ top: 12, bottom: 8, left: 2, right: 2 })
    .onClick((): void => {
      void this.toggleGroup(row.groupId)
    })
  }

  @Builder
  buildNoteTile(row: NotesTabListRow) {
    if (row.note !== null) {
      this.noteTileBody(row.note)
    }
  }

  @Builder
  noteTileBody(note: Note) {
    Row({ space: 10 }) {
      Column() {
        if (NotesTabLogic.leadingKindFor(note, this.mindMapSet()) === 'mp3') {
          // mp3 音频笔记：图标复用笔记统计卡「图谱」旧版（sys.symbol.shareplay），按主题 accent 绿色上色。
          SymbolGlyph($r('sys.symbol.shareplay'))
            .fontSize(18)
            .fontColor([$r('app.color.calendar_kind_note_fg')])
        } else if (NotesTabLogic.leadingKindFor(note, this.mindMapSet()) === 'flowchart') {
          // 思维导图：与首页快捷创建卡「思维导图」入口同图，三个 tab 共用蓝色。
          Image($r('app.media.ic_quick_mindmap'))
            .width(18)
            .height(18)
            .objectFit(ImageFit.Contain)
            .fillColor(this.noteLeadingColor(NotesTabLogic.leadingKindFor(note, this.mindMapSet())))
        } else if (NotesTabLogic.leadingKindFor(note, this.mindMapSet()) === 'knowledgeGraph') {
          // 知识图谱：图一 SVG，三个 tab 共用蓝色。
          Image($r('app.media.ic_note_knowledge_graph'))
            .width(18)
            .height(18)
            .objectFit(ImageFit.Contain)
            .fillColor(this.noteLeadingColor(NotesTabLogic.leadingKindFor(note, this.mindMapSet())))
        } else if (NotesTabLogic.leadingKindFor(note, this.mindMapSet()) === 'todo') {
          // 待办事项：与首页快捷创建卡「待办事项」入口同图（ic_quick_todo.svg），三个 tab 共用橙色。
          Image($r('app.media.ic_quick_todo'))
            .width(18)
            .height(18)
            .objectFit(ImageFit.Contain)
            .fillColor(this.noteLeadingColor(NotesTabLogic.leadingKindFor(note, this.mindMapSet())))
        } else if (NotesTabLogic.leadingKindFor(note, this.mindMapSet()) === 'schedule') {
          // 待办日程：三个 tab 共用紫色。
          SymbolGlyph($r('sys.symbol.calendar'))
            .fontSize(18)
            .fontColor([this.noteLeadingColor(NotesTabLogic.leadingKindFor(note, this.mindMapSet()))])
        } else if (NotesTabLogic.leadingKindFor(note, this.mindMapSet()) === 'extract') {
          SymbolGlyph($r('sys.symbol.link'))
            .fontSize(18)
            .fontColor([this.noteLeadingColor(NotesTabLogic.leadingKindFor(note, this.mindMapSet()))])
        } else {
          SymbolGlyph($r('sys.symbol.doc_text'))
            .fontSize(18)
            .fontColor([this.noteLeadingColor(NotesTabLogic.leadingKindFor(note, this.mindMapSet()))])
        }
      }
      .width(40)
      .height(40)
      .justifyContent(FlexAlign.Center)
      .borderRadius(10)
      // 边框与图标本身同色（与首页 tab 笔记列表保持一致语义）。
      .border({ width: 1.2, color: this.noteLeadingColor(NotesTabLogic.leadingKindFor(note, this.mindMapSet())) })
      // 中心到边缘的径向渐变（与首页 tab 笔记统计卡 stat 同款 80% → 95% 白色）。
      .radialGradient({
        center: [20, 20],
        radius: 24,
        colors: [
          [this.leadingSoftInner(NotesTabLogic.leadingKindFor(note, this.mindMapSet())), 0.0],
          [this.leadingSoftOuter(NotesTabLogic.leadingKindFor(note, this.mindMapSet())), 1.0]
        ]
      })
      Column({ space: 3 }) {
        Row({ space: 6 }) {
          Text(this.noteTitleLabel(note))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(note.extractStatus === 'failed' ? $r('app.color.danger') : $r('app.color.primary_text'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (isExtractStatusPending(note.extractStatus)) {
            Text(LocaleService.loc('进行中', 'In progress', '進行中'))
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.warning'))
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(8)
              .backgroundColor($r('app.color.warning_subtle'))
          }
        }
        .width('100%')
        Text(this.noteSubtitleLabel(note))
          .fontSize(12)
          .fontColor(note.extractStatus === 'failed' ? $r('app.color.danger') : $r('app.color.secondary_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (!isExtractStatusPending(note.extractStatus) &&
          note.extractStatus !== 'failed' &&
          note.tags.length > 0) {
          Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Start }) {
            ForEach(this.visibleTags(note), (tag: string, index: number) => {
              Text(`#${tag}`)
                .fontSize(11)
                .fontColor(this.tagFg(index))
                .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                .margin({ right: 6, top: 2 })
                .borderRadius(999)
                .backgroundColor(this.tagBg(index))
            }, (tag: string, index: number) => `${note.id}_tag_${index}_${tag}`)
          }
          .width('100%')
          .margin({ top: 3 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      if (isExtractStatusPending(note.extractStatus)) {
        Column({ space: 6 }) {
          Text(LocaleService.loc('提取中', 'Extracting', '抽出中'))
            .fontSize(11)
            .fontColor($r('app.color.secondary_text'))
          LoadingProgress()
            .width(18)
            .height(18)
            .color($r('app.color.warning'))
        }
        .alignItems(HorizontalAlign.End)
        .flexShrink(0)
      } else if (note.extractStatus === 'failed') {
        Row({ space: 6 }) {
          Text(LocaleService.loc('重试', 'Retry', '再試行'))
            .fontSize(12)
            .fontColor($r('app.color.danger'))
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .border({ width: 1, color: $r('app.color.danger'), radius: 8 })
            .onClick((): void => {
              void this.openNote(note)
            })
          SymbolGlyph((note.isFavorite ?? 0) !== 0 ? $r('sys.symbol.star_fill') : $r('sys.symbol.star'))
            .fontSize(16)
            .fontColor([(note.isFavorite ?? 0) !== 0 ? $r('app.color.accent') : $r('app.color.secondary_text')])
            .onClick((): void => {
              void this.toggleFavorite(note)
            })
        }
        .flexShrink(0)
      } else {
        Column({ space: 6 }) {
          Row({ space: 6 }) {
            Text(NotesTabLogic.relativeTimeLabel(note.updatedAt > 0 ? note.updatedAt : note.localModified))
              .fontSize(11)
              .fontColor($r('app.color.secondary_text'))
            SymbolGlyph((note.isFavorite ?? 0) !== 0 ? $r('sys.symbol.star_fill') : $r('sys.symbol.star'))
              .fontSize(16)
              .fontColor([(note.isFavorite ?? 0) !== 0 ? $r('app.color.accent') : $r('app.color.secondary_text')])
              .onClick((): void => {
                void this.toggleFavorite(note)
              })
          }
          .justifyContent(FlexAlign.End)
          if (this.thumbUri(note).length > 0) {
            Image(this.thumbUri(note))
              .width(48)
              .height(48)
              .borderRadius(8)
              .objectFit(ImageFit.Cover)
          }
        }
        .alignItems(HorizontalAlign.End)
        .flexShrink(0)
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ top: 10, bottom: 10, left: 2, right: 2 })
    .border({ width: { bottom: 0.5 }, color: $r('app.color.divider') })
    .onClick((): void => {
      void this.openNote(note)
    })
  }

  private noteTitleLabel(note: Note): string {
    if (isExtractStatusPending(note.extractStatus)) {
      return LocaleService.loc('AI 提取链接中…', 'AI extracting link…', 'AIリンク抽出中…')
    }
    if (note.extractStatus === 'failed') {
      return LocaleService.loc('AI 提取失败', 'AI extract failed', 'AI抽出失敗')
    }
    const t = `${note.title ?? ''}`.trim()
    return t.length > 0 ? t : LocaleService.loc('无标题', 'Untitled', '無題')
  }

  private noteSubtitleLabel(note: Note): string {
    if (isExtractStatusPending(note.extractStatus) || note.extractStatus === 'failed') {
      const url = `${note.sourceUrl ?? ''}`.trim()
      if (url.length > 0) {
        return url
      }
    }
    return this.snippetFor(note)
  }

  /**
   * 笔记列表 leading icon 的「主色」：与首页 / 日历三个 tab 共用，
   * 4 种语义图标（思维导图 / 知识图谱 / 待办 / 日程）使用对应主题色资源，
   * 其它类型（mp3 / 提取中链接 / 普通文档）走主题 accent。
   */
  private noteLeadingColor(leadingKind: string): ResourceColor {
    if (leadingKind === 'flowchart') {
      return $r('app.color.note_leading_mindmap_fg')
    }
    if (leadingKind === 'knowledgeGraph') {
      return $r('app.color.note_leading_knowledge_graph_fg')
    }
    if (leadingKind === 'todo') {
      return $r('app.color.calendar_kind_todo_fg')
    }
    if (leadingKind === 'schedule') {
      // 待办日程与待办事项共用 todo 橙，视觉上两者不再区分（与首页 tab 一致）。
      return $r('app.color.calendar_kind_todo_fg')
    }
    return $r('app.color.calendar_kind_note_fg')
  }

  /** 笔记 tab 列表 icon 盒子径向渐变内层（80% 白色混合）。 */
  private leadingSoftInner(leadingKind: string): string {
    // 思维导图 / 知识图谱共用蓝色（首页 tab 标签图标色 = #3B82F6），
    // 共用蓝色径向渐变内/外圈，保持视觉一致。
    if (leadingKind === 'flowchart' || leadingKind === 'knowledgeGraph') {
      return '#D8E6FD'
    }
    if (leadingKind === 'todo') {
      return '#FDECCE'
    }
    if (leadingKind === 'schedule') {
      // 待办日程与待办事项共用 todo 同款橙色径向渐变底色。
      return '#FDECCE'
    }
    return '#CFEEDB'
  }

  /** 笔记 tab 列表 icon 盒子径向渐变外层（95% 白色混合）。 */
  private leadingSoftOuter(leadingKind: string): string {
    if (leadingKind === 'flowchart' || leadingKind === 'knowledgeGraph') {
      return '#F5F9FF'
    }
    if (leadingKind === 'todo') {
      return '#FFFAF3'
    }
    if (leadingKind === 'schedule') {
      // 待办日程与待办事项共用 todo 同款橙色径向渐变底色。
      return '#FFFAF3'
    }
    return '#F3FBF6'
  }

  private tagFg(index: number): ResourceColor {
    const colors: ResourceColor[] = [
      $r('app.color.notes_tag_fg_blue'),
      $r('app.color.notes_tag_fg_green'),
      $r('app.color.notes_tag_fg_gray')
    ]
    return colors[index % colors.length]
  }

  private tagBg(index: number): ResourceColor {
    const colors: ResourceColor[] = [
      $r('app.color.notes_tag_bg_blue'),
      $r('app.color.notes_tag_bg_green'),
      $r('app.color.notes_tag_bg_gray')
    ]
    return colors[index % colors.length]
  }

  private snippetFor(note: Note): string {
    const summary = `${note.summary ?? ''}`.trim()
    if (summary.length > 0) {
      return summary
    }
    const content = `${note.content ?? ''}`.trim().replace(/\s+/g, ' ')
    return content.length > 0 ? content :
      LocaleService.loc('暂无内容', 'No content', '内容なし')
  }

  private visibleTags(note: Note): string[] {
    const out: string[] = []
    for (let i = 0; i < note.tags.length; i++) {
      const t = `${note.tags[i] ?? ''}`.trim()
      if (t.length > 0) {
        out.push(t)
      }
    }
    return out
  }

  @Builder
  buildDeleteAction(note: Note) {
    Row() {
      Text(LocaleService.loc('删除', 'Delete', '削除'))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.on_accent'))
    }
    .width(88)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.danger'))
    .onClick((): void => {
      void this.handleDelete(note.id)
    })
  }

  @Builder
  buildUndoBar() {
    Row() {
      Text(LocaleService.loc('已删除', 'Deleted', '削除しました'))
        .fontSize(14)
        .fontColor($r('app.color.on_accent'))
        .layoutWeight(1)
      Text(LocaleService.loc('撤销', 'Undo', '元に戻す'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.accent'))
        .onClick((): void => {
          void this.undoDelete()
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor('#CC000000')
  }

  @Builder
  buildFilterDropdownOverlay() {
    Column() {
      // 顶部占位高度 = 芯片底边相对本页 Stack 的偏移，随滚动更新。
      Blank()
        .width('100%')
        .height(this.filterDropdownTop)
        .onClick((): void => {
          this.applyMultiSelect()
        })
      Row() {
        Blank()
          .width(this.filterDropdownLeft)
          .onClick((): void => {
            this.applyMultiSelect()
          })
        Column() {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.folder'))
              .fontSize(16)
              .fontColor([$r('app.color.accent')])
            Text(this.multiSelectTitle)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
          }
          .width('100%')
          .justifyContent(FlexAlign.Start)
          .padding({ left: 14, right: 14, top: 12, bottom: 8 })
          Divider().color($r('app.color.divider'))
          Scroll() {
            Column() {
              ForEach(this.multiSelectItems, (item: NotesTabMultiSelectItem) => {
                Row({ space: 8 }) {
                  Text(`${item.label}  ${item.count}`)
                    .fontSize(14)
                    .fontColor($r('app.color.primary_text'))
                  if (this.multiSelectDraft.indexOf(item.id) >= 0) {
                    SymbolGlyph($r('sys.symbol.checkmark'))
                      .fontSize(18)
                      .fontColor([$r('app.color.accent')])
                  } else {
                    Blank().width(18).height(18)
                  }
                }
                .width('100%')
                .justifyContent(FlexAlign.Start)
                .padding({ left: 14, right: 14, top: 10, bottom: 10 })
                .onClick((): void => {
                  const next = this.multiSelectDraft.slice()
                  const idx = next.indexOf(item.id)
                  if (idx >= 0) {
                    next.splice(idx, 1)
                  } else {
                    next.push(item.id)
                  }
                  this.multiSelectDraft = next
                })
              }, (item: NotesTabMultiSelectItem) => item.id)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .constraintSize({ maxHeight: 280 })
          .scrollBar(BarState.Off)
          Divider().color($r('app.color.divider'))
          Row({ space: 16 }) {
            Text(this.multiSelectKind === 'tags' ?
              LocaleService.loc('管理标签', 'Manage tags', 'タグ管理') :
              LocaleService.loc('管理文件夹', 'Manage folders', 'フォルダ管理'))
              .fontSize(13)
              .fontColor($r('app.color.accent'))
            SymbolGlyph($r('sys.symbol.gearshape'))
              .fontSize(16)
              .fontColor([$r('app.color.accent')])
          }
          .width('100%')
          .justifyContent(FlexAlign.Start)
          .padding({ left: 14, right: 14, top: 10, bottom: 12 })
          .onClick((): void => {
            this.applyMultiSelect()
            void this.openManageEntry(this.multiSelectKind === 'tags' ? 'tag' : 'folder')
          })
        }
        .width(this.filterDropdownWidth())
        .alignItems(HorizontalAlign.Start)
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(12)
        .shadow({ radius: 16, color: $r('app.color.shadow_color'), offsetX: 0, offsetY: 4 })
        .flexShrink(0)
        Blank()
          .layoutWeight(1)
          .onClick((): void => {
            this.applyMultiSelect()
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      Blank()
        .width('100%')
        .layoutWeight(1)
        .onClick((): void => {
          this.applyMultiSelect()
        })
    }
    .width('100%')
    .height('100%')
  }
}
