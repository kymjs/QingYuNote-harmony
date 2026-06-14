/**
 * 极简 HTML → Markdown 转换器。
 * 与 Flutter 端 html2md 行为对齐（不要求 100% 等价，覆盖常见 block / inline 元素）。
 *
 * 转换流程：
 *  1. tokenize：把 HTML 切成 startTag / endTag / text / comment / cdata。
 *  2. 在 token 流上维护一个块级栈（h1..h6 / p / pre / blockquote / ul / ol / li / table），
 *     按行输出 markdown；inline 在块内即时折叠。
 *  3. 输出按连续空行折叠成 1 个空行。
 */
export class HtmlToMarkdown {
  private static readonly VOID_ELEMENTS: Set<string> = new Set<string>([
    'br', 'hr', 'img', 'input', 'meta', 'link', 'wbr', 'area', 'base', 'col', 'embed', 'source', 'track'
  ])

  static convert(html: string): string {
    if (html.length === 0) {
      return ''
    }
    const tokens = HtmlToMarkdown.tokenize(html)
    const ctx = new HtmlToMarkdownContext()
    for (const token of tokens) {
      HtmlToMarkdown.handleToken(token, ctx)
    }
    ctx.flushList()
    ctx.flushTable()
    return ctx.finish()
  }

  private static handleToken(token: HtmlToken, ctx: HtmlToMarkdownContext): void {
    if (token.kind === 'text') {
      ctx.appendText(token.text ?? '')
      return
    }
    if (token.kind === 'comment' || token.kind === 'cdata') {
      return
    }
    if (token.kind === 'end') {
      HtmlToMarkdown.handleEndTag(token.tag ?? '', ctx)
      return
    }
    const tag = (token.tag ?? '').toLowerCase()
    if (HtmlToMarkdown.VOID_ELEMENTS.has(tag)) {
      if (tag === 'br') {
        ctx.appendBreak()
        return
      }
      if (tag === 'hr') {
        ctx.appendHorizontalRule()
        return
      }
      if (tag === 'img') {
        const attrs = token.attrs ?? {}
        ctx.appendImage(attrs['src'] ?? '', attrs['alt'] ?? '')
        return
      }
      return
    }
    HtmlToMarkdown.handleStartTag(tag, token.attrs ?? {}, ctx)
  }

  private static handleStartTag(tag: string, attrs: Record<string, string>, ctx: HtmlToMarkdownContext): void {
    if (tag === 'script' || tag === 'style' || tag === 'head' || tag === 'noscript' || tag === 'template') {
      ctx.skipUntilClose(tag)
      return
    }
    if (tag === 'h1' || tag === 'h2' || tag === 'h3' || tag === 'h4' || tag === 'h5' || tag === 'h6') {
      const level = parseInt(tag.substring(1))
      ctx.openHeading(level)
      return
    }
    if (tag === 'p' || tag === 'div') {
      ctx.openParagraph()
      return
    }
    if (tag === 'pre') {
      ctx.openCodeBlock()
      return
    }
    if (tag === 'code' && !ctx.inCodeBlock) {
      ctx.appendInlineCode(' ')
      ctx.inCodeInline = true
      return
    }
    if (tag === 'blockquote') {
      ctx.openBlockquote()
      return
    }
    if (tag === 'ul') {
      ctx.openList(false)
      return
    }
    if (tag === 'ol') {
      ctx.openList(true)
      return
    }
    if (tag === 'li') {
      ctx.openListItem()
      return
    }
    if (tag === 'table') {
      ctx.openTable()
      return
    }
    if (tag === 'thead' || tag === 'tbody' || tag === 'tfoot') {
      ctx.appendTableSectionBreak()
      return
    }
    if (tag === 'tr') {
      ctx.openTableRow()
      return
    }
    if (tag === 'th' || tag === 'td') {
      ctx.openTableCell(tag === 'th')
      return
    }
    if (tag === 'strong' || tag === 'b') {
      ctx.appendInline('**')
      return
    }
    if (tag === 'em' || tag === 'i') {
      ctx.appendInline('*')
      return
    }
    if (tag === 'del' || tag === 's' || tag === 'strike') {
      ctx.appendInline('~~')
      return
    }
    if (tag === 'a') {
      ctx.appendLinkOpen(attrs['href'] ?? '', attrs['title'] ?? '')
      return
    }
  }

