import pako from 'pako'
import { util } from '@kit.ArkTS'
import { HtmlToMarkdown } from './HtmlToMarkdown'

function escapeYoudaoTableCell(text: string): string {
  return text.replace(/\|/g, '\\|').replace(/\n/g, ' ').trim()
}

interface YoudaoTableCellSpan {
  text: string
  rs: number
  cs: number
}

/** 将有道云笔记原始内容（JSON / XML / HTML）转为 Markdown。 */
export class YoudaoNoteContentConverter {
  /** 尝试转换；无法识别时返回 null。 */
  static tryConvert(raw: string): string | null {
    const trimmed = YoudaoNoteContentConverter.preprocessRaw(YoudaoNoteContentConverter.unwrapContent(raw))
    if (trimmed.length === 0) {
      return null
    }
    const jsonMd = YoudaoNoteContentConverter.tryConvertJson(trimmed)
    if (jsonMd !== null) {
      return jsonMd
    }
    return YoudaoNoteContentConverter.tryConvertMarkup(trimmed)
  }

  /** 结构化转换失败时的兜底（HTML / TSV 表格等）。 */
  static convertWithFallback(raw: string, rawFormat: string): string {
    const trimmed = YoudaoNoteContentConverter.preprocessRaw(raw.trim())
    if (trimmed.length === 0) {
      return ''
    }
    const structured = YoudaoNoteContentConverter.tryConvert(trimmed)
    if (structured !== null && structured.length > 0) {
      return structured
    }
    if (rawFormat === 'md') {
      return trimmed
    }
    const htmlMd = YoudaoNoteContentConverter.tryConvertHtmlFragment(trimmed)
    if (htmlMd !== null && htmlMd.length > 0) {
      return htmlMd
    }
    const tabMd = YoudaoNoteContentConverter.tryConvertTabSeparatedTable(trimmed)
    if (tabMd !== null && tabMd.length > 0) {
      return tabMd
    }
    const spaceMd = YoudaoNoteContentConverter.tryConvertSpaceSeparatedTable(trimmed)
    if (spaceMd !== null && spaceMd.length > 0) {
      return spaceMd
    }
    const imgMd = YoudaoNoteContentConverter.tryConvertHtmlImages(trimmed)
    if (imgMd !== null && imgMd.length > 0) {
      return imgMd
    }
    return trimmed
  }

  static preprocessRaw(raw: string): string {
    let text = YoudaoNoteContentConverter.decodeCommonHtmlEntities(raw)
    const gzipText = YoudaoNoteContentConverter.tryDecompressGzipText(text)
    if (gzipText !== null && gzipText.length > 0) {
      text = gzipText
    }
    return text
  }

