import type { CreateNoteInput, Note } from '../common/model/Note'
import { NoteFolderTree, type FolderManageRow, type MovePickerEntry } from '../common/utils/NoteFolderTree'
import { NoteRepository } from '../services/NoteRepository'
import { PageLifecycle } from '../common/utils/PageLifecycle'
import { PageCloseGuard } from '../common/utils/PageCloseGuard'

@Entry
@Component
struct FolderManage {
  @State notes: Note[] = []
  @State rows: FolderManageRow[] = []
  @State loading: boolean = true
  @State busy: boolean = false

  @State draggingNoteId: string = ''
  @State hoverIntoFolderId: string = ''
  @State insertBeforeIndex: number = -1

  @State creatingActive: boolean = false
  @State creatingUnderParentId: string = ''
  @State createTitle: string = ''

  @State menuVisible: boolean = false
  @State menuX: number = 0
  @State menuY: number = 0
  @State menuRowId: string = ''

  @State pickerVisible: boolean = false
  @State pickerHint: string = ''
  @State pickerSourceId: string = ''
  @State pickerMode: string = ''
  @State expandedFolderIds: string[] = [NoteFolderTree.VIRTUAL_ROOT_FOLDER_ID]
  @State pageWidth: number = 360
  @State pageHeight: number = 800

  private readonly defaultFolderTitle: string = '未命名文档'
  private readonly menuWidth: number = 168
  private readonly menuHeight: number = 132
  private readonly indentPerDepth: number = 14
  private readonly baseIndent: number = 12
  private readonly rowInsertEdgeMaxPx: number = 10
  private readonly rowInsertEdgeFraction: number = 0.18
  private readonly estimatedManageRowHeight: number = 44
  private readonly dragGhostOpacity: number = 0.45
  private readonly dropBorderWidth: number = 2
  private rowAreaHeights: Map<string, number> = new Map()
  private rowAreaWindowTops: Map<string, number> = new Map()
  private lifecycle = new PageLifecycle()
  private closeGuard = new PageCloseGuard()

  aboutToAppear(): void {
    this.lifecycle.appear()
    this.closeGuard.reset()
    void this.loadNotes()
  }

  aboutToDisappear(): void {
    this.lifecycle.disappear()
  }

  private async loadNotes(): Promise<void> {
    if (!this.lifecycle.isActive()) {
      return
    }
    this.loading = true
    await NoteRepository.getInstance().init()
    const list = await NoteRepository.getInstance().listNotes()
    const allList = await NoteRepository.getInstance().listAllNotes()
    if (!this.lifecycle.isActive()) {
      return
    }
    this.notes = list
    this.rows = NoteFolderTree.visibleManageRows(list, allList)
    this.loading = false
  }

  private showUserMessage(message: string): void {
    if (`${message ?? ''}`.trim().length === 0 || !this.lifecycle.isActive()) {
      return
    }
    try {
      this.getUIContext().getPromptAction().showToast({ message, duration: 2000 })
    } catch (error) {
      console.error(`showToast failed: ${JSON.stringify(error)}`)
    }
  }

  private clearDragUi(): void {
    this.draggingNoteId = ''
    this.hoverIntoFolderId = ''
    this.insertBeforeIndex = -1
  }

  private rowInsertEdgeHeight(rowHeight: number): number {
    const scaled = rowHeight * this.rowInsertEdgeFraction
    return scaled > this.rowInsertEdgeMaxPx ? this.rowInsertEdgeMaxPx : scaled
  }

  private shareInsertParent(a: FolderManageRow, b: FolderManageRow): boolean {
    if (a.isRoot === true || b.isRoot === true) {
      return false
    }
    const parentA = NoteFolderTree.rawParentIdForManageRow(a, this.notes)
    const parentB = NoteFolderTree.rawParentIdForManageRow(b, this.notes)
    return parentA === parentB
  }

