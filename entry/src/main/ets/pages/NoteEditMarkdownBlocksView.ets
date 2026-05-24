import type { MarkdownBlock, MarkdownInline } from '../common/utils/MarkdownUtils'
import { CodeHighlight, type CodeHighlightToken, type CodeHighlightTokenKind } from '../common/utils/CodeHighlight'
import { KatexFormulaPreview } from '../components/KatexFormulaPreview'
import { KatexUtils } from '../common/utils/KatexUtils'
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

  private mathTextColor(): string {
    return this.forShareExport ? '#F5E6B8' : '#1D1D1F'
  }

  private mathBackgroundColor(): string {
    return this.forShareExport ? '#1A1A1C' : 'transparent'
  }

  private hasMathInline(inlines: MarkdownInline[]): boolean {
    return inlines.some((inline: MarkdownInline) => inline.type === 'math_inline')
  }

  private hasAnyMath(): boolean {
    for (const block of this.blocks) {
      if (block.type === 'math_display') {
        return true
      }
      if (this.hasMathInline(block.inlines)) {
        return true
      }
      for (const item of block.items) {
        if (this.hasMathInline(item)) {
          return true
        }
      }
    }
    return false
  }

  /** 首个非图片/分割线的块索引，用于插入合并后的 KaTeX Web。 */
  private firstRenderableBlockIndex(): number {
    for (let i = 0; i < this.blocks.length; i++) {
      const t = this.blocks[i].type
      if (t !== 'image' && t !== 'divider') {
        return i
      }
    }
    return -1
  }

  private skipBlockInUnifiedKatex(block: MarkdownBlock, index: number): boolean {
    if (!this.hasAnyMath()) {
      return false
    }
    if (block.type === 'image' || block.type === 'divider') {
      return false
    }
    return index !== this.firstRenderableBlockIndex()
  }

  /** 由 inlines 还原含 $ 定界符的原文（列表项等无 block.content 时使用）。 */
  private inlineSource(inlines: MarkdownInline[]): string {
    let buf = ''
    for (const inline of inlines) {
      if (inline.type === 'math_inline') {
        buf += `$${inline.content}$`
      } else {
        buf += inline.content
      }
    }
    return buf
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
    if (block.type === 'math_display') {
      return `${block.type}:${block.content.slice(0, 48)}:${index}`
    }
    if (block.type === 'unordered_list' || block.type === 'ordered_list') {
      const items = block.items
        .map((item: MarkdownInline[]) => item.map((inline: MarkdownInline) => inline.content.slice(0, 20)).join(''))
        .join('|')
      return `${block.type}:${items}:${index}`
    }
    return `${block.type}:${block.language}:${block.content.slice(0, 48)}:${index}`
  }

  private codeTokenColor(kind: CodeHighlightTokenKind): ResourceColor {
    if (kind === 'comment') {
      return this.tertiaryTextColor()
    }
    if (kind === 'string' || kind === 'keyword') {
      return this.accentTextColor()
    }
    if (kind === 'number') {
      return '#E67E22'
    }
    return this.primaryTextColor()
  }

  @Builder
  private buildInlineCodeTokenSpans(content: string) {
    ForEach(CodeHighlight.highlight(content), (token: CodeHighlightToken, index: number) => {
      Span(token.text)
        .fontFamily('monospace')
        .fontColor(this.codeTokenColor(token.kind))
        .backgroundColor(this.codeBackgroundColor())
    }, (token: CodeHighlightToken, index: number) => `${token.kind}:${token.text.slice(0, 16)}:${index}`)
  }

  @Builder
  private buildHighlightedCode(code: string, fontSize: number | Resource, lineHeight: number) {
    Text() {
      ForEach(CodeHighlight.highlight(code), (token: CodeHighlightToken, index: number) => {
        Span(token.text)
          .fontFamily('monospace')
          .fontColor(this.codeTokenColor(token.kind))
      }, (token: CodeHighlightToken, index: number) => `${token.kind}:${token.text.slice(0, 16)}:${index}`)
    }
    .fontSize(fontSize)
    .lineHeight(lineHeight)
    .copyOption(CopyOptions.LocalDevice)
    .width('100%')
  }

  @Builder
  private buildInlineText(inlines: MarkdownInline[], rawContent: string, fontSize: number | Resource,
    fontColor: ResourceColor, lineHeight: number, fontWeight: FontWeight = FontWeight.Regular) {
    if (this.hasMathInline(inlines) && !this.hasAnyMath()) {
      KatexFormulaPreview({
        source: rawContent,
        textColor: this.mathTextColor(),
        previewBackgroundColor: this.mathBackgroundColor(),
        displayBlock: false
      })
        .key(`katex_inline:${rawContent.slice(0, 64)}`)
    } else {
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
      this.buildInlineCodeTokenSpans(inline.content)
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
            this.buildInlineText(item, this.inlineSource(item), $r('app.float.body_font_size'),
              this.primaryTextColor(), this.contentLineHeight(24))
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
      this.buildInlineText(block.inlines, block.content, 24, this.primaryTextColor(), this.contentLineHeight(32),
        FontWeight.Bold)
    } else if (block.type === 'heading2') {
      this.buildInlineText(block.inlines, block.content, 20, this.primaryTextColor(), this.contentLineHeight(28),
        FontWeight.Medium)
    } else if (block.type === 'heading3') {
      this.buildInlineText(block.inlines, block.content, 17, this.primaryTextColor(), this.contentLineHeight(24),
        FontWeight.Medium)
    } else if (block.type === 'quote') {
      Column() {
        this.buildInlineText(block.inlines, block.content, $r('app.float.body_font_size'), this.secondaryTextColor(),
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
        this.buildHighlightedCode(block.content, $r('app.float.caption_font_size'), this.contentLineHeight(22))
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
    } else if (block.type === 'math_display' && !this.hasAnyMath()) {
      KatexFormulaPreview({
        source: KatexUtils.wrapDisplaySource(block.content),
        textColor: this.mathTextColor(),
        previewBackgroundColor: this.mathBackgroundColor(),
        displayBlock: true
      })
        .key(`math_display:${block.content.slice(0, 48)}`)
    } else {
      this.buildInlineText(block.inlines, block.content, $r('app.float.body_font_size'), this.primaryTextColor(),
        this.contentLineHeight(24))
    }
  }

  @Builder
  private buildUnifiedKatexPreview() {
    KatexFormulaPreview({
      source: KatexUtils.combineBlocksForKatex(this.blocks),
      textColor: this.mathTextColor(),
      previewBackgroundColor: this.mathBackgroundColor(),
      displayBlock: false
    })
      .key(`katex_unified:${this.blocks.length}`)
  }

  build() {
    Column({ space: 14 }) {
      ForEach(this.blocks, (block: MarkdownBlock, index: number) => {
        if (!this.skipBlockInUnifiedKatex(block, index)) {
          if (this.hasAnyMath() && index === this.firstRenderableBlockIndex()) {
            this.buildUnifiedKatexPreview()
          } else {
            this.buildPreviewBlock(block)
          }
        }
      }, (block: MarkdownBlock, index: number) => this.previewBlockKey(block, index))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