  private static decodeCommonHtmlEntities(text: string): string {
    return text
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&amp;/g, '&')
      .replace(/&quot;/g, '"')
      .replace(/&nbsp;/g, ' ')
  }

  private static tryDecompressGzipText(raw: string): string | null {
    const trimmed = raw.trim()
    if (trimmed.startsWith('{') || trimmed.startsWith('<')) {
      return null
    }
    try {
      if (trimmed.startsWith('H4sI')) {
        const helper = new util.Base64Helper()
        const decoded = helper.decodeSync(trimmed.replace(/\s+/g, ''), util.Type.BASIC)
        const inflated = pako.ungzip(decoded) as Uint8Array
        return YoudaoNoteContentConverter.uint8ToString(inflated)
      }
      const bytes = new Uint8Array(trimmed.length)
      for (let i = 0; i < trimmed.length; i++) {
        bytes[i] = trimmed.charCodeAt(i) & 0xff
      }
      if (bytes.length >= 2 && bytes[0] === 0x1f && bytes[1] === 0x8b) {
        const inflated = pako.ungzip(bytes) as Uint8Array
        return YoudaoNoteContentConverter.uint8ToString(inflated)
      }
    } catch (_) {
    }
    return null
  }

  private static uint8ToString(bytes: Uint8Array): string {
    let out = ''
    for (let i = 0; i < bytes.length; i++) {
      out += String.fromCharCode(bytes[i])
    }
    return out
  }

  private static tryConvertHtmlImages(text: string): string | null {
    if (!text.includes('<img')) {
      return null
    }
    const imgRegex = /<img\b[^>]*\bsrc\s*=\s*["']([^"']+)["'][^>]*>/gi
    if (!imgRegex.test(text)) {
      return null
    }
    return text.replace(imgRegex, (_all: string, src: string) => {
      const url = `${src ?? ''}`.trim()
      return url.length > 0 ? `![](${url})` : ''
    })
  }

  /** MCP 返回内容是否像有道原始 JSON / HTML。 */
  static looksStructured(content: string): boolean {
    const trimmed = YoudaoNoteContentConverter.preprocessRaw(YoudaoNoteContentConverter.unwrapContent(content))
    if (trimmed.startsWith('{') && trimmed.includes('"5"')) {
      return true
    }
    if (trimmed.startsWith('H4sI')) {
      return true
    }
    return YoudaoNoteContentConverter.looksLikeHtml(trimmed)
  }

  private static unwrapContent(raw: string): string {
    let trimmed = raw.trim()
    if (trimmed.startsWith('"') && trimmed.endsWith('"')) {
      try {
        const decoded = JSON.parse(trimmed) as Object
        if (typeof decoded === 'string') {
          trimmed = decoded.trim()
        }
      } catch (_) {
      }
    }
    return trimmed
  }

  private static tryConvertJson(trimmed: string): string | null {
    if (!trimmed.startsWith('{')) {
      return null
    }
    try {
      const decoded = JSON.parse(trimmed) as Object
      if (typeof decoded === 'object' && decoded !== null) {
        const map = decoded as Record<string, Object>
        if (map['5'] !== undefined) {
          const md = YoudaoJsonNoteConverter.convertDocument(map)
          if (md.trim().length > 0) {
            return md.trim()
          }
        }
      }
    } catch (_) {
    }
    return null
  }

  private static tryConvertMarkup(trimmed: string): string | null {
    if (!trimmed.startsWith('<')) {
      return null
    }
    if (trimmed.includes('<note') || trimmed.includes('note.youdao.com')) {
      const xmlMd = YoudaoXmlNoteConverter.convert(trimmed)
      if (xmlMd.trim().length > 0) {
        return xmlMd.trim()
      }
    }
    try {
      return HtmlToMarkdown.convert(trimmed).trim()
    } catch (_) {
      return null
    }
  }

  private static tryConvertHtmlFragment(trimmed: string): string | null {
    if (!YoudaoNoteContentConverter.looksLikeHtml(trimmed)) {
      return null
    }
    const wrapped = trimmed.startsWith('<') ? trimmed : `<div>${trimmed}</div>`
    if (wrapped.includes('<note') || wrapped.includes('note.youdao.com')) {
      const xmlMd = YoudaoXmlNoteConverter.convert(wrapped)
      if (xmlMd.trim().length > 0) {
        return xmlMd.trim()
      }
    }
    try {
      return HtmlToMarkdown.convert(wrapped).trim()
    } catch (_) {
      return null
    }
  }

  private static looksLikeHtml(text: string): boolean {
    return /<\s*(table|tr|td|th|p|div|img|ul|ol|li|h[1-6]|br|span)\b/i.test(text)
  }

  private static tryConvertSpaceSeparatedTable(trimmed: string): string | null {
    const lines = trimmed.split('\n').filter((line) => line.trim().length > 0)
    if (lines.length < 2) {
      return null
    }
    const rows: string[][] = []
    for (const line of lines) {
      const cells = line.trim().split(/ {2,}/).map((cell) => cell.trim()).filter((cell) => cell.length > 0)
      if (cells.length < 2) {
        return null
      }
      rows.push(cells.map((cell) => escapeYoudaoTableCell(cell)))
    }
    const colCount = rows[0].length
    for (const row of rows) {
      if (row.length !== colCount) {
        return null
      }
    }
    return YoudaoNoteContentConverter.formatMarkdownTable(rows)
  }

  static formatMarkdownTable(rows: string[][]): string {
    if (rows.length === 0) {
      return ''
    }
    const colCount = rows[0].length
    const mdLines: string[] = [
      `| ${rows[0].join(' | ')} |`,
      `| ${Array(colCount).fill('---').join(' | ')} |`
    ]
    for (let i = 1; i < rows.length; i++) {
      mdLines.push(`| ${rows[i].join(' | ')} |`)
    }
    return mdLines.join('\n')
  }

  private static tryConvertTabSeparatedTable(trimmed: string): string | null {
    const lines = trimmed.split('\n').filter((line) => line.includes('\t'))
    if (lines.length < 2) {
      return null
    }
    const columnCounts = new Set<number>()
    for (const line of lines) {
      columnCounts.add(line.split('\t').length)
    }
    if (columnCounts.size !== 1) {
      return null
    }
    const colCount = columnCounts.values().next().value as number
    if (colCount < 2) {
      return null
    }
    const rows: string[][] = []
    for (const line of lines) {
      rows.push(line.split('\t').map((cell) => escapeYoudaoTableCell(cell)))
    }
    return YoudaoNoteContentConverter.formatMarkdownTable(rows)
  }

  /** 与 youdaonote CLI 一致：从标题扩展名推断格式。 */
  static inferRawFormatFromTitle(title: string | undefined): string {
    const t = `${title ?? ''}`.trim()
    if (t.length === 0) {
      return 'note'
    }
    const dot = t.lastIndexOf('.')
    if (dot < 0 || dot >= t.length - 1) {
      return 'note'
    }
    const ext = t.substring(dot + 1).toLowerCase()
    if (ext === 'md') {
      return 'md'
    }
    if (ext === 'txt') {
      return 'txt'
    }
    return 'note'
  }
}