  private isDropIntoTarget(row: FolderManageRow): boolean {
    return this.hoverIntoFolderId === row.noteId && this.draggingNoteId.length > 0
  }

  /** ForEach key 纳入拖拽高亮/插入位/隐藏源行，避免 hover 变化时 skip mark dirty。 */
  private manageRowForEachKey(row: FolderManageRow, index: number): string {
    const hoverPart = this.hoverIntoFolderId === row.noteId ? 'h' : ''
    const insertPart = this.insertBeforeIndex === index ? 'i' : ''
    const dragPart = this.draggingNoteId === row.noteId ? 'g' : ''
    return `fm_${row.noteId}_${index}_${hoverPart}${insertPart}${dragPart}`
  }

  private recordRowDropArea(rowId: string, area: Area): void {
    const h = Number.parseFloat(`${area.height}`)
    if (h <= 0) {
      return
    }
    const globalY = Number.parseFloat(`${area.globalPosition?.y ?? -1}`)
    const localY = Number.parseFloat(`${area.position?.y ?? -1}`)
    const top = globalY >= 0 ? globalY : localY
    this.rowAreaHeights.set(rowId, h)
    this.rowAreaWindowTops.set(rowId, top)
  }

  private handleRowDragMove(row: FolderManageRow, index: number, event: DragEvent): void {
    if (this.draggingNoteId.length === 0) {
      return
    }
    const height = this.rowAreaHeights.get(row.noteId) ?? this.estimatedManageRowHeight
    const areaTop = this.rowAreaWindowTops.get(row.noteId) ?? 0
    const y = event.getWindowY() - areaTop
    const edge = this.rowInsertEdgeHeight(height)
    const dropBottom = height - edge
    const canDrop = this.canDropOnRow(this.draggingNoteId, row)

    if (y >= edge && y <= dropBottom) {
      if (canDrop) {
        this.hoverIntoFolderId = row.noteId
        this.insertBeforeIndex = -1
      }
    } else if (y > dropBottom) {
      const nextIndex = index + 1
      if (this.canInsertBefore(this.draggingNoteId, nextIndex)) {
        this.insertBeforeIndex = nextIndex
        this.hoverIntoFolderId = ''
      }
    } else if (index > 0) {
      const prev = this.rows[index - 1]
      if (this.shareInsertParent(prev, row)) {
        if (canDrop) {
          this.hoverIntoFolderId = row.noteId
          this.insertBeforeIndex = -1
        }
      } else if (this.canInsertBefore(this.draggingNoteId, index)) {
        this.insertBeforeIndex = index
        this.hoverIntoFolderId = ''
      }
    } else if (this.canInsertBefore(this.draggingNoteId, index)) {
      this.insertBeforeIndex = index
      this.hoverIntoFolderId = ''
    }
  }

  private createParentIdForRow(row: FolderManageRow): string {
    return row.isRoot === true ? '' : row.noteId
  }

  private draggingRow(): FolderManageRow | undefined {
    if (this.draggingNoteId.length === 0) {
      return undefined
    }
    return this.rows.find((r: FolderManageRow) => r.noteId === this.draggingNoteId)
  }

  private describeCanDropOnRow(draggedId: string, target: FolderManageRow): string {
    if (draggedId.length === 0) {
      return 'empty-dragged'
    }
    const targetParentId = NoteFolderTree.parentIdForDropOnRow(target)
    if (draggedId === target.noteId) {
      return 'same-node'
    }
    if (NoteFolderTree.wouldCreateParentCycle(draggedId, targetParentId, this.notes)) {
      return `parent-cycle newParent=${targetParentId}`
    }
    if (targetParentId.length > 0 &&
      NoteFolderTree.isDescendantOf(draggedId, targetParentId, this.notes)) {
      return `descendant-block targetParent=${targetParentId}`
    }
    return 'ok'
  }

