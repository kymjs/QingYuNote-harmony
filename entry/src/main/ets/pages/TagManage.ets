import type { Note } from '../common/model/Note'
import { NoteRepository } from '../services/NoteRepository'
import { PreferencesService } from '../services/PreferencesService'
import { AppContextHolder } from '../services/AppContextHolder'

@Entry
@Component
struct TagManage {
  @State tags: string[] = []
  @State newTag: string = ''
  @State saving: boolean = false
  private activeNotes: Note[] = []

  aboutToAppear(): void {
    void this.loadData()
  }

  private async loadData(): Promise<void> {
    await NoteRepository.getInstance().init()
    this.activeNotes = await NoteRepository.getInstance().listNotes()
    await this.ensurePreferencesInitialized()
    const storedTags = await PreferencesService.getInstance().getNoteTags()
    const mergedTags = this.normalizeTags(this.extractTagsFromNotes(this.activeNotes).concat(storedTags))
    this.tags = mergedTags
  }

  private async ensurePreferencesInitialized(): Promise<void> {
    const context = AppContextHolder.tryGetContext()
    if (context) {
      await PreferencesService.getInstance().init(context)
    }
  }

  private normalizeTags(tags: string[]): string[] {
    const seen: Set<string> = new Set()
    const normalized: string[] = []
    for (const rawTag of tags) {
      const tag = `${rawTag ?? ''}`.trim()
      if (tag.length === 0 || seen.has(tag)) {
        continue
      }
      seen.add(tag)
      normalized.push(tag)
    }
    normalized.sort((left: string, right: string) => left.localeCompare(right, 'zh-Hans-CN'))
    return normalized
  }

  private extractTagsFromNotes(notes: Note[]): string[] {
    const tags: string[] = []
    for (const note of notes) {
      for (const tag of note.tags) {
        tags.push(tag)
      }
    }
    return this.normalizeTags(tags)
  }

