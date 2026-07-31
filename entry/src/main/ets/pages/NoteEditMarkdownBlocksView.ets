import type { MarkdownBlock, MarkdownCheckboxItem, MarkdownInline } from '../common/utils/MarkdownUtils'
import { CodeHighlight, type CodeHighlightToken, type CodeHighlightTokenKind } from '../common/utils/CodeHighlight'
import { CachedNetworkImage } from '../components/CachedNetworkImage'
import { PreviewStandaloneLinkCard } from '../components/PreviewStandaloneLinkCard'
import { KatexFormulaPreview } from '../components/KatexFormulaPreview'
import { ImageCacheService } from '../services/ImageCacheService'
import { KatexUtils } from '../common/utils/KatexUtils'
import { fileUri } from '@kit.CoreFileKit'
import display from '@ohos.display'
import { FileService } from '../services/FileService'
import { AppContextHolder } from '../services/AppContextHolder'

/** 笔记预览/分享卡片共用的 Markdown 块渲染，独立于编辑页以缩小状态失效范围。 */
@Component
export struct NoteEditMarkdownBlocksView {
  @Prop blocks: MarkdownBlock[] = []
  @Prop filesDirCache: string = ''
  /** 远端图片落盘后由编辑页递增，用于强制 Image 块重建。 */
  @Prop imageRefreshKey: number = 0
  /** 分享长图导出：深色底 + 金色文字，与 NoteEdit 分享卡片一致。 */
  @Prop forShareExport: boolean = false
  /** 分享导出时覆盖文字色（#AARRGGBB），为空则用默认 share 资源色。 */
  @Prop shareTextOverride: string = ''
  @Prop shareCodeBgOverride: string = ''
  @Prop shareDividerOverride: string = ''
  @Prop shareBackgroundOverride: string = ''
  /** 主题/色调变更时递增，用于强制 Markdown 块重建。 */
  @Prop shareStyleKey: string = ''
  /** 语音笔记播放高亮：非分享场景下将正文主色改为 accent。 */
  @Prop forceAccentText: boolean = false
  onLinkToast: (href: string) => void = (_href: string) => {
  }
  onCheckboxToggle: (lineIndex: number, checked: boolean) => void =
    (_lineIndex: number, _checked: boolean) => {
    }
  onImageTap: (src: string) => void = (_src: string) => {
  }

  private primaryTextColor(): ResourceColor {
    if (this.forShareExport && this.shareTextOverride.length > 0) {
      return this.shareTextOverride
    }
    if (this.forShareExport) {
      return $r('app.color.share_text')
    }
    return this.forceAccentText ? $r('app.color.accent') : $r('app.color.primary_text')
  }

  private secondaryTextColor(): ResourceColor {
    if (this.forShareExport && this.shareTextOverride.length > 0) {
      return this.shareTextOverride
    }
    if (this.forShareExport) {
      return $r('app.color.share_text')
    }
    return this.forceAccentText ? $r('app.color.accent') : $r('app.color.secondary_text')
  }

  private accentTextColor(): ResourceColor {
    if (this.forShareExport && this.shareTextOverride.length > 0) {
      return this.shareTextOverride
    }
    return this.forShareExport ? $r('app.color.share_text') : $r('app.color.accent')
  }

  private codeBackgroundColor(): ResourceColor {
    if (this.forShareExport && this.shareCodeBgOverride.length > 0) {
      return this.shareCodeBgOverride
    }
    return this.forShareExport ? $r('app.color.share_code_background') : $r('app.color.surface_muted')
  }

  private dividerColor(): ResourceColor {
    if (this.forShareExport && this.shareDividerOverride.length > 0) {
      return this.shareDividerOverride
    }
    return this.forShareExport ? $r('app.color.share_divider') : $r('app.color.divider')
  }

  private cardBorderColor(): ResourceColor {
    if (this.forShareExport && this.shareDividerOverride.length > 0) {
      return this.shareDividerOverride
    }
    return this.forShareExport ? $r('app.color.share_divider') : $r('app.color.card_border')
  }

  private tertiaryTextColor(): ResourceColor {
    if (this.forShareExport && this.shareTextOverride.length > 0) {
      return this.shareTextOverride
    }
    if (this.forShareExport) {
      return $r('app.color.share_text')
    }
    return this.forceAccentText ? $r('app.color.accent') : $r('app.color.tertiary_text')
  }

