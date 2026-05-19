import type { MarkdownBlock, MarkdownInline } from '../common/utils/MarkdownUtils'
import { fileUri } from '@kit.CoreFileKit'

/** 笔记预览/分享卡片共用的 Markdown 块渲染，独立于编辑页以缩小状态失效范围。 */
@Component
export struct NoteEditMarkdownBlocksView {
  @Prop blocks: MarkdownBlock[] = []
  @Prop filesDirCache: string = ''
  /** 分享长图导出：深色底 + 金色文字，与 NoteEdit 分享卡片一致。 */
  @Prop forShareExport: boolean = false
  onLinkToast: (href: string) => void = (_href: string) => {
  }

  private primaryTextColor(): ResourceColor {
    return this.forShareExport ? $r('app.color.share_text') : $r('app.color.primary_text')
  }

  private secondaryTextColor(): ResourceColor {
    return this.forShareExport ? $r('app.color.share_text') : $r('app.color.secondary_text')
  }

  private accentTextColor(): ResourceColor {
    return this.forShareExport ? $r('app.color.share_text') : $r('app.color.accent')
  }

  private codeBackgroundColor(): ResourceColor {
    return this.forShareExport ? $r('app.color.share_code_background') : $r('app.color.surface_muted')
  }

  private dividerColor(): ResourceColor {
    return this.forShareExport ? $r('app.color.share_divider') : $r('app.color.divider')
  }

  private cardBorderColor(): ResourceColor {
    return this.forShareExport ? $r('app.color.share_divider') : $r('app.color.card_border')
  }

  private tertiaryTextColor(): ResourceColor {
    return this.forShareExport ? $r('app.color.share_text') : $r('app.color.tertiary_text')
  }

  /** 分享长图正文行高相对预览/编辑再收紧 15%。 */
  private contentLineHeight(base: number): number {
    return this.forShareExport ? Math.round(base * 0.85) : base
  }

  private resolveImageSrc(src: string): string {
    if (src.startsWith('http://') || src.startsWith('https://')) {
      return src
    }
    if (src.startsWith('file://')) {
      return src
    }
    if (src.startsWith('/')) {
      return fileUri.getUriFromPath(src)
    }
    const base = this.filesDirCache
    const absPath = `${base}/${src}`
    return fileUri.getUriFromPath(absPath)
  }

  private inlineKey(inline: MarkdownInline, index: number): string {
    return `${inline.type}:${inline.href}:${inline.content.slice(0, 32)}:${index}`
  }

  private listItemKey(item: MarkdownInline[], index: number): string {
    const content = item
      .map((inline: MarkdownInline) => `${inline.type}:${inline.content.slice(0, 24)}:${inline.href}`)
      .join('|')
    return `${content}:${index}`
  }

  private previewBlockKey(block: MarkdownBlock, index: number): string {
    if (block.type === 'unordered_list' || block.type === 'ordered_list') {
      const items = block.items
        .map((item: MarkdownInline[]) => item.map((inline: MarkdownInline) => inline.content.slice(0, 20)).join(''))
        .join('|')
      return `${block.type}:${items}:${index}`
    }
    return `${block.type}:${block.language}:${block.content.slice(0, 48)}:${index}`
  }

  @Builder
  private buildInlineText(inlines: MarkdownInline[], fontSize: number | Resource, fontColor: ResourceColor,
    lineHeight: number, fontWeight: FontWeight = FontWeight.Regular) {
    Text() {
      ForEach(inlines, (inline: MarkdownInline, index: number) => {
        this.buildInlineSpan(inline, fontColor)
      }, (inline: MarkdownInline, index: number) => this.inlineKey(inline, index))
    }
    .fontSize(fontSize)
    .fontColor(fontColor)
    .lineHeight(lineHeight)
    .fontWeight(fontWeight)
    .copyOption(CopyOptions.LocalDevice)
    .width('100%')
  }