  private async openTagNoteAssign(tag: string): Promise<void> {
    const name = `${tag ?? ''}`.trim()
    if (name.length === 0) {
      return
    }
    try {
      await this.getUIContext().getRouter().pushUrl({
        url: 'pages/TagNoteAssign',
        params: {
          tagName: name
        }
      })
    } catch (error) {
      console.error(JSON.stringify(error))
      this.showUserMessage('打开笔记列表失败，请稍后重试')
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

  private addTag(): void {
    if (this.saving) {
      this.showUserMessage('请稍候')
      return
    }
    const candidate = this.newTag.trim()
    if (candidate.length === 0) {
      this.showUserMessage('请输入标签名')
      return
    }
    if (this.tags.includes(candidate)) {
      this.showUserMessage('标签已存在')
      return
    }
    const previousTags = [...this.tags]
    const revertNewTag = this.newTag
    const nextTags = this.normalizeTags([...this.tags, candidate])
    this.tags = nextTags
    this.newTag = ''
    void this.applyTagsPersist(previousTags, nextTags, revertNewTag)
  }

  private removeTag(tag: string): void {
    if (this.saving) {
      this.showUserMessage('请稍候')
      return
    }
    const previousTags = [...this.tags]
    const nextTags = this.tags.filter((item: string) => item !== tag)
    this.tags = nextTags
    void this.applyTagsPersist(previousTags, nextTags)
  }

  private async applyTagsPersist(previousTags: string[], nextTags: string[], revertNewTag?: string): Promise<void> {
    this.saving = true
    try {
      const removedTags = previousTags.filter((t: string) => !nextTags.includes(t))
      if (removedTags.length > 0) {
        const removedSet: Set<string> = new Set(removedTags)
        for (const note of this.activeNotes) {
          if (!note.tags.some((t: string) => removedSet.has(t))) {
            continue
          }
          const noteNextTags = note.tags.filter((t: string) => !removedSet.has(t))
          await NoteRepository.getInstance().saveDraft(note.id, {
            tags: noteNextTags
          })
          note.tags = noteNextTags
        }
      }
      await this.ensurePreferencesInitialized()
      await PreferencesService.getInstance().saveNoteTags(nextTags)
    } catch (error) {
      console.error(JSON.stringify(error))
      this.tags = previousTags
      if (revertNewTag !== undefined) {
        this.newTag = revertNewTag
      }
      this.showUserMessage('保存标签失败，请稍后重试')
    } finally {
      this.saving = false
    }
  }

  @Builder
  private buildTagItem(tag: string) {
    Row({ space: 10 }) {
      Text(tag)
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('app.color.primary_text'))
        .layoutWeight(1)
        .onClick(() => {
          void this.openTagNoteAssign(tag)
        })
      Text('删除')
        .fontSize(13)
        .fontColor($r('app.color.danger'))
        .enabled(!this.saving)
        .opacity(this.saving ? 0.55 : 1)
        .onClick(() => {
          this.removeTag(tag)
        })
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor($r('app.color.surface_muted'))
    .borderRadius(12)
  }

  build() {
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
          this.getUIContext().getRouter().back()
        })

        Row() {
          Text($r('app.string.tag_manage'))
            .fontSize($r('app.float.title_font_size'))
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
            .textAlign(TextAlign.Center)
        }
        .layoutWeight(1)
        .height('100%')
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.Start)
      }
      .width('100%')
      .height($r('app.float.toolbar_height'))
      .alignItems(VerticalAlign.Center)

      Column({ space: 12 }) {
        Text('新增标签')
          .fontSize(12)
          .fontColor($r('app.color.tertiary_text'))
          .margin({ left: 4 })

        Row({ space: 10 }) {
          TextInput({ text: $$this.newTag, placeholder: '输入标签名' })
            .layoutWeight(1)
            .fontSize($r('app.float.body_font_size'))
            .fontColor($r('app.color.primary_text'))
            .placeholderColor($r('app.color.tertiary_text'))
            .backgroundColor($r('app.color.editor_background'))
            .borderRadius(12)
            .border({ width: 1, color: $r('app.color.card_border') })
            .padding({ left: 14, right: 14 })
          Button('添加')
            .fontSize($r('app.float.caption_font_size'))
            .fontColor($r('app.color.on_accent'))
            .backgroundColor($r('app.color.accent'))
            .borderRadius(12)
            .padding({ left: 16, right: 16, top: 10, bottom: 10 })
            .enabled(!this.saving)
            .opacity(this.saving ? 0.55 : 1)
            .onClick(() => {
              this.addTag()
            })
        }
        .width('100%')

        Divider()
          .strokeWidth(1)
          .color($r('app.color.divider'))
          .margin({ top: 4, bottom: 4 })

        if (this.tags.length > 0) {
          Text('点击标签可批量编辑笔记')
            .fontSize(12)
            .fontColor($r('app.color.tertiary_text'))
            .margin({ left: 4 })
        }

        if (this.tags.length === 0) {
          Text('暂无标签')
            .fontSize($r('app.float.body_font_size'))
            .fontColor($r('app.color.tertiary_text'))
            .padding({ top: 12, bottom: 12 })
        } else {
          Column({ space: 8 }) {
            ForEach(this.tags, (tag: string) => {
              this.buildTagItem(tag)
            }, (tag: string) => `manage_${tag}`)
          }
          .width('100%')
        }
      }
      .width('100%')
      .padding(16)
      .backgroundColor($r('app.color.card_background'))
      .borderRadius($r('app.float.card_radius'))
      .border({ width: 1, color: $r('app.color.card_border') })
      .shadow({
        radius: 18,
        color: $r('app.color.shadow_color'),
        offsetX: 0,
        offsetY: 3
      })
    }
    .width('100%')
    .height('100%')
    .padding({
      left: 16,
      right: 16
    })
    .backgroundColor($r('app.color.app_background'))
  }
}