  private static handleEndTag(tag: string, ctx: HtmlToMarkdownContext): void {
    if (tag === 'script' || tag === 'style' || tag === 'head' || tag === 'noscript' || tag === 'template') {
      ctx.skipClear(tag)
      return
    }
    if (tag === 'h1' || tag === 'h2' || tag === 'h3' || tag === 'h4' || tag === 'h5' || tag === 'h6') {
      ctx.closeHeading()
      return
    }
    if (tag === 'p' || tag === 'div') {
      ctx.closeParagraph()
      return
    }
    if (tag === 'pre') {
      ctx.closeCodeBlock()
      return
    }
    if (tag === 'code') {
      if (ctx.inCodeBlock) {
        return
      }
      ctx.inCodeInline = false
      ctx.appendInlineCode(' ')
      return
    }
    if (tag === 'blockquote') {
      ctx.closeBlockquote()
      return
    }
    if (tag === 'ul') {
      ctx.closeList(false)
      return
    }
    if (tag === 'ol') {
      ctx.closeList(true)
      return
    }
    if (tag === 'li') {
      ctx.closeListItem()
      return
    }
    if (tag === 'table') {
      ctx.closeTable()
      return
    }
    if (tag === 'thead' || tag === 'tbody' || tag === 'tfoot') {
      ctx.appendTableSectionBreak()
      return
    }
    if (tag === 'tr') {
      ctx.closeTableRow()
      return
    }
    if (tag === 'th' || tag === 'td') {
      ctx.closeTableCell()
      return
    }
    if (tag === 'strong' || tag === 'b') {
      ctx.appendInline('**')
      return
    }
    if (tag === 'em' || tag === 'i') {
      ctx.appendInline('*')
      return
    }
    if (tag === 'del' || tag === 's' || tag === 'strike') {
      ctx.appendInline('~~')
      return
    }
    if (tag === 'a') {
      ctx.appendLinkClose()
      return
    }
  }

  // ---------- tokenizer ----------

  private static tokenize(html: string): HtmlToken[] {
    const tokens: HtmlToken[] = []
    const len = html.length
    let pos = 0
    while (pos < len) {
      const ch = html.charAt(pos)
      if (ch === '<') {
        if (pos + 4 <= len && html.substring(pos, pos + 4) === '<!--') {
          const end = html.indexOf('-->', pos + 4)
          if (end < 0) {
            tokens.push({ kind: 'text', text: html.substring(pos) })
            break
          }
          tokens.push({ kind: 'comment', text: html.substring(pos + 4, end) })
          pos = end + 3
          continue
        }
        if (pos + 9 <= len && html.substring(pos, pos + 9) === '<![CDATA[') {
          const end = html.indexOf(']]>', pos + 9)
          if (end < 0) {
            tokens.push({ kind: 'text', text: html.substring(pos) })
            break
          }
          tokens.push({ kind: 'cdata', text: html.substring(pos + 9, end) })
          pos = end + 3
          continue
        }
        if (pos + 2 <= len && html.charAt(pos + 1) === '?') {
          const end = html.indexOf('?>', pos + 2)
          if (end < 0) {
            break
          }
          pos = end + 2
          continue
        }
        if (pos + 9 <= len && html.substring(pos, pos + 9).toLowerCase() === '<!doctype') {
          const end = html.indexOf('>', pos + 9)
          if (end < 0) {
            break
          }
          pos = end + 1
          continue
        }
        const tagEnd = html.indexOf('>', pos)
        if (tagEnd < 0) {
          tokens.push({ kind: 'text', text: html.substring(pos) })
          break
        }
        const raw = html.substring(pos + 1, tagEnd)
        if (raw.length === 0) {
          pos = tagEnd + 1
          continue
        }
        if (raw.charAt(0) === '/') {
          const tagName = raw.substring(1).trim()
          tokens.push({ kind: 'end', tag: tagName })
        } else {
          const selfClosing = raw.charAt(raw.length - 1) === '/'
          const body = selfClosing ? raw.substring(0, raw.length - 1) : raw
          const trimmed = body.trim()
          if (trimmed.length === 0) {
            pos = tagEnd + 1
            continue
          }
          const space = trimmed.indexOf(' ')
          const tag = space < 0 ? trimmed : trimmed.substring(0, space)
          const rest = space < 0 ? '' : trimmed.substring(space + 1)
          const attrs = HtmlToMarkdown.parseAttrs(rest)
          tokens.push({ kind: 'start', tag, attrs })
        }
        pos = tagEnd + 1
        continue
      }
      const nextLt = html.indexOf('<', pos)
      const end = nextLt < 0 ? len : nextLt
      const text = html.substring(pos, end)
      if (text.length > 0) {
        tokens.push({ kind: 'text', text: HtmlToMarkdown.decodeEntities(text) })
      }
      pos = end
    }
    return tokens
  }