  private mathTextColor(): string {
    if (this.forShareExport && this.shareTextOverride.length > 0) {
      return this.shareColorToRgb(this.shareTextOverride)
    }
    return this.forShareExport ? '#F5E6B8' : '#1D1D1F'
  }

  private mathBackgroundColor(): string {
    if (this.forShareExport && this.shareCodeBgOverride.length > 0) {
      return this.shareColorToRgb(this.shareCodeBgOverride)
    }
    if (this.forShareExport && this.shareBackgroundOverride.length > 0) {
      return this.shareColorToRgb(this.shareBackgroundOverride)
    }
    return this.forShareExport ? '#1A1A1C' : 'transparent'
  }

  private shareColorToRgb(color: string): string {
    if (color.length === 9 && color.startsWith('#FF')) {
      return `#${color.substring(3)}`
    }
    if (color.length === 9 && color.startsWith('#')) {
      return `#${color.substring(3)}`
    }
    return color
  }

  private hasMathInline(inlines: MarkdownInline[]): boolean {
    return inlines.some((inline: MarkdownInline) => inline.type === 'math_inline')
  }

  /** 整段仅含一个链接（可忽略空白 text）时返回该 link，否则 null。 */
  private standaloneLinkInline(inlines: MarkdownInline[]): MarkdownInline | null {
    let found: MarkdownInline | null = null
    for (let i = 0; i < inlines.length; i++) {
      const inline = inlines[i]
      if (inline.type === 'text' && inline.content.trim().length === 0) {
        continue
      }
      if (inline.type === 'link' && inline.href.trim().length > 0) {
        if (found !== null) {
          return null
        }
        found = inline
        continue
      }
      return null
    }
    return found
  }

  private isStandaloneLinkParagraph(inlines: MarkdownInline[]): boolean {
    return this.standaloneLinkInline(inlines) !== null
  }

  private standaloneLinkHref(inlines: MarkdownInline[]): string {
    const link = this.standaloneLinkInline(inlines)
    return link !== null ? link.href : ''
  }

