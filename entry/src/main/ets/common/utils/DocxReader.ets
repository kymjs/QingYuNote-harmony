import { Logger } from './Logger'
import { ZipEntry, ZipReader } from './ZipReader'

/** docx 解析结果：HTML 正文 + RID→媒体文件名映射。 */
export class DocxExtractResult {
  html: string = ''
  mediaByRid: Map<string, string> = new Map()
}

/** `DocxBuilder.finish` 的可选参数。 */
interface DocxFinishOptions {
  trim?: boolean
  collapseBlank?: boolean
}

/** `parseOpenTag` 的返回结构。 */
interface ParsedOpenTag {
  tag: string
  attrs: Record<string, string>
}

/**
 * 极简 docx → HTML 解析器。流程：ZipReader 拿到所有条目，
 * 解析 `word/document.xml` 与 `word/_rels/document.xml.rels`，
 * 把段落 / 表格 / 图片 / 换行转成 HTML 字符串。
 *
 * 设计取舍：
 * - 不实现 OOXML 全部样式（粗体/斜体/字号等），优先保证结构、文本、图片、超链接可用。
 * - XML 解析使用自写的极简 token 解析器，docx 内部不会出现外部 DTD、命名空间前缀以外的怪语法。
 */
export class DocxReader {
  static extract(buffer: Uint8Array): DocxExtractResult {
    const entries = ZipReader.readEntries(buffer)
    const documentEntry = ZipReader.findEntry(entries, 'word/document.xml')
    if (!documentEntry) {
      throw new Error('docx missing word/document.xml')
    }
    const relsEntry = ZipReader.findEntry(entries, 'word/_rels/document.xml.rels')
    const result = new DocxExtractResult()
    if (relsEntry) {
      result.mediaByRid = DocxReader.parseRels(relsEntry)
    }
    const documentXml = DocxReader.decodeUtf8(documentEntry.data)
    result.html = DocxReader.convertBody(documentXml)
    return result
  }

  private static parseRels(relsEntry: ZipEntry): Map<string, string> {
    const map = new Map<string, string>()
    const xml = DocxReader.decodeUtf8(relsEntry.data)
    const rels = DocxReader.parseSimpleXml(xml)
    for (const node of rels) {
      if (node.tag !== 'Relationship') {
        continue
      }
      const id = node.attrs['Id'] ?? ''
      const target = node.attrs['Target'] ?? ''
      if (id.length === 0 || target.length === 0) {
        continue
      }
      if (target.toLowerCase().startsWith('http://') || target.toLowerCase().startsWith('https://')) {
        continue
      }
      const normalized = DocxReader.normalizeMediaTarget(target)
      if (normalized.length > 0) {
        map.set(id, normalized)
      }
    }
    return map
  }

  private static normalizeMediaTarget(target: string): string {
    // rels Target 形如 "media/image1.png" 或 "../media/image1.png"
    const parts = target.split('/')
    const last = parts[parts.length - 1] ?? ''
    if (last.length === 0) {
      return ''
    }
    const slash = last.lastIndexOf('\\')
    return slash >= 0 ? last.substring(slash + 1) : last
  }

  private static convertBody(documentXml: string): string {
    const bodyStart = documentXml.indexOf('<w:body>')
    const bodyEnd = documentXml.lastIndexOf('</w:body>')
    if (bodyStart < 0 || bodyEnd < 0 || bodyEnd <= bodyStart) {
      throw new Error('docx missing w:body')
    }
    const bodyXml = documentXml.substring(bodyStart, bodyEnd + '</w:body>'.length)
    const nodes = DocxReader.parseSimpleXml(bodyXml)
    const sb = new DocxBuilder()
    for (const node of nodes) {
      if (node.tag !== 'body' && node.tag !== 'w:body') {
        continue
      }
      for (const child of node.children) {
        DocxReader.emitNode(child, sb)
      }
    }
    return sb.finish()
  }

