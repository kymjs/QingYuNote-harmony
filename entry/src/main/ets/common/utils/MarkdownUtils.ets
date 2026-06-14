import type { EditorInsertResult } from './EditorMarkdownInsert'

export type MarkdownInlineType =
  'text' | 'bold' | 'italic' | 'strikethrough' | 'inline_code' | 'link' | 'image' | 'math_inline'

export interface MarkdownInline {
  type: MarkdownInlineType
  content: string
  href: string
}

export type MarkdownBlockType =
  'heading1' | 'heading2' | 'heading3' | 'quote' | 'unordered_list' | 'ordered_list' | 'checkbox_list' | 'code' | 'divider' | 'image' | 'paragraph' | 'math_display' | 'table'

type MarkdownListBlockType = 'unordered_list' | 'ordered_list'

export interface MarkdownCheckboxItem {
  checked: boolean
  inlines: MarkdownInline[]
  sourceLineIndex: number
}

export interface MarkdownBlock {
  type: MarkdownBlockType
  content: string
  inlines: MarkdownInline[]
  items: MarkdownInline[][]
  language: string
  checkboxItems?: MarkdownCheckboxItem[]
  tableHeaders?: MarkdownInline[][]
  tableRows?: MarkdownInline[][][]
}

export interface LinkSummaryParts {
  title: string
  body: string
}

interface MarkdownToken {
  type: 'bold' | 'italic' | 'strikethrough' | 'inline_code' | 'link' | 'image' | 'math_inline'
  index: number
  marker: string
}

export class MarkdownUtils {
  /** 编辑页自动标题：正文 trim 后取前 5 个字符（与 Flutter `editorAutoTitle` 对齐）。 */
  static editorAutoTitle(content: string): string {
    const trimmed = content.trim()
    if (trimmed.length === 0) {
      return ''
    }
    return trimmed.length <= 5 ? trimmed : trimmed.slice(0, 5)
  }

  static extractTitle(content: string): string {
    const lines = content.split('\n')
    for (const line of lines) {
      const trimmed = line.trim()
      if (trimmed.length === 0) {
        continue
      }
      if (trimmed.startsWith('#')) {
        return trimmed.replace(/^#+\s*/, '').slice(0, 40)
      }
      return trimmed.slice(0, 30)
    }
    return '未命名笔记'
  }

  /** AI 链接摘要：若首段非空行为 Markdown 标题，拆出标题与正文（不含标题行）。 */
  static splitLinkSummary(summary: string): LinkSummaryParts {
    const trimmed = summary.trim()
    if (trimmed.length === 0) {
      return { title: '', body: '' }
    }
    const lines = trimmed.split('\n')
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim()
      if (line.length === 0) {
        continue
      }
      if (line.startsWith('#')) {
        const titleText = line.replace(/^#+\s*/, '').trim()
        const title = titleText.length <= 40 ? titleText : titleText.slice(0, 40)
        let bodyStart = i + 1
        while (bodyStart < lines.length && lines[bodyStart].trim().length === 0) {
          bodyStart++
        }
        const body = bodyStart >= lines.length
          ? ''
          : lines.slice(bodyStart).join('\n').trim()
        return { title: title, body: body }
      }
      break
    }
    return { title: '', body: trimmed }
  }

  static stripMarkdown(content: string): string {
    if (!MarkdownUtils.containsMarkdownMarkers(content)) {
      return content.replace(/\r/g, '').trim()
    }
    return content
      .replace(/\$\$[\s\S]*?\$\$/g, ' ')
      .replace(/\\\[[\s\S]*?\\\]/g, ' ')
      .replace(/\\\([\s\S]*?\\\)/g, ' ')
      .replace(/(?<!\\)\$[^$\n]+(?<!\\)\$/g, ' ')
      .replace(/```\w*\n[\s\S]*?\n```/g, ' ')
      .replace(/```([^`\n]+)```/g, '$1')
      .replace(/`([^`]+)`/g, '$1')
      .replace(/^>\s?/gm, '')
      .replace(/^#+\s?/gm, '')
      .replace(/^\d+\.\s+/gm, '')
      .replace(/\*\*([^*]+)\*\*/g, '$1')
      .replace(/__([^_]+)__/g, '$1')
      .replace(/\*([^*]+)\*/g, '$1')
      .replace(/_([^_]+)_/g, '$1')
      .replace(/~~([^~]+)~~/g, '$1')
      .replace(/!\[[^\]]*\]\([^)]+\)/g, '')
      .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
      .replace(/^[-*+]\s+/gm, '')
      .replace(/^\[[ -]\]\s?/gm, '')
      .replace(/^☐\s?/gm, '')
      .replace(/\r/g, '')
      .trim()
  }