  private static parseAttrs(rest: string): Record<string, string> {
    const attrs: Record<string, string> = {}
    let i = 0
    const len = rest.length
    while (i < len) {
      while (i < len && (rest.charAt(i) === ' ' || rest.charAt(i) === '\t' || rest.charAt(i) === '\n')) {
        i += 1
      }
      if (i >= len) {
        break
      }
      const eq = rest.indexOf('=', i)
      if (eq < 0) {
        break
      }
      const name = rest.substring(i, eq).trim()
      i = eq + 1
      if (i >= len) {
        break
      }
      const quote = rest.charAt(i)
      if (quote !== '"' && quote !== '\'') {
        const ws = rest.indexOf(' ', i)
        const end = ws < 0 ? len : ws
        attrs[name] = rest.substring(i, end)
        i = end
        continue
      }
      i += 1
      const endQuote = rest.indexOf(quote, i)
      if (endQuote < 0) {
        break
      }
      attrs[name] = HtmlToMarkdown.decodeEntities(rest.substring(i, endQuote))
      i = endQuote + 1
    }
    return attrs
  }

  private static decodeEntities(text: string): string {
    const decRe: RegExp = /&#(\d+);/g
    const hexRe: RegExp = /&#x([0-9a-f]+);/gi
    let result = text.replace(decRe, (match: string, dec: string): string => {
      const code = parseInt(dec)
      return String.fromCharCode(code)
    })
    result = result.replace(hexRe, (match: string, hex: string): string => {
      const code = parseInt(hex, 16)
      return String.fromCharCode(code)
    })
    result = result.replace(/&nbsp;/g, ' ')
    result = result.replace(/&amp;/g, '&')
    result = result.replace(/&lt;/g, '<')
    result = result.replace(/&gt;/g, '>')
    result = result.replace(/&quot;/g, '"')
    result = result.replace(/&apos;/g, '\'')
    return result
  }
}

interface HtmlToken {
  kind: 'start' | 'end' | 'text' | 'comment' | 'cdata'
  tag?: string
  attrs?: Record<string, string>
  text?: string
}

interface ListStackEntry {
  ordered: boolean
  index: number
}

interface FlushInlineOptions {
  newParagraph: boolean
  headingLevel?: number
}

class HtmlToMarkdownContext {
  private output: string[] = []
  private inlineBuffer: string = ''
  /** 当前块级栈的「inline 部分是否需要换行」。 */
  private pendingBlockType: 'paragraph' | 'heading' | 'list' | 'blockquote' | 'code' | 'cell' | null = null
  private blockquoteDepth: number = 0
  private listStack: ListStackEntry[] = []
  private inList: boolean = false
  inCodeBlock: boolean = false
  inCodeInline: boolean = false
  inLink: boolean = false
  private linkHref: string = ''
  private linkTitle: string = ''
  private linkText: string = ''
  private currentHeadingLevel: number = 0
  private skipTag: string | null = null
  private tableActive: boolean = false
  private tableHeaderEmitted: boolean = false
  private tableRowsBuffer: string[] = []
  private currentTableRow: string[] | null = null
  private currentTableCellInline: string = ''
  private currentTableCellIsHeader: boolean = false

  private readonly optsFlushParagraph: FlushInlineOptions = { newParagraph: true }

  appendText(raw: string): void {
    if (this.skipTag !== null) {
      return
    }
    if (this.inCodeBlock) {
      this.inlineBuffer += raw
      return
    }
    let text = raw
    if (this.inCodeInline) {
      // inline code 保留空白
      this.appendInline(text)
      return
    }
    // 普通文本：折叠空白
    text = text.replace(/\r/g, '').replace(/\t/g, ' ').replace(/\n{2,}/g, '\n')
    text = text.replace(/[  ]+/g, ' ')
    if (text.length === 0) {
      return
    }
    if (this.tableActive && this.currentTableRow !== null) {
      this.currentTableCellInline += text
      return
    }
    if (this.inLink) {
      this.linkText += text
      return
    }
    this.appendInline(text)
  }

