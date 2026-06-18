import { EditorUiStrings } from '../common/utils/EditorUiStrings'

export interface EditorAiLinkExtractDialogParams {
  onCancel: () => void
  onConfirm: (url: string) => void
}

@Component
export struct EditorAiLinkExtractDialog {
  @Prop params: EditorAiLinkExtractDialogParams = {
    onCancel: (): void => {},
    onConfirm: (_: string): void => {}
  }
  @State urlDraft: string = ''

  private canConfirm(): boolean {
    return this.urlDraft.trim().length > 0
  }

  build() {
    Column({ space: 16 }) {
      Text(EditorUiStrings.loc('AI提取链接', 'AI extract link', 'AIでリンク抽出'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .width('100%')
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
          .fontColor(this.canConfirm() ? $r('app.color.on_accent') : $r('app.color.secondary_text'))
          .backgroundColor(this.canConfirm() ? $r('app.color.accent') : $r('app.color.surface_muted'))
          .borderRadius($r('app.float.pill_radius'))
          .padding({ top: 12, bottom: 12 })
          .enabled(this.canConfirm())
          .onClick(() => {
            if (this.canConfirm()) {
              this.params.onConfirm(this.urlDraft.trim())
            }
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
export function buildEditorAiLinkExtractDialogContent(params: EditorAiLinkExtractDialogParams): void {
  EditorAiLinkExtractDialog({ params: params })
}