  private static emitNode(node: XmlNode, sb: DocxBuilder): void {
    const local = DocxReader.localName(node.tag)
    if (local === 'p') {
      DocxReader.emitParagraph(node, sb)
      return
    }
    if (local === 'tbl') {
      DocxReader.emitTable(node, sb)
      return
    }
    if (local === 'sectPr') {
      return
    }
    // 容器类元素：递归子节点
    for (const child of node.children) {
      DocxReader.emitNode(child, sb)
    }
  }

  private static emitParagraph(node: XmlNode, sb: DocxBuilder): void {
    const text = new DocxBuilder()
    DocxReader.collectInline(node, text)
    const opts: DocxFinishOptions = { trim: true, collapseBlank: true }
    const content = text.finish(opts)
    sb.appendParagraph(content)
  }

  private static emitTable(node: XmlNode, sb: DocxBuilder): void {
    sb.appendTableOpen()
    for (const child of node.children) {
      if (DocxReader.localName(child.tag) !== 'tr') {
        continue
      }
      sb.appendTableRowOpen()
      for (const cell of child.children) {
        if (DocxReader.localName(cell.tag) !== 'tc') {
          continue
        }
        const cellText = new DocxBuilder()
        for (const cellChild of cell.children) {
          if (DocxReader.localName(cellChild.tag) === 'p') {
            DocxReader.collectInline(cellChild, cellText)
          }
        }
        const cellOpts: DocxFinishOptions = { trim: true, collapseBlank: true }
        sb.appendTableCell(cellText.finish(cellOpts))
      }
      sb.appendTableRowClose()
    }
    sb.appendTableClose()
  }

  /** 收集一个段落里的所有 inline（文本 / br / tab / drawing）。 */
  private static collectInline(node: XmlNode, sb: DocxBuilder): void {
    for (const child of node.children) {
      const local = DocxReader.localName(child.tag)
      if (local === 'r') {
        DocxReader.emitRun(child, sb)
      } else if (local === 'hyperlink') {
        for (const inner of child.children) {
          if (DocxReader.localName(inner.tag) === 'r') {
            DocxReader.emitRun(inner, sb)
          }
        }
      } else if (local === 'drawing' || local === 'pict' || local === 'object') {
        DocxReader.emitImage(child, sb)
      } else if (local === 'br' || local === 'w:br' || local === 'tab' || local === 'w:tab') {
        sb.appendInline(' ')
      }
    }
  }

  private static emitRun(node: XmlNode, sb: DocxBuilder): void {
    for (const child of node.children) {
      const local = DocxReader.localName(child.tag)
      if (local === 't') {
        const preserve = (child.attrs['xml:space'] ?? '').toLowerCase() === 'preserve'
        const value = DocxReader.combineText(child)
        sb.appendInline(preserve ? value : value)
      } else if (local === 'tab') {
        sb.appendInline('\t')
      } else if (local === 'br') {
        sb.appendInline('\n')
      } else if (local === 'drawing' || local === 'pict' || local === 'object') {
        DocxReader.emitImage(child, sb)
      } else if (local === 'noBreakHyphen') {
        sb.appendInline('-')
      } else if (local === 'softHyphen') {
        // 跳过软连字符
      }
    }
  }

  private static combineText(node: XmlNode): string {
    let result = ''
    for (const child of node.children) {
      if (child.kind === 'text') {
        result += child.text
      }
    }
    return result
  }

  private static emitImage(node: XmlNode, sb: DocxBuilder): void {
    const rid = DocxReader.findImageRid(node)
    if (rid === null) {
      return
    }
    // 占位符在后续 NoteImportService 阶段会被替换成实际媒体名。
    sb.appendInline('[[docx-img:' + rid + ']]')
  }