  private standaloneLinkLabel(inlines: MarkdownInline[]): string {
    const link = this.standaloneLinkInline(inlines)
    return link !== null ? link.content : ''
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

  private resolveLocalImageAbsPath(src: string): string {
    if (src.startsWith('file://')) {
      return src.replace('file://', '')
    }
    if (src.startsWith('/')) {
      return src
    }
    let base = this.filesDirCache
    if (base.length === 0) {
      try {
        base = AppContextHolder.getContext().filesDir
      } catch (_) {
        base = ''
      }
    }
    return base.length > 0 ? `${base}/${src}` : src
  }

  private resolveImageSrc(src: string): string {
    if (src.startsWith('http://') || src.startsWith('https://')) {
      return src
    }
    return fileUri.getUriFromPath(this.resolveLocalImageAbsPath(src))
  }

  private isLocalNoteImageSrc(src: string): boolean {
    return src.includes('qingyu-note-image')
  }

  private localNoteImageExists(src: string): boolean {
    if (src.startsWith('http://') || src.startsWith('https://')) {
      return true
    }
    return FileService.fileExists(this.resolveLocalImageAbsPath(src))
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
    if (block.type === 'image') {
      return `image:${block.language}:${this.imageRefreshKey}:${index}`
    }
    let body = ''
    if (block.type === 'math_display') {
      body = `${block.type}:${block.content.slice(0, 48)}:${index}`
    } else if (block.type === 'unordered_list' || block.type === 'ordered_list') {
      const items = block.items
        .map((item: MarkdownInline[]) => item.map((inline: MarkdownInline) => inline.content.slice(0, 20)).join(''))
        .join('|')
      body = `${block.type}:${items}:${index}`
    } else if (block.type === 'checkbox_list') {
      const items = (block.checkboxItems ?? [])
        .map((item: MarkdownCheckboxItem) => `${item.checked}:${item.sourceLineIndex}`)
        .join('|')
      body = `${block.type}:${items}:${index}`
    } else if (block.type === 'table') {
      const headers = (block.tableHeaders ?? [])
        .map((cell: MarkdownInline[]) => cell.map((inline: MarkdownInline) => inline.content.slice(0, 12)).join(''))
        .join('|')
      const rows = (block.tableRows ?? [])
        .map((row: MarkdownInline[][]) =>
          row.map((cell: MarkdownInline[]) => cell.map((inline: MarkdownInline) => inline.content.slice(0, 12)).join('')).join(',')
        )
        .join('|')
      body = `${block.type}:${headers}:${rows}:${index}`
    } else {
      body = `${block.type}:${block.language}:${block.content.slice(0, 48)}:${index}`
    }
    return this.shareStyleKey.length > 0 ? `${this.shareStyleKey}:${body}` : body
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
    fontColor: ResourceColor, lineHeight: number, fontWeight: FontWeight = FontWeight.Regular,
    onTap?: () => void, wrapLongText: boolean = false) {
    if (this.hasMathInline(inlines) && !this.hasAnyMath()) {
      KatexFormulaPreview({
        source: rawContent,
        textColor: this.mathTextColor(),
        previewBackgroundColor: this.mathBackgroundColor(),
        displayBlock: false
      })
        .key(`katex_inline:${rawContent.slice(0, 64)}`)
    } else if (onTap) {
      Text() {
        ForEach(inlines, (inline: MarkdownInline, index: number) => {
          this.buildInlineSpan(inline, fontColor, wrapLongText)
        }, (inline: MarkdownInline, index: number) => this.inlineKey(inline, index))
      }
      .fontSize(fontSize)
      .fontColor(fontColor)
      .lineHeight(lineHeight)
      .fontWeight(fontWeight)
      .width('100%')
      .constraintSize({ minHeight: 24 })
      .wordBreak(wrapLongText ? WordBreak.BREAK_ALL : WordBreak.NORMAL)
      .onClick(() => {
        onTap()
      })
    } else {
      Text() {
        ForEach(inlines, (inline: MarkdownInline, index: number) => {
          this.buildInlineSpan(inline, fontColor, wrapLongText)
        }, (inline: MarkdownInline, index: number) => this.inlineKey(inline, index))
      }
      .fontSize(fontSize)
      .fontColor(fontColor)
      .lineHeight(lineHeight)
      .fontWeight(fontWeight)
      .copyOption(CopyOptions.LocalDevice)
      .width('100%')
      .wordBreak(wrapLongText ? WordBreak.BREAK_ALL : WordBreak.NORMAL)
    }
  }

  @Builder
  private buildInlineSpan(inline: MarkdownInline, defaultColor: ResourceColor, plainInlineCode: boolean = false) {
    if (inline.type === 'bold') {
      Span(inline.content)
        .fontWeight(FontWeight.Bold)
        .fontColor(defaultColor)
    } else if (inline.type === 'italic') {
      Span(inline.content)
        .fontStyle(FontStyle.Italic)
        .fontColor(defaultColor)
    } else if (inline.type === 'inline_code') {
      if (plainInlineCode) {
        Span(inline.content)
          .fontFamily('monospace')
          .fontColor(this.codeTokenColor('plain'))
          .backgroundColor(this.codeBackgroundColor())
      } else {
        this.buildInlineCodeTokenSpans(inline.content)
      }
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
    } else if (inline.type === 'image') {
      this.buildInlineImage(inline)
    } else {
      Span(inline.content)
        .fontColor(defaultColor)
    }
  }

  private tableCellKey(cell: MarkdownInline[], rowIndex: number, colIndex: number): string {
    const content = cell
      .map((inline: MarkdownInline) => `${inline.type}:${inline.content.slice(0, 16)}:${inline.href}`)
      .join('|')
    return `${content}:${rowIndex}:${colIndex}`
  }

  @Builder
  private buildInlineImage(inline: MarkdownInline) {
    if (inline.href.length === 0) {
      Blank()
    } else if (ImageCacheService.isNetworkImageUrl(inline.href)) {
      CachedNetworkImage({
        url: inline.href,
        imageWidth: '100%',
        objectFit: ImageFit.Contain,
        imageBorderRadius: 8,
        alt: inline.content
      })
    } else {
      Image(this.resolveImageSrc(inline.href))
        .width('100%')
        .objectFit(ImageFit.Contain)
        .borderRadius(8)
        .alt(inline.content)
    }
  }

  private tableCellHasImage(inlines: MarkdownInline[]): boolean {
    return inlines.some((inline: MarkdownInline) => inline.type === 'image')
  }

  @Builder
  private buildTableCellContent(inlines: MarkdownInline[], isHeader: boolean, wrapLongText: boolean = false) {
    if (this.tableCellHasImage(inlines)) {
      Column({ space: 4 }) {
        ForEach(inlines, (inline: MarkdownInline, index: number) => {
          if (inline.type === 'image') {
            this.buildInlineImage(inline)
          } else if (inline.content.length > 0) {
            Text() {
              this.buildInlineSpan(inline, this.primaryTextColor(), wrapLongText)
            }
            .fontSize(isHeader ? 15 : $r('app.float.body_font_size'))
            .fontColor(this.primaryTextColor())
            .lineHeight(this.contentLineHeight(22))
            .fontWeight(isHeader ? FontWeight.Medium : FontWeight.Regular)
            .width('100%')
            .wordBreak(wrapLongText ? WordBreak.BREAK_ALL : WordBreak.NORMAL)
          }
        }, (inline: MarkdownInline, index: number) => this.inlineKey(inline, index))
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    } else {
      this.buildInlineText(inlines, this.inlineSource(inlines),
        isHeader ? 15 : $r('app.float.body_font_size'),
        this.primaryTextColor(), this.contentLineHeight(22),
        isHeader ? FontWeight.Medium : FontWeight.Regular, undefined, wrapLongText)
    }
  }

  @Builder
  private buildTableCell(inlines: MarkdownInline[], isHeader: boolean, wrapLongText: boolean = false) {
    Column() {
      this.buildTableCellContent(inlines, isHeader, wrapLongText)
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .alignItems(HorizontalAlign.Start)
  }

  private readScreenWidthVp(): number {
    try {
      const dd = display.getDefaultDisplaySync()
      return this.getUIContext().px2vp(dd.width)
    } catch (_e) {
      return 360
    }
  }

  private tableColumnCount(block: MarkdownBlock): number {
    let count = (block.tableHeaders ?? []).length
    for (const row of block.tableRows ?? []) {
      if (row.length > count) {
        count = row.length
      }
    }
    return count
  }

  private screenWidthVp(): number {
    return this.readScreenWidthVp()
  }

  private wideTableMaxColumnWidthVp(): number {
    return this.screenWidthVp() * 0.4
  }

  private clampTableColumnWidthVp(width: number): number {
    const maxWidth = this.wideTableMaxColumnWidthVp()
    const minWidth = 48
    return Math.min(maxWidth, Math.max(minWidth, width))
  }

  private estimateTableCellWidthVp(text: string, fontSize: number, fontWeight: FontWeight,
    maxWidth: number, minWidth: number): number {
    const padding = 20
    if (text.trim().length === 0) {
      return minWidth
    }
    const em = fontSize
    const wideFactor = fontWeight === FontWeight.Medium || fontWeight === FontWeight.Bold ? 1.08 : 1
    let maxLineWidth = 0
    const lines = text.split('\n')
    for (const line of lines) {
      let lineWidth = 0
      for (let i = 0; i < line.length; i++) {
        const code = line.charCodeAt(i)
        const isWide = code > 0x2E7F
        lineWidth += isWide ? em * wideFactor : em * 0.56
      }
      maxLineWidth = Math.max(maxLineWidth, lineWidth)
    }
    const contentWidth = padding + maxLineWidth
    if (contentWidth >= maxWidth) {
      return maxWidth
    }
    return Math.max(minWidth, contentWidth)
  }

  private computeWideTableColumnWidths(block: MarkdownBlock, columnCount: number): number[] {
    const maxWidth = this.wideTableMaxColumnWidthVp()
    const minWidth = 48
    const widths = new Array<number>(columnCount)
    for (let col = 0; col < columnCount; col++) {
      widths[col] = minWidth
    }
    const measureRows: Array<MarkdownInline[][]> = []
    if ((block.tableHeaders ?? []).length > 0) {
      measureRows.push(block.tableHeaders ?? [])
    }
    for (const row of block.tableRows ?? []) {
      measureRows.push(row)
    }
    for (let col = 0; col < columnCount; col++) {
      for (let rowIndex = 0; rowIndex < measureRows.length; rowIndex++) {
        const row = measureRows[rowIndex]
        const isHeader = rowIndex === 0 && (block.tableHeaders ?? []).length > 0
        const cell = this.tableRowCells(row, columnCount)[col]
        const text = this.inlineSource(cell)
        const fontSize = 15
        const fontWeight = isHeader ? FontWeight.Medium : FontWeight.Regular
        const cellWidth = this.estimateTableCellWidthVp(text, fontSize, fontWeight, maxWidth, minWidth)
        if (cellWidth > widths[col]) {
          widths[col] = cellWidth
        }
      }
      widths[col] = this.clampTableColumnWidthVp(widths[col])
    }
    return widths
  }

  private tableTotalWidthVp(columnWidthsVp: number[] | null): number {
    if (columnWidthsVp === null || columnWidthsVp.length === 0) {
      return 0
    }
    let total = 0
    for (const width of columnWidthsVp) {
      total += width
    }
    return total
  }

  private tableRowCells(cells: MarkdownInline[][], columnCount: number): MarkdownInline[][] {
    const padded: MarkdownInline[][] = []
    for (let i = 0; i < columnCount; i++) {
      padded.push(cells[i] ?? [{ type: 'text', content: '', href: '' }])
    }
    return padded
  }

  @Builder
  private buildWideTableCell(cell: MarkdownInline[], isHeader: boolean, colWidth: number) {
    Column() {
      this.buildTableCell(cell, isHeader, true)
    }
    .width(colWidth)
    .constraintSize({ minWidth: colWidth, maxWidth: colWidth })
    .flexShrink(0)
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
    .border({ width: { right: 1, bottom: 1 }, color: this.cardBorderColor() })
    .backgroundColor(isHeader ? this.codeBackgroundColor() : Color.Transparent)
    .clip(true)
  }

  @Builder
  private buildTableDataRow(cells: MarkdownInline[][], rowIndex: number, isHeader: boolean, columnCount: number,
    columnWidthsVp: number[] | null = null) {
    Flex({
      direction: FlexDirection.Row,
      alignItems: ItemAlign.Stretch
    }) {
      ForEach(this.tableRowCells(cells, columnCount), (cell: MarkdownInline[], colIndex: number) => {
        if (columnWidthsVp !== null && colIndex < columnWidthsVp.length) {
          this.buildWideTableCell(cell, isHeader, this.clampTableColumnWidthVp(columnWidthsVp[colIndex]))
        } else {
          Column() {
            this.buildTableCell(cell, isHeader)
          }
          .layoutWeight(1)
          .constraintSize({ minWidth: 72 })
          .alignItems(HorizontalAlign.Start)
          .justifyContent(FlexAlign.Start)
          .border({ width: { right: 1, bottom: 1 }, color: this.cardBorderColor() })
          .backgroundColor(isHeader ? this.codeBackgroundColor() : Color.Transparent)
        }
      }, (cell: MarkdownInline[], colIndex: number) => this.tableCellKey(cell, rowIndex, colIndex))
    }
    .width(columnWidthsVp !== null ? this.tableTotalWidthVp(columnWidthsVp) : '100%')
    .flexShrink(columnWidthsVp !== null ? 0 : 1)
  }

  @Builder
  private buildTableBlockContent(block: MarkdownBlock, columnCount: number, columnWidthsVp: number[] | null) {
    Column() {
      if ((block.tableHeaders ?? []).length > 0) {
        this.buildTableDataRow(block.tableHeaders ?? [], -1, true, columnCount, columnWidthsVp)
      }
      ForEach(block.tableRows ?? [], (row: MarkdownInline[][], rowIndex: number) => {
        this.buildTableDataRow(row, rowIndex, false, columnCount, columnWidthsVp)
      }, (row: MarkdownInline[][], rowIndex: number) => {
        const content = row
          .map((cell: MarkdownInline[]) => cell.map((inline: MarkdownInline) => inline.content.slice(0, 12)).join(''))
          .join('|')
        return `${content}:${rowIndex}`
      })
    }
    .alignItems(HorizontalAlign.Start)
    .border({ width: 1, color: this.cardBorderColor() })
    .borderRadius(8)
    .width(columnWidthsVp !== null ? this.tableTotalWidthVp(columnWidthsVp) : '100%')
    .constraintSize({
      minWidth: columnWidthsVp !== null ? this.tableTotalWidthVp(columnWidthsVp) : 0
    })
    .flexShrink(columnWidthsVp !== null ? 0 : 1)
  }

  @Builder
  private buildWideTableScroll(block: MarkdownBlock, columnCount: number, columnWidthsVp: number[]) {
    Scroll() {
      this.buildTableBlockContent(block, columnCount, columnWidthsVp)
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Auto)
    .width('100%')
    .align(Alignment.TopStart)
    .nestedScroll({
      scrollForward: NestedScrollMode.SELF_FIRST,
      scrollBackward: NestedScrollMode.SELF_FIRST
    })
  }

  @Builder
  private buildTableBlock(block: MarkdownBlock, columnCount: number) {
    if (columnCount <= 3) {
      this.buildTableBlockContent(block, columnCount, null)
    } else {
      this.buildWideTableScroll(block, columnCount, this.computeWideTableColumnWidths(block, columnCount))
    }
  }

  @Builder
  private buildCheckboxListBlock(block: MarkdownBlock) {
    Column({ space: 10 }) {
      ForEach(block.checkboxItems ?? [], (item: MarkdownCheckboxItem, index: number) => {
        Row({ space: 8 }) {
          Checkbox({ name: `todo_${item.sourceLineIndex}`, group: 'todo_preview' })
            .select(item.checked)
            .enabled(false)
            .hitTestBehavior(HitTestMode.None)
          Column() {
            this.buildInlineText(item.inlines, this.inlineSource(item.inlines), $r('app.float.body_font_size'),
              this.primaryTextColor(), this.contentLineHeight(24), FontWeight.Regular, (): void => {
                if (!this.forShareExport) {
                  this.onCheckboxToggle(item.sourceLineIndex, !item.checked)
                }
              })
          }
          .layoutWeight(1)
          .width('100%')
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
        .onClick(() => {
          if (!this.forShareExport) {
            this.onCheckboxToggle(item.sourceLineIndex, !item.checked)
          }
        })
      }, (item: MarkdownCheckboxItem, index: number) =>
        `checkbox:${item.sourceLineIndex}:${item.checked}:${index}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
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
    } else if (block.type === 'checkbox_list') {
      this.buildCheckboxListBlock(block)
    } else if (block.type === 'table') {
      this.buildTableBlock(block, this.tableColumnCount(block))
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
      if (this.isLocalNoteImageSrc(block.language) && !this.localNoteImageExists(block.language)) {
        Column({ space: 10 }) {
          LoadingProgress()
            .width(28)
            .height(28)
            .color(this.accentTextColor())
          Text(block.content.length > 0 ? block.content : '图片同步中…')
            .fontSize($r('app.float.caption_font_size'))
            .fontColor(this.secondaryTextColor())
        }
        .width('100%')
        .padding({ top: 28, bottom: 28 })
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(this.codeBackgroundColor())
        .borderRadius(12)
        .onClick(() => {
          if (!this.forShareExport) {
            this.onImageTap(block.language)
          }
        })
      } else if (ImageCacheService.isNetworkImageUrl(block.language)) {
        CachedNetworkImage({
          url: block.language,
          imageWidth: '100%',
          objectFit: ImageFit.Cover,
          imageBorderRadius: 12,
          alt: block.content
        })
          .onClick(() => {
            if (!this.forShareExport) {
              this.onImageTap(block.language)
            }
          })
      } else {
        Image(this.resolveImageSrc(block.language))
          .width('100%')
          .objectFit(ImageFit.Cover)
          .borderRadius(12)
          .alt(block.content)
          .onClick(() => {
            if (!this.forShareExport) {
              this.onImageTap(block.language)
            }
          })
      }
    } else if (block.type === 'math_display' && !this.hasAnyMath()) {
      KatexFormulaPreview({
        source: KatexUtils.wrapDisplaySource(block.content),
        textColor: this.mathTextColor(),
        previewBackgroundColor: this.mathBackgroundColor(),
        displayBlock: true
      })
        .key(`math_display:${block.content.slice(0, 48)}`)
    } else if (this.isStandaloneLinkParagraph(block.inlines)) {
      PreviewStandaloneLinkCard({
        href: this.standaloneLinkHref(block.inlines),
        label: this.standaloneLinkLabel(block.inlines),
        onCardTap: (): void => {
          this.onLinkToast(this.standaloneLinkHref(block.inlines))
        }
      })
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