  /** 行首 `[ ]` 或 `☐` 为未选中勾选框，`[-]` 为已选中勾选框。 */
  static isUncheckedCheckboxLine(trimmed: string): boolean {
    return /^\[ \]/.test(trimmed) || trimmed.startsWith('☐')
  }

  static isCheckedCheckboxLine(trimmed: string): boolean {
    return /^\[-\]/.test(trimmed)
  }

  static isCheckboxLine(trimmed: string): boolean {
    return MarkdownUtils.isUncheckedCheckboxLine(trimmed) ||
      MarkdownUtils.isCheckedCheckboxLine(trimmed)
  }

  static checkboxLineText(trimmed: string): string {
    if (MarkdownUtils.isUncheckedCheckboxLine(trimmed)) {
      if (trimmed.startsWith('☐')) {
        return trimmed.replace(/^☐\s?/, '')
      }
      return trimmed.replace(/^\[ \]\s?/, '')
    }
    if (MarkdownUtils.isCheckedCheckboxLine(trimmed)) {
      return trimmed.replace(/^\[-\]\s?/, '')
    }
    return trimmed
  }

  static isTableRow(trimmed: string): boolean {
    if (!trimmed.includes('|')) {
      return false
    }
    return /^\|?.+\|/.test(trimmed)
  }

  static isTableSeparator(trimmed: string): boolean {
    if (!trimmed.includes('|') || !trimmed.includes('-')) {
      return false
    }
    return /^\|?[\s|:-]+\|[\s|:-]*$/.test(trimmed)
  }

  static parseTableRowCells(row: string): string[] {
    let line = row.trim()
    if (line.startsWith('|')) {
      line = line.slice(1)
    }
    if (line.endsWith('|')) {
      line = line.slice(0, line.length - 1)
    }
    return line.split('|').map((cell: string) => cell.trim())
  }

  private static parseTableCells(cells: string[]): MarkdownInline[][] {
    return cells.map((cell: string) => MarkdownUtils.parseInlines(cell))
  }

  static toggleCheckboxLine(content: string, lineIndex: number, checked?: boolean): string {
    const lines = content.replace(/\r/g, '').split('\n')
    if (lineIndex < 0 || lineIndex >= lines.length) {
      return content
    }
    const line = lines[lineIndex]
    const trimmed = line.trimStart()
    if (!MarkdownUtils.isCheckboxLine(trimmed)) {
      return content
    }
    const wasChecked = MarkdownUtils.isCheckedCheckboxLine(trimmed)
    const newChecked = checked !== undefined ? checked : !wasChecked
    const text = MarkdownUtils.checkboxLineText(trimmed)
    const leading = line.slice(0, line.length - trimmed.length)
    const marker = newChecked ? '[-]' : '[ ]'
    lines[lineIndex] = text.length === 0 ? `${leading}${marker}` : `${leading}${marker} ${text}`
    return lines.join('\n')
  }

  private static findNewlineInsertAt(oldContent: string, newContent: string): number | null {
    if (newContent.length <= oldContent.length) {
      return null
    }
    let insertAt = -1
    for (let i = 0; i < oldContent.length; i++) {
      if (i >= newContent.length || oldContent[i] !== newContent[i]) {
        insertAt = i
        break
      }
    }
    if (insertAt === -1 && newContent.length === oldContent.length + 1) {
      insertAt = oldContent.length
    }
    if (insertAt === -1 || newContent[insertAt] !== '\n') {
      return null
    }
    return insertAt
  }

