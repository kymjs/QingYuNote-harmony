export type MarkdownSyntaxTokenType =
  'plain' | 'h1' | 'heading' | 'quote' | 'bold' | 'italic' | 'strike' | 'code' | 'fence' | 'linkUrl'

export interface MarkdownSyntaxToken {
  start: number
  end: number
  type: MarkdownSyntaxTokenType
}

/** 编辑态引用行文字色（含 `>`）。 */
export const MARKDOWN_EDIT_QUOTE_COLOR: string = '#666666'

/** 编辑态 Markdown 语法着色（与 Flutter 对齐）。 */
export class MarkdownSyntaxHighlighter {
  static tokenize(text: string): MarkdownSyntaxToken[] {
    if (text.length === 0) {
      return []
    }
    const covered: Array<MarkdownSyntaxTokenType | null> = []
    for (let i = 0; i < text.length; i++) {
      covered.push(null)
    }

    const mark = (start: number, end: number, type: MarkdownSyntaxTokenType): void => {
      const s = Math.max(0, Math.min(start, text.length))
      const e = Math.max(0, Math.min(end, text.length))
      for (let i = s; i < e; i++) {
        if (covered[i] === null) {
          covered[i] = type
        }
      }
    }

    const fenceRe = /```[\s\S]*?```/g
    let fm = fenceRe.exec(text)
    while (fm !== null) {
      mark(fm.index, fm.index + fm[0].length, 'fence')
      fm = fenceRe.exec(text)
    }

    let lineStart = 0
    while (lineStart <= text.length) {
      const lineEndIdx = text.indexOf('\n', lineStart)
      const lineEnd = lineEndIdx < 0 ? text.length : lineEndIdx
      const line = text.substring(lineStart, lineEnd)
      const heading = /^(#{1,6})(\s+)(.*)$/.exec(line)
      if (heading !== null) {
        if (heading[1].length === 1) {
          mark(lineStart, lineEnd, 'h1')
        } else {
          mark(lineStart, lineEnd, 'heading')
        }
      } else if (line.startsWith('>')) {
        for (let i = lineStart; i < lineEnd; i++) {
          if (covered[i] !== 'fence') {
            covered[i] = 'quote'
          }
        }
      }
      if (lineEndIdx < 0) {
        break
      }
      lineStart = lineEndIdx + 1
    }

    const markPairs = (re: RegExp, type: MarkdownSyntaxTokenType): void => {
      let m = re.exec(text)
      while (m !== null) {
        let blocked = false
        for (let i = m.index; i < m.index + m[0].length; i++) {
          const t = covered[i]
          if (t === 'fence' || t === 'h1' || t === 'heading' || t === 'quote') {
            blocked = true
            break
          }
        }
        if (!blocked) {
          mark(m.index, m.index + m[0].length, type)
        }
        m = re.exec(text)
      }
    }

    markPairs(/\*\*[^*\n]+?\*\*/g, 'bold')
    markPairs(/~~[^~\n]+?~~/g, 'strike')
    markPairs(/`[^`\n]+?`/g, 'code')

    const italicRe = /\*[^*\n]+?\*/g
    let im = italicRe.exec(text)
    while (im !== null) {
      if (im.index > 0 && text.charAt(im.index - 1) === '*') {
        im = italicRe.exec(text)
        continue
      }
      if (im.index + im[0].length < text.length &&
        text.charAt(im.index + im[0].length) === '*') {
        im = italicRe.exec(text)
        continue
      }
      let blocked = false
      for (let i = im.index; i < im.index + im[0].length; i++) {
        const t = covered[i]
        if (t === 'fence' || t === 'h1' || t === 'heading' || t === 'bold' || t === 'quote') {
          blocked = true
          break
        }
      }
      if (!blocked) {
        mark(im.index, im.index + im[0].length, 'italic')
      }
      im = italicRe.exec(text)
    }

    const embedUrlRe = /\]\(([^)]+)\)/g
    let em = embedUrlRe.exec(text)
    while (em !== null) {
      const parenStart = em.index + 1
      const parenEnd = em.index + em[0].length
      let blocked = false
      for (let i = parenStart; i < parenEnd; i++) {
        if (covered[i] === 'fence' || covered[i] === 'quote') {
          blocked = true
          break
        }
      }
      if (!blocked) {
        mark(parenStart, parenEnd, 'linkUrl')
      }
      em = embedUrlRe.exec(text)
    }

    const tokens: MarkdownSyntaxToken[] = []
    let i = 0
    while (i < text.length) {
      const type: MarkdownSyntaxTokenType = covered[i] ?? 'plain'
      let j = i + 1
      while (j < text.length && (covered[j] ?? 'plain') === type) {
        j++
      }
      tokens.push({ start: i, end: j, type: type })
      i = j
    }
    return tokens
  }
}
