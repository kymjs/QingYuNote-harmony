import type { NoteHistoryEntry } from '../common/model/NoteHistory'
import { NoteHistoryReason } from '../common/model/NoteHistory'
import { NoteHistoryService } from '../services/NoteHistoryService'
import { EditorUiStrings } from '../common/utils/EditorUiStrings'
import { PageLifecycle } from '../common/utils/PageLifecycle'
import { PageCloseGuard } from '../common/utils/PageCloseGuard'

@Entry
@Component
struct NoteHistoryPage {
  @State versions: NoteHistoryEntry[] = []
  @State loading: boolean = true
  @State selectedId: string = ''
  @State restoring: boolean = false
  private noteId: string = ''
  private lifecycle = new PageLifecycle()
  private closeGuard = new PageCloseGuard()

  aboutToAppear(): void {
    this.lifecycle.appear()
    this.closeGuard.reset()
    const params = this.getUIContext().getRouter().getParams() as Record<string, Object>
    this.noteId = `${params['noteId'] ?? ''}`
    void this.loadList()
  }

  aboutToDisappear(): void {
    this.lifecycle.disappear()
  }

  private handleBack(): void {
    this.closeGuard.runBack(() => {
      this.getUIContext().getRouter().back()
    }, 'NoteHistoryPage')
  }

  onBackPress(): boolean {
    this.handleBack()
    return true
  }

  private async loadList(): Promise<void> {
    this.loading = true
    try {
      this.versions = await NoteHistoryService.getInstance().listVersions(this.noteId)
    } catch (_) {
      this.versions = []
    }
    if (this.lifecycle.isActive()) {
      this.loading = false
    }
  }

  private reasonLabel(reason: string): string {
    if (reason === NoteHistoryReason.editorLeave) {
      return EditorUiStrings.loc('离开编辑', 'Left editor', '編集終了')
    }
    if (reason === NoteHistoryReason.remoteClobber || reason === NoteHistoryReason.remoteOverwrite) {
      return EditorUiStrings.loc('云端覆盖', 'Cloud overwrite', 'クラウド上書き')
    }
    if (reason === NoteHistoryReason.restore) {
      return EditorUiStrings.loc('恢复前', 'Before restore', '復元前')
    }
    if (reason === NoteHistoryReason.agentWrite) {
      return 'Agent'
    }
    if (reason === NoteHistoryReason.aiReplace) {
      return 'AI'
    }
    if (reason === NoteHistoryReason.userManual) {
      return EditorUiStrings.loc('手动', 'Manual', '手動')
    }
    return EditorUiStrings.loc('自动保存', 'Auto save', '自動保存')
  }

  private timeLabel(ms: number): string {
    if (ms <= 0) {
      return ''
    }
    const dt = new Date(ms)
    const pad = (n: number): string => n < 10 ? `0${n}` : `${n}`
    return `${dt.getFullYear()}-${pad(dt.getMonth() + 1)}-${pad(dt.getDate())} ${pad(dt.getHours())}:${pad(dt.getMinutes())}`
  }

  private async restoreSelected(): Promise<void> {
    if (this.selectedId.length === 0 || this.restoring) {
      return
    }
    this.restoring = true
    try {
      await NoteHistoryService.getInstance().restore(this.noteId, this.selectedId)
      if (this.lifecycle.isActive()) {
        this.getUIContext().getRouter().back()
      }
    } catch (_) {
      this.restoring = false
    }
  }

  build() {
    Column() {
      Row() {
        Row() {
          SymbolGlyph($r('sys.symbol.arrow_left'))
            .fontSize(18)
            .fontColor([$r('app.color.primary_text')])
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
            this.handleBack()
          })

        Text(EditorUiStrings.loc('历史版本', 'Version history', '履歴'))
          .fontSize($r('app.float.title_font_size'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
          .textAlign(TextAlign.Start)
      }
      .width('100%')
      .height($r('app.float.toolbar_height'))
      .alignItems(VerticalAlign.Center)

      if (this.loading) {
        Text(EditorUiStrings.loc('加载中…', 'Loading…', '読み込み中…'))
          .padding(24)
      } else if (this.versions.length === 0) {
        Text(EditorUiStrings.loc('暂无历史版本。编辑一段时间或离开编辑页后会自动保存。',
          'No history yet. Versions are saved after you edit for a while or leave the editor.',
          '履歴はまだありません。しばらく編集するか編集画面を離れると自動保存されます。'))
          .padding(24)
      } else {
        List() {
          ForEach(this.versions, (entry: NoteHistoryEntry) => {
            ListItem() {
              Column() {
                Text(entry.title.length > 0 ? entry.title : EditorUiStrings.loc('无标题', 'Untitled', '無題'))
                  .fontSize(16)
                  .fontColor($r('app.color.primary_text'))
                  .maxLines(1)
                Text(`${this.timeLabel(entry.createdAt)} · ${this.reasonLabel(entry.reason)}`)
                  .fontSize(12)
                  .fontColor($r('app.color.secondary_text'))
                if (this.selectedId === entry.id) {
                  Button(this.restoring ?
                    EditorUiStrings.loc('恢复中…', 'Restoring…', '復元中…') :
                    EditorUiStrings.loc('恢复此版本', 'Restore this version', 'このバージョンに戻す'))
                    .enabled(!this.restoring)
                    .fontColor($r('app.color.on_accent'))
                    .backgroundColor($r('app.color.accent'))
                    .margin({ top: 12 })
                    .onClick(() => {
                      void this.restoreSelected()
                    })
                }
              }
              .padding(12)
              .width('100%')
              .onClick(() => {
                this.selectedId = entry.id
              })
            }
          }, (entry: NoteHistoryEntry) => entry.id)
        }
        .layoutWeight(1)
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({
      left: 16,
      right: 16
    })
    .backgroundColor($r('app.color.app_background'))
  }
}