  private static lineStartBefore(text: string, offset: number): number {
    if (offset <= 0) {
      return 0
    }
    const idx = text.lastIndexOf('\n', offset - 1)
    return idx < 0 ? 0 : idx + 1
  }

  private static lineAlreadyHasContinuableMarker(lineContent: string): boolean {
    const trimmed = lineContent.trimStart()
    if (trimmed.length === 0) {
      return false
    }
    if (MarkdownUtils.isCheckboxLine(trimmed)) {
      return true
    }
    if (/^[-*+]\s+/.test(trimmed)) {
      return true
    }
    if (/^\d+\.\s+/.test(trimmed)) {
      return true
    }
    if (trimmed.startsWith('>')) {
      return true
    }
    return false
  }

  /** 从行首提取可在换行后延续的 Markdown 标记；仅含标记无正文时返回 null（退出列表）。 */
  static lineMarkerPrefixForContinuation(line: string): string | null {
    const trimmed = line.trimStart()
    const leading = line.slice(0, line.length - trimmed.length)
    if (MarkdownUtils.isUncheckedCheckboxLine(trimmed)) {
      const text = MarkdownUtils.checkboxLineText(trimmed)
      if (text.trim().length === 0) {
        return null
      }
      return `${leading}[ ] `
    }
    if (MarkdownUtils.isCheckedCheckboxLine(trimmed)) {
      const text = MarkdownUtils.checkboxLineText(trimmed)
      if (text.trim().length === 0) {
        return null
      }
      return `${leading}[-] `
    }
    const bulletMatch = /^([-*+])\s+(.*)$/.exec(trimmed)
    if (bulletMatch !== null) {
      if ((bulletMatch[2] ?? '').trim().length === 0) {
        return null
      }
      return `${leading}${bulletMatch[1]} `
    }
    const orderedMatch = /^(\d+)\.\s+(.*)$/.exec(trimmed)
    if (orderedMatch !== null) {
      if ((orderedMatch[2] ?? '').trim().length === 0) {
        return null
      }
      const number = parseInt(orderedMatch[1] ?? '0', 10)
      return `${leading}${number + 1}. `
    }
    if (trimmed.startsWith('>')) {
      const text = trimmed.replace(/^>\s?/, '')
      if (text.trim().length === 0) {
        return null
      }
      return `${leading}> `
    }
    return null
  }

  /** 换行时延续上一行行首 Markdown 标记；todoFallback 为 true 且无标记时插入 `[ ] `。 */
  static applyMarkdownMarkerOnNewline(
    oldContent: string,
    newContent: string,
    todoFallback: boolean = false
  ): EditorInsertResult | null {
    const insertAt = MarkdownUtils.findNewlineInsertAt(oldContent, newContent)
    if (insertAt === null) {
      return null
    }
    const prevLineStart = MarkdownUtils.lineStartBefore(oldContent, insertAt)
    const prevLine = oldContent.slice(prevLineStart, insertAt)
    let prefix = MarkdownUtils.lineMarkerPrefixForContinuation(prevLine)
    if (prefix === null && todoFallback) {
      prefix = '[ ] '
    }
    if (prefix === null) {
      return null
    }
    const lineStart = insertAt + 1
    const lineEnd = newContent.indexOf('\n', lineStart)
    const lineContent = lineEnd === -1
      ? newContent.slice(lineStart)
      : newContent.slice(lineStart, lineEnd)
    if (MarkdownUtils.lineAlreadyHasContinuableMarker(lineContent)) {
      return null
    }
    const updated = `${newContent.slice(0, lineStart)}${prefix}${newContent.slice(lineStart)}`
    return { text: updated, caret: lineStart + prefix.length }
  }

  /** Todo 标签笔记换行时，在新行行首自动插入 `[ ] `。 */
  static applyTodoCheckboxOnNewline(
    oldContent: string,
    newContent: string,
    caret: number
  ): EditorInsertResult | null {
    return MarkdownUtils.applyMarkdownMarkerOnNewline(oldContent, newContent, true)
  }

