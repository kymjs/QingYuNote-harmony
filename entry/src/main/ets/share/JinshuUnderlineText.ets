import { ShareThemeColors } from './ShareTheme'

@Component
export struct JinshuUnderlineText {
  @Prop text: string = ''
  @Prop accent: string = '#FF39FF14'
  @Prop fontSize: number = 15
  @Prop lineHeight: number = 22
  @Prop fontColor: string = '#FFFFFFFF'

  build() {
    Text() {
      ForEach(this.buildSpanItems(), (item: JinshuSpanItem) => {
        if (item.underline) {
          Span(item.text)
            .decoration({
              type: TextDecorationType.Underline,
              color: this.accent,
              style: TextDecorationStyle.SOLID
            })
            .fontWeight(FontWeight.Medium)
        } else {
          Span(item.text)
        }
      }, (item: JinshuSpanItem, index: number) => `${index}_${item.text}`)
    }
    .fontSize(this.fontSize)
    .fontColor(this.fontColor)
    .lineHeight(this.lineHeight)
    .width('100%')
  }

  private buildSpanItems(): JinshuSpanItem[] {
    const display = this.text.length > 0 ? this.text : '开始写作后，这里会实时显示预览。'
    const ranges = ShareThemeColors.pickUnderlineRanges(display, display.length, 2, 4)
    const items: JinshuSpanItem[] = []
    if (ranges.length === 0) {
      items.push({ text: display, underline: false })
      return items
    }
    let cursor = 0
    for (let i = 0; i < ranges.length; i++) {
      const start = ranges[i][0]
      const end = ranges[i][1]
      if (start > cursor) {
        items.push({ text: display.substring(cursor, start), underline: false })
      }
      items.push({ text: display.substring(start, end), underline: true })
      cursor = end
    }
    if (cursor < display.length) {
      items.push({ text: display.substring(cursor), underline: false })
    }
    return items
  }
}

interface JinshuSpanItem {
  text: string
  underline: boolean
}