  private static findImageRid(node: XmlNode): string | null {
    for (const child of node.children) {
      const childLocal = DocxReader.localName(child.tag)
      if (childLocal === 'drawing') {
        for (const drawingChild of child.children) {
          if (DocxReader.localName(drawingChild.tag) === 'inline' ||
            DocxReader.localName(drawingChild.tag) === 'anchor') {
            for (const anchorChild of drawingChild.children) {
              if (DocxReader.localName(anchorChild.tag) === 'graphic') {
                const found = DocxReader.findAttributeDeep(anchorChild, 'embed')
                if (found !== null) {
                  return found
                }
                const link = DocxReader.findAttributeDeep(anchorChild, 'link')
                if (link !== null) {
                  return link
                }
              }
            }
          }
        }
      } else if (childLocal === 'pict' || childLocal === 'object') {
        for (const grand of child.children) {
          if (DocxReader.localName(grand.tag) === 'r') {
            for (const gg of grand.children) {
              if (DocxReader.localName(gg.tag) === 'rPr') {
                continue
              }
              const found = DocxReader.findAttributeDeep(gg, 'embed')
              if (found !== null) {
                return found
              }
            }
          }
        }
      }
    }
    return null
  }

  private static findAttributeDeep(node: XmlNode, attrName: string): string | null {
    if (node.attrs[attrName] !== undefined) {
      return node.attrs[attrName]
    }
    if (node.attrs['r:' + attrName] !== undefined) {
      return node.attrs['r:' + attrName]
    }
    for (const child of node.children) {
      const found = DocxReader.findAttributeDeep(child, attrName)
      if (found !== null) {
        return found
      }
    }
    return null
  }

  private static localName(tag: string): string {
    const colon = tag.indexOf(':')
    return colon >= 0 ? tag.substring(colon + 1) : tag
  }

  private static decodeUtf8(bytes: Uint8Array): string {
    let result = ''
    let i = 0
    while (i < bytes.length) {
      const b1 = bytes[i]
      if (b1 < 0x80) {
        result += String.fromCharCode(b1)
        i += 1
      } else if (b1 >= 0xc0 && b1 < 0xe0) {
        result += String.fromCharCode(((b1 & 0x1f) << 6) | (bytes[i + 1] & 0x3f))
        i += 2
      } else if (b1 >= 0xe0 && b1 < 0xf0) {
        result += String.fromCharCode(((b1 & 0x0f) << 12) | ((bytes[i + 1] & 0x3f) << 6) | (bytes[i + 2] & 0x3f))
        i += 3
      } else {
        result += '?'
        i += 1
      }
    }
    return result
  }

  // ---------- 极简 XML 解析 ----------

  private static parseSimpleXml(xml: string): XmlNode[] {
    const root: XmlNode = { kind: 'element', tag: '#root', attrs: {}, children: [] }
    const stack: XmlNode[] = [root]
    let pos = 0
    const len = xml.length
    while (pos < len) {
      const ch = xml.charAt(pos)
      if (ch === '<') {
        if (pos + 4 < len && xml.substring(pos, pos + 4) === '<!--') {
          const end = xml.indexOf('-->', pos + 4)
          if (end < 0) {
            break
          }
          pos = end + 3
          continue
        }
        if (pos + 9 < len && xml.substring(pos, pos + 9) === '<![CDATA[') {
          const end = xml.indexOf(']]>', pos + 9)
          if (end < 0) {
            break
          }
          const text = xml.substring(pos + 9, end)
          stack[stack.length - 1].children.push({ kind: 'text', tag: '', attrs: {}, children: [], text })
          pos = end + 3
          continue
        }
        if (pos + 2 < len && xml.charAt(pos + 1) === '?') {
          const end = xml.indexOf('?>', pos + 2)
          if (end < 0) {
            break
          }
          pos = end + 2
          continue
        }
        if (pos + 9 < len && xml.substring(pos, pos + 9) === '<!DOCTYPE') {
          const end = xml.indexOf('>', pos + 9)
          if (end < 0) {
            break
          }
          pos = end + 1
          continue
        }
        const tagEnd = xml.indexOf('>', pos)
        if (tagEnd < 0) {
          break
        }
        const raw = xml.substring(pos + 1, tagEnd)
        if (raw.length === 0) {
          pos = tagEnd + 1
          continue
        }
        if (raw.charAt(0) === '/') {
          // 闭合标签，弹栈
          const tagName = DocxReader.parseTagName(raw.substring(1))
          while (stack.length > 1) {
            const popped = stack.pop() as XmlNode
            if (popped.tag === tagName) {
              break
            }
          }
          pos = tagEnd + 1
          continue
        }
        const selfClosing = raw.charAt(raw.length - 1) === '/'
        const body = selfClosing ? raw.substring(0, raw.length - 1) : raw
        const parsed: ParsedOpenTag = DocxReader.parseOpenTag(body)
        const tag: string = parsed.tag
        const attrs: Record<string, string> = parsed.attrs
        if (selfClosing) {
          const node: XmlNode = { kind: 'element', tag, attrs, children: [] }
          stack[stack.length - 1].children.push(node)
        } else {
          const node: XmlNode = { kind: 'element', tag, attrs, children: [] }
          stack[stack.length - 1].children.push(node)
          stack.push(node)
        }
        pos = tagEnd + 1
        continue
      }
      // 文本节点
      const nextLt = xml.indexOf('<', pos)
      const end = nextLt < 0 ? len : nextLt
      const text = xml.substring(pos, end)
      if (text.length > 0) {
        stack[stack.length - 1].children.push({ kind: 'text', tag: '', attrs: {}, children: [], text })
      }
      pos = end
    }
    return root.children
  }

