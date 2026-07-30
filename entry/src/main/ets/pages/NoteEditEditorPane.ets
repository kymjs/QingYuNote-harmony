import { MarkdownRichEditor } from '../components/MarkdownRichEditor'
import { Logger } from '../common/utils/Logger'

/** 标题与正文编辑区，父组件仅通过 @Link 与回调参与保存/预览调度。 */
@Component
export struct NoteEditEditorPane {
  @Link title: string
  @Link content: string
  @Prop enterEditToken: number = 0
  @Prop refreshToken: number = 0
  @Prop toolbarSignal: string = ''
  @Prop filesDir: string = ''
  /** 窄屏语音式布局：标题在页面 header，此处只编辑正文。 */
  @Prop includeTitle: boolean = true
  /** 窄屏：去掉边框阴影卡片。 */
  @Prop flatChrome: boolean = false
  /** flatChrome 时传给 RichEditor 的最小高度（Swiper 可视高）。 */
  @Prop minContentHeight: number = 280
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

  aboutToAppear(): void {
    Logger.info('NoteEditEditorPane',
      `appear titleLen=${this.title.length} contentLen=${this.content.length} ` +
        `enterEditToken=${this.enterEditToken} refreshToken=${this.refreshToken}`)
  }

  build() {
    if (this.flatChrome) {
      Column({ space: 0 }) {
        MarkdownRichEditor({
          content: $content,
          enterEditToken: this.enterEditToken,
          refreshToken: this.refreshToken,
          toolbarSignal: this.toolbarSignal,
          filesDir: this.filesDir,
          flatChrome: true,
          minContentHeight: this.minContentHeight,
          onContentChange: (): void => {
            this.onContentChange()
          },
          onContentSelectionChange: (selectionStart: number, selectionEnd: number): void => {
            this.onContentSelectionChange(selectionStart, selectionEnd)
          }
        })
          .width('100%')
          .constraintSize({ minHeight: this.minContentHeight })
      }
      .width('100%')
      .padding(0)
      .backgroundColor(Color.Transparent)
    } else {
      Column({ space: 0 }) {
        if (this.includeTitle) {
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
        }

        MarkdownRichEditor({
          content: $content,
          enterEditToken: this.enterEditToken,
          refreshToken: this.refreshToken,
          toolbarSignal: this.toolbarSignal,
          filesDir: this.filesDir,
          flatChrome: false,
          onContentChange: (): void => {
            this.onContentChange()
          },
          onContentSelectionChange: (selectionStart: number, selectionEnd: number): void => {
            this.onContentSelectionChange(selectionStart, selectionEnd)
          }
        })
          .width('100%')
          .layoutWeight(1)
          .constraintSize({ minHeight: 120 })
      }
      .layoutWeight(1)
      .height('100%')
      .width('100%')
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
}