  @Builder
  private buildInlineSpan(inline: MarkdownInline, defaultColor: ResourceColor) {
    if (inline.type === 'bold') {
      Span(inline.content)
        .fontWeight(FontWeight.Bold)
        .fontColor(defaultColor)
    } else if (inline.type === 'italic') {
      Span(inline.content)
        .fontStyle(FontStyle.Italic)
        .fontColor(defaultColor)
    } else if (inline.type === 'inline_code') {
      Span(inline.content)
        .fontFamily('monospace')
        .fontColor(defaultColor)
        .backgroundColor(this.codeBackgroundColor())
    } else if (inline.type === 'strikethrough') {
      Span(inline.content)
        .fontColor(defaultColor)
        .decoration({ type: TextDecorationType.LineThrough })
    } else if (inline.type === 'link') {
      Span(inline.content)
        .fontColor(this.accentTextColor())
        .decoration({ type: TextDecorationType.Underline })
        .onClick(() => {
          this.onLinkToast(inline.href)
        })
    } else {
      Span(inline.content)
        .fontColor(defaultColor)
    }
  }

  @Builder
  private buildListBlock(block: MarkdownBlock, ordered: boolean) {
    Column({ space: 10 }) {
      ForEach(block.items, (item: MarkdownInline[], index: number) => {
        Row({ space: 10 }) {
          Text(ordered ? `${index + 1}.` : '•')
            .fontSize($r('app.float.body_font_size'))
            .fontWeight(FontWeight.Medium)
            .fontColor(this.primaryTextColor())
            .copyOption(CopyOptions.LocalDevice)
            .margin({ top: 1 })
          Column() {
            this.buildInlineText(item, $r('app.float.body_font_size'), this.primaryTextColor(),
              this.contentLineHeight(24))
          }
          .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
      }, (item: MarkdownInline[], index: number) => this.listItemKey(item, index))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildPreviewBlock(block: MarkdownBlock) {
    if (block.type === 'heading1') {
      this.buildInlineText(block.inlines, 24, this.primaryTextColor(), this.contentLineHeight(32),
        FontWeight.Bold)
    } else if (block.type === 'heading2') {
      this.buildInlineText(block.inlines, 20, this.primaryTextColor(), this.contentLineHeight(28),
        FontWeight.Medium)
    } else if (block.type === 'heading3') {
      this.buildInlineText(block.inlines, 17, this.primaryTextColor(), this.contentLineHeight(24),
        FontWeight.Medium)
    } else if (block.type === 'quote') {
      Column() {
        this.buildInlineText(block.inlines, $r('app.float.body_font_size'), this.secondaryTextColor(),
          this.contentLineHeight(24))
      }
      .width('100%')
        .padding({ left: 14, top: 8, bottom: 8 })
        .border({ width: { left: 3 }, color: this.accentTextColor() })
    } else if (block.type === 'unordered_list') {
      this.buildListBlock(block, false)
    } else if (block.type === 'ordered_list') {
      this.buildListBlock(block, true)
    } else if (block.type === 'code') {
      Column({ space: 8 }) {
        if (block.language.length > 0) {
          Text(block.language.toLowerCase())
            .fontSize(11)
            .fontColor(this.tertiaryTextColor())
            .copyOption(CopyOptions.LocalDevice)
        }
        Text(block.content)
          .fontSize($r('app.float.caption_font_size'))
          .fontColor(this.primaryTextColor())
          .fontFamily('monospace')
          .lineHeight(this.contentLineHeight(22))
          .copyOption(CopyOptions.LocalDevice)
          .width('100%')
      }
      .width('100%')
      .padding(14)
      .backgroundColor(this.codeBackgroundColor())
      .borderRadius(12)
      .border({ width: 1, color: this.cardBorderColor() })
    } else if (block.type === 'divider') {
      Divider()
        .strokeWidth(1)
        .color(this.dividerColor())
    } else if (block.type === 'image') {
      Image(this.resolveImageSrc(block.language))
        .width('100%')
        .objectFit(ImageFit.Cover)
        .borderRadius(12)
        .alt(block.content)
    } else {
      this.buildInlineText(block.inlines, $r('app.float.body_font_size'), this.primaryTextColor(),
        this.contentLineHeight(24))
    }
  }

  build() {
    Column({ space: 14 }) {
      ForEach(this.blocks, (block: MarkdownBlock, index: number) => {
        this.buildPreviewBlock(block)
      }, (block: MarkdownBlock, index: number) => this.previewBlockKey(block, index))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