  private canDropOnRow(draggedId: string, target: FolderManageRow): boolean {
    return this.describeCanDropOnRow(draggedId, target) === 'ok'
  }

  private canInsertBefore(draggedId: string, index: number): boolean {
    const parentId = NoteFolderTree.parentIdForInsertBefore(this.rows, index, this.notes)
    return !NoteFolderTree.wouldCreateParentCycle(draggedId, parentId, this.notes)
  }

  private expandedFolderIdSet(): Set<string> {
    return new Set(this.expandedFolderIds)
  }

  private getMovePickerEntries(): MovePickerEntry[] {
    return NoteFolderTree.visibleMovePickerEntries(
      this.notes,
      this.expandedFolderIdSet(),
      this.pickerSourceId
    )
  }

  private isMovePickerEntryExpanded(entry: MovePickerEntry): boolean {
    return this.expandedFolderIds.indexOf(entry.id) >= 0
  }

  private onToggleFolderExpand(folderId: string): void {
    if (folderId === NoteFolderTree.VIRTUAL_ROOT_FOLDER_ID) {
      const idx = this.expandedFolderIds.indexOf(folderId)
      if (idx >= 0) {
        this.expandedFolderIds = this.expandedFolderIds.filter((id: string) => id !== folderId)
      } else {
        this.expandedFolderIds = this.expandedFolderIds.concat([folderId])
      }
      return
    }
    const expanded = this.expandedFolderIdSet()
    NoteFolderTree.applyToggleExpand(folderId, this.notes, expanded)
    this.expandedFolderIds = Array.from(expanded)
  }

  private async moveFolder(noteId: string, newParentId: string): Promise<void> {
    if (this.busy) {
      return
    }
    this.busy = true
    try {
      await NoteRepository.getInstance().saveDraft(noteId, { parentId: newParentId.trim() })
      await this.loadNotes()
    } catch (error) {
      console.error(JSON.stringify(error))
      this.showUserMessage('移动失败，请稍后重试')
    } finally {
      this.busy = false
    }
  }

  private async confirmCreateUnder(parentId: string): Promise<void> {
    if (this.busy) {
      return
    }
    const raw = this.createTitle.trim()
    const title = raw.length > 0 ? raw : this.defaultFolderTitle
    this.busy = true
    try {
      const input: CreateNoteInput = {
        title,
        content: '',
        tags: [],
        skipTitleAutoFill: true
      }
      const note = await NoteRepository.getInstance().createNote(input)
      const parent = `${parentId ?? ''}`.trim()
      if (parent.length > 0) {
        await NoteRepository.getInstance().saveDraft(note.id, {
          parentId: parent,
          skipTitleAutoFill: true
        })
      }
      this.creatingActive = false
      this.creatingUnderParentId = ''
      this.createTitle = ''
      await this.loadNotes()
    } catch (error) {
      console.error(JSON.stringify(error))
      this.showUserMessage('创建失败，请稍后重试')
    } finally {
      this.busy = false
    }
  }

  private async copySubtree(sourceId: string, targetParentId: string): Promise<void> {
    const byId: Map<string, Note> = new Map()
    for (const note of this.notes) {
      byId.set(note.id, note)
    }
    const ordered: string[] = []
    const walk = (id: string): void => {
      ordered.push(id)
      for (const note of this.notes) {
        if (note.deleted || (note.deletedTime ?? 0) !== 0) {
          continue
        }
        if (`${note.parentId ?? ''}`.trim() !== id) {
          continue
        }
        walk(note.id)
      }
    }
    walk(sourceId)

    const idMap: Map<string, string> = new Map()
    for (const oldId of ordered) {
      const source = byId.get(oldId) ?? await NoteRepository.getInstance().getNote(oldId)
      if (!source) {
        continue
      }
      const newParent = oldId === sourceId ?
        targetParentId.trim() :
        (idMap.get(`${source.parentId ?? ''}`.trim()) ?? targetParentId.trim())
      const created = await NoteRepository.getInstance().createNote({
        title: source.title,
        content: source.content,
        tags: source.tags,
        skipTitleAutoFill: `${source.title ?? ''}`.trim().length === 0
      })
      idMap.set(oldId, created.id)
      if (newParent.length > 0 || oldId !== sourceId) {
        await NoteRepository.getInstance().saveDraft(created.id, {
          parentId: newParent,
          skipTitleAutoFill: `${source.title ?? ''}`.trim().length === 0
        })
      }
    }
  }

