import { EditorUiStrings } from '../common/utils/EditorUiStrings'

export interface EditorLinkInsertDialogParams {
  onCancel: () => void
  onConfirm: (label: string, url: string) => void
}

@Component
export struct EditorLinkInsertDialog {
  @Prop params: EditorLinkInsertDialogParams = {
    onCancel: (): void => {},
    onConfirm: (_: string, __: string): void => {}
  }
  @State labelDraft: string = ''
  @State urlDraft: string = ''

  build() {
    Column({ space: 16 }) {
      Text(EditorUiStrings.loc('插入链接', 'Insert link', 'リンクを挿入'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .width('100%')
      TextInput({ text: this.labelDraft, placeholder: EditorUiStrings.loc('文案', 'Label', '表示テキスト') })
        .fontSize($r('app.float.body_font_size'))
        .width('100%')
        .onChange((v: string) => {
          this.labelDraft = v
        })
      TextInput({ text: this.urlDraft, placeholder: EditorUiStrings.loc('链接', 'Link', 'リンク') })
        .fontSize($r('app.float.body_font_size'))
        .width('100%')
        .onChange((v: string) => {
          this.urlDraft = v
        })
      Row({ space: 12 }) {
        Button(EditorUiStrings.loc('取消', 'Cancel', 'キャンセル'))
          .layoutWeight(1)
          .fontSize($r('app.float.body_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .backgroundColor($r('app.color.surface_muted'))
          .borderRadius($r('app.float.pill_radius'))
          .padding({ top: 12, bottom: 12 })
          .onClick(() => {
            this.params.onCancel()
          })
        Button(EditorUiStrings.loc('确定', 'OK', 'OK'))
          .layoutWeight(1)
          .fontSize($r('app.float.body_font_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.on_accent'))
          .backgroundColor($r('app.color.accent'))
          .borderRadius($r('app.float.pill_radius'))
          .padding({ top: 12, bottom: 12 })
          .onClick(() => {
            this.params.onConfirm(this.labelDraft.trim(), this.urlDraft.trim())
          })
      }
      .width('100%')
    }
    .width('85%')
    .constraintSize({ maxWidth: 400 })
    .padding(20)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius($r('app.float.card_radius'))
    .border({ width: 1, color: $r('app.color.card_border') })
    .shadow({
      radius: 20,
      color: $r('app.color.shadow_color'),
      offsetX: 0,
      offsetY: 4
    })
    .alignItems(HorizontalAlign.Start)
  }
}

@Builder
export function buildEditorLinkInsertDialogContent(params: EditorLinkInsertDialogParams): void {
  EditorLinkInsertDialog({ params: params })
}
