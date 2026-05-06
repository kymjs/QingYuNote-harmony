import type { Note } from '../common/model/Note'
import { NoteRepository } from '../services/NoteRepository'

interface TagNoteAssignParams {
  tagName?: string
}

interface TagAssignRow {
  noteId: string
  title: string
  summary: string
  selected: boolean
}

@Entry
@Component
struct TagNoteAssign {
  @State tagName: string = ''
  @State rows: TagAssignRow[] = []
  @State saving: boolean = false
  @State loading: boolean = true

  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as TagNoteAssignParams
    this.tagName = `${params?.tagName ?? ''}`.trim()
    void this.loadNotes()
  }

  private async loadNotes(): Promise<void> {
    this.loading = true
    try {
      await NoteRepository.getInstance().init()
      const notes = await NoteRepository.getInstance().listNotes()
      const tag = this.tagName
      const nextRows: TagAssignRow[] = []
      for (const note of notes) {
        nextRows.push({
          noteId: note.id,
          title: note.title.length > 0 ? note.title : '无标题',
          summary: note.summary.length > 0 ? note.summary : '暂无内容',
          selected: note.tags.includes(tag)
        })
      }
      this.rows = nextRows
    } finally {
      this.loading = false
    }
  }

  private showUserMessage(message: string): void {
    if (message.trim().length === 0) {
      return
    }
    try {
      this.getUIContext().getPromptAction().showToast({
        message,
        duration: 2000
      })
    } catch (error) {
      console.error(`showToast failed: ${JSON.stringify(error)}`)
    }
  }

  private toggleRow(noteId: string): void {
    this.rows = this.rows.map((row: TagAssignRow) => {
      if (row.noteId !== noteId) {
        return row
      }
      return {
        noteId: row.noteId,
        title: row.title,
        summary: row.summary,
        selected: !row.selected
      }
    })
  }

  private normalizeTagOrder(tags: string[]): string[] {
    const copy = [...tags]
    copy.sort((a: string, b: string) => a.localeCompare(b, 'zh-Hans-CN'))
    return copy
  }

  private nextTagsForNote(existingTags: string[], targetTag: string, shouldHave: boolean): string[] {
    const set: Set<string> = new Set(existingTags)
    if (shouldHave) {
      set.add(targetTag)
    } else {
      set.delete(targetTag)
    }
    return this.normalizeTagOrder(Array.from(set))
  }

  private async save(): Promise<void> {
    if (this.saving || this.tagName.length === 0) {
      return
    }
    this.saving = true
    const repo = NoteRepository.getInstance()
    repo.beginBulkNotification()
    try {
      for (const row of this.rows) {
        const note: Note | null = await repo.getNote(row.noteId)
        if (!note) {
          continue
        }
        const hasTag = note.tags.includes(this.tagName)
        if (row.selected === hasTag) {
          continue
        }
        const nextTags = this.nextTagsForNote(note.tags, this.tagName, row.selected)
        await repo.saveDraft(row.noteId, { tags: nextTags })
      }
      this.showUserMessage('已保存')
      this.getUIContext().getRouter().back()
    } catch (error) {
      console.error(JSON.stringify(error))
      this.showUserMessage('保存失败，请稍后重试')
    } finally {
      repo.endBulkNotification()
      this.saving = false
    }
  }

  @Builder
  private buildToolbar() {
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
        this.getUIContext().getRouter().back()
      })

      Row() {
        Text(this.tagName.length > 0 ? this.tagName : '标签')
          .fontSize($r('app.float.title_font_size'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .height('100%')
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Start)

      Row() {
        Image($r('app.media.ic_save'))
          .width(25)
          .height(25)
          .objectFit(ImageFit.Contain)
      }
      .height('100%')
      .padding({
        left: $r('app.float.toolbar_icon_button_padding_h'),
        right: $r('app.float.toolbar_icon_button_padding_h')
      })
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .enabled(!this.saving && this.tagName.length > 0)
      .opacity(this.saving || this.tagName.length === 0 ? 0.45 : 1)
      .onClick(() => {
        void this.save()
      })
    }
    .width('100%')
    .height($r('app.float.toolbar_height'))
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildNoteRow(row: TagAssignRow) {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text(row.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
          .lineHeight(20)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Text(row.summary)
          .fontSize(13)
          .fontColor(row.summary !== '暂无内容' ? $r('app.color.secondary_text') : $r('app.color.tertiary_text'))
          .lineHeight(18)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Checkbox({ name: row.noteId, group: 'tag_note_assign_' + row.noteId })
        .select(row.selected)
        .selectedColor($r('app.color.accent'))
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor($r('app.color.surface_muted'))
    .borderRadius(12)
  }

  build() {
    Column({ space: $r('app.float.toolbar_spacing_section') }) {
      this.buildToolbar()

      if (this.loading) {
        Column({ space: 16 }) {
          LoadingProgress()
            .width(36)
            .height(36)
            .color($r('app.color.accent'))
          Text('正在加载笔记…')
            .fontSize($r('app.float.body_font_size'))
            .fontColor($r('app.color.secondary_text'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.tagName.length === 0) {
        Text('缺少标签参数')
          .fontSize($r('app.float.body_font_size'))
          .fontColor($r('app.color.tertiary_text'))
          .width('100%')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
      } else if (this.rows.length === 0) {
        Text('暂无笔记')
          .fontSize($r('app.float.body_font_size'))
          .fontColor($r('app.color.tertiary_text'))
          .width('100%')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
      } else {
        List({ space: 8 }) {
          ForEach(this.rows, (row: TagAssignRow) => {
            ListItem() {
              this.buildNoteRow(row)
            }
            .width('100%')
            .onClick(() => {
              this.toggleRow(row.noteId)
            })
          }, (row: TagAssignRow) => `assign_${row.noteId}_${row.selected ? '1' : '0'}`)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      }
    }
    .width('100%')
    .height('100%')
    .padding({
      top: $r('app.float.toolbar_editor_page_padding_top'),
      bottom: 16,
      left: 16,
      right: 16
    })
    .backgroundColor($r('app.color.app_background'))
  }
}
