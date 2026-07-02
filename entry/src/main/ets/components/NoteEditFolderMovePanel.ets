import { NoteFolderTree, type MovePickerEntry } from '../common/utils/NoteFolderTree'
import type { Note } from '../common/model/Note'
import { EditorUiStrings } from '../common/utils/EditorUiStrings'

/** 笔记「移动到文件夹」弹层（从 NoteEdit.ets 拆出）。 */
@Component
export struct NoteEditFolderMovePanel {
  @Prop noteId: string = ''
  @Prop parentId: string = ''
  @Prop allNotes: Note[] = []
  @Prop entries: MovePickerEntry[] = []
  @Prop expandedFolderIds: string[] = []
  onSelectFolder: (folderId: string) => void = () => {
  }
  onToggleExpand: (folderId: string) => void = () => {
  }

  private isEntryExpanded(entry: MovePickerEntry): boolean {
    return this.expandedFolderIds.includes(entry.id)
  }

  private isCurrentParent(entry: MovePickerEntry): boolean {
    const current = `${this.parentId ?? ''}`.trim()
    if (!entry.isFolder) {
      return false
    }
    if (entry.id === NoteFolderTree.VIRTUAL_ROOT_FOLDER_ID) {
      return current.length === 0
    }
    const target = `${entry.moveTargetParentId ?? ''}`.trim()
    return target.length > 0 && target === current
  }

  @Builder
  private buildFileRow(entry: MovePickerEntry) {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.doc_text'))
        .fontSize(16)
        .fontColor([$r('app.color.accent')])
      Text(entry.title)
        .fontSize(14)
        .fontColor(
          NoteFolderTree.wouldCreateParentCycle(this.noteId, entry.id, this.allNotes) ?
            $r('app.color.tertiary_text') : $r('app.color.primary_text')
        )
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .padding({
      left: 20 + entry.depth * 14,
      right: 16,
      top: 6,
      bottom: 6
    })
    .onClick(() => {
      if (!NoteFolderTree.wouldCreateParentCycle(this.noteId, entry.id, this.allNotes)) {
        this.onSelectFolder(entry.id)
      }
    })
  }

  @Builder
  private buildFolderRow(entry: MovePickerEntry) {
    Row({ space: 0 }) {
      Image(this.isEntryExpanded(entry) ? $r('app.media.ic_folder_open') : $r('app.media.ic_folder_closed'))
        .width(20)
        .height(20)
        .objectFit(ImageFit.Contain)
        .margin({ left: 8 + entry.depth * 14, right: 10 })
        .onClick(() => {
          if (entry.canExpand) {
            this.onToggleExpand(entry.id)
          }
        })
      Text(entry.title)
        .fontSize($r('app.float.body_font_size'))
        .fontColor(
          this.isCurrentParent(entry) ? $r('app.color.tertiary_text') :
            (entry.moveTargetParentId !== undefined &&
              entry.moveTargetParentId.length > 0 &&
              NoteFolderTree.wouldCreateParentCycle(this.noteId, entry.moveTargetParentId, this.allNotes) ?
              $r('app.color.tertiary_text') : $r('app.color.primary_text'))
        )
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .padding({ top: 10, bottom: 10, right: 12 })
        .onClick(() => {
          const target = entry.moveTargetParentId ?? ''
          if (target.length === 0 ||
            !NoteFolderTree.wouldCreateParentCycle(this.noteId, target, this.allNotes)) {
            this.onSelectFolder(target)
          }
        })
    }
    .width('100%')
  }

  @Builder
  private buildEntryRow(entry: MovePickerEntry) {
    if (entry.isFolder) {
      this.buildFolderRow(entry)
    } else {
      this.buildFileRow(entry)
    }
  }

  build() {
    Column({ space: 0 }) {
      Text(EditorUiStrings.loc('将当前文件移动到', 'Move file to', 'ファイルの移動先'))
        .fontSize($r('app.float.move_panel_hint_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .textAlign(TextAlign.Center)
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 8 })
      Scroll() {
        Column({ space: 0 }) {
          ForEach(this.entries, (entry: MovePickerEntry) => {
            this.buildEntryRow(entry)
          }, (entry: MovePickerEntry) =>
            `pick_${entry.id}_${entry.depth}_${entry.isFolder}_${this.isEntryExpanded(entry)}`)
        }
        .width('100%')
      }
      .scrollBar(BarState.Off)
      .constraintSize({ maxHeight: '50%' })
    }
    .width('100%')
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
}
