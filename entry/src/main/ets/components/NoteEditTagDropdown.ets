import { EditorUiStrings } from '../common/utils/EditorUiStrings'

/** 笔记编辑页标签下拉菜单（从 NoteEdit.ets 拆出）。 */
@Component
export struct NoteEditTagDropdown {
  @Prop tagPool: string[] = []
  @Prop noteTags: string[] = []
  @Prop aiTagCreating: boolean = false
  onTagChecked: (tag: string, selected: boolean) => void = () => {
  }
  onAiCreateTag: () => void = () => {
  }
  onOpenTagManage: () => void = () => {
  }

  private static readonly ITEM_HEIGHT_VP: number = 44
  private static readonly MAX_VISIBLE_ITEMS: number = 5

  @Builder
  private buildTagChip(tag: string) {
    Stack() {
      Text(tag)
        .fontSize(12)
        .fontColor(0X00FFFFFF)
        .padding({ left: 8, right: 8, top: 3, bottom: 4 })
        .backgroundColor($r('app.color.tag_text_accent'))
        .opacity(0.12)
        .borderRadius(10)
      Text(tag)
        .fontSize(12)
        .fontColor($r('app.color.primary_text'))
        .padding({ left: 8, right: 8, top: 3, bottom: 4 })
        .borderRadius(10)
    }
  }

  @Builder
  private buildTagDropdownItem(tag: string) {
    Row() {
      Checkbox()
        .select(this.noteTags.includes(tag))
        .selectedColor($r('app.color.accent'))
        .onChange((value: boolean) => {
          this.onTagChecked(tag, value)
        })
      Text(tag)
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('app.color.primary_text'))
        .layoutWeight(1)
    }
    .width('100%')
    .height(NoteEditTagDropdown.ITEM_HEIGHT_VP)
    .padding({ left: 12, right: 12 })
    .onClick(() => {
      const selected = !this.noteTags.includes(tag)
      this.onTagChecked(tag, selected)
    })
  }

  @Builder
  private buildTagList() {
    if (this.tagPool.length === 0) {
      Text(EditorUiStrings.loc('暂无可用标签', 'No tags available', '利用可能なタグがありません'))
        .fontSize($r('app.float.caption_font_size'))
        .fontColor($r('app.color.tertiary_text'))
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    } else if (this.tagPool.length > NoteEditTagDropdown.MAX_VISIBLE_ITEMS) {
      Scroll() {
        Column() {
          ForEach(this.tagPool, (tag: string) => {
            this.buildTagDropdownItem(tag)
          }, (tag: string) => `tag_item_${tag}`)
        }
      }
      .width('100%')
      .height(NoteEditTagDropdown.ITEM_HEIGHT_VP * NoteEditTagDropdown.MAX_VISIBLE_ITEMS)
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Auto)
    } else {
      ForEach(this.tagPool, (tag: string) => {
        this.buildTagDropdownItem(tag)
      }, (tag: string) => `tag_item_${tag}`)
    }
  }

  build() {
    Column() {
      this.buildTagList()
      Divider()
        .strokeWidth(1)
        .color($r('app.color.divider'))
        .margin({ top: 4, bottom: 4 })
      Row() {
        if (this.aiTagCreating) {
          LoadingProgress()
            .width(16)
            .height(16)
            .color($r('app.color.accent'))
        } else {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(16)
            .fontColor([$r('app.color.accent')])
        }
        Text(this.aiTagCreating
          ? EditorUiStrings.loc('AI 生成中…', 'AI generating…', 'AI生成中…')
          : EditorUiStrings.loc('AI创建标签', 'AI create tag', 'AIでタグ作成'))
          .fontSize($r('app.float.body_font_size'))
          .fontColor($r('app.color.accent'))
          .margin({ left: 8 })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .onClick(() => {
        if (!this.aiTagCreating) {
          this.onAiCreateTag()
        }
      })
      Row() {
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(16)
          .fontColor([$r('app.color.accent')])
        Text(EditorUiStrings.loc('添加标签', 'Add tag', 'タグを追加'))
          .fontSize($r('app.float.body_font_size'))
          .fontColor($r('app.color.accent'))
          .margin({ left: 8 })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .onClick(() => {
        this.onOpenTagManage()
      })
    }
    .width(154)
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

/** 供 NoteEdit 预览/编辑栏复用的标签 Chip。 */
@Component
export struct NoteEditTagChip {
  @Prop tag: string = ''

  build() {
    Stack() {
      Text(this.tag)
        .fontSize(12)
        .fontColor(0X00FFFFFF)
        .padding({ left: 8, right: 8, top: 3, bottom: 4 })
        .backgroundColor($r('app.color.tag_text_accent'))
        .opacity(0.12)
        .borderRadius(10)
      Text(this.tag)
        .fontSize(12)
        .fontColor($r('app.color.primary_text'))
        .padding({ left: 8, right: 8, top: 3, bottom: 4 })
        .borderRadius(10)
    }
  }
}