class YoudaoJsonNoteConverter {
  static convertDocument(root: Record<string, Object>): string {
    const blocksRaw = root['5']
    if (!Array.isArray(blocksRaw)) {
      return ''
    }
    const parts: string[] = []
    for (const block of blocksRaw as Object[]) {
      if (typeof block !== 'object' || block === null) {
        continue
      }
      const line = YoudaoJsonNoteConverter.convertBlock(block as Record<string, Object>)
      if (line.length > 0) {
        parts.push(line)
      }
    }
    return parts.join('\n\n')
  }

  private static convertBlock(content: Record<string, Object>): string {
    const attrs = content['4']
    if (typeof attrs === 'object' && attrs !== null) {
      const cw = (attrs as Record<string, Object>)['cw']
      if (Array.isArray(cw) && (cw as Object[]).length > 0) {
        return YoudaoJsonNoteConverter.convertTable(content)
      }
    }
    const type = `${content['6'] ?? ''}`
    if (type.length === 0) {
      return YoudaoJsonNoteConverter.convertText(content, true)
    }
    switch (type) {
      case 'h':
        return YoudaoJsonNoteConverter.convertHeading(content)
      case 'im':
      case 'drawio-ynote':
      case 'excalidraw':
      case 'mindmap':
        return YoudaoJsonNoteConverter.convertImage(content)
      case 'a':
        return YoudaoJsonNoteConverter.convertAttachment(content)
      case 'cd':
        return YoudaoJsonNoteConverter.convertCode(content)
      case 'q':
        return YoudaoJsonNoteConverter.convertQuote(content)
      case 'l':
        return YoudaoJsonNoteConverter.convertList(content)
      case 't':
        return YoudaoJsonNoteConverter.convertTable(content)
      case 'tc':
        return escapeYoudaoTableCell(YoudaoJsonNoteConverter.convertTableCell(content))
      case 'cl':
        return YoudaoJsonNoteConverter.convertText(content, true)
      case 'hr':
        return '---'
      case 'li':
        return YoudaoJsonNoteConverter.convertLink(content)
      case 'la':
        return YoudaoJsonNoteConverter.convertHighlight(content)
      case 'media':
        return YoudaoJsonNoteConverter.convertMedia(content)
      default:
        return YoudaoJsonNoteConverter.convertText(content, true)
    }
  }

  private static convertText(content: Record<string, Object>, addAttr: boolean): string {
    const fiveRaw = content['5']
    if (!Array.isArray(fiveRaw) || (fiveRaw as Object[]).length === 0) {
      return ''
    }
    let out = ''
    for (const item of fiveRaw as Object[]) {
      if (typeof item !== 'object' || item === null) {
        continue
      }
      const map = item as Record<string, Object>
      const type = `${map['6'] ?? ''}`
      if (type.length > 0) {
        out += YoudaoJsonNoteConverter.convertBlock(map)
        continue
      }
      const seven = map['7']
      if (Array.isArray(seven)) {
        out += YoudaoJsonNoteConverter.joinSeven(seven as Object[], addAttr)
        continue
      }
      if (Array.isArray(map['5'])) {
        out += YoudaoJsonNoteConverter.convertText(map, addAttr)
      }
    }
    return YoudaoJsonNoteConverter.optimizeText(out)
  }