  private async deleteFolderOnly(folderId: string): Promise<void> {
    const byId: Map<string, Note> = new Map()
    for (const note of this.notes) {
      byId.set(note.id, note)
    }
    const folder = byId.get(folderId)
    if (folder === undefined) {
      return
    }
    const newParent = `${folder.parentId ?? ''}`.trim()
    this.busy = true
    try {
      for (const note of this.notes) {
        if (`${note.parentId ?? ''}`.trim() === folderId) {
          await NoteRepository.getInstance().saveDraft(note.id, { parentId: newParent })
        }
      }
      await NoteRepository.getInstance().deleteNote(folderId, Date.now())
      await this.loadNotes()
    } catch (error) {
      console.error(JSON.stringify(error))
      this.showUserMessage('删除失败，请稍后重试')
    } finally {
      this.busy = false
    }
  }

  private depthOf(noteId: string): number {
    const byId: Map<string, Note> = new Map()
    for (const note of this.notes) {
      byId.set(note.id, note)
    }
    let depth = 0
    let current = `${byId.get(noteId)?.parentId ?? ''}`.trim()
    const visited: Set<string> = new Set()
    while (current.length > 0 && !visited.has(current)) {
      depth += 1
      visited.add(current)
      current = `${byId.get(current)?.parentId ?? ''}`.trim()
    }
    return depth
  }

  private async deleteFolderWithDescendants(folderId: string): Promise<void> {
    this.busy = true
    try {
      const descendants = Array.from(NoteFolderTree.descendantNoteIds(folderId, this.notes))
      descendants.sort((a: string, b: string) => this.depthOf(b) - this.depthOf(a))
      const now = Date.now()
      for (const id of descendants) {
        await NoteRepository.getInstance().deleteNote(id, now)
      }
      await NoteRepository.getInstance().deleteNote(folderId, now)
      await this.loadNotes()
    } catch (error) {
      console.error(JSON.stringify(error))
      this.showUserMessage('删除失败，请稍后重试')
    } finally {
      this.busy = false
    }
  }

  private openPicker(sourceId: string, hint: string, mode: string): void {
    this.pickerSourceId = sourceId
    this.pickerHint = hint
    this.pickerMode = mode
    this.pickerVisible = true
    if (this.expandedFolderIds.indexOf(NoteFolderTree.VIRTUAL_ROOT_FOLDER_ID) < 0) {
      this.expandedFolderIds = [NoteFolderTree.VIRTUAL_ROOT_FOLDER_ID].concat(this.expandedFolderIds)
    }
  }

  private async onPickerSelect(targetParentId: string): Promise<void> {
    const sourceId = this.pickerSourceId
    const mode = this.pickerMode
    this.pickerVisible = false
    if (sourceId.length === 0) {
      return
    }
    if (mode === 'copy') {
      this.busy = true
      try {
        await this.copySubtree(sourceId, targetParentId)
        await this.loadNotes()
        this.showUserMessage('已创建副本')
      } catch (error) {
        console.error(JSON.stringify(error))
        this.showUserMessage('创建副本失败，请稍后重试')
      } finally {
        this.busy = false
      }
      return
    }
    await this.moveFolder(sourceId, targetParentId)
  }