  static summary(content: string, maxLength: number = 100): string {
    const plainText = MarkdownUtils.normalizeWhitespace(MarkdownUtils.stripMarkdown(content))
    if (plainText.length === 0) {
      return '空白笔记'
    }
    return plainText.length > maxLength ? `${plainText.slice(0, maxLength)}...` : plainText
  }

  static parseBlocks(content: string): MarkdownBlock[] {
    if (content.trim().length === 0) {
      return [MarkdownUtils.placeholderBlock()]
    }
    const lines = content.replace(/\r/g, '').split('\n')
    const blocks: MarkdownBlock[] = []
    const paragraphLines: string[] = []
    const quoteLines: string[] = []
    const listItems: string[] = []
    const checkboxItems: MarkdownCheckboxItem[] = []
    let inCodeBlock = false
    const codeLines: string[] = []
    let codeLanguage = ''
    let inMathBlock = false
    const mathLines: string[] = []
    let activeListType: MarkdownListBlockType = 'unordered_list'
    let hasActiveList = false

    const flushMathBlock = (): void => {
      if (!inMathBlock) {
        return
      }
      const latex = mathLines.join('\n').trim()
      mathLines.length = 0
      inMathBlock = false
      if (latex.length === 0) {
        return
      }
      blocks.push({
        type: 'math_display',
        content: latex,
        inlines: [],
        items: [],
        language: ''
      })
    }

    const flushParagraph = (): void => {
      if (paragraphLines.length === 0) {
        return
      }
      const text = paragraphLines.join('\n').trim()
      paragraphLines.length = 0
      if (text.length === 0) {
        return
      }
      blocks.push({
        type: 'paragraph',
        content: text,
        inlines: MarkdownUtils.parseInlines(text),
        items: [],
        language: ''
      })
    }

    const flushQuote = (): void => {
      if (quoteLines.length === 0) {
        return
      }
      const text = quoteLines.join('\n').trim()
      quoteLines.length = 0
      if (text.length === 0) {
        return
      }
      blocks.push({
        type: 'quote',
        content: text,
        inlines: MarkdownUtils.parseInlines(text),
        items: [],
        language: ''
      })
    }

    const flushCheckboxList = (): void => {
      if (checkboxItems.length === 0) {
        return
      }
      blocks.push({
        type: 'checkbox_list',
        content: '',
        inlines: [],
        items: [],
        language: '',
        checkboxItems: [...checkboxItems]
      })
      checkboxItems.length = 0
    }

    const flushList = (): void => {
      if (listItems.length === 0 || !hasActiveList) {
        listItems.length = 0
        hasActiveList = false
        return
      }
      const items = listItems.map((item: string) => MarkdownUtils.parseInlines(item))
      blocks.push({
        type: activeListType,
        content: listItems.join('\n'),
        inlines: [],
        items,
        language: ''
      })
      listItems.length = 0
      hasActiveList = false
    }

    const flushAll = (): void => {
      flushMathBlock()
      flushParagraph()
      flushQuote()
      flushList()
      flushCheckboxList()
    }

    for (let lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      const line = lines[lineIndex]
      const trimmed = line.trim()
      if (inCodeBlock) {
        if (MarkdownUtils.isCodeFenceCloser(trimmed)) {
          blocks.push({
            type: 'code',
            content: codeLines.join('\n'),
            inlines: [],
            items: [],
            language: codeLanguage
          })
          codeLines.length = 0
          codeLanguage = ''
          inCodeBlock = false
        } else {
          codeLines.push(line)
        }
        continue
      }
      if (MarkdownUtils.isCodeFenceOpener(trimmed)) {
        flushAll()
        inCodeBlock = true
        codeLanguage = MarkdownUtils.codeFenceLanguage(trimmed)
        continue
      }
      if (inMathBlock) {
        if (trimmed.endsWith('$$')) {
          const withoutClose = trimmed.slice(0, trimmed.length - 2).trim()
          if (withoutClose.length > 0) {
            mathLines.push(withoutClose)
          }
          flushMathBlock()
        } else {
          mathLines.push(line)
        }
        continue
      }
      if (trimmed.startsWith('$$')) {
        flushAll()
        const inner = trimmed.slice(2)
        if (trimmed.endsWith('$$') && trimmed.length > 4) {
          blocks.push({
            type: 'math_display',
            content: inner.slice(0, inner.length - 2).trim(),
            inlines: [],
            items: [],
            language: ''
          })
        } else if (trimmed === '$$') {
          inMathBlock = true
        } else {
          inMathBlock = true
          mathLines.push(inner)
        }
        continue
      }
      if (trimmed.startsWith('\\[') && trimmed.endsWith('\\]') && trimmed.length > 4) {
        flushAll()
        blocks.push({
          type: 'math_display',
          content: trimmed.slice(2, trimmed.length - 2).trim(),
          inlines: [],
          items: [],
          language: ''
        })
        continue
      }
      if (trimmed.length === 0) {
        flushAll()
        continue
      }
      if (/^([-*_])\1{2,}$/.test(trimmed)) {
        flushAll()
        blocks.push({
          type: 'divider',
          content: '',
          inlines: [],
          items: [],
          language: ''
        })
        continue
      }
      const imageMatch = trimmed.match(/^!\[([^\]]*)\]\(([^)]+)\)$/)
      if (imageMatch) {
        flushAll()
        blocks.push({
          type: 'image',
          content: imageMatch[1] ?? '',
          inlines: [],
          items: [],
          language: imageMatch[2] ?? ''
        })
        continue
      }
      if (trimmed.startsWith('### ')) {
        flushAll()
        const text = trimmed.slice(4)
        blocks.push({
          type: 'heading3',
          content: text,
          inlines: MarkdownUtils.parseInlines(text),
          items: [],
          language: ''
        })
        continue
      }
      if (trimmed.startsWith('## ')) {
        flushAll()
        const text = trimmed.slice(3)
        blocks.push({
          type: 'heading2',
          content: text,
          inlines: MarkdownUtils.parseInlines(text),
          items: [],
          language: ''
        })
        continue
      }
      if (trimmed.startsWith('# ')) {
        flushAll()
        const text = trimmed.slice(2)
        blocks.push({
          type: 'heading1',
          content: text,
          inlines: MarkdownUtils.parseInlines(text),
          items: [],
          language: ''
        })
        continue
      }
      if (trimmed.startsWith('>')) {
        flushParagraph()
        flushList()
        quoteLines.push(trimmed.replace(/^>\s?/, ''))
        continue
      }
      if (quoteLines.length > 0) {
        flushQuote()
      }
      if (MarkdownUtils.isUncheckedCheckboxLine(trimmed) ||
        MarkdownUtils.isCheckedCheckboxLine(trimmed)) {
        flushParagraph()
        flushList()
        const checked = MarkdownUtils.isCheckedCheckboxLine(trimmed)
        const text = MarkdownUtils.checkboxLineText(trimmed)
        checkboxItems.push({
          checked,
          inlines: MarkdownUtils.parseInlines(text),
          sourceLineIndex: lineIndex
        })
        continue
      }
      if (checkboxItems.length > 0) {
        flushCheckboxList()
      }
      if (MarkdownUtils.isTableRow(trimmed)) {
        flushParagraph()
        flushList()
        const tableLines: string[] = [trimmed]
        let nextIndex = lineIndex + 1
        while (nextIndex < lines.length) {
          const nextTrimmed = lines[nextIndex].trim()
          if (nextTrimmed.length === 0 || !MarkdownUtils.isTableRow(nextTrimmed)) {
            break
          }
          tableLines.push(nextTrimmed)
          nextIndex++
        }
        lineIndex = nextIndex - 1

        const tableHeaders: MarkdownInline[][] = []
        const tableRows: MarkdownInline[][][] = []
        let bodyStart = 0
        if (tableLines.length >= 2 && MarkdownUtils.isTableSeparator(tableLines[1])) {
          tableHeaders.push(...MarkdownUtils.parseTableCells(MarkdownUtils.parseTableRowCells(tableLines[0])))
          bodyStart = 2
        }
        for (let i = bodyStart; i < tableLines.length; i++) {
          if (MarkdownUtils.isTableSeparator(tableLines[i])) {
            continue
          }
          tableRows.push(MarkdownUtils.parseTableCells(MarkdownUtils.parseTableRowCells(tableLines[i])))
        }
        blocks.push({
          type: 'table',
          content: '',
          inlines: [],
          items: [],
          language: '',
          tableHeaders,
          tableRows
        })
        continue
      }
      if (/^[-*+]\s+/.test(trimmed)) {
        flushParagraph()
        const text = trimmed.replace(/^[-*+]\s+/, '')
        if (activeListType === 'ordered_list') {
          flushList()
        }
        activeListType = 'unordered_list'
        hasActiveList = true
        listItems.push(text)
        continue
      }
      if (/^\d+\.\s+/.test(trimmed)) {
        flushParagraph()
        const text = trimmed.replace(/^\d+\.\s+/, '')
        if (activeListType === 'unordered_list') {
          flushList()
        }
        activeListType = 'ordered_list'
        hasActiveList = true
        listItems.push(text)
        continue
      }
      if (hasActiveList) {
        flushList()
      }
      paragraphLines.push(line)
    }
    if (inCodeBlock && codeLines.length > 0) {
      blocks.push({
        type: 'code',
        content: codeLines.join('\n'),
        inlines: [],
        items: [],
        language: codeLanguage
      })
    }
    flushAll()
    return blocks.length > 0 ? blocks : [MarkdownUtils.placeholderBlock()]
  }

  private static parseInlines(content: string): MarkdownInline[] {
    if (content.length === 0) {
      return [{ type: 'text', content: '', href: '' }]
    }
    if (!MarkdownUtils.containsInlineMarkers(content)) {
      return [{ type: 'text', content, href: '' }]
    }
    const inlines: MarkdownInline[] = []
    let cursor = 0
    while (cursor < content.length) {
      const nextToken = MarkdownUtils.findNextToken(content, cursor)
      if (!nextToken) {
        MarkdownUtils.pushInline(inlines, {
          type: 'text',
          content: content.slice(cursor),
          href: ''
        })
        break
      }
      if (nextToken.index > cursor) {
        MarkdownUtils.pushInline(inlines, {
          type: 'text',
          content: content.slice(cursor, nextToken.index),
          href: ''
        })
      }
      if (nextToken.type === 'math_inline') {
        const isParen = nextToken.marker === '\\('
        const closingToken = isParen ? '\\)' : '$'
        const closingIndex = isParen
          ? content.indexOf(closingToken, nextToken.index + 2)
          : MarkdownUtils.findClosingInlineDollar(content, nextToken.index + 1)
        if (closingIndex === -1) {
          MarkdownUtils.pushInline(inlines, {
            type: 'text',
            content: content.slice(nextToken.index),
            href: ''
          })
          break
        }
        MarkdownUtils.pushInline(inlines, {
          type: 'math_inline',
          content: content.slice(nextToken.index + nextToken.marker.length, closingIndex).trim(),
          href: ''
        })
        cursor = closingIndex + closingToken.length
        continue
      }
      if (nextToken.type === 'inline_code') {
        const isTripleFence = nextToken.marker === '```'
        const markerLength = isTripleFence ? 3 : 1
        const closingIndex = isTripleFence
          ? content.indexOf('```', nextToken.index + 3)
          : content.indexOf('`', nextToken.index + 1)
        if (closingIndex === -1) {
          MarkdownUtils.pushInline(inlines, {
            type: 'text',
            content: content.slice(nextToken.index),
            href: ''
          })
          break
        }
        const codeContent = content.slice(nextToken.index + markerLength, closingIndex)
        if (isTripleFence && codeContent.includes('\n')) {
          MarkdownUtils.pushInline(inlines, {
            type: 'text',
            content: content.slice(nextToken.index, nextToken.index + markerLength),
            href: ''
          })
          cursor = nextToken.index + markerLength
          continue
        }
        MarkdownUtils.pushInline(inlines, {
          type: 'inline_code',
          content: codeContent,
          href: ''
        })
        cursor = closingIndex + markerLength
        continue
      }
      if (nextToken.type === 'image') {
        const labelEnd = content.indexOf('](', nextToken.index)
        const hrefEnd = labelEnd === -1 ? -1 : content.indexOf(')', labelEnd + 2)
        if (labelEnd === -1 || hrefEnd === -1) {
          MarkdownUtils.pushInline(inlines, {
            type: 'text',
            content: content.slice(nextToken.index, nextToken.index + 1),
            href: ''
          })
          cursor = nextToken.index + 1
          continue
        }
        MarkdownUtils.pushInline(inlines, {
          type: 'image',
          content: content.slice(nextToken.index + 2, labelEnd),
          href: content.slice(labelEnd + 2, hrefEnd).trim()
        })
        cursor = hrefEnd + 1
        continue
      }
      if (nextToken.type === 'link') {
        const labelEnd = content.indexOf('](', nextToken.index)
        const hrefEnd = labelEnd === -1 ? -1 : content.indexOf(')', labelEnd + 2)
        if (labelEnd === -1 || hrefEnd === -1) {
          MarkdownUtils.pushInline(inlines, {
            type: 'text',
            content: content.slice(nextToken.index, nextToken.index + 1),
            href: ''
          })
          cursor = nextToken.index + 1
          continue
        }
        MarkdownUtils.pushInline(inlines, {
          type: 'link',
          content: content.slice(nextToken.index + 1, labelEnd),
          href: content.slice(labelEnd + 2, hrefEnd).trim()
        })
        cursor = hrefEnd + 1
        continue
      }

      const marker = nextToken.type === 'bold' ? nextToken.marker : nextToken.marker
      const closingIndex = content.indexOf(marker, nextToken.index + marker.length)
      if (closingIndex === -1) {
        MarkdownUtils.pushInline(inlines, {
          type: 'text',
          content: content.slice(nextToken.index, nextToken.index + marker.length),
          href: ''
        })
        cursor = nextToken.index + marker.length
        continue
      }
      let inlineType: MarkdownInlineType = 'italic'
      if (nextToken.type === 'bold') {
        inlineType = 'bold'
      } else if (nextToken.type === 'strikethrough') {
        inlineType = 'strikethrough'
      }
      MarkdownUtils.pushInline(inlines, {
        type: inlineType,
        content: content.slice(nextToken.index + marker.length, closingIndex),
        href: ''
      })
      cursor = closingIndex + marker.length
    }
    if (inlines.length === 0) {
      inlines.push({ type: 'text', content: '', href: '' })
    }
    return inlines
  }

  private static findNextToken(content: string, from: number): MarkdownToken | null {
    let nextToken: MarkdownToken | null = null

    const updateCandidate = (type: 'bold' | 'italic' | 'strikethrough' | 'inline_code' | 'link' | 'image' | 'math_inline',
      index: number, marker: string): void => {
      if (index === -1) {
        return
      }
      if (!nextToken || index < nextToken.index || (index === nextToken.index && marker.length > nextToken.marker.length)) {
        nextToken = { type, index, marker }
      }
    }

    updateCandidate('inline_code', content.indexOf('```', from), '```')
    updateCandidate('inline_code', content.indexOf('`', from), '`')
    updateCandidate('math_inline', content.indexOf('\\(', from), '\\(')
    const dollarIndex = MarkdownUtils.findInlineDollarStart(content, from)
    if (dollarIndex !== -1) {
      updateCandidate('math_inline', dollarIndex, '$')
    }
    updateCandidate('image', content.indexOf('![', from), '![')
    updateCandidate('link', content.indexOf('[', from), '[')
    updateCandidate('bold', content.indexOf('**', from), '**')
    updateCandidate('bold', content.indexOf('__', from), '__')
    updateCandidate('strikethrough', content.indexOf('~~', from), '~~')

    const italicMarkers = ['*', '_']
    for (const marker of italicMarkers) {
      const markerIndex = content.indexOf(marker, from)
      if (markerIndex === -1) {
        continue
      }
      const previousChar = markerIndex > 0 ? content.charAt(markerIndex - 1) : ''
      const nextChar = markerIndex + 1 < content.length ? content.charAt(markerIndex + 1) : ''
      if (marker === '*' && (previousChar === '*' || nextChar === '*')) {
        continue
      }
      if (marker === '_' && (previousChar === '_' || nextChar === '_')) {
        continue
      }
      updateCandidate('italic', markerIndex, marker)
    }

    return nextToken
  }

  private static pushInline(inlines: MarkdownInline[], inline: MarkdownInline): void {
    if (inline.content.length === 0 && inline.type !== 'inline_code') {
      return
    }
    if (inline.type === 'text' && inlines.length > 0 && inlines[inlines.length - 1].type === 'text') {
      inlines[inlines.length - 1].content += inline.content
      return
    }
    inlines.push(inline)
  }

  private static placeholderBlock(): MarkdownBlock {
    const placeholder = '开始写作后，这里会实时显示预览。'
    return {
      type: 'paragraph',
      content: placeholder,
      inlines: MarkdownUtils.parseInlines(placeholder),
      items: [],
      language: ''
    }
  }

  private static findInlineDollarStart(content: string, from: number): number {
    for (let i = from; i < content.length; i++) {
      if (content.charAt(i) !== '$' || (i > 0 && content.charAt(i - 1) === '\\')) {
        continue
      }
      if (i + 1 < content.length && content.charAt(i + 1) === '$') {
        continue
      }
      return i
    }
    return -1
  }

  private static findClosingInlineDollar(content: string, from: number): number {
    for (let i = from; i < content.length; i++) {
      if (content.charAt(i) === '$' && (i === 0 || content.charAt(i - 1) !== '\\')) {
        return i
      }
      if (content.charAt(i) === '\n') {
        return -1
      }
    }
    return -1
  }

  /** 多行代码块开围栏：独立一行且仅为 ``` 或 ```语言标识。 */
  static isCodeFenceOpener(trimmed: string): boolean {
    return /^```\w*$/.test(trimmed)
  }

  /** 多行代码块闭围栏：独立一行且仅为 ```。 */
  static isCodeFenceCloser(trimmed: string): boolean {
    return trimmed === '```'
  }

  static codeFenceLanguage(trimmed: string): string {
    const match = trimmed.match(/^```(\w*)$/)
    return match?.[1] ?? ''
  }

  private static containsInlineMarkers(content: string): boolean {
    return content.includes('`') || content.includes('```') || content.includes('![') || content.includes('[') || content.includes('*') || content.includes('_')
      || content.includes('~') || content.includes('$') || content.includes('\\(')
  }

  private static containsMarkdownMarkers(content: string): boolean {
    return content.includes('`') || content.includes('#') || content.includes('>') || content.includes('[')
      || content.includes('*') || content.includes('_') || content.includes('~') || content.includes('-')
      || content.includes('!')
  }

  private static normalizeWhitespace(content: string): string {
    return content.replace(/\s+/g, ' ').trim()
  }
}

/** 待办笔记默认标题（与 NoteEdit.applyTodoListEntryDefaults 一致）。 */
export const DEFAULT_TODO_TITLE = '待办事项'

export function isDefaultTodoTitle(title: string): boolean {
  const trimmed = title.trim()
  return trimmed.length === 0 || trimmed === DEFAULT_TODO_TITLE
}

/** 仅有空勾选框（`[ ]` / `[-]` / `☐`，无正文）时视为占位内容。 */
export function isPlaceholderTodoContent(content: string): boolean {
  const normalized = content.replace(/\r/g, '')
  if (normalized.trim().length === 0) {
    return true
  }
  for (const line of normalized.split('\n')) {
    const trimmed = line.trim()
    if (trimmed.length === 0) {
      continue
    }
    if (!MarkdownUtils.isCheckboxLine(trimmed)) {
      return false
    }
    if (MarkdownUtils.checkboxLineText(trimmed).trim().length > 0) {
      return false
    }
  }
  return true
}

export function shouldPersistTodoNote(title: string, content: string): boolean {
  if (!isDefaultTodoTitle(title)) {
    return true
  }
  return !isPlaceholderTodoContent(content)
}

export function shouldShowTodoNoteInHomeList(title: string, content: string, tags: string[]): boolean {
  if (!tags.includes('Todo')) {
    return true
  }
  return shouldPersistTodoNote(title, content)
}