  private static joinSeven(seven: Object[], addAttr: boolean): string {
    let out = ''
    for (const item of seven) {
      if (typeof item !== 'object' || item === null) {
        continue
      }
      const map = item as Record<string, Object>
      let text = `${map['8'] ?? ''}`
      if (text.length === 0) {
        continue
      }
      if (addAttr) {
        text = YoudaoJsonNoteConverter.applyTextAttrs(text, map['9'])
      }
      out += text
    }
    return out
  }

  private static applyTextAttrs(text: string, attrsRaw: Object | undefined): string {
    if (!Array.isArray(attrsRaw) || (attrsRaw as Object[]).length === 0) {
      return text
    }
    let out = text
    for (const attr of attrsRaw as Object[]) {
      if (typeof attr !== 'object' || attr === null) {
        continue
      }
      const flag = `${(attr as Record<string, Object>)['2'] ?? ''}`
      switch (flag) {
        case 'b':
          out = `**${out}**`
          break
        case 'i':
          out = `*${out}*`
          break
        case 'u':
          out = ` ${out} `
          break
        case 'd':
          out = `~~${out}~~`
          break
        case 'c':
          out = ` ${out} `
          break
        default:
          break
      }
    }
    return out
  }

  private static convertHeading(content: Record<string, Object>): string {
    const attrs = content['4']
    const levelRaw = typeof attrs === 'object' && attrs !== null
      ? `${(attrs as Record<string, Object>)['l'] ?? 'h1'}`
      : 'h1'
    const level = parseInt(levelRaw.replace('h', ''), 10)
    const safeLevel = Number.isNaN(level) ? 1 : Math.min(Math.max(level, 1), 6)
    const text = YoudaoJsonNoteConverter.convertText(content, true)
    if (text.length === 0) {
      return ''
    }
    return `${'#'.repeat(safeLevel)} ${text}`
  }

  private static convertImage(content: Record<string, Object>): string {
    const attrs = content['4']
    const url = typeof attrs === 'object' && attrs !== null
      ? `${(attrs as Record<string, Object>)['u'] ?? ''}`.trim()
      : ''
    if (url.length === 0) {
      return ''
    }
    return `![](${url})`
  }

  private static convertAttachment(content: Record<string, Object>): string {
    const attrs = content['4'] as Record<string, Object> | undefined
    const name = `${attrs?.['fn'] ?? '附件'}`
    const url = `${attrs?.['re'] ?? ''}`.trim()
    if (url.length === 0) {
      return name
    }
    return `[${name}](${url})`
  }

  private static convertCode(content: Record<string, Object>): string {
    const attrs = content['4'] as Record<string, Object> | undefined
    const lang = `${attrs?.['la'] ?? ''}`
    const codes = content['5']
    if (!Array.isArray(codes)) {
      return ''
    }
    let body = ''
    for (const code of codes as Object[]) {
      if (typeof code === 'object' && code !== null) {
        body += `${YoudaoJsonNoteConverter.convertText(code as Record<string, Object>, true)}\n`
      }
    }
    return '```' + lang + '\n' + body.trim() + '\n```'
  }

  private static convertQuote(content: Record<string, Object>): string {
    const items = content['5']
    if (!Array.isArray(items)) {
      return ''
    }
    const lines: string[] = []
    for (const item of items as Object[]) {
      if (typeof item === 'object' && item !== null) {
        const text = YoudaoJsonNoteConverter.convertText(item as Record<string, Object>, true)
          .replace(/\n/g, ' ')
          .trim()
        if (text.length > 0) {
          lines.push(`> ${text}`)
        }
      }
    }
    return lines.join('\n')
  }

  private static convertList(content: Record<string, Object>): string {
    const text = YoudaoJsonNoteConverter.convertText(content, true)
    if (text.length === 0) {
      return ''
    }
    const attrs = content['4'] as Record<string, Object> | undefined
    const ordered = `${attrs?.['lt'] ?? ''}` === 'ordered'
    return ordered ? `1. ${text}` : `- ${text}`
  }

  private static convertLink(content: Record<string, Object>): string {
    const label = YoudaoJsonNoteConverter.convertText(content, false)
    const attrs = content['4'] as Record<string, Object> | undefined
    const url = `${attrs?.['hf'] ?? ''}`.trim()
    if (url.length === 0) {
      return label
    }
    return `[${label}](${url})`
  }