  private async confirmDelete(row: FolderManageRow): Promise<void> {
    try {
      if (!row.isFolder) {
        const result = await this.getUIContext().getPromptAction().showDialog({
          title: `删除「${row.title}」`,
          message: '确定删除该文件吗？',
          buttons: [
            { text: '删除', color: '#FF3B30' },
            { text: '取消', color: '#8E8E93' }
          ]
        })
        if (result.index === 0) {
          await this.deleteFolderWithDescendants(row.noteId)
        }
        return
      }
      if (row.isRoot === true) {
        return
      }
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: `删除「${row.title}」`,
        message: '请选择删除方式',
        buttons: [
          { text: '仅删除当前页面', color: '#007AFF' },
          { text: '删除当前页面及全部子页面', color: '#FF3B30' },
          { text: '取消', color: '#8E8E93' }
        ]
      })
      if (result.index === 0) {
        await this.deleteFolderOnly(row.noteId)
      } else if (result.index === 1) {
        await this.deleteFolderWithDescendants(row.noteId)
      }
    } catch (error) {
      console.error(JSON.stringify(error))
    }
  }

  private dragTitle(noteId: string): string {
    const row = this.rows.find((r: FolderManageRow) => r.noteId === noteId)
    return row !== undefined ? row.title : '文件夹'
  }

  private openRowMenu(row: FolderManageRow, touchX: number, touchY: number): void {
    const edge = 8
    let x = touchX - this.menuWidth
    let y = touchY - this.menuHeight / 2
    if (x < edge) {
      x = edge
    }
    if (x + this.menuWidth > this.pageWidth - edge) {
      x = this.pageWidth - this.menuWidth - edge
    }
    if (y < edge) {
      y = edge
    }
    if (y + this.menuHeight > this.pageHeight - edge) {
      y = this.pageHeight - this.menuHeight - edge
    }
    this.menuRowId = row.noteId
    this.menuX = x
    this.menuY = y
    this.menuVisible = true
  }

  @Builder
  private buildDragPlaceholder(depth: number) {
    if (this.draggingRow() !== undefined) {
      Row() {
        this.buildItemRow({
          noteId: this.draggingNoteId,
          title: this.dragTitle(this.draggingNoteId),
          depth: depth,
          isFolder: this.draggingRow()?.isFolder === true
        }, false)
      }
      .width('100%')
      .opacity(this.dragGhostOpacity)
    }
  }

  @Builder
  private buildDropIntoFolderGroup(row: FolderManageRow, dropActive: boolean) {
    Column() {
      Row() {
        this.buildItemRow(row, !this.busy)
      }
      .width('100%')

      if (dropActive) {
        this.buildDragPlaceholder(row.depth + 1)
      }
    }
    .width('100%')
    .backgroundColor(dropActive ? $r('app.color.accent_subtle') : Color.Transparent)
    .borderRadius(12)
    .border({
      width: dropActive ? this.dropBorderWidth : 0,
      color: dropActive ? $r('app.color.accent') : Color.Transparent
    })
    .onAreaChange((_: Area, area: Area) => {
      this.recordRowDropArea(row.noteId, area)
    })
  }

  @Builder
  private buildInsertSlot(index: number) {
    if (this.insertBeforeIndex === index && this.draggingNoteId.length > 0) {
      this.buildDragPlaceholder(NoteFolderTree.depthForInsertBefore(this.rows, index))
    } else {
      Row().height(this.draggingNoteId.length > 0 ? 8 : 4)
    }
  }

  @Builder
  private buildInlineCreate(depth: number) {
    Row({ space: 8 }) {
      TextInput({ text: this.createTitle, placeholder: this.defaultFolderTitle })
        .layoutWeight(1)
        .height(40)
        .backgroundColor($r('app.color.surface_muted'))
        .borderRadius(8)
        .onChange((value: string) => {
          this.createTitle = value
        })
        .onSubmit(() => {
          void this.confirmCreateUnder(this.creatingUnderParentId)
        })
      SymbolGlyph($r('sys.symbol.checkmark'))
        .fontSize(20)
        .fontColor([$r('app.color.accent')])
        .onClick(() => {
          void this.confirmCreateUnder(this.creatingUnderParentId)
        })
      SymbolGlyph($r('sys.symbol.xmark'))
        .fontSize(18)
        .fontColor([$r('app.color.tertiary_text')])
        .onClick(() => {
          this.creatingActive = false
          this.creatingUnderParentId = ''
          this.createTitle = ''
        })
    }
    .width('100%')
    .padding({
      left: this.baseIndent + depth * this.indentPerDepth + 12,
      right: 8,
      bottom: 6
    })
  }

  @Builder
  private buildItemRow(row: FolderManageRow, showActions: boolean) {
    Row({ space: 10 }) {
      if (row.isFolder) {
        Image(row.isRoot === true ? $r('app.media.ic_folder_open') : $r('app.media.ic_folder_closed'))
          .width(20)
          .height(20)
          .objectFit(ImageFit.Contain)
      } else {
        SymbolGlyph($r('sys.symbol.doc_text'))
          .fontSize(18)
          .fontColor([$r('app.color.accent')])
      }
      Text(row.title)
        .fontSize($r('app.float.body_font_size'))
        .fontWeight(row.isRoot === true ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(row.isRoot === true ? $r('app.color.accent') : $r('app.color.primary_text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      if (showActions && row.isRoot !== true) {
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(20)
          .fontColor([$r('app.color.tertiary_text')])
          .onClick(() => {
            this.creatingActive = true
            this.creatingUnderParentId = this.createParentIdForRow(row)
            this.createTitle = ''
          })
        SymbolGlyph($r('sys.symbol.line_3_horizontal'))
          .fontSize(20)
          .fontColor([$r('app.color.tertiary_text')])
          .margin({ left: 4 })
          .onClick((event: ClickEvent) => {
            this.openRowMenu(row, event.displayX, event.displayY)
          })
      }
    }
    .width('100%')
    .padding({
      left: this.baseIndent + row.depth * this.indentPerDepth,
      right: 8,
      top: 10,
      bottom: 10
    })
  }

  @Builder
  private buildManageRow(row: FolderManageRow, index: number) {
    Column() {
      Row() {
        this.buildInsertSlot(index)
      }
      .width('100%')
      .onDrop(() => {
        const canInsert = this.draggingNoteId.length > 0 &&
          this.canInsertBefore(this.draggingNoteId, index)
        if (canInsert) {
          const parentId = NoteFolderTree.parentIdForInsertBefore(this.rows, index, this.notes)
          const dragged = this.draggingNoteId
          this.clearDragUi()
          void this.moveFolder(dragged, parentId)
        }
      })

      Column() {
        if (this.draggingNoteId !== row.noteId) {
          this.buildDropIntoFolderGroup(row, this.isDropIntoTarget(row))
        }
      }
      .width('100%')
      .draggable(row.isRoot !== true)
      .onDragStart(() => {
        if (!this.busy && row.isRoot !== true) {
          this.draggingNoteId = row.noteId
        }
      })
      .onDragEnd(() => {
        this.clearDragUi()
      })
      .onDragEnter((event: DragEvent) => {
        const canDrop = this.draggingNoteId.length > 0 && this.canDropOnRow(this.draggingNoteId, row)
        if (canDrop) {
          this.hoverIntoFolderId = row.noteId
          this.insertBeforeIndex = -1
        }
        this.handleRowDragMove(row, index, event)
      })
      .onDragMove((event: DragEvent) => {
        this.handleRowDragMove(row, index, event)
      })
      .onDragLeave(() => {
        if (this.hoverIntoFolderId === row.noteId) {
          this.hoverIntoFolderId = ''
        }
      })
      .onDrop(() => {
        const canDrop = this.draggingNoteId.length > 0 && this.canDropOnRow(this.draggingNoteId, row)
        if (canDrop) {
          const dragged = this.draggingNoteId
          const parentId = NoteFolderTree.parentIdForDropOnRow(row)
          this.clearDragUi()
          void this.moveFolder(dragged, parentId)
        }
      })

      if (this.creatingActive && this.creatingUnderParentId === this.createParentIdForRow(row)) {
        this.buildInlineCreate(row.depth + 1)
      }
    }
    .width('100%')
  }

  @Builder
  private buildMovePickerFolderRow(entry: MovePickerEntry) {
    Row() {
      Image(this.isMovePickerEntryExpanded(entry) ? $r('app.media.ic_folder_open') : $r('app.media.ic_folder_closed'))
        .width(20)
        .height(20)
        .objectFit(ImageFit.Contain)
        .margin({ left: 8 + entry.depth * 14, right: 10 })
        .onClick(() => {
          if (entry.canExpand) {
            this.onToggleFolderExpand(entry.id)
          }
        })
      Text(entry.title)
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('app.color.primary_text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .padding({ top: 10, bottom: 10, right: 12 })
        .onClick(() => {
          const target = entry.moveTargetParentId ?? ''
          if (!NoteFolderTree.wouldCreateParentCycle(this.pickerSourceId, target, this.notes)) {
            void this.onPickerSelect(target)
          }
        })
    }
    .width('100%')
  }

  @Builder
  private buildMovePickerFileRow(entry: MovePickerEntry) {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.doc_text'))
        .fontSize(18)
        .fontColor([$r('app.color.accent')])
        .margin({ left: 20 + entry.depth * 14 })
      Text(entry.title)
        .fontSize(14)
        .fontColor($r('app.color.primary_text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .padding({ top: 6, bottom: 6, right: 12 })
        .onClick(() => {
          const target = entry.moveTargetParentId ?? ''
          if (!NoteFolderTree.wouldCreateParentCycle(this.pickerSourceId, target, this.notes)) {
            void this.onPickerSelect(target)
          }
        })
    }
    .width('100%')
  }

  @Builder
  private buildMovePickerEntry(entry: MovePickerEntry) {
    if (entry.isFolder) {
      this.buildMovePickerFolderRow(entry)
    } else {
      this.buildMovePickerFileRow(entry)
    }
  }

  @Builder
  private buildFolderPickerOverlay() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.3)')
        .onClick(() => {
          this.pickerVisible = false
        })
      Column({ space: 0 }) {
        Text(this.pickerHint)
          .fontSize($r('app.float.move_panel_hint_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .textAlign(TextAlign.Center)
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 8 })
        Scroll() {
          Column({ space: 0 }) {
            ForEach(this.getMovePickerEntries(), (entry: MovePickerEntry) => {
              this.buildMovePickerEntry(entry)
            }, (entry: MovePickerEntry) =>
              `pick_${entry.id}_${entry.depth}_${entry.isFolder}_${this.isMovePickerEntryExpanded(entry)}`)
          }
          .width('100%')
        }
        .scrollBar(BarState.Off)
        .constraintSize({ maxHeight: '50%' })
      }
      .width('100%')
      .margin({ left: 16, right: 16, top: 48 })
      .backgroundColor($r('app.color.card_background'))
      .borderRadius(12)
      .border({ width: 1, color: $r('app.color.card_border') })
      .shadow({
        radius: 12,
        color: $r('app.color.shadow_color'),
        offsetX: 0,
        offsetY: 4
      })
    }
    .width('100%')
    .height('100%')
    .zIndex(1000)
  }

  @Builder
  private buildRowMenu() {
    Column() {
      Text('创建副本')
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('app.color.primary_text'))
        .width('100%')
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })
        .onClick(() => {
          this.menuVisible = false
          this.openPicker(this.menuRowId, '将副本移动到', 'copy')
        })
      Text('移动到')
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('app.color.primary_text'))
        .width('100%')
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })
        .onClick(() => {
          this.menuVisible = false
          this.openPicker(this.menuRowId, '将文件夹移动到', 'move')
        })
      Text('删除')
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('app.color.primary_text'))
        .width('100%')
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })
        .onClick(() => {
          this.menuVisible = false
          const menuRow = this.rows.find((r: FolderManageRow) => r.noteId === this.menuRowId)
          if (menuRow !== undefined) {
            void this.confirmDelete(menuRow)
          }
        })
    }
    .width(168)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(12)
    .border({ width: 1, color: $r('app.color.card_border') })
    .shadow({
      radius: 12,
      color: $r('app.color.shadow_color'),
      offsetX: 0,
      offsetY: 4
    })
    .position({ x: this.menuX, y: this.menuY })
    .zIndex(1001)
  }

  private handleToolbarBack(): void {
    this.closeGuard.runBack(() => {
      this.getUIContext().getRouter().back()
    }, 'FolderManage')
  }

  onBackPress(): boolean {
    this.handleToolbarBack()
    return true
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Row() {
          Row() {
            Image($r('app.media.ic_back'))
              .width($r('app.float.toolbar_back_icon_size'))
              .height($r('app.float.toolbar_back_icon_size'))
              .objectFit(ImageFit.Contain)
          }
          .height('100%')
          .padding({
            left: $r('app.float.toolbar_icon_button_padding_h'),
            right: $r('app.float.toolbar_icon_button_padding_h')
          })
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius($r('app.float.pill_radius'))
          .onClick(() => {
            this.handleToolbarBack()
          })

          Row() {
            Text($r('app.string.folder_manage'))
              .fontSize($r('app.float.title_font_size'))
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.primary_text'))
              .textAlign(TextAlign.Center)
          }
          .layoutWeight(1)
          .height('100%')
          .alignItems(VerticalAlign.Center)
          .justifyContent(FlexAlign.Start)

          Row()
            .width(72)
            .height('100%')
        }
        .width('100%')
        .height($r('app.float.toolbar_height'))
        .alignItems(VerticalAlign.Center)

        if (this.loading) {
          LoadingProgress()
            .width(36)
            .height(36)
            .margin({ top: 24 })
        } else {
          Scroll() {
            Column() {
              ForEach(this.rows, (row: FolderManageRow, index: number) => {
                this.buildManageRow(row, index)
              }, (row: FolderManageRow, index: number) => this.manageRowForEachKey(row, index))

              Row() {
                this.buildInsertSlot(this.rows.length)
              }
              .width('100%')
              .onDrop(() => {
                const canInsert = this.draggingNoteId.length > 0 &&
                  this.canInsertBefore(this.draggingNoteId, this.rows.length)
                if (canInsert) {
                  const parentId =
                    NoteFolderTree.parentIdForInsertBefore(this.rows, this.rows.length, this.notes)
                  const dragged = this.draggingNoteId
                  this.clearDragUi()
                  void this.moveFolder(dragged, parentId)
                }
              })

              if (this.creatingActive && this.creatingUnderParentId.length === 0) {
                this.buildInlineCreate(0)
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding({ top: 8, bottom: 16 })
          }
          .width('100%')
          .layoutWeight(1)
          .align(Alignment.TopStart)
          .scrollBar(BarState.Off)
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 16 })
      .backgroundColor($r('app.color.app_background'))
      .onAreaChange((_: Area, area: Area) => {
        this.pageWidth = Number.parseFloat(`${area.width}`) || 360
        this.pageHeight = Number.parseFloat(`${area.height}`) || 800
      })

      if (this.menuVisible) {
        Column()
          .width('100%')
          .height('100%')
          .onClick(() => {
            this.menuVisible = false
          })
        this.buildRowMenu()
      }

      if (this.pickerVisible) {
        this.buildFolderPickerOverlay()
      }
    }
    .width('100%')
    .height('100%')
  }
}
