export type MarkdownInlineType =
  'text' | 'bold' | 'italic' | 'strikethrough' | 'inline_code' | 'link' | 'math_inline'

export interface MarkdownInline {
  type: MarkdownInlineType
  content: string
  href: string
}

export type MarkdownBlockType =
  'heading1' | 'heading2' | 'heading3' | 'quote' | 'unordered_list' | 'ordered_list' | 'code' | 'divider' | 'image' | 'paragraph' | 'math_display'

type MarkdownListBlockType = 'unordered_list' | 'ordered_list'

export interface MarkdownBlock {
  type: MarkdownBlockType
  content: string
  inlines: MarkdownInline[]
  items: MarkdownInline[][]
  language: string
}

interface MarkdownToken {
  type: 'bold' | 'italic' | 'strikethrough' | 'inline_code' | 'link' | 'math_inline'
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

  static stripMarkdown(content: string): string {
    if (!MarkdownUtils.containsMarkdownMarkers(content)) {
      return content.replace(/\r/g, '').trim()
    }
    return content
      .replace(/\$\$[\s\S]*?\$\$/g, ' ')
      .replace(/\\\[[\s\S]*?\\\]/g, ' ')
      .replace(/\\\([\s\S]*?\\\)/g, ' ')
      .replace(/(?<!\\)\$[^$\n]+(?<!\\)\$/g, ' ')
      .replace(/```[\s\S]*?```/g, ' ')
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
      .replace(/\r/g, '')
      .trim()
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
    }

    for (const line of lines) {
      const trimmed = line.trim()
      if (trimmed.startsWith('```')) {
        if (inCodeBlock) {
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
          flushAll()
          inCodeBlock = true
          codeLanguage = trimmed.slice(3).trim()
        }
        continue
      }
      if (inCodeBlock) {
        codeLines.push(line)
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
        const closingIndex = content.indexOf('`', nextToken.index + 1)
        if (closingIndex === -1) {
          MarkdownUtils.pushInline(inlines, {
            type: 'text',
            content: content.slice(nextToken.index),
            href: ''
          })
          break
        }
        MarkdownUtils.pushInline(inlines, {
          type: 'inline_code',
          content: content.slice(nextToken.index + 1, closingIndex),
          href: ''
        })
        cursor = closingIndex + 1
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

    const updateCandidate = (type: 'bold' | 'italic' | 'strikethrough' | 'inline_code' | 'link' | 'math_inline',
      index: number, marker: string): void => {
      if (index === -1) {
        return
      }
      if (!nextToken || index < nextToken.index || (index === nextToken.index && marker.length > nextToken.marker.length)) {
        nextToken = { type, index, marker }
      }
    }

    updateCandidate('inline_code', content.indexOf('`', from), '`')
    updateCandidate('math_inline', content.indexOf('\\(', from), '\\(')
    const dollarIndex = MarkdownUtils.findInlineDollarStart(content, from)
    if (dollarIndex !== -1) {
      updateCandidate('math_inline', dollarIndex, '$')
    }
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

  private static containsInlineMarkers(content: string): boolean {
    return content.includes('`') || content.includes('[') || content.includes('*') || content.includes('_')
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