  private static parseTagName(raw: string): string {
    const trimmed = raw.trim()
    const space = trimmed.indexOf(' ')
    return space < 0 ? trimmed : trimmed.substring(0, space)
  }

  private static parseOpenTag(body: string): ParsedOpenTag {
    const trimmed = body.trim()
    const space = trimmed.indexOf(' ')
    if (space < 0) {
      const result: ParsedOpenTag = { tag: trimmed, attrs: {} }
      return result
    }
    const tag = trimmed.substring(0, space)
    const rest = trimmed.substring(space + 1)
    const result: ParsedOpenTag = { tag, attrs: DocxReader.parseAttrs(rest) }
    return result
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
        // 无引号属性：读取到空白
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
      attrs[name] = rest.substring(i, endQuote)
      i = endQuote + 1
    }
    return attrs
  }
}

interface XmlNode {
  kind: 'element' | 'text'
  tag: string
  attrs: Record<string, string>
  children: XmlNode[]
  text?: string
}

/** 拼装 docx→HTML 的中间结构：按行聚合，cell 单独成段。 */
class DocxBuilder {
  private lines: string[] = []
  private inlineBuffer: string = ''

  appendInline(text: string): void {
    if (text.length === 0) {
      return
    }
    this.inlineBuffer += text
  }

  appendParagraph(content: string): void {
    if (content.length === 0) {
      // 空段落也输出 <p></p>，避免段落信息丢失
      this.lines.push('<p></p>')
      return
    }
    this.lines.push('<p>' + this.escape(content) + '</p>')
  }

  appendTableOpen(): void {
    this.lines.push('<table>')
  }

  appendTableClose(): void {
    this.lines.push('</table>')
  }

  appendTableRowOpen(): void {
    this.lines.push('<tr>')
  }

  appendTableRowClose(): void {
    this.lines.push('</tr>')
  }

  appendTableCell(content: string): void {
    this.lines.push('<td>' + this.escape(content) + '</td>')
  }

  finish(options?: DocxFinishOptions): string {
    const tail = this.inlineBuffer
    this.inlineBuffer = ''
    if (!options || !options.trim) {
      return tail
    }
    let value = tail
    if (options.trim) {
      value = value.replace(/^\s+|\s+$/g, '')
    }
    if (options.collapseBlank) {
      value = value.replace(/[ \t]+/g, ' ').replace(/\n{3,}/g, '\n\n')
    }
    return value
  }

  private escape(text: string): string {
    return text
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/\n/g, '<br/>')
  }
}