  appendInline(text: string): void {
    if (this.skipTag !== null) {
      return
    }
    this.inlineBuffer += text
  }

  appendInlineCode(_text: string): void {
    // 仅作为锚点用，实际 inline code 由 appendInline 输出反引号包裹
  }

  appendBreak(): void {
    if (this.tableActive && this.currentTableRow !== null) {
      this.currentTableCellInline += '<br/>'
      return
    }
    this.inlineBuffer += '  \n'
  }

  appendHorizontalRule(): void {
    this.flushInline(this.optsFlushParagraph)
    this.output.push('---')
    this.output.push('')
  }

  appendImage(src: string, alt: string): void {
    if (src.length === 0) {
      return
    }
    this.inlineBuffer += '![' + alt + '](' + src + ')'
  }

  appendLinkOpen(href: string, title: string): void {
    this.inLink = true
    this.linkHref = href
    this.linkTitle = title
    this.linkText = ''
  }

  appendLinkClose(): void {
    if (!this.inLink) {
      return
    }
    const text = this.linkText
    const href = this.linkHref
    const title = this.linkTitle
    this.inLink = false
    this.linkText = ''
    this.linkHref = ''
    this.linkTitle = ''
    if (href.length === 0) {
      this.appendInline(text)
      return
    }
    if (text.trim().length === 0) {
      this.appendInline('<' + href + '>')
      return
    }
    const titlePart = title.length > 0 ? ' "' + title + '"' : ''
    this.inlineBuffer += '[' + text + '](' + href + titlePart + ')'
  }

  openHeading(level: number): void {
    this.flushInline(this.optsFlushParagraph)
    this.pendingBlockType = 'heading'
    this.currentHeadingLevel = level
  }

  closeHeading(): void {
    const opts: FlushInlineOptions = { newParagraph: true, headingLevel: this.currentHeadingLevel }
    this.flushInline(opts)
    this.currentHeadingLevel = 0
    this.pendingBlockType = null
  }

  openParagraph(): void {
    this.flushInline(this.optsFlushParagraph)
    this.pendingBlockType = 'paragraph'
  }

  closeParagraph(): void {
    this.flushInline(this.optsFlushParagraph)
    this.pendingBlockType = null
  }

  openCodeBlock(): void {
    this.flushInline(this.optsFlushParagraph)
    this.inCodeBlock = true
    this.output.push('```')
  }

  closeCodeBlock(): void {
    if (!this.inCodeBlock) {
      return
    }
    this.output.push(this.inlineBuffer)
    this.inlineBuffer = ''
    this.inCodeBlock = false
    this.output.push('```')
    this.output.push('')
  }

  openBlockquote(): void {
    this.flushInline(this.optsFlushParagraph)
    this.blockquoteDepth += 1
  }

  closeBlockquote(): void {
    if (this.blockquoteDepth <= 0) {
      return
    }
    this.flushInline(this.optsFlushParagraph)
    this.blockquoteDepth -= 1
  }

  openList(ordered: boolean): void {
    this.flushInline(this.optsFlushParagraph)
    this.listStack.push({ ordered, index: 1 })
    this.inList = true
  }

  closeList(_ordered: boolean): void {
    if (this.listStack.length === 0) {
      return
    }
    this.listStack.pop()
    if (this.listStack.length === 0) {
      this.inList = false
      this.output.push('')
    }
  }

  openListItem(): void {
    this.flushInline(this.optsFlushParagraph)
    const top = this.listStack[this.listStack.length - 1]
    if (top === undefined) {
      this.listStack.push({ ordered: false, index: 1 })
    }
    const current = this.listStack[this.listStack.length - 1]
    if (current === undefined) {
      return
    }
    const marker = current.ordered ? (current.index + '. ') : '- '
    const indent = '  '.repeat(this.listStack.length - 1)
    this.appendInline(indent + marker)
  }

  closeListItem(): void {
    this.flushInline(this.optsFlushParagraph)
    const top = this.listStack[this.listStack.length - 1]
    if (top !== undefined && top.ordered) {
      top.index += 1
    }
  }