  private static convertHighlight(content: Record<string, Object>): string {
    const text = YoudaoJsonNoteConverter.convertText(content, true).replace(/\n/g, ' ').trim()
    return text.length === 0 ? '' : ` ${text} `
  }

  private static convertMedia(content: Record<string, Object>): string {
    const attrs = content['4'] as Record<string, Object> | undefined
    const label = `${attrs?.['sr'] ?? 'link'}`
    const url = `${attrs?.['hf'] ?? ''}`.trim()
    if (url.length === 0) {
      return label
    }
    return `[${label}](${url})`
  }

  private static convertTable(content: Record<string, Object>): string {
    const rows = content['5']
    if (!Array.isArray(rows) || (rows as Object[]).length === 0) {
      return ''
    }
    const tableAttrs = content['4'] as Record<string, Object> | undefined
    const cw = tableAttrs?.['cw']
    let colCount = Array.isArray(cw) && (cw as Object[]).length > 0 ? (cw as Object[]).length : 0

    const parsedRows: YoudaoTableCellSpan[][] = []
    for (const row of rows as Object[]) {
      if (typeof row !== 'object' || row === null) {
        continue
      }
      const cells = (row as Record<string, Object>)['5']
      if (!Array.isArray(cells)) {
        continue
      }
      const parsedCells: YoudaoTableCellSpan[] = []
      for (const cell of cells as Object[]) {
        if (typeof cell !== 'object' || cell === null) {
          continue
        }
        const cellRecord = cell as Record<string, Object>
        const cellAttrs = cellRecord['4'] as Record<string, Object> | undefined
        parsedCells.push({
          text: escapeYoudaoTableCell(
            YoudaoJsonNoteConverter.convertTableCell(cellRecord)
          ),
          rs: YoudaoJsonNoteConverter.tableSpanValue(cellAttrs?.['rs']),
          cs: YoudaoJsonNoteConverter.tableSpanValue(cellAttrs?.['cs'])
        })
      }
      if (parsedCells.length > 0) {
        parsedRows.push(parsedCells)
      }
    }
    if (parsedRows.length === 0) {
      return ''
    }
    if (colCount <= 0) {
      colCount = YoudaoJsonNoteConverter.estimateTableColumnCount(parsedRows)
    }

    const rowCount = parsedRows.length
    const grid: string[][] = []
    const skip: boolean[][] = []
    for (let r = 0; r < rowCount; r++) {
      grid.push(Array(colCount).fill(''))
      skip.push(Array(colCount).fill(false))
    }

    for (let r = 0; r < rowCount; r++) {
      let c = 0
      for (const cell of parsedRows[r]) {
        while (c < colCount && skip[r][c]) {
          c++
        }
        if (c >= colCount) {
          break
        }
        grid[r][c] = cell.text
        for (let dr = 0; dr < cell.rs; dr++) {
          for (let dc = 0; dc < cell.cs; dc++) {
            if (dr === 0 && dc === 0) {
              continue
            }
            const rr = r + dr
            const cc = c + dc
            if (rr < rowCount && cc < colCount) {
              skip[rr][cc] = true
            }
          }
        }
        c += cell.cs
      }
    }

    if (grid.length === 1) {
      return YoudaoNoteContentConverter.formatMarkdownTable([
        Array(colCount).fill(' '),
        grid[0]
      ])
    }
    return YoudaoNoteContentConverter.formatMarkdownTable(grid)
  }

  private static tableSpanValue(raw: Object | undefined): number {
    if (raw === undefined || raw === null) {
      return 1
    }
    if (typeof raw === 'number') {
      return Math.min(Math.max(Math.trunc(raw), 1), 99)
    }
    const parsed = parseInt(`${raw}`, 10)
    if (Number.isNaN(parsed)) {
      return 1
    }
    return Math.min(Math.max(parsed, 1), 99)
  }

  private static estimateTableColumnCount(parsedRows: YoudaoTableCellSpan[][]): number {
    let max = 0
    for (const row of parsedRows) {
      let count = 0
      for (const cell of row) {
        count += cell.cs
      }
      if (count > max) {
        max = count
      }
    }
    return Math.min(Math.max(max, 1), 99)
  }

  private static convertTableCell(cell: Record<string, Object>): string {
    const items = cell['5']
    if (!Array.isArray(items)) {
      return ''
    }
    const parts: string[] = []
    for (const item of items as Object[]) {
      if (typeof item !== 'object' || item === null) {
        continue
      }
      const record = item as Record<string, Object>
      const type = `${record['6'] ?? ''}`.trim()
      if (type.length > 0) {
        parts.push(YoudaoJsonNoteConverter.convertBlock(record))
      } else {
        parts.push(YoudaoJsonNoteConverter.convertText(record, true))
      }
    }
    return parts.join(' ').trim()
  }

