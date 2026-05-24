/** 通用代码高亮：不区分编程语言，仅按注释/字符串/数字/关键字着色。 */
export type CodeHighlightTokenKind = 'plain' | 'comment' | 'string' | 'number' | 'keyword'

export interface CodeHighlightToken {
  text: string
  kind: CodeHighlightTokenKind
}

export class CodeHighlight {
  private static readonly KEYWORDS: Set<string> = new Set([
    'if', 'else', 'elif', 'for', 'while', 'do', 'switch', 'case', 'break', 'continue', 'return',
    'function', 'func', 'def', 'class', 'struct', 'enum', 'interface', 'type', 'import', 'export',
    'from', 'as', 'const', 'let', 'var', 'val', 'public', 'private', 'protected', 'static', 'void',
    'null', 'true', 'false', 'new', 'this', 'super', 'async', 'await', 'try', 'catch', 'finally',
    'throw', 'package', 'extends', 'implements'
  ])

  static highlight(code: string): CodeHighlightToken[] {
    if (code.length === 0) {
      return []
    }
    const tokens: CodeHighlightToken[] = []
    const lines = code.split('\n')
    for (let lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      CodeHighlight.highlightLine(lines[lineIndex], tokens)
      if (lineIndex < lines.length - 1) {
        tokens.push({ text: '\n', kind: 'plain' })
      }
    }
    return tokens
  }

  private static highlightLine(line: string, tokens: CodeHighlightToken[]): void {
    let index = 0
    let lineStart = true
    while (index < line.length) {
      const ch = line.charAt(index)
      if (ch === ' ' || ch === '\t') {
        const start = index
        while (index < line.length && (line.charAt(index) === ' ' || line.charAt(index) === '\t')) {
          index++
        }
        tokens.push({ text: line.slice(start, index), kind: 'plain' })
        continue
      }
      if (index + 1 < line.length && line.charAt(index) === '/' && line.charAt(index + 1) === '/') {
        tokens.push({ text: line.slice(index), kind: 'comment' })
        return
      }
      if (lineStart && ch === '#') {
        tokens.push({ text: line.slice(index), kind: 'comment' })
        return
      }
      if (ch === '"' || ch === '\'') {
        const end = CodeHighlight.readQuotedString(line, index)
        tokens.push({ text: line.slice(index, end), kind: 'string' })
        index = end
        lineStart = false
        continue
      }
      if (CodeHighlight.isDigit(ch) ||
        (ch === '.' && index + 1 < line.length && CodeHighlight.isDigit(line.charAt(index + 1)))) {
        const start = index
        index++
        while (index < line.length &&
          (CodeHighlight.isDigit(line.charAt(index)) || line.charAt(index) === '.' || line.charAt(index) === '_')) {
          index++
        }
        tokens.push({ text: line.slice(start, index), kind: 'number' })
        lineStart = false
        continue
      }
      if (CodeHighlight.isIdentStart(ch)) {
        const start = index
        index++
        while (index < line.length && CodeHighlight.isIdentPart(line.charAt(index))) {
          index++
        }
        const word = line.slice(start, index)
        tokens.push({
          text: word,
          kind: CodeHighlight.KEYWORDS.has(word) ? 'keyword' : 'plain'
        })
        lineStart = false
        continue
      }
      tokens.push({ text: ch, kind: 'plain' })
      index++
      lineStart = false
    }
  }

  private static readQuotedString(line: string, start: number): number {
    const quote = line.charAt(start)
    let index = start + 1
    while (index < line.length) {
      if (line.charAt(index) === '\\' && index + 1 < line.length) {
        index += 2
        continue
      }
      if (line.charAt(index) === quote) {
        return index + 1
      }
      index++
    }
    return line.length
  }

  private static isDigit(ch: string): boolean {
    const code = ch.charCodeAt(0)
    return code >= 48 && code <= 57
  }

  private static isIdentStart(ch: string): boolean {
    const code = ch.charCodeAt(0)
    return (code >= 65 && code <= 90) || (code >= 97 && code <= 122) || ch === '_'
  }

  private static isIdentPart(ch: string): boolean {
    return CodeHighlight.isIdentStart(ch) || CodeHighlight.isDigit(ch)
  }
}