  openTable(): void {
    this.flushInline(this.optsFlushParagraph)
    this.tableActive = true
    this.tableHeaderEmitted = false
    this.tableRowsBuffer = []
    this.currentTableRow = null
  }

  closeTable(): void {
    if (!this.tableActive) {
      return
    }
    this.flushInline(this.optsFlushParagraph)
    this.output = this.output.concat(this.tableRowsBuffer)
    this.output.push('')
    this.tableActive = false
    this.tableRowsBuffer = []
    this.currentTableRow = null
  }

  appendTableSectionBreak(): void {
    if (!this.tableActive) {
      return
    }
    // thead/tbody/tfoot 不强区分，按行直接累加
  }

  openTableRow(): void {
    if (!this.tableActive) {
      return
    }
    this.currentTableRow = []
  }

  closeTableRow(): void {
    if (!this.tableActive || this.currentTableRow === null) {
      return
    }
    const cells = this.currentTableRow
    this.currentTableRow = null
    if (cells.length === 0) {
      return
    }
    this.tableRowsBuffer.push('| ' + cells.join(' | ') + ' |')
    if (!this.tableHeaderEmitted) {
      this.tableHeaderEmitted = true
      this.tableRowsBuffer.push('| ' + cells.map(() => '---').join(' | ') + ' |')
    }
  }

  openTableCell(isHeader: boolean): void {
    if (!this.tableActive) {
      return
    }
    this.currentTableCellInline = ''
    this.currentTableCellIsHeader = isHeader
  }

  closeTableCell(): void {
    if (!this.tableActive || this.currentTableRow === null) {
      return
    }
    let inline = this.currentTableCellInline.trim().replace(/\|/g, '\\|').replace(/\n+/g, ' ')
    if (inline.length === 0) {
      inline = ' '
    }
    this.currentTableRow.push(inline)
    this.currentTableCellInline = ''
  }

  flushList(): void {
    while (this.listStack.length > 0) {
      this.listStack.pop()
    }
    this.inList = false
  }

  flushTable(): void {
    if (this.tableActive) {
      this.closeTable()
    }
  }

  skipUntilClose(tag: string): void {
    this.flushInline(this.optsFlushParagraph)
    this.skipTag = tag
  }

  skipClear(tag: string): void {
    if (this.skipTag === tag) {
      this.skipTag = null
    }
  }

  finish(): string {
    this.flushInline(this.optsFlushParagraph)
    // 折叠连续空行
    const result: string[] = []
    let lastEmpty = false
    for (const line of this.output) {
      const isEmpty = line.trim().length === 0
      if (isEmpty && lastEmpty) {
        continue
      }
      result.push(line)
      lastEmpty = isEmpty
    }
    while (result.length > 0 && result[result.length - 1].trim().length === 0) {
      result.pop()
    }
    return result.join('\n')
  }

  private flushInline(options: FlushInlineOptions): void {
    const text = this.inlineBuffer
    this.inlineBuffer = ''
    if (this.inCodeBlock) {
      if (text.length > 0) {
        this.output.push(text)
      }
      return
    }
    if (options.newParagraph) {
      let trimmed = text
      if (trimmed.length === 0 && options.headingLevel === undefined) {
        return
      }
      if (options.headingLevel !== undefined && options.headingLevel > 0) {
        const hashes = '#'.repeat(options.headingLevel)
        if (trimmed.length === 0) {
          this.output.push(hashes)
        } else {
          this.output.push(hashes + ' ' + trimmed)
        }
        this.output.push('')
        return
      }
      // 块引用：在文本前每行加 '> '
      if (this.blockquoteDepth > 0) {
        const lines = trimmed.split('\n')
        const prefix = '> '.repeat(this.blockquoteDepth)
        trimmed = lines.map(l => l.length === 0 ? prefix.trimEnd() : prefix + l).join('\n')
      }
      this.output.push(trimmed)
      if (this.inList) {
        // 列表项已自带缩进 marker，不补额外空行
      } else if (this.blockquoteDepth > 0) {
        // 紧跟下一段同样缩进
      } else {
        this.output.push('')
      }
      return
    }
    if (text.length > 0) {
      const lastIdx = this.output.length - 1
      if (lastIdx >= 0) {
        const lastLine = this.output[lastIdx] ?? ''
        this.output[lastIdx] = lastLine + text
      }
    }
  }
}