  private static optimizeText(text: string): string {
    return text.replace(/\r/g, '').trim()
  }
}

class YoudaoXmlNoteConverter {
  static convert(xml: string): string {
    const parts: string[] = []
    const blockRegex = /<(?:note-)?([\w-]+)[^>]*>([\s\S]*?)<\/(?:note-)?\1>/g
    let match: RegExpExecArray | null = blockRegex.exec(xml)
    while (match !== null) {
      const tag = match[1] ?? ''
      const inner = match[2] ?? ''
      YoudaoXmlNoteConverter.appendBlock(tag, match[0], inner, parts)
      match = blockRegex.exec(xml)
    }
    if (parts.length === 0) {
      return YoudaoXmlNoteConverter.plainText(xml)
    }
    return parts.join('\n\n')
  }

  private static appendBlock(tag: string, rawTag: string, inner: string, parts: string[]): void {
    switch (tag) {
      case 'heading': {
        const levelMatch = /level="(\d+)"/.exec(rawTag)
        const level = parseInt(levelMatch?.[1] ?? '1', 10)
        const safeLevel = Number.isNaN(level) ? 1 : Math.min(Math.max(level, 1), 6)
        const text = YoudaoXmlNoteConverter.plainText(inner)
        if (text.length > 0) {
          parts.push(`${'#'.repeat(safeLevel)} ${text}`)
        }
        break
      }
      case 'image': {
        const urlMatch = /<source>([\s\S]*?)<\/source>/.exec(inner)
        const url = `${urlMatch?.[1] ?? ''}`.trim()
        if (url.length > 0) {
          parts.push(`![](${url})`)
        }
        break
      }
      case 'table':
        parts.push(YoudaoXmlNoteConverter.convertTable(inner))
        break
      case 'code': {
        const langMatch = /<language>([\s\S]*?)<\/language>/.exec(inner)
        const lang = `${langMatch?.[1] ?? ''}`.trim()
        parts.push('```' + lang + '\n' + YoudaoXmlNoteConverter.plainText(inner) + '\n```')
        break
      }
      case 'todo':
        parts.push(`- [ ] ${YoudaoXmlNoteConverter.plainText(inner)}`)
        break
      case 'quote':
        parts.push(`> ${YoudaoXmlNoteConverter.plainText(inner)}`)
        break
      case 'horizontal-line':
        parts.push('---')
        break
      default: {
        const text = YoudaoXmlNoteConverter.plainText(inner)
        if (text.length > 0) {
          parts.push(text)
        }
        break
      }
    }
  }

  private static convertTable(inner: string): string {
    const contentMatch = /<content>([\s\S]*?)<\/content>/.exec(inner)
    if (contentMatch === null) {
      return ''
    }
    try {
      const data = JSON.parse(contentMatch[1] ?? '') as Record<string, Object>
      const widthsRaw = data['widths']
      const colCount = Array.isArray(widthsRaw) ? (widthsRaw as Object[]).length : 0
      if (colCount === 0) {
        return ''
      }
      const cells = Array.isArray(data['cells']) ? (data['cells'] as Object[]) : []
      const rows: string[][] = []
      let current: string[] = []
      for (const cell of cells) {
        if (typeof cell !== 'object' || cell === null) {
          continue
        }
        const value = escapeYoudaoTableCell(`${(cell as Record<string, Object>)['value'] ?? ''}`)
        current.push(value)
        if (current.length === colCount) {
          rows.push(current)
          current = []
        }
      }
      if (rows.length === 0) {
        return ''
      }
      if (rows.length === 1) {
        rows.unshift(Array(colCount).fill(' '))
      }
      const lines: string[] = []
      for (let i = 0; i < rows.length; i++) {
        if (i === 1) {
          lines.push(`| ${Array(colCount).fill('---').join(' | ')} |`)
        }
        lines.push(`| ${rows[i].join(' | ')} |`)
      }
      return lines.join('\n')
    } catch (_) {
      return ''
    }
  }

  private static plainText(xml: string): string {
    return xml
      .replace(/<[^>]+>/g, '')
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&nbsp;/g, ' ')
      .trim()
  }
}
