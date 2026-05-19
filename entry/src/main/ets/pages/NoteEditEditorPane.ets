/** 标题与正文编辑区，父组件仅通过 @Link 与回调参与保存/预览调度。 */
@Component
export struct NoteEditEditorPane {
  @Link title: string
  @Link content: string
  textAreaController: TextAreaController = new TextAreaController()
  onTitleChange: () => void = () => {
  }
  onTitleFocus: () => void = () => {
  }
  onTitleBlur: () => void = () => {
  }
  onContentChange: () => void = () => {
  }
  onContentSelectionChange: (selectionStart: number, selectionEnd: number) => void =
    (_selectionStart: number, _selectionEnd: number) => {
    }

  build() {
    Column({ space: 0 }) {
      TextInput({ text: $$this.title, placeholder: $r('app.string.editor_title_placeholder') })
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .placeholderColor($r('app.color.tertiary_text'))
        .backgroundColor($r('app.color.editor_background'))
        .borderRadius(12)
        .padding({ bottom: 0 })
        .focusOnTouch(true)
        .onFocus(() => {
          this.onTitleFocus()
        })
        .onBlur(() => {
          this.onTitleBlur()
        })
        .onChange((_value: string) => {
          this.onTitleChange()
        })

      TextArea({
        text: $$this.content,
        placeholder: $r('app.string.editor_content_placeholder'),
        controller: this.textAreaController
      })
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('app.color.primary_text'))
        .placeholderColor($r('app.color.tertiary_text'))
        .backgroundColor($r('app.color.editor_background'))
        .borderRadius(12)
        .layoutWeight(1)
        .onTextSelectionChange((selectionStart: number, selectionEnd: number) => {
          this.onContentSelectionChange(selectionStart, selectionEnd)
        })
        .onChange((_value: string) => {
          this.onContentChange()
        })
    }
    .layoutWeight(1)
    .height('100%')
    .padding(5)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius($r('app.float.card_radius'))
    .border({ width: 1, color: $r('app.color.card_border') })
    .shadow({
      radius: 16,
      color: $r('app.color.shadow_color'),
      offsetX: 0,
      offsetY: 3
    })
  }
}
